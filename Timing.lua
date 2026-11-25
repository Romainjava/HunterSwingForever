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
	INTERRUPT_MIN_LAG = 0.04,
	FAILURE_EARLY = 0.5,
	FEIGN_ID = 5384,
	STOP_GRACE = 0.1,
	STOP_LEAD = 0.06,
	MOVE_CONFIRM = 0.03,
	JUMP_GRACE = 0.1,
	AIM_MAX = 4.5,
	CHANNEL_MAX = 15,
	AUTO_FLICKER = 0.5,
	PRESS_KEEP = 5,
	PRESS_NEAR = 0.05,
	PRESS_CLEAR = 0.15,
	PRESS_WINDUP_GRACE = 0.25,
	BLOCK_NEAR = 0.2,
	RF_ID = 3045,
	RF_HASTE = 1.4,
	RF_DURATION = 15,
	QS_HASTE = 1.3,
	QS_DURATION = 12,
	QS_CONFIRM = 1.15,
	QS_END_SLOP = 0.15,
	STEADY_SHOTS = 20,
	STEADY_TOLERANCE = 0.02,
}
ns.T = T

ns.latency = 0

local AIMED_IDS = {
	[19434] = true,
	[20900] = true,
	[20901] = true,
	[20902] = true,
	[20903] = true,
	[20904] = true,
	[27065] = true,
}

local ERROR_KINDS = {
	ERR_BADATTACKFACING = "facing",
	SPELL_FAILED_UNIT_NOT_INFRONT = "facing",
	SPELL_FAILED_LINE_OF_SIGHT = "los",
	SPELL_FAILED_OUT_OF_RANGE = "range",
	ERR_OUT_OF_RANGE = "range",
	SPELL_FAILED_TOO_CLOSE = "range",
}

local move = {
	known = false,
	moving = false,
	stillSince = 0,
	movingSince = nil,
	ground = false,
	airborne = false,
	cc = false,
	jumpAt = nil,
	pendingSince = nil,
	aimKey = nil,
	aimAt = 0,
	events = 0,
	source = "nothing",
}
ns.move = move

local timing = {
	lastShot = nil,
	speed = nil,
	prevSpeed = nil,
	running = false,
	autoRepeat = false,
	lastAutoStopAt = -1,
	autoOffAt = -1,
	autoStartAt = nil,
	onBeforeStop = false,
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
	lastFailGuid = nil,
	lastInterruptGuid = nil,
	failUndo = nil,
	pressIDs = {},
	pressWindupAt = nil,
	pressWindupGuid = nil,
	blockErrAt = -1,
	blockErrKind = nil,
	channelAt = nil,
	ratio = 1,
	rfEnd = 0,
	rfHasted = false,
	qsEnd = 0,
	qsHasted = false,
	qsProcAt = -1,
	qsBaseSpeed = nil,
	auraAt = -1,
	windupShift = 0,
	cycleStart = nil,
	cycleOverride = nil,
	feignArmed = false,
	ratios = {},
	ratioItem = nil,
}
ns.timing = timing

local nextPing = 0
local spellNames = {}
local errorLookup = nil

local function Round3(value)
	if type(value) ~= "number" then
		return nil
	end
	return math.floor(value * 1000 + 0.5) / 1000
end

local function PlainString(value)
	if type(value) ~= "string" or ns.IsSecret(value) then
		return nil
	end
	return value
end

local function SpellName(spellID)
	local id = ns.PlainNumber(spellID)
	if not id then
		return nil
	end
	local cached = spellNames[id]
	if cached then
		return cached
	end
	if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		if ok and type(info) == "table" and not ns.IsSecret(info) then
			local name = PlainString(info.name)
			if name then
				spellNames[id] = name
				return name
			end
		end
	elseif type(_G.GetSpellInfo) == "function" then
		local ok, name = pcall(_G.GetSpellInfo, id)
		if ok then
			name = PlainString(name)
			if name then
				spellNames[id] = name
				return name
			end
		end
	end
	return nil
end

local function IsAimedSpell(spellID)
	local id = ns.PlainNumber(spellID)
	if not id then
		return false
	end
	if AIMED_IDS[id] then
		return true
	end
	local aimedName = SpellName(19434)
	return aimedName ~= nil and SpellName(id) == aimedName
