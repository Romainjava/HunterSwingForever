-- Hunter Swing Forever by Illusion
-- Unit 2: the swing / shot timing model, movement tracking, latency, calibration and shot log.
local ADDON, ns = ...

local T = {
	NEED = 0.5,
	SPELL_ID = 75,
	LATENCY_CAP = 0.25,
	MIN_WINDOW = 0.1,
	CALIB_MAX = 9,
	CALIB_MIN = 3,
	SAMPLE_MIN = 0.15,
	SAMPLE_MAX = 1.2,
	HELD_UP = 1.2,
	MAX_SWING = 10,
	MELEE_GRACE = 0.5,
	LOG_MAX = 40,
	GAPS_MAX = 10,
	DEMO_CYCLE = 3.0,
	RETRY = 0.5,
	FAILURE_EARLY = 0.25,
	FEIGN_ID = 5384,
	FEIGN_EXTRA = 0.15, -- after Feign Death the swing restarts at the weapon's base speed + this
	STOP_GRACE = 0.1, -- a move this close to the shot no longer stops it
	STEADY_SHOTS = 20, -- swings whose haste ratio sets the unhasted reference
	STEADY_TOLERANCE = 0.02,
}
ns.T = T

ns.latency = 0

local move = {
	known = false,
	moving = false,
	stillSince = 0,
	movingSince = nil,
	events = 0,
	source = "nothing",
}
ns.move = move

local timing = {
	lastShot = nil,
	speed = nil,
	running = false,
	autoRepeat = false,
	lastMelee = nil,
	meleeSpeed = nil,
	meleeAuto = false,
	broken = false,
	heldUp = false,
	moved = false,
	haste = {},
	eventsAtShot = 0,
	gaps = {},
	failCount = 0,
	failLast = nil,
	ratio = 1, -- swing speed / weapon base speed, locked for the current swing
	cycleStart = nil, -- the current swing can be restarted by a melee swing
	cycleOverride = nil, -- a Feign Death reset runs one swing at the weapon's base speed
	feignArmed = false, -- Feign Death cast: the next move or jump restarts the swing
	ratios = {}, -- haste ratios of the last swings, to tell unhasted shots apart
	ratioItem = nil,
}
ns.timing = timing

local nextPing = 0

local function Round3(value)
	if type(value) ~= "number" then
		return nil
	end
	return math.floor(value * 1000 + 0.5) / 1000
end

-- The three prediction rules, each with its own option (default on).
local function RetryModel()
	return not (ns.db and ns.db.retryModel == false)
end

local function MeleeResets()
	return not (ns.db and ns.db.meleeResetsRanged == false)
end

local function HasteWindup()
	return not (ns.db and ns.db.hasteWindup == false)
end

local function FeignResets()
	return not (ns.db and ns.db.feignResetsRanged == false)
end

----------------------------------------------------------------------------
-- Diagnostics: an Auto Shot the game refused, and the weapon's own speed
----------------------------------------------------------------------------

-- Counted per swing for the shot log only; nothing here feeds the prediction.
local failed = CreateFrame("Frame")
local function OnFailedQuiet(_, _, unit, _, spellID)
	if unit ~= "player" then
		return
	end
	local id = ns.PlainNumber(spellID)
	if id ~= T.SPELL_ID then
		return
	end
	timing.failCount = timing.failCount + 1
	timing.failLast = GetTime()
end
failed:SetScript("OnEvent", OnFailedQuiet)
pcall(failed.RegisterEvent, failed, "UNIT_SPELLCAST_FAILED_QUIET")

-- The client's own word for "Speed" (SPEED is a Blizzard global string: "Vitesse",
-- "Tempo", "Velocidad"...), so a non-English tooltip is read too; English as fallback.
local function SpeedLabels()
	local labels = { "Speed" }
	local localized = rawget(_G, "SPEED")
	if type(localized) == "string" and localized ~= "" and localized ~= "Speed" then
		table.insert(labels, 1, localized)
	end
	return labels
end

