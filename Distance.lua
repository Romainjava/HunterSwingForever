local ADDON, ns = ...

local range = {
	state = nil,
	held = nil,
	pending = nil,
	pendingSince = 0,
	last = 0,
	lastError = nil,
	lo = nil,
	hi = nil,
	distance = nil,
	report = {},
}
ns.range = range

local RANGE_WORDS = {
	["in"] = "In range",
	close = "Too close",
	far = "Out of range",
}
ns.RANGE_WORDS = RANGE_WORDS

local RANGE_COLOURS = {
	["in"] = { 0.36, 0.82, 0.47 },
	close = { 1.00, 0.66, 0.20 },
	far = { 0.96, 0.40, 0.29 },
}
ns.RANGE_COLOURS = RANGE_COLOURS

local DISTANCE_STEPS = {
	{ 5, { 8149, 15826, 16308, 17117 } },
	{ 10, { 9606, 9618, 9619, 9620 } },
	{ 15, { 4559 } },
	{ 20, { 1191, 2012, 4388, 10645 } },
	{ 25, { 13289 } },
	{ 30, { 835, 1404, 1434, 1444 } },
	{ 35, { 1258, 1399, 1402, 8688 } },
	{ 40, { 4945, 8348 } },
	{ 45, { 221316 } },
	{ 100, { 5418, 17162, 23715, 23718 } },
}
ns.DISTANCE_STEPS = DISTANCE_STEPS

function ns.InCombat()
	local ok, value = ns.SafeCall(UnitAffectingCombat, "player")
	if not ok then
		return false
	end
	return ns.PlainTrue(value) == true
end

function ns.RequestDistanceItems()
	local loader = C_Item and C_Item.RequestLoadItemDataByID
	if type(loader) ~= "function" then
		return
	end
	for _, step in ipairs(DISTANCE_STEPS) do
		for _, itemID in ipairs(step[2]) do
			pcall(loader, itemID)
		end
	end
end

local function ItemInRange(itemID)
	local func = (C_Item and C_Item.IsItemInRange) or _G.IsItemInRange
	if type(func) ~= "function" then
		return nil
	end
	local ok, value = pcall(func, itemID, "target")
	if not ok or value == nil or ns.IsSecret(value) then
		return nil
	end
	if value == true or value == 1 then
		return true
	end
	return false
end

function ns.ComputeBracket(state)
	local lo, hi = 0, nil
	for _, step in ipairs(DISTANCE_STEPS) do
		local yards = step[1]
		local answer
		for _, itemID in ipairs(step[2]) do
			answer = ItemInRange(itemID)
			if answer ~= nil then
				break
			end
		end
		if answer == true and hi == nil then
			hi = yards
		end
		if answer == false and (hi == nil or yards < hi) and yards > lo then
			lo = yards
		end
	end
	if hi == 100 then
		hi = nil
	end
	if state == "close" then
		hi = 8
		lo = math.min(lo, 5)
	end
	if state == "in" then
		lo = math.max(lo, 8)
		if hi and hi <= 8 then
			hi = 10
		end
	end
	if lo == 0 and hi == nil then
		return nil, nil
	end
	if hi and lo >= hi then
		lo = hi - 5
	end
	return lo, hi
end

function ns.FormatDistance(state, lo, hi)
	local mode = ns.db and ns.db.rangeDistance or "bracket"
	if mode == "off" or not lo then
		return nil
	end
	if not hi then
		return string.format("%d+ yd", lo)
	end
	if mode == "estimate" then
		return string.format("~%d yd", math.floor((lo + hi) / 2 + 0.5))
	end
	return string.format("%d-%d yd", lo, hi)
end

local function Ask(func, ...)
	if type(func) ~= "function" then
		return nil
	end
	local ok, value = pcall(func, ...)
	if not ok then
		range.lastError = tostring(value)
		return nil
	end
	if value == nil or ns.IsSecret(value) then
		return nil
	end
	return value
end