end

local function IsRapidFireSpell(spellID)
	local id = ns.PlainNumber(spellID)
	if not id then
		return false
	end
	if id == T.RF_ID then
		return true
	end
	local rfName = SpellName(T.RF_ID)
	return rfName ~= nil and SpellName(id) == rfName
end

local function IsFeignSpell(spellID)
	local id = ns.PlainNumber(spellID)
	if not id then
		return false
	end
	if id == T.FEIGN_ID then
		return true
	end
	local feignName = SpellName(T.FEIGN_ID)
	return feignName ~= nil and SpellName(id) == feignName
end

function ns.ClassifyError(first, second)
	if not errorLookup then
		errorLookup = {}
		for globalKey, kind in pairs(ERROR_KINDS) do
			local text = PlainString(rawget(_G, globalKey))
			if text and text ~= "" then
				errorLookup[text] = kind
			end
		end
	end
	local a = PlainString(first)
	if a and errorLookup[a] then
		return errorLookup[a]
	end
	local b = PlainString(second)
	if b and errorLookup[b] then
		return errorLookup[b]
	end
	return nil
end

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

local function AddPingEnabled()
	return not (ns.db and ns.db.addPing == false)
end

local function StopLead()
	if not AddPingEnabled() then
		return 0
	end
	return ns.latency + T.STOP_LEAD
end

local function Channeling(now)
	if timing.channelAt and now - timing.channelAt > T.CHANNEL_MAX then
		timing.channelAt = nil
	end
	return timing.channelAt ~= nil
end

local function NoLivingTarget()
	local okExists, exists = ns.SafeCall(UnitExists, "target")
	if okExists and ns.PlainTrue(exists) == false then
		return true
	end
	local okDead, dead = ns.SafeCall(UnitIsDeadOrGhost, "target")
	if okDead and ns.PlainTrue(dead) == true then
		return true
	end
	return false
end

local function Record(kind, ...)
	if ns.RecordMovement then
		ns.RecordMovement(kind, ...)
	end
end

local function HasteDelta(now)
	local factor = 1
	local rfActive = timing.rfEnd > 0 and now < timing.rfEnd
	if rfActive and not timing.rfHasted then
		factor = factor * T.RF_HASTE
	elseif not rfActive and timing.rfHasted then
		factor = factor / T.RF_HASTE
	end
	local qsActive = timing.qsEnd > 0 and now < timing.qsEnd
	if qsActive and not timing.qsHasted then
		factor = factor * T.QS_HASTE
	elseif not qsActive and timing.qsHasted then
		factor = factor / T.QS_HASTE
	end
	return factor
end

local function EffectiveRatio(now)
	local ratio = timing.ratio
	if type(ratio) ~= "number" or ratio <= 0 then
		return 1
	end
	return ratio / HasteDelta(now)
end

local function CycleOrigin(now)
	return timing.cycleStart or timing.lastShot or now
end

local function EffectiveCycle(now)
	local base = timing.cycleOverride or timing.speed
	if not base or base <= 0 then
		return nil
	end
	if timing.cycleOverride then
		return base
	end
	local delta = HasteDelta(now)
	if delta == 1 then
		return base + (timing.windupShift or 0)
	end
	local origin = CycleOrigin(now)
	if now >= origin + base + (timing.windupShift or 0) then
		return base / delta
	end
	return base + (timing.windupShift or 0)
end

local function UpdateWindupShift(now)
	if not timing.speed or timing.speed <= 0 or timing.cycleOverride then
		return
	end
	local origin = CycleOrigin(now)
	local currentEnd = origin + timing.speed + (timing.windupShift or 0)
	local currentWindup = ns.Windup(now)
	if now < currentEnd - currentWindup then
		local shotWindup = HasteWindup() and (T.NEED * (timing.ratio or 1)) or T.NEED
		timing.windupShift = currentWindup - shotWindup
	end
end