local function SpeedFromLines(lines)
	if type(lines) ~= "table" then
		return nil
	end
	local labels = SpeedLabels()
	for _, line in ipairs(lines) do
		if type(line) == "table" then
			for _, key in ipairs({ "leftText", "rightText" }) do
				local text = line[key]
				local speed
				if type(text) == "string" then
					for _, label in ipairs(labels) do
						local escaped = string.gsub(label, "(%p)", "%%%1")
						speed = speed or string.match(text, escaped .. "[%s\194\160]*:?[%s\194\160]*(%d+[%.,]%d+)")
					end
					if speed then
						return ns.PlainNumber(tonumber((string.gsub(speed, ",", "."))))
					end
				end
			end
		end
	end
	return nil
end

-- The ranged weapon's own speed (the "Speed 2.80" line of its tooltip), or nil.
local baseSpeed = { item = nil, speed = nil }

function ns.WeaponBaseSpeed()
	local ok, value = ns.SafeCall(_G.GetInventoryItemID, "player", 18)
	local itemID = ok and ns.PlainNumber(value) or nil
	if not itemID then
		return nil
	end
	if baseSpeed.item == itemID then
		return baseSpeed.speed
	end
	local speed
	local getter = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
	if type(getter) == "function" then
		local loaded, data = pcall(getter, "player", 18)
		if loaded and type(data) == "table" then
			speed = SpeedFromLines(data.lines)
		end
	end
	if speed and speed > 0 then
		baseSpeed.item, baseSpeed.speed = itemID, speed
	end
	return speed
end

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------

function ns.ResetMovement(now)
	move.moving = false
	move.stillSince = now
	if move.events == 0 and not move.known then
		move.source = "nothing"
	end
end

function ns.OnMovementEvent(isMoving, now)
	move.events = move.events + 1
	move.known = true
	move.source = "events"
	local wasMoving = move.moving
	move.moving = isMoving and true or false
	if not move.moving then
		move.stillSince = now
	elseif not wasMoving then
		move.movingSince = now
	end
	if move.moving and timing.lastShot then
		timing.moved = true
	end
	if move.moving then
		ns.OnFeignMove(now)
	end
end

function ns.PollMovement(now)
	if move.events > 0 then
		move.known = true
		move.source = "events"
		return
	end

	local speedOK, speed = ns.SafeCall(GetUnitSpeed, "player")
	local fallOK, falling = ns.SafeCall(IsFalling)

	local plainSpeed = speedOK and ns.PlainNumber(speed) or nil
	local plainFalling = fallOK and ns.PlainTrue(falling) or nil

	if plainSpeed == nil and plainFalling == nil then
		move.source = "nothing"
		return
	end

	local isMoving = (plainSpeed ~= nil and plainSpeed > 0) or plainFalling == true
	move.known = true
	move.source = "speed"
	if isMoving ~= move.moving then
		move.moving = isMoving
		if not isMoving then
			move.stillSince = now
		else
			move.movingSince = now
			ns.OnFeignMove(now)
		end
	end
end

function ns.MovementKnown()
	return move.known
end

---------------------------------------------------------------------------
-- Latency
---------------------------------------------------------------------------

function ns.UpdateLatency(now)
	if now < nextPing then
		return
	end
	nextPing = now + 5
	local ok, _, _, _, home, world = ns.SafeCall(GetNetStats)
	if not ok then
		return
	end
	local ms = ns.PlainNumber(world)
	if ms == nil then
		ms = ns.PlainNumber(home)
	end
	if ms ~= nil and ms >= 0 then
		ns.latency = math.min(ms / 1000, T.LATENCY_CAP)
	end
end

---------------------------------------------------------------------------
-- The stand-still window and the learned stand-still time
---------------------------------------------------------------------------

function ns.Window()
	local extra = (ns.db and ns.db.windowExtra or 0) / 1000
	local ping = (ns.db and ns.db.addPing) and ns.latency or 0
	return math.max(T.MIN_WINDOW, ns.Windup() + ping + extra)
end

-- The wind-up of the current swing: 0.5 s, shorter when ranged haste is on.
function ns.Windup()
	if not HasteWindup() then
		return T.NEED
	end
	local ratio = timing.ratio
	if type(ratio) ~= "number" or ratio <= 0 then
		return T.NEED
	end
	return T.NEED * ratio