local function CombatSafeInRange()
	local api = C_SwingTimer
	local func = api and api.IsTargetWithinSwingRange
	if type(func) ~= "function" then
		return nil
	end
	local types = Enum and Enum.PlayerSwingType
	local ranged = types and types.Ranged
	if ranged == nil then
		return nil
	end
	local ok, value = pcall(func, ranged)
	if not ok or value == nil or ns.IsSecret(value) then
		return nil
	end
	if value == true then
		return true
	end
	if value == false then
		return false
	end
	return nil
end

function ns.UpdateRange(now)
	local db = ns.db
	if not db then
		return
	end
	if now - range.last < 0.1 then
		return
	end
	range.last = now

	local report = {}
	range.report = report

	local okExists, exists = ns.SafeCall(UnitExists, "target")
	report.exists = ns.Describe(exists, okExists)
	local okDead, dead = ns.SafeCall(UnitIsDeadOrGhost, "target")
	report.dead = ns.Describe(dead, okDead)
	local okAttack, canAttack = ns.SafeCall(UnitCanAttack, "player", "target")
	report.canAttack = ns.Describe(canAttack, okAttack)

	local function Hide()
		range.state = nil
		range.distance = nil
	end

	if not ns.isHunter or not db.rangeEnabled then
		Hide()
		return
	end
	if db.rangeCombatOnly and not ns.InCombat() then
		Hide()
		return
	end
	if ns.IsSecret(exists) or exists ~= true then
		Hide()
		return
	end
	if ns.IsSecret(dead) or dead ~= false then
		Hide()
		return
	end
	if not okAttack then
		Hide()
		return
	end
	if not ns.IsSecret(canAttack) then
		if canAttack ~= true and canAttack ~= 1 then
			Hide()
			return
		end
	end

	local swing = CombatSafeInRange()

	local state
	if swing == true then
		state = "in"
	else
		local answer = Ask(C_Spell and C_Spell.IsSpellInRange, ns.T.SPELL_ID, "target")
		if answer == nil then
			answer = Ask(C_Spell and C_Spell.IsSpellInRange, "Auto Shot", "target")
		end
		if answer == nil then
			answer = Ask(_G.IsSpellInRange, "Auto Shot", "target")
		end

		if answer == true or answer == 1 then
			state = "in"
		elseif swing == false or answer == false or answer == 0 then
			local interact = Ask(_G.CheckInteractDistance, "target", 3)
			if interact == true or interact == 1 then
				state = "close"
			else
				state = "far"
			end
		end
	end

	range.state = state
	if state and db.rangeDistance ~= "off" then
		range.lo, range.hi = ns.ComputeBracket(state)
		range.distance = ns.FormatDistance(state, range.lo, range.hi)
	else
		range.lo, range.hi, range.distance = nil, nil, nil
	end

	if state == "close" or state == "far" then
		ns.timing.heldUp = true
	end

	if range.held == state then
		range.pending = state
		range.pendingSince = now
	elseif range.pending ~= state then
		range.pending = state
		range.pendingSince = now
	elseif now - range.pendingSince >= 0.2 then
		range.held = state
	end
end

function ns.ReportRange()
	ns.Print("Range check:")

	local report = range.report or {}
	ns.PrintLine("target exists = " .. (report.exists or "missing"))
	ns.PrintLine("target dead = " .. (report.dead or "missing"))
	ns.PrintLine("can attack = " .. (report.canAttack or "missing"))
	ns.PrintLine("C_Spell id 75 = " .. ns.DescribeCall(C_Spell and C_Spell.IsSpellInRange, ns.T.SPELL_ID, "target"))
	ns.PrintLine("C_Spell 'Auto Shot' = " .. ns.DescribeCall(C_Spell and C_Spell.IsSpellInRange, "Auto Shot", "target"))
	ns.PrintLine("IsSpellInRange 'Auto Shot' = " .. ns.DescribeCall(_G.IsSpellInRange, "Auto Shot", "target"))
	ns.PrintLine("within ~10 yd = " .. ns.DescribeCall(_G.CheckInteractDistance, "target", 3))
	ns.PrintLine("result = " .. tostring(range.state))
	if range.lastError then
		ns.PrintLine("last error = " .. range.lastError)
	end
end