local function ExpireHasteBuffs(now)
	local changed = false
	if timing.rfEnd > 0 and now >= timing.rfEnd then
		timing.rfEnd = 0
		changed = true
		Record("HT", "rf_end", EffectiveRatio(now))
	end
	if timing.qsEnd > 0 and now >= timing.qsEnd then
		timing.qsEnd = 0
		timing.qsBaseSpeed = nil
		changed = true
		Record("HT", "qs_end", EffectiveRatio(now))
	end
	if changed then
		UpdateWindupShift(now)
	end
end

local function OnQuickShotsProc(now, previousSpeed, currentSpeed)
	local active = timing.qsEnd > 0 and now < timing.qsEnd
	if active and now >= timing.qsEnd - T.QS_END_SLOP then
		return
	end
	timing.qsEnd = now + T.QS_DURATION
	if active then
		return
	end
	if not currentSpeed or currentSpeed <= 0 then
		return
	end
	timing.qsProcAt = now
	timing.qsBaseSpeed = currentSpeed
	if previousSpeed and currentSpeed < previousSpeed / T.QS_CONFIRM then
		timing.qsBaseSpeed = previousSpeed
		timing.qsHasted = true
		Record("HT", "qs_in_reload", EffectiveRatio(now))
		return
	end
	UpdateWindupShift(now)
	Record("HT", "qs_proc", EffectiveRatio(now))
end

local function ClearPressWindup()
	timing.pressWindupAt = nil
	timing.pressWindupGuid = nil
end

