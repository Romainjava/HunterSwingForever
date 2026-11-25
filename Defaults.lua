local ADDON, ns = ...

ns.addonName = ADDON
ns.fontDir = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Fonts\\"

local DEFAULTS = {
	width = 220,
	barHeight = 10,
	fontSize = 12,
	smallFontSize = 10,
	font = "Fonts\\2002B.ttf",
	outline = "",
	layout = "standard",
	texture = "Interface\\Buttons\\WHITE8X8",
	gradient = true,
	opacity = 100,
	windowExtra = 0,
	addPing = true,
	showStatus = true,
	showCountdown = true,
	showSpeed = true,
	showSpark = true,
	showFlash = true,
	showBorder = true,
	showShots = true,
	showMelee = true,
	showStandBar = true,
	ammoDisplay = "percent",
	rangeEnabled = true,
	rangeText = true,
	rangeCombatOnly = false,
	rangeWhenIdle = true,
	rangePosition = "belowRight",
	rangeDistance = "bracket",
	retryModel = true,
	meleeResetsRanged = true,
	hasteWindup = true,
	feignResetsRanged = true,
	vendorPins = true,
	vendorMinimap = true,
	vendorContinent = true,
	vendorNeutral = true,
	vendorOtherFaction = false,
	vendorAmmo = "weapon",
	colors = {
		move = { 0.36, 0.82, 0.47, 1 },
		stand = { 0.96, 0.40, 0.29, 1 },
		zone = { 0.42, 0.11, 0.08, 0.9 },
		track = { 0.07, 0.07, 0.08, 0.88 },
		text = { 0.95, 0.95, 0.95, 1 },
		melee = { 1.00, 0.78, 0.30, 1 },
	},
	configVersion = 6,
	calib = { stand = {}, early = {}, missed = {} },
	shotLog = {},
}
ns.DEFAULTS = DEFAULTS

local MEASURE_MAX = 9
local LOG_MAX = 40

local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in pairs(value) do
		out[key] = Copy(inner)
	end
	return out
end
ns.Copy = Copy

local function EqualsWithoutError(value, expected)
	return pcall(function()
		return value == expected
	end)
end

function ns.IsSecret(value)
	local checker = rawget(_G, "issecretvalue")
	if type(checker) ~= "function" then
		return false
	end
	local checked, result = pcall(checker, value)
	if not checked then
		return true
	end
	local comparable, secret = EqualsWithoutError(result, true)
	if not comparable then
		return true
	end
	return secret
end

function ns.PlainNumber(value)
	if value == nil or ns.IsSecret(value) then
		return nil
	end
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value then
		return nil
	end
	return value
end

function ns.PlainTrue(value)
	if value == nil or ns.IsSecret(value) then
		return nil
	end
	if value == true or value == 1 then
		return true
	end
	if value == false or value == 0 then
		return false
	end
	return nil
end

function ns.SafeCall(func, ...)
	if type(func) ~= "function" then
		return false, nil
	end
	return pcall(func, ...)
end

function ns.Describe(value, ok, ...)
	if not ok then
		return "error: " .. tostring(value)
	end
	if value == nil then
		return "missing"
	end
	if ns.IsSecret(value) then
		return "secret"
	end
	return tostring(value)
end

function ns.DescribeCall(func, ...)
	if type(func) ~= "function" then
		return "missing"
	end
	local ok, first = pcall(func, ...)
	return ns.Describe(first, ok)
end

local CHAT_PREFIX = "|cffabd473Hunter Swing Forever|r "

function ns.Print(message)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(message))
	end
end

function ns.PrintLine(message)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage("  " .. tostring(message))
	end
end

ns.FONTS = {
	{ label = "2002 Bold", value = "Fonts\\2002B.ttf" },
	{ label = "2002", value = "Fonts\\2002.TTF" },
	{ label = "Arial Narrow", value = "Fonts\\ARIALN.TTF" },
	{ label = "Friz Quadrata", value = "Fonts\\FRIZQT__.TTF" },
	{ label = "Skurri", value = "Fonts\\skurri.ttf" },
	{ label = "Nimrod", value = "Fonts\\NIM_____.ttf" },
	{ label = "Morpheus", value = "Fonts\\MORPHEUS.TTF" },
	{ label = "Barlow Condensed", value = ns.fontDir .. "BarlowCondensed-SemiBold.ttf" },
	{ label = "Barlow Condensed Bold", value = ns.fontDir .. "BarlowCondensed-Bold.ttf" },
	{ label = "Bebas Neue", value = ns.fontDir .. "BebasNeue-Regular.ttf" },
	{ label = "Chakra Petch", value = ns.fontDir .. "ChakraPetch-Bold.ttf" },
	{ label = "Rajdhani", value = ns.fontDir .. "Rajdhani-Bold.ttf" },
	{ label = "Russo One", value = ns.fontDir .. "RussoOne-Regular.ttf" },
	{ label = "Saira Condensed", value = ns.fontDir .. "SairaCondensed-Bold.ttf" },
	{ label = "Share Tech Mono", value = ns.fontDir .. "ShareTechMono-Regular.ttf" },
	{ label = "Titillium Web", value = ns.fontDir .. "TitilliumWeb-Bold.ttf" },
}

ns.FALLBACK_FONT = ns.FONTS[1].value

ns.OUTLINES = {
	{ label = "Shadow", value = "" },
	{ label = "Outline", value = "OUTLINE" },
	{ label = "Thick outline", value = "THICKOUTLINE" },
}

ns.LAYOUTS = {
	{ label = "Horizontal, text above", value = "standard" },
	{ label = "Horizontal, one row", value = "row" },
	{ label = "Vertical", value = "vertical" },
}