end

-- When the game makes its next Auto Shot attempt for a player who stops at `stop`.
-- A refusal up to 0.25 s before the first attempt counts as that attempt.
function ns.NextAttempt(firstAttempt, stop)
	local last = timing.failLast
	if last and last >= firstAttempt - T.FAILURE_EARLY then
		-- Retries go on every 0.5 s from the last refusal, even when the client did
		-- not report the later ones: the first retry at or after the stop.
		local nextTry = last + T.RETRY
		if stop and stop > nextTry then
			nextTry = nextTry + math.ceil((stop - nextTry) / T.RETRY) * T.RETRY
		end
		return nextTry
	end
	if stop and stop > firstAttempt then
		return firstAttempt + math.ceil((stop - firstAttempt) / T.RETRY) * T.RETRY
	end
	return firstAttempt
end

-- Where the current swing counts from: a melee swing can restart it (rule 2).
local function CycleOrigin(now)
	return timing.cycleStart or timing.lastShot or now
end

function ns.MedianStand()
	local list = ns.db and ns.db.calib and ns.db.calib.stand or {}
	local count = #list
	local newest = list[count]
	local cache = ns.medianCache
	if cache and cache.count == count and cache.newest == newest then
		return cache.value
	end

	local sorted = {}
	for index = 1, count do
		sorted[index] = list[index]
	end
	table.sort(sorted)

	local value
	if count == 0 then
		value = nil
	elseif count % 2 == 1 then
		value = sorted[(count + 1) / 2]
	else
		value = (sorted[count / 2] + sorted[count / 2 + 1]) / 2
	end
	ns.medianCache = { count = count, newest = newest, value = value }
	return value
end

function ns.Need(demo)
	if demo then
		return ns.Window(), false, 0
	end
	local samples = ns.db and ns.db.calib and ns.db.calib.stand or {}
	local count = #samples
	if count >= T.CALIB_MIN then
		local median = ns.MedianStand()
		if median then
			local extra = (ns.db.windowExtra or 0) / 1000
			local ratio = HasteWindup() and timing.ratio or 1
			return math.max(T.MIN_WINDOW, median * ratio + extra), true, count
		end
	end
	return ns.Window(), false, count
end

---------------------------------------------------------------------------
-- The phase of the current swing (SPEC 7.2)
---------------------------------------------------------------------------

function ns.Phase(now, demo)
	local cycle
	local need
	if demo then
		cycle = T.DEMO_CYCLE
		need = ns.Window()
	else
		cycle = timing.cycleOverride or timing.speed
		need = ns.Need()
	end
	if not cycle or cycle <= 0 then
		return nil
	end

	local stand = math.min(need, cycle)
	local moveUntil = cycle - stand
	local elapsed
	if demo then
		elapsed = now - (now - now % cycle)
	else
		elapsed = now - CycleOrigin(now)
	end

	local info = {
		cycle = cycle,
		need = need,
		stand = stand,
		moveUntil = moveUntil,
		elapsed = elapsed,
	}
	if elapsed < moveUntil then
		info.phase = "move"
		info.fill = elapsed / cycle
		info.left = moveUntil - elapsed
	elseif elapsed < cycle then
		info.phase = "stand"
		info.fill = elapsed / cycle
		info.left = cycle - elapsed
	else
		info.phase = "late"
		info.fill = 1
		info.left = 0
	end
	return info
end

