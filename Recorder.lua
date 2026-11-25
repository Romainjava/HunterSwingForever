local ADDON, ns = ...

local MAX_LINES = 40000
local RANGE_POLL = 0.1

local recorder = CreateFrame("Frame")
local lastRange = "unset"
local sinceRangePoll = 0

local function Field(value)
	if value == nil then
		return "-"
	end
	if type(value) == "number" then
		local plain = ns.PlainNumber(value)
		return plain and string.format("%.3f", plain) or "?"
	end
	if type(value) == "boolean" then
		return value and "1" or "0"
	end
	if ns.IsSecret(value) then
		return "?"
	end
	return tostring(value)
end

local function Recording()
	return ns.db and ns.db.recording == true
end

local function StopRecorder()
	recorder:SetScript("OnUpdate", nil)
end

local function Log(kind, ...)
	if not Recording() then
		return
	end
	local log = ns.db.recordLog
	if #log >= MAX_LINES then
		ns.db.recording = false
		StopRecorder()
		ns.Print(string.format("Recording stopped: the log is full (%d lines). /reload, send it, then /hsf record clear.", MAX_LINES))
		return
	end
	local parts = { string.format("%.3f", GetTime()), kind }
	for index = 1, select("#", ...) do
		parts[#parts + 1] = Field((select(index, ...)))
	end
	log[#log + 1] = table.concat(parts, "|")
end

local function RangedSpeed()
	local ok, speed = ns.SafeCall(UnitRangedDamage, "player")
	return ok and ns.PlainNumber(speed) or nil
end

local function LogPrediction(reason)
	if not Recording() then
		return
	end
	local now = GetTime()
	local phase = ns.Phase(now)
	if not phase then
		return
	end
	local shot, start = ns.StandStill(now, phase.cycle, phase.need)
	local timing = ns.timing
	Log("P", reason, phase.phase, shot, start, phase.need, ns.Windup(), phase.cycle,
		timing.cycleStart, timing.ratio, ns.latency)
end

local function LogPredictionNextFrame(reason)
	C_Timer.After(0, function()
		LogPrediction(reason)
	end)
end

local function PollRange(_, elapsed)
	sinceRangePoll = sinceRangePoll + elapsed
	if sinceRangePoll < RANGE_POLL then
		return
	end
	sinceRangePoll = 0
	local state = ns.range and ns.range.state
	local current = state == nil and "unknown" or tostring(state)
	if current ~= lastRange then
		lastRange = current
		Log("RG", current)
	end
end

local function StartRecorder()
	lastRange = "unset"
	sinceRangePoll = 0
	recorder:SetScript("OnUpdate", PollRange)
	local db = ns.db
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
	Log("START", version, date("%Y-%m-%d %H:%M:%S"), ns.latency, RangedSpeed(), ns.WeaponBaseSpeed(),
		db.retryModel, db.meleeResetsRanged, db.hasteWindup, db.feignResetsRanged, db.addPing, db.windowExtra)
end

local HANDLERS = {
	PLAYER_SWING = function(duration, swingType)
		Log("SW", swingType, duration)
		LogPredictionNextFrame("swing")
	end,
	UNIT_SPELLCAST_FAILED_QUIET = function(unit, _, spellID)
		if unit == "player" then
			Log("FQ", spellID)
		end
	end,
	UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
		if unit == "player" then
			Log("CS", spellID)
		end
	end,
	PLAYER_STARTED_MOVING = function()
		Log("MV", 1)
	end,
	PLAYER_STOPPED_MOVING = function()
		Log("MV", 0)
		LogPredictionNextFrame("stop")
	end,
	UNIT_RANGEDDAMAGE = function(unit)
		if unit == "player" then
			Log("HS", "R", RangedSpeed())
		end
	end,
	UNIT_ATTACK_SPEED = function(unit)
		if unit == "player" then
			Log("HS", "A", RangedSpeed())
		end
	end,
	START_AUTOREPEAT_SPELL = function()
		Log("AR", 1)
	end,
	STOP_AUTOREPEAT_SPELL = function()
		Log("AR", 0)
	end,
	PLAYER_REGEN_DISABLED = function()
		Log("CB", 1)
	end,
	PLAYER_REGEN_ENABLED = function()
		Log("CB", 0)
	end,
	PLAYER_TARGET_CHANGED = function()
		Log("TG")
	end,
	PLAYER_LOGIN = function()
		if Recording() then
			StartRecorder()
			ns.Print(string.format("Recording is on (%d lines). /hsf record off to stop.", #ns.db.recordLog))
		end
	end,
}

for event in pairs(HANDLERS) do
	pcall(recorder.RegisterEvent, recorder, event)
end

recorder:SetScript("OnEvent", function(_, event, ...)
	if event ~= "PLAYER_LOGIN" and not Recording() then
		return
	end
	HANDLERS[event](...)
end)

if type(hooksecurefunc) == "function" and type(JumpOrAscendStart) == "function" then
	pcall(hooksecurefunc, "JumpOrAscendStart", function()
		Log("JP")
	end)
end

function ns.Record(subcommand)
	local db = ns.db
	if subcommand == "on" then
		if Recording() then
			ns.Print(string.format("Already recording (%d lines).", #db.recordLog))
			return
		end
		db.recording = true
		StartRecorder()
		ns.Print(string.format("Recording on (%d lines so far). Play, then /hsf record off and /reload.", #db.recordLog))
	elseif subcommand == "off" then
		if Recording() then
			Log("STOP")
		end
		db.recording = false
		StopRecorder()
		ns.Print(string.format("Recording off: %d lines. /reload or log out to save them.", #db.recordLog))
	elseif subcommand == "clear" then
		db.recordLog = {}
		ns.Print("Recording log cleared.")
	else
		ns.Print(string.format("Recording is %s: %d lines. /hsf record on | off | clear",
			Recording() and "on" or "off", #db.recordLog))
	end
end