ns.TEXTURES = {
	{ label = "Flat", value = "Interface\\Buttons\\WHITE8X8" },
	{ label = "Blizzard", value = "Interface\\TargetingFrame\\UI-StatusBar" },
	{ label = "Raid", value = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}

ns.RANGE_POSITIONS = {
	{ label = "Below, right", value = "belowRight" },
	{ label = "Below, left", value = "belowLeft" },
	{ label = "Right of bar", value = "right" },
	{ label = "Left of bar", value = "left" },
}

ns.DISTANCE_MODES = {
	{ label = "Off", value = "off" },
	{ label = "Range (20-25 yd)", value = "bracket" },
	{ label = "Number (~23 yd)", value = "estimate" },
}

ns.AMMO_MODES = {
	{ label = "Off", value = "off" },
	{ label = "Percent (62%)", value = "percent" },
	{ label = "Count (1234)", value = "count" },
}

ns.VENDOR_AMMO_MODES = {
	{ label = "Match my weapon", value = "weapon" },
	{ label = "Arrows and bullets", value = "both" },
	{ label = "Arrows only", value = "arrow" },
	{ label = "Bullets only", value = "bullet" },
}

function ns.ChoiceLabel(list, value)
	for _, entry in ipairs(list) do
		if entry.value == value then
			return entry.label
		end
	end
	return list[1] and list[1].label or ""
end

function ns.ChoiceIndex(list, value)
	for index, entry in ipairs(list) do
		if entry.value == value then
			return index
		end
	end
	return 1
end

function ns.NextChoice(list, value, step)
	local index = ns.ChoiceIndex(list, value) + (step or 1)
	if index > #list then
		index = 1
	elseif index < 1 then
		index = #list
	end
	return list[index].value, list[index].label
end

function ns.FontPath(value)
	for _, entry in ipairs(ns.FONTS) do
		if entry.value == value then
			return entry.value
		end
	end
	return ns.FALLBACK_FONT
end

local function IsFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function CleanMeasures(list)
	local out = {}
	if type(list) == "table" then
		for _, value in ipairs(list) do
			if IsFiniteNumber(value) and value > -1 and value < 2 then
				out[#out + 1] = value
			end
		end
	end
	while #out > MEASURE_MAX do
		table.remove(out, 1)
	end
	return out
end

local function CleanShotLog(list)
	local out = {}
	if type(list) == "table" then
		for _, row in ipairs(list) do
			if type(row) == "table" and IsFiniteNumber(row.t) then
				if not (IsFiniteNumber(row.failed) and row.failed >= 0) then
					row.failed = 0
				end
				if not (IsFiniteNumber(row.failedAgo) and row.failedAgo >= 0) then
					row.failedAgo = nil
				end
				if not (IsFiniteNumber(row.hasteRatio) and row.hasteRatio > 0 and row.hasteRatio < 4) then
					row.hasteRatio = nil
				end
				out[#out + 1] = row
			end
		end
	end
	while #out > LOG_MAX do
		table.remove(out, 1)
	end
	return out
end

local function Merge(saved, defaults)
	for key, def in pairs(defaults) do
		local have = saved[key]
		if type(def) == "table" then
			if type(have) == "table" then
				Merge(have, def)
			else
				saved[key] = Copy(def)
			end
		elseif type(have) ~= type(def) then
			saved[key] = def
		end
	end
end
ns.MergeDefaults = Merge

function ns.ResetMedian()
	ns.medianCache = { count = -1, newest = nil, value = nil }
end

function ns.LoadSaved()
	if type(HunterSwingForeverDB) ~= "table" then
		HunterSwingForeverDB = {}
	end
	local db = HunterSwingForeverDB

	local version = tonumber(db.configVersion) or 1
	if version < 2 then
		if db.font == "Fonts\\ARIALN.TTF" then
			db.font = DEFAULTS.font
		end
	end
	if version < 3 then
		if db.ammoDisplay == "count" then
			db.ammoDisplay = "percent"
		end
	end
	if version < 4 then
		db.vendorAlliance = nil
		db.vendorHorde = nil
	end
	if version < 5 then
		if type(db.calib) == "table" then
			db.calib.stand = {}
		end
	end
	if version < 6 then
		if type(db.calib) == "table" then
			db.calib.stand = {}
		end
	end

	Merge(db, DEFAULTS)
	db.configVersion = 6

	local calib = db.calib
	db.calib = {
		stand = CleanMeasures(calib.stand),
		early = CleanMeasures(calib.early),
		missed = CleanMeasures(calib.missed),
	}
	db.shotLog = CleanShotLog(db.shotLog)

	ns.db = db
	ns.ResetMedian()
end

function ns.ResetSaved()
	local old = ns.db or {}
	local keepPoint = old.point
	local keepCalib = ns.Copy(old.calib or DEFAULTS.calib)
	local keepLog = ns.Copy(old.shotLog or {})

	local db = {}
	Merge(db, DEFAULTS)
	db.configVersion = 6
	db.point = keepPoint
	db.calib = { stand = CleanMeasures(keepCalib.stand), early = CleanMeasures(keepCalib.early), missed = CleanMeasures(keepCalib.missed) }
	db.shotLog = CleanShotLog(keepLog)

	HunterSwingForeverDB = db
	ns.db = db
	ns.ResetMedian()
end

function ns.Colour(key)
	local colour = ns.db and ns.db.colors and ns.db.colors[key]
	if type(colour) == "table" then
		return colour[1] or 1, colour[2] or 1, colour[3] or 1, colour[4] or 1
	end
	return 1, 1, 1, 1
end