-- When the shot actually fires, and when the stand-still began (SPEC 7.6).
function ns.StandStill(now, cycle, need, demo)
	if demo then
		return nil
	end
	if not move.known or not move.stillSince then
		return nil
	end
	-- A move that starts in the last tenth of a second before the shot does not stop
	-- it (the server already has it): keep the prediction made while standing.
	local grace = false
	if move.moving then
		if not move.movingSince or move.movingSince < move.stillSince then
			return nil
		end
		local saved = move.moving
		move.moving = false
		local shot = ns.StandStill(move.movingSince, cycle, need, demo)
		move.moving = saved
		if not shot or move.movingSince < shot - T.STOP_GRACE or now > shot then
			return nil
		end
		grace = true
	end
	local origin = CycleOrigin(now)
	local start, shotTime
	local pushed = false
	if RetryModel() then
		-- The game tries again every 0.5 s while the player is moving; the wind-up
		-- only begins once an attempt lands.
		local windup = ns.Windup()
		local nextAttempt = ns.NextAttempt(origin + cycle - windup, move.stillSince)
		pushed = nextAttempt > move.stillSince
		start = math.max(move.stillSince, nextAttempt)
		shotTime = start + windup
	else
		local swingEnd = origin + cycle
		local stopBy = swingEnd - need
		if move.stillSince <= stopBy then
			shotTime = swingEnd
			start = stopBy
		else
			shotTime = move.stillSince + need
			start = move.stillSince
		end
	end
	local left = shotTime - now
	local progress
	if shotTime - start <= 0 then
		progress = 1
	else
		progress = math.max(0, math.min(1, (now - start) / (shotTime - start)))
	end
	return shotTime, start, left, progress, pushed, grace
end

---------------------------------------------------------------------------
-- Inputs
---------------------------------------------------------------------------

local function KnownCode()
	if move.events > 0 then
		return 2
	end
	if move.known then
		return 1
	end
	return 0
end