local function OnFailedQuiet(_, _, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	local id = ns.PlainNumber(spellID)
	if id ~= T.SPELL_ID then
		return
	end
	local now = GetTime()
	local key = PlainString(castGUID)
	if key and key == timing.pressWindupGuid then
		ClearPressWindup()
	end
	if key then
		if key == timing.lastFailGuid then
			return
		end
		timing.lastFailGuid = key
	end
	if now == timing.lastAutoStopAt then
		return
	end
	if Channeling(now) or NoLivingTarget() then
		return
	end

	local pressAt = key and timing.pressIDs[key] or nil
	if pressAt and now - pressAt <= T.PRESS_KEEP then
		if now - pressAt > T.PRESS_NEAR then
			return
		end
		if move.moving then
			timing.failUndo = { at = now, count = timing.failCount, last = timing.failLast }
			timing.failCount = timing.failCount + 1
			timing.failLast = pressAt
			return
		end
		local sinceStop = move.stillSince and (pressAt - move.stillSince) or nil
		local closeToStop = sinceStop ~= nil and sinceStop >= 0 and sinceStop < StopLead()
		local cycle = EffectiveCycle(now)
		local beforeWindup = cycle ~= nil and timing.cycleStart ~= nil
			and pressAt < (timing.cycleStart + cycle - ns.Windup(now) - T.PRESS_CLEAR)
		if closeToStop or beforeWindup then
			timing.failUndo = { at = now, count = timing.failCount, last = timing.failLast }
			timing.failCount = timing.failCount + 1
			timing.failLast = pressAt
		end
		return
	end

	if not move.moving and now - timing.blockErrAt <= T.BLOCK_NEAR then
		timing.heldUp = true
	end
	timing.failUndo = { at = now, count = timing.failCount, last = timing.failLast }
	timing.failCount = timing.failCount + 1
	timing.failLast = now
end

local failed = CreateFrame("Frame")
failed:SetScript("OnEvent", OnFailedQuiet)
pcall(failed.RegisterEvent, failed, "UNIT_SPELLCAST_FAILED_QUIET")

local function LocalizedSpeedLabels()
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
	local labels = LocalizedSpeedLabels()
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

local function ReadSpeed()
	local ok, speed = ns.SafeCall(GetUnitSpeed, "player")
	return ok and ns.PlainNumber(speed) or nil
end

local function ReadFalling()
	local ok, falling = ns.SafeCall(IsFalling)
	if not ok then
		return nil
	end
	return ns.PlainTrue(falling)
end

local function ReadControlLost()
	local taxiOK, onTaxi = ns.SafeCall(UnitOnTaxi, "player")
	if taxiOK and ns.PlainTrue(onTaxi) == true then
		return false
	end
	local ok, full = ns.SafeCall(HasFullControl)
	if not ok then
		return false
	end
	return ns.PlainTrue(full) == false
end

local function Aiming(now)
	if move.aimKey and now - move.aimAt > T.AIM_MAX then
		move.aimKey = nil
	end
	return move.aimKey ~= nil
end

local function SetMoving(isMoving, now, voluntary)
	if isMoving == move.moving then
		return
	end
	move.moving = isMoving
	if isMoving then
		move.movingSince = now
		if timing.pressWindupAt then
			local graceWindow = T.STOP_GRACE + (AddPingEnabled() and ns.latency or 0)
			if now < timing.pressWindupAt + ns.Windup(now) - graceWindow then
				ClearPressWindup()
			end
		end
		if voluntary then
			if timing.lastShot then
				timing.moved = true
			end
			ns.OnFeignMove(now)
		end
	else
		move.stillSince = now
		Record("ST")
	end
end

local function Resolve(now)
	local physical = move.ground or move.airborne
	SetMoving(physical or move.cc, now, physical)
end

local function ConfirmPending(now)
	if not move.pendingSince then
		return
	end
	local speed = ReadSpeed()
	local held = now - move.pendingSince
	local how
	if speed ~= nil then
		how = speed > 0 and "speed" or nil
	elseif not Aiming(now) and held >= T.MOVE_CONFIRM then
		how = "time"
	end
	if how then
		local since = how == "time" and move.pendingSince or now
		move.pendingSince = nil
		move.ground = true
		SetMoving(true, since, true)
		Record("MC", how, held)
	end
end

local function PollFalling(now)
	local falling = ReadFalling()
	if falling == true then
		if not move.airborne then
			move.airborne = true
			Record("AIR", true)
		end
	elseif falling == false then
		if move.airborne and (not move.jumpAt or now - move.jumpAt >= T.JUMP_GRACE) then
			move.airborne = false
			move.jumpAt = nil
			Record("AIR", false)
		end
	elseif move.airborne and move.jumpAt and now - move.jumpAt >= T.JUMP_GRACE then
		move.airborne = false
		move.jumpAt = nil
		Record("AIR", false)
	end
end

local function PollControl()
	local lost = ReadControlLost()
	if lost ~= move.cc then
		move.cc = lost
		Record("CC", lost)
	end
end

function ns.ResetMovement(now)
	move.moving = false
	move.ground = false
	move.airborne = false
	move.cc = false
	move.jumpAt = nil
	move.pendingSince = nil
	move.aimKey = nil
	move.stillSince = now
	timing.channelAt = nil
	ClearPressWindup()
	if move.events == 0 and not move.known then
		move.source = "nothing"
	end
end

function ns.OnJump(now)
	ns.OnFeignMove(now)
	if ReadFalling() ~= nil then
		move.jumpAt = now
		if not move.airborne then
			move.airborne = true
			Record("AIR", true)
		end
		Resolve(now)
	end
end

function ns.OnMovementEvent(isMoving, now)
	move.events = move.events + 1
	move.known = true
	move.source = "events"
	if isMoving then
		if not move.ground and not move.pendingSince then
			move.pendingSince = now
		end
		ConfirmPending(now)
	else
		if move.pendingSince then
			Record("MD", now - move.pendingSince)
			move.pendingSince = nil
		end
		move.ground = false
	end
	Resolve(now)
end

function ns.PollMovement(now)
	ExpireHasteBuffs(now)
	PollFalling(now)
	PollControl()
	if move.events > 0 then
		move.known = true
		move.source = "events"
		ConfirmPending(now)
		Resolve(now)
		return
	end

	local speed = ReadSpeed()
	if speed == nil and ReadFalling() == nil then
		move.source = "nothing"
		return
	end

	move.known = true
	move.source = "speed"
	move.ground = speed ~= nil and speed > 0
	Resolve(now)
end

function ns.MovementKnown()
	return move.known
end

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

function ns.Window(now)
	local extra = (ns.db and ns.db.windowExtra or 0) / 1000
	local ping = AddPingEnabled() and ns.latency or 0
	return math.max(T.MIN_WINDOW, ns.Windup(now) + ping + extra)
end

function ns.Windup(now)
	if not HasteWindup() then
		return T.NEED
	end
	return T.NEED * EffectiveRatio(now or GetTime())
end

function ns.NextAttempt(firstAttempt, stop)
	local reach = stop and (stop + StopLead()) or nil
	local last = timing.failLast
	if last and last >= firstAttempt - T.FAILURE_EARLY then
		local firstRetryAfterStop = last + T.RETRY
		if reach and reach > firstRetryAfterStop then
			firstRetryAfterStop = firstRetryAfterStop + math.ceil((reach - firstRetryAfterStop) / T.RETRY) * T.RETRY
		end
		return firstRetryAfterStop
	end
	if reach and reach > firstAttempt then
		return firstAttempt + math.ceil((reach - firstAttempt) / T.RETRY) * T.RETRY
	end
	return firstAttempt
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

function ns.Need(demo, now)
	if demo then
		return ns.Window(now), false, 0
	end
	local samples = ns.db and ns.db.calib and ns.db.calib.stand or {}
	local count = #samples
	if count >= T.CALIB_MIN then
		local median = ns.MedianStand()
		if median then
			local extra = (ns.db.windowExtra or 0) / 1000
			local ratio = HasteWindup() and EffectiveRatio(now or GetTime()) or 1
			return math.max(T.MIN_WINDOW, median * ratio + extra), true, count
		end
	end
	return ns.Window(now), false, count
end

function ns.Phase(now, demo)
	local cycle
	local need
	if demo then
		cycle = T.DEMO_CYCLE
		need = ns.Window(now)
	else
		cycle = EffectiveCycle(now)
		need = ns.Need(false, now)
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

function ns.StandStill(now, cycle, need, demo)
	if demo then
		return nil
	end
	if not move.known or not move.stillSince then
		return nil
	end
	local grace = false
	if move.moving then
		if not move.movingSince or move.movingSince < move.stillSince then
			return nil
		end
		local saved = move.moving
		move.moving = false
		local shot = ns.StandStill(move.movingSince, cycle, need, demo)
		move.moving = saved
		local graceWindow = T.STOP_GRACE + (AddPingEnabled() and ns.latency or 0)
		if not shot or move.movingSince < shot - graceWindow or now > shot then
			return nil
		end
		grace = true
	end
	local origin = CycleOrigin(now)
	local start, shotTime
	local pushed = false
	if RetryModel() then
		local windup = ns.Windup(now)
		if timing.pressWindupAt and now - timing.pressWindupAt <= windup + T.PRESS_WINDUP_GRACE then
			start = timing.pressWindupAt
			shotTime = start + windup
		elseif timing.autoStartAt and origin + cycle <= timing.autoStartAt then
			local firstAttempt = timing.autoStartAt
			local nextAttempt = ns.NextAttempt(firstAttempt, move.stillSince)
			pushed = nextAttempt > move.stillSince
			start = math.max(move.stillSince, nextAttempt)
			local extra = (nextAttempt == firstAttempt and AddPingEnabled()) and ns.latency or 0
			shotTime = start + windup + extra
		else
			local nextAttempt = ns.NextAttempt(origin + cycle - windup, move.stillSince)
			pushed = nextAttempt > move.stillSince
			start = math.max(move.stillSince, nextAttempt)
			shotTime = start + windup
		end
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

local function HealUnreportedStop(now)
	local shotFiredWhileMarkedMoving = timing.lastShot and move.moving and move.known
	local noMovementEventSinceLastShot = move.events == timing.eventsAtShot
	if shotFiredWhileMarkedMoving and noMovementEventSinceLastShot then
		move.moving = false
		move.ground = false
		move.airborne = false
		move.cc = false
		move.jumpAt = nil
		move.pendingSince = nil
		move.stillSince = now
		timing.moved = true
	end
end

function ns.OnRangedSwing(duration)
	local db = ns.db
	if not db then
		return
	end
	local now = GetTime()
	ExpireHasteBuffs(now)
	local reported = ns.PlainNumber(duration)
	local speed = timing.speed
	if reported and reported > 0 and reported <= T.MAX_SWING then
		speed = reported
	end

	HealUnreportedStop(now)

	local previous = timing.lastShot
	local previousSpeed = timing.speed
	local previousWindup = ns.Windup(now)
	local previousRatio = HasteWindup() and EffectiveRatio(now) or 1
	local previousUnhasted = Unhasted(timing.lastRatio)
		and not timing.rfHasted and not timing.qsHasted and HasteDelta(now) == 1
	local gap = previous and (now - previous) or nil

	if previous and previousSpeed and not timing.broken and not timing.heldUp
		and #timing.haste == 0 and not ns.demoActive and previousUnhasted
		and move.known and not move.moving and move.stillSince and gap then
		local need = ns.Need(false, now)
		local stopBefore = (previous + previousSpeed) - move.stillSince
		local measured
		if RetryModel() then
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
	timing.ratio = hasteRatio or 1
	timing.lastRatio = hasteRatio
	RememberRatio(hasteRatio)

	if timing.qsEnd > 0 and timing.qsBaseSpeed and now > timing.qsProcAt then
		local baseQS = timing.qsBaseSpeed
		timing.qsBaseSpeed = nil
		if speed and speed > baseQS / T.QS_CONFIRM then
			timing.qsEnd = 0
			Record("HT", "qs_false", hasteRatio)
		end
	end

	local rfJustEnded = timing.rfHasted and (timing.rfEnd == 0 or now >= timing.rfEnd)
	if timing.qsHasted and timing.qsEnd > 0 and now < timing.qsEnd and previousSpeed and speed
		and speed > previousSpeed * T.QS_CONFIRM and not rfJustEnded then
		timing.qsEnd = 0
		Record("HT", "qs_early_end", hasteRatio)
	end

	timing.rfHasted = timing.rfEnd > 0 and now < timing.rfEnd
	timing.qsHasted = timing.qsEnd > 0 and now < timing.qsEnd
	timing.windupShift = 0

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

	timing.prevSpeed = previousSpeed
	timing.lastShot = now
	if speed then
		timing.speed = speed
	end
	timing.cycleStart = now
	timing.cycleOverride = nil
	timing.autoStartAt = nil
	timing.feignArmed = false
	timing.running = true
	timing.broken = false
	timing.heldUp = false
	timing.moved = false
	timing.haste = {}
	timing.eventsAtShot = move.events
	timing.failCount = 0
	timing.failLast = nil
	timing.failUndo = nil
	ClearPressWindup()

	if timing.auraAt == now then
		OnQuickShotsProc(now, previousSpeed, speed)
	end
end

function ns.OnMeleeSwing(duration)
	local now = GetTime()
	timing.lastMelee = now
	local reported = ns.PlainNumber(duration)
	if reported and reported > 0 and reported <= T.MAX_SWING then
		timing.meleeSpeed = reported
	end
	timing.feignArmed = false
	timing.broken = true
	if MeleeResets() and timing.speed then
		timing.cycleStart = now
		timing.cycleOverride = nil
		timing.autoStartAt = nil
		timing.windupShift = 0
		timing.failCount = 0
		timing.failLast = nil
		ClearPressWindup()
	end
end

function ns.OnSpellSent(guid, spellID, now)
	if ns.PlainNumber(spellID) ~= T.SPELL_ID then
		return
	end
	local key = PlainString(guid)
	if not key then
		return
	end
	now = now or GetTime()
	for id, sentAt in pairs(timing.pressIDs) do
		if now - sentAt > T.PRESS_KEEP then
			timing.pressIDs[id] = nil
		end
	end
	timing.pressIDs[key] = now
	if not move.moving and not Channeling(now) and not NoLivingTarget() then
		local active = timing.pressWindupAt and now - timing.pressWindupAt <= ns.Windup(now) + T.PRESS_WINDUP_GRACE
		if not active then
			timing.pressWindupAt = now
			timing.pressWindupGuid = key
		end
	end
end

function ns.OnCastStart(guid, spellID, now)
	now = now or GetTime()
	timing.feignArmed = false
	if IsAimedSpell(spellID) then
		move.aimKey = PlainString(guid) or true
		move.aimAt = now
	end
end

function ns.OnCastEnd(guid, spellID, interrupted, now)
	now = now or GetTime()
	local key = PlainString(guid)
	if move.aimKey and IsAimedSpell(spellID) then
		local match = key or true
		if match == true or move.aimKey == true or match == move.aimKey then
			move.aimKey = nil
		end
	end
	if interrupted and ns.PlainNumber(spellID) == T.SPELL_ID then
		if key and key == timing.pressWindupGuid then
			ClearPressWindup()
		end
		if key and timing.pressIDs[key] then
			return
		end
		if key then
			if key == timing.lastInterruptGuid then
				return
			end
			timing.lastInterruptGuid = key
		end
		if move.moving and move.movingSince then
			local sinceMove = now - move.movingSince
			if sinceMove >= T.INTERRUPT_MIN_LAG and sinceMove <= 0.6 then
				if not timing.failLast or timing.failLast < move.movingSince then
					timing.failLast = now
					Record("CR", T.SPELL_ID, now)
				end
			end
		end
	end
end

function ns.OnSpellSucceeded(spellID, guid, now)
	now = now or GetTime()
	ns.OnCastEnd(guid, spellID, false, now)
	if IsFeignSpell(spellID) and FeignResets() and timing.speed then
		timing.cycleStart = now
		timing.cycleOverride = nil
		timing.autoStartAt = nil
		timing.windupShift = 0
		timing.failCount = 0
		timing.failLast = nil
		ClearPressWindup()
		timing.broken = true
	end
	if IsRapidFireSpell(spellID) then
		timing.rfEnd = now + T.RF_DURATION
		UpdateWindupShift(now)
		Record("HT", "rf_start", EffectiveRatio(now))
	end
end

function ns.OnChannelState(active, now)
	now = now or GetTime()
	timing.channelAt = active and now or nil
end

local function OnlyRemovedAuras(info)
	local full = info.isFullUpdate
	local added = info.addedAuras
	local updated = info.updatedAuraInstanceIDs
	local removed = info.removedAuraInstanceIDs
	if ns.IsSecret(full) or ns.IsSecret(added) or ns.IsSecret(updated) or ns.IsSecret(removed) then
		return false
	end
	return not full and added == nil and updated == nil and removed ~= nil
end

function ns.OnPlayerAura(updateInfo, now)
	if type(updateInfo) == "table" then
		local ok, removedOnly = pcall(OnlyRemovedAuras, updateInfo)
		if ok and removedOnly == true then
			return
		end
	end
	now = now or GetTime()
	timing.auraAt = now
	if timing.lastShot == now then
		OnQuickShotsProc(now, timing.prevSpeed, timing.speed)
	end
end

function ns.OnErrorMessage(now, first, second)
	local kind = ns.ClassifyError(first, second)
	if not kind then
		return
	end
	now = now or GetTime()
	timing.blockErrAt = now
	timing.blockErrKind = kind
	if not move.moving and timing.failLast and now - timing.failLast <= T.BLOCK_NEAR then
		timing.heldUp = true
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
	timing.cycleOverride = nil
	timing.windupShift = 0
	timing.broken = true
end

function ns.SetAutoRepeat(running, now)
	now = now or GetTime()
	if running then
		local sameFrameFlip = (now == timing.lastAutoStopAt) and timing.onBeforeStop
		local flicker = timing.autoOffAt and (now - timing.autoOffAt < T.AUTO_FLICKER) and timing.onBeforeStop
		timing.running = true
		timing.autoRepeat = true
		if not sameFrameFlip and not flicker then
			timing.broken = true
			local cycle = EffectiveCycle(now)
			if not cycle or now >= CycleOrigin(now) + cycle then
				timing.autoStartAt = now
			end
		end
	else
		if timing.failUndo and timing.failUndo.at == now then
			timing.failCount = timing.failUndo.count
			timing.failLast = timing.failUndo.last
			timing.failUndo = nil
		end
		timing.onBeforeStop = timing.autoRepeat
		timing.lastAutoStopAt = now
		timing.autoOffAt = now
		timing.autoStartAt = nil
		timing.running = false
		timing.autoRepeat = false
		ClearPressWindup()
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