local function AppendShotLog(row)
	local log = ns.db.shotLog
	log[#log + 1] = row
	while #log > T.LOG_MAX do
		table.remove(log, 1)
	end
end

-- True when a swing ran without a temporary haste buff (Rapid Fire, Quick Shots...):
-- its ratio is the highest of the recent swings, i.e. the quiver and gear only.
local function Unhasted(ratio)
	if type(ratio) ~= "number" then
		return true
	end
	local steady = ratio
	for _, value in ipairs(timing.ratios) do
		if value > steady then
			steady = value
		end
	end
	return ratio >= steady * (1 - T.STEADY_TOLERANCE)
end

local function RememberRatio(ratio)
	local ok, value = ns.SafeCall(_G.GetInventoryItemID, "player", 18)
	local item = ok and ns.PlainNumber(value) or nil
	if item ~= timing.ratioItem then
		timing.ratios = {}
		timing.ratioItem = item
	end
	if type(ratio) == "number" then
		timing.ratios[#timing.ratios + 1] = ratio
		while #timing.ratios > T.STEADY_SHOTS do
			table.remove(timing.ratios, 1)
		end
	end
end

function ns.OnRangedSwing(duration)
	local db = ns.db
	if not db then
		return
	end
	local now = GetTime()
	local reported = ns.PlainNumber(duration)
	local speed = timing.speed
	if reported and reported > 0 and reported <= T.MAX_SWING then
		speed = reported
	end

	-- A shot can not fire while moving: heal a stop event the client swallowed.
	if timing.lastShot and move.moving and move.known and move.events == timing.eventsAtShot then
		move.moving = false
		move.stillSince = now
		timing.moved = true
	end

	local previous = timing.lastShot
	local previousSpeed = timing.speed
	local previousWindup = ns.Windup()
	local previousRatio = HasteWindup() and (timing.ratio or 1) or 1
	local previousUnhasted = Unhasted(timing.lastRatio)
	local gap = previous and (now - previous) or nil

	-- Learn from the swing that just ended (SPEC 7.5).
	if previous and previousSpeed and not timing.broken and not timing.heldUp
		and #timing.haste == 0 and not ns.demoActive and previousUnhasted
		and move.known and not move.moving and move.stillSince and gap then
		local need = ns.Need()
		local stopBefore = (previous + previousSpeed) - move.stillSince
		local measured
		if RetryModel() then
			-- Measure the wind-up as the game applies it: a retry can push the start.
			local firstAttempt = previous + previousSpeed - previousWindup
			measured = now - math.max(move.stillSince, ns.NextAttempt(firstAttempt, move.stillSince))
		else
			measured = now - move.stillSince
		end
		if stopBefore < need and measured >= T.SAMPLE_MIN and measured <= T.SAMPLE_MAX then
			local samples = db.calib.stand
			samples[#samples + 1] = Round3(measured / previousRatio)
			while #samples > T.CALIB_MAX do
				table.remove(samples, 1)
			end
			ns.ResetMedian()
		end
	end

	-- Gap memory for the /hsf timing report.
	if gap then
		timing.gaps[#timing.gaps + 1] = {
			gap = gap,
			speed = previousSpeed,
			moved = timing.moved,
			haste = #timing.haste > 0,
			broken = timing.broken,
		}
		while #timing.gaps > T.GAPS_MAX do
			table.remove(timing.gaps, 1)
		end
	end

	local still
	if move.moving then
		still = -1
	else
		still = Round3(now - (move.stillSince or now))
	end

	local base = ns.WeaponBaseSpeed()
	local hasteRatio
	if base and base > 0 and speed and speed > 0 then
		hasteRatio = Round3(speed / base)
	end
	-- Locked for the swing that starts now: the wind-up follows this ratio.
	timing.ratio = hasteRatio or 1
	timing.lastRatio = hasteRatio
	RememberRatio(hasteRatio)

	AppendShotLog({
		t = Round3(now),
		speed = Round3(speed or 0),
		ping = math.floor(ns.latency * 1000 + 0.5),
		known = KnownCode(),
		gap = gap and Round3(gap) or nil,
		prev = previousSpeed and Round3(previousSpeed) or nil,
		afterSwing = (gap and previousSpeed) and Round3(gap - previousSpeed) or nil,
		broken = timing.broken and 1 or 0,
		moved = timing.moved and 1 or 0,
		haste = table.concat(timing.haste, ","),
		still = still,
		failed = timing.failCount,
		failedAgo = (timing.failCount > 0 and timing.failLast) and Round3(now - timing.failLast) or nil,
		hasteRatio = hasteRatio,
	})

	timing.lastShot = now
	if speed then
		timing.speed = speed
	end
	timing.cycleStart = now
	timing.cycleOverride = nil
	timing.feignArmed = false
	timing.running = true
	timing.broken = false
	timing.heldUp = false
	timing.moved = false
	timing.haste = {}
	timing.eventsAtShot = move.events
	timing.failCount = 0
	timing.failLast = nil
end

function ns.OnMeleeSwing(duration)
	local now = GetTime()
	timing.lastMelee = now
	local reported = ns.PlainNumber(duration)
	if reported and reported > 0 and reported <= T.MAX_SWING then
		timing.meleeSpeed = reported
	end
	timing.broken = true
	-- A melee swing restarts the Auto Shot swing from the melee swing time.
	if MeleeResets() and timing.speed then
		timing.cycleStart = now
		timing.cycleOverride = nil
	end
end

-- Feign Death: the next move or jump restarts the Auto Shot swing, unhasted, at the
-- weapon's base speed + 0.15 s (the rule WeaponSwingTimer uses on Forever).
function ns.OnSpellSucceeded(spellID)
	if ns.PlainNumber(spellID) == T.FEIGN_ID and FeignResets() then
		timing.feignArmed = true
	end
end

function ns.OnFeignMove(now)
	if not timing.feignArmed then
		return
	end
	timing.feignArmed = false
	if not FeignResets() or not timing.speed then
		return
	end
	timing.cycleStart = now
	local base = ns.WeaponBaseSpeed()
	timing.cycleOverride = base and (base + T.FEIGN_EXTRA) or nil
	timing.broken = true
end

function ns.SetAutoRepeat(running)
	timing.running = running and true or false
	timing.autoRepeat = timing.running
	if timing.running then
		timing.broken = true
	end
end

function ns.SetMeleeAuto(running)
	timing.meleeAuto = running and true or false
end

function ns.OnAttackSpeedChange(kind)
	if not timing.lastShot then
		return
	end
	if #timing.haste >= 6 then
		return
	end
	local since = GetTime() - timing.lastShot
	timing.haste[#timing.haste + 1] = kind .. string.format("%.3f", since)
end

function ns.MeleeActive(now)
	if timing.lastMelee then
		local speed = timing.meleeSpeed or 2
		if now - timing.lastMelee < speed + T.MELEE_GRACE
			and (not timing.lastShot or timing.lastMelee > timing.lastShot) then
			return true
		end
		return false
	end
	if timing.meleeAuto and not timing.autoRepeat and ns.range and ns.range.held == "close" then
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Reports (SPEC 4.2, 4.3)
---------------------------------------------------------------------------

function ns.ReportMovement()
	ns.Print("Movement (run it standing, then while running):")
	ns.PrintLine("GetUnitSpeed = " .. ns.DescribeCall(GetUnitSpeed, "player"))
	ns.PrintLine("IsFalling = " .. ns.DescribeCall(IsFalling))
	ns.PrintLine(string.format("movement events seen = %d", move.events))
	local using
	if move.events > 0 then
		using = "events"
	elseif move.known then
		using = "speed"
	else
		using = "nothing (the bar goes by the swing time alone)"
	end
	ns.PrintLine("using = " .. using)
	local state = "unknown"
	if move.known then
		state = move.moving and "moving" or "standing still"
	end
	ns.PrintLine("you are " .. state)
end

function ns.ReportTiming()
	ns.Print("Auto Shot timing (stand still and shoot first):")

	local usable = {}
	for index, entry in ipairs(timing.gaps) do
		local over = math.floor((entry.gap - entry.speed) * 100 + 0.5) / 100
		local why = ""
		if entry.moved then
			why = " - you moved, left out"
		elseif over > T.HELD_UP then
			why = " - held up, left out"
		end
		ns.PrintLine(string.format("%d. %.2f s apart, speed %.2f s (%+.2f s)%s", index, entry.gap, entry.speed, over, why))
		if not entry.moved and not entry.haste and not entry.broken and over <= T.HELD_UP then
			usable[#usable + 1] = over
		end
	end

	-- Diagnostics added with 1.0.0: refused tries and the haste ratio seen (never used above).
	local log = ns.db.shotLog or {}
	local failedShots, agoSum, agoCount = 0, 0, 0
	local low, high
	for _, row in ipairs(log) do
		if (ns.PlainNumber(row.failed) or 0) > 0 then
			failedShots = failedShots + 1
			local ago = ns.PlainNumber(row.failedAgo)
			if ago then
				agoSum = agoSum + ago
				agoCount = agoCount + 1
			end
		end
		local ratio = ns.PlainNumber(row.hasteRatio)
		if ratio then
			low = math.min(low or ratio, ratio)
			high = math.max(high or ratio, ratio)
		end
	end
	local tries
	if failedShots == 0 then
		tries = "none"
	elseif agoCount == 0 then
		tries = string.format("%d of %d shots", failedShots, #log)
	else
		tries = string.format("%d of %d shots, %.2f s between the last failed try and the shot", failedShots, #log, agoSum / agoCount)
	end
	local speedText = low and string.format("%.2fx to %.2fx", low, high) or "not readable"
	ns.PrintLine(string.format("Failed Auto Shot tries: %s; swing speed against the weapon's %s.", tries, speedText))

	local samples = ns.db.calib.stand
	local count = #samples
	if count >= T.CALIB_MIN then
		local median = ns.MedianStand() or 0
		ns.PrintLine(string.format("Measured stand-still time: %.2f s (from %d shots where you stopped late).", median, count))
	else
		ns.PrintLine(string.format("Stand-still time not measured yet (%d of %d shots): stop after a swing ends and let the shot go. Using %.2f s.", count, T.CALIB_MIN, ns.Window()))
	end

	if #usable < 3 then
		ns.Print("Not enough shots yet: stand still and let Auto Shot fire 6 times, then type /hsf timing.")
		return
	end

	local sum = 0
	for _, over in ipairs(usable) do
		sum = sum + over
	end
	local mean = sum / #usable
	if mean < 0.15 then
		ns.Print(string.format("Shots come %.2f s after the speed on average: the stand-still fits inside the swing.", mean))
	else
		ns.Print(string.format("Shots come %.2f s after the speed on average: the stand-still is added to the swing.", mean))
	end
end
