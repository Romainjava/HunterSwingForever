-- Hunter Swing Forever by Illusion
-- Unit 9: the bar (frames, per-frame update, events, slash command).
local ADDON, ns = ...

local GAP = 4
local GREY = { 0.42, 0.43, 0.46, 0.8 }
local MUTED = { 0.62, 0.64, 0.67, 1 }

local bar = {
	mode = "auto",
	locked = true,
	flashAlpha = 0,
	fillKey = nil,
	parts = {
		timer = { alpha = 0, target = 0, arrived = true },
		range = { alpha = 0, target = 0, arrived = true },
	},
}
ns.bar = bar

local function Colour(key)
	local r, g, b, a = ns.Colour(key)
	return { r, g, b, a }
end

local function Smooth(t)
	return t * t * (3 - 2 * t)
end

---------------------------------------------------------------------------
-- Small drawing helpers
---------------------------------------------------------------------------

local function Solid(parent, layer, subLevel)
	local texture
	if subLevel then
		texture = parent:CreateTexture(nil, layer, nil, subLevel)
	else
		texture = parent:CreateTexture(nil, layer)
	end
	if type(texture.SetColorTexture) == "function" then
		texture:SetColorTexture(1, 1, 1, 1)
	else
		texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	end
	return texture
end

local function Tint(texture, r, g, b, a)
	if type(texture.SetVertexColor) ~= "function" then
		return
	end
	local key = string.format("%.3f %.3f %.3f %.3f", r or 1, g or 1, b or 1, a or 1)
	if texture.hsfTint == key then
		return
	end
	texture.hsfTint = key
	texture:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
end

local function SetText(fontString, text)
	if fontString.hsfText ~= text then
		fontString.hsfText = text
		fontString:SetText(text or "")
	end
end

local function SetTextAlpha(fontString, alpha)
	if fontString.hsfAlpha ~= alpha then
		fontString.hsfAlpha = alpha
		fontString:SetAlpha(alpha)
	end
end

local function SetTextColour(fontString, r, g, b, a)
	local key = string.format("%.3f %.3f %.3f %.3f", r, g, b, a or 1)
	if fontString.hsfColour ~= key then
		fontString.hsfColour = key
		fontString:SetTextColor(r, g, b, a or 1)
	end
end

local function ApplyFont(fontString, size)
	local db = ns.db
	local path = ns.FontPath(db.font)
	local ok = pcall(fontString.SetFont, fontString, path, size, db.outline or "")
	if not ok then
		pcall(fontString.SetFont, fontString, ns.FALLBACK_FONT, size, db.outline or "")
	end
	if type(fontString.SetWordWrap) == "function" then
		fontString:SetWordWrap(false)
	end
end

local function UpdateFade(part, show, dt)
	local frame = part.frame
	if not frame then
		return 0
	end
	local target = show and 1 or 0
	if part.arrived and part.target == target then
		return part.alpha
	end
	local rate = math.min(1, (dt or 0) * 14)
	local alpha = (part.alpha or 0) + (target - (part.alpha or 0)) * rate
	if target == 1 and alpha > 0.98 then
		alpha = 1
	elseif target == 0 and alpha < 0.02 then
		alpha = 0
	end
	part.alpha = alpha
	part.target = target
	part.arrived = (alpha == 1 and target == 1) or (alpha == 0 and target == 0)
	if alpha > 0 then
		frame:Show()
		frame:SetAlpha(alpha)
	else
		frame:SetAlpha(0)
		frame:Hide()
	end
	return alpha
end

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------

function ns.BuildBar()
	if bar.frame then
		return
	end
	local db = ns.db

	local root = CreateFrame("Frame", "HunterSwingForeverBar", UIParent)
	bar.frame = root
	root:SetFrameStrata("MEDIUM")
	root:SetSize(220, 47)
	root:SetClampedToScreen(true)
	root:SetMovable(true)
	root:EnableMouse(false)
	root:RegisterForDrag("LeftButton")
	root:SetScript("OnDragStart", function(self)
		if bar.locked then
			return
		end
		self:StartMoving()
	end)
	root:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		ns.SavePosition()
	end)
	root:SetScript("OnUpdate", function(_, elapsed)
		ns.BarOnUpdate(elapsed)
	end)

	local timerPart = CreateFrame("Frame", nil, root)
	timerPart:SetAllPoints(root)
	timerPart:SetAlpha(0)
	timerPart:Hide()
	bar.parts.timer.frame = timerPart

	local rangePart = CreateFrame("Frame", nil, root)
	rangePart:SetSize(1, 10)
	rangePart:SetAlpha(0)
	rangePart:Hide()
	bar.parts.range.frame = rangePart

	-- Main bar -----------------------------------------------------------
	local statusBar = CreateFrame("StatusBar", nil, timerPart)
	statusBar:SetMinMaxValues(0, 1)
	statusBar:SetValue(0)
	bar.statusBar = statusBar

	local track = Solid(timerPart, "BACKGROUND")
	track:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
	track:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
	bar.track = track

	local zone = Solid(timerPart, "BACKGROUND", 1)
	bar.zone = zone

	local divider = Solid(statusBar, "OVERLAY")
	divider:SetAlpha(0.55)
	bar.divider = divider

	local sheen = Solid(statusBar, "OVERLAY")
	sheen:SetAlpha(0.08)
	bar.sheen = sheen

	local spark = statusBar:CreateTexture(nil, "OVERLAY", nil, 2)
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	if type(spark.SetBlendMode) == "function" then
		spark:SetBlendMode("ADD")
	end
	spark:SetVertexColor(1, 1, 1, 0.9)
	bar.spark = spark

	local flash = Solid(statusBar, "OVERLAY", 3)
	if type(flash.SetBlendMode) == "function" then
		flash:SetBlendMode("ADD")
	end
	flash:SetAllPoints(statusBar)
	flash:SetAlpha(0)
	bar.flash = flash

	local borders = {}
	local function Border()
		local texture = Solid(statusBar, "BORDER")
		borders[#borders + 1] = texture
		return texture
	end
	borders.top = Border()
	borders.bottom = Border()
	borders.left = Border()
	borders.right = Border()
	borders.top:SetPoint("BOTTOMLEFT", statusBar, "TOPLEFT", -1, 0)
	borders.top:SetPoint("BOTTOMRIGHT", statusBar, "TOPRIGHT", 1, 0)
	borders.top:SetHeight(1)
	borders.bottom:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", -1, 0)
	borders.bottom:SetPoint("TOPRIGHT", statusBar, "BOTTOMRIGHT", 1, 0)
	borders.bottom:SetHeight(1)
	borders.left:SetPoint("TOPRIGHT", statusBar, "TOPLEFT", 0, 0)
	borders.left:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMLEFT", 0, 0)
	borders.left:SetWidth(1)
	borders.right:SetPoint("TOPLEFT", statusBar, "TOPRIGHT", 0, 0)
	borders.right:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMRIGHT", 0, 0)
	borders.right:SetWidth(1)
	bar.borders = borders

	-- Stand-still bar ----------------------------------------------------
	local standBar = CreateFrame("StatusBar", nil, timerPart)
	standBar:SetMinMaxValues(0, 1)
	standBar:SetValue(0)
	bar.standBar = standBar

	local standTrack = Solid(standBar, "BACKGROUND")
	standTrack:SetPoint("TOPLEFT", standBar, "TOPLEFT", 0, 0)
	standTrack:SetPoint("BOTTOMRIGHT", standBar, "BOTTOMRIGHT", 0, 0)
	bar.standTrack = standTrack

	local standOutline = Solid(timerPart, "BACKGROUND", -1)
	bar.standOutline = standOutline

	-- Texts --------------------------------------------------------------
	local status = timerPart:CreateFontString(nil, "OVERLAY")
	status:SetJustifyH("LEFT")
	bar.statusText = status

	local countdown = timerPart:CreateFontString(nil, "OVERLAY")
	countdown:SetJustifyH("RIGHT")
	bar.countdownText = countdown

	local info = timerPart:CreateFontString(nil, "OVERLAY")
	info:SetJustifyH("LEFT")
	bar.infoText = info

	local ammoIcon = timerPart:CreateTexture(nil, "OVERLAY")
	ammoIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	bar.ammoIcon = ammoIcon

	local ammoText = timerPart:CreateFontString(nil, "OVERLAY")
	ammoText:SetJustifyH("LEFT")
	bar.ammoText = ammoText

	local rangeText = rangePart:CreateFontString(nil, "OVERLAY")
	rangeText:SetJustifyH("RIGHT")
	bar.rangeText = rangeText

	local rangeDot = rangePart:CreateTexture(nil, "OVERLAY")
	if type(rangeDot.SetColorTexture) == "function" then
		rangeDot:SetColorTexture(1, 1, 1, 1)
	else
		rangeDot:SetTexture("Interface\\Buttons\\WHITE8X8")
	end
	bar.rangeDot = rangeDot

	ns.ApplyPosition()
	bar:SetLocked(true)
	bar:Layout()
end

function ns.ApplyPosition()
	local frame = bar.frame
	if not frame then
		return
	end
	frame:ClearAllPoints()
	local point = ns.db and ns.db.point
	if type(point) == "table" and type(point.point) == "string" and type(point.relativePoint) == "string" then
		frame:SetPoint(point.point, UIParent, point.relativePoint, tonumber(point.x) or 0, tonumber(point.y) or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
end

function ns.SavePosition()
	local frame = bar.frame
	if not frame then
		return
	end
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	if not point then
		return
	end
	ns.db.point = {
		point = point,
		relativePoint = relativePoint or point,
		x = x or 0,
		y = y or 0,
	}
end

function bar:SetLocked(locked)
	self.locked = locked and true or false
	if self.frame then
		self.frame:EnableMouse(not self.locked)
		self.frame:SetMovable(true)
	end
end

---------------------------------------------------------------------------
-- Layout (SPEC 5.4, 5.5, 5.6)
---------------------------------------------------------------------------

function bar:ClearCache()
	self.fillKey = nil
	local list = { self.statusText, self.countdownText, self.infoText, self.ammoText, self.rangeText }
	for _, fontString in pairs(list) do
		if fontString then
			fontString.hsfText = nil
			fontString.hsfColour = nil
			fontString.hsfAlpha = nil
		end
	end
	self.shownStatus = nil
	self.shownCountdown = nil
	self.rangeAnchorKey = nil
	self.infoWidth = nil
	self.zoneKey = nil
end

function bar:Layout()
	local db = ns.db
	if not db or not self.frame then
		return
	end
	local root = self.frame
	local width = db.width
	local thickness = db.barHeight
	local fs = db.fontSize
	local sfs = db.smallFontSize

	local standH = math.max(3, math.floor(thickness * 0.4 + 0.5))
	local standExtra = db.showStandBar and (standH + 3) or 0
	local statusW = math.ceil(fs * 6)
	local countW = math.ceil(fs * 2.2)
	local ammoTextW = math.ceil(sfs * 3)
	local ammoW = sfs + 3 + ammoTextW
	local dotSize = math.max(4, math.floor(sfs * 0.5))
	local ammoOn = db.ammoDisplay ~= "off"
	local countSlot = db.showCountdown and (countW + 8) or 0
	local ammoSlot = ammoOn and (ammoW + 8) or 0
	local rangeBelow = db.rangeEnabled and (db.rangePosition == "belowRight" or db.rangePosition == "belowLeft")
	local layout = db.layout
	local vertical = layout == "vertical"

	self.standH = standH
	self.standExtra = standExtra
	self.dotSize = dotSize
	self.ammoTextW = ammoTextW
	self.statusW = statusW
	self.countW = countW
	self.ammoW = ammoW
	self.vertical = vertical
	self.layout = layout
	self.rangeBelow = rangeBelow
	self.fillKey = nil

	local statusBar = self.statusBar
	local standBar = self.standBar
	local infoShown = db.showSpeed or db.showShots
	local bottomH = (infoShown or rangeBelow) and (sfs + GAP) or 0

	local barX, barY, barLength, barThick
	local frameWidth, frameHeight
	local textW = math.max(statusW, math.ceil(sfs * 11))

	if vertical then
		barX, barY = 0, 0
		barLength, barThick = width, thickness
		frameWidth = thickness + 6 + standExtra + textW
		frameHeight = width
	else
		barLength, barThick = width, thickness
		frameWidth = width
		local topH
		local left, right, rowH
		if layout == "row" then
			left = db.showStatus and (statusW + 6) or 0
			right = (db.showCountdown and (countW + 6) or 0) + (ammoOn and (ammoW + 6) or 0)
			rowH = math.max(thickness, fs + 2)
			frameWidth = left + width + right
			barX = left
			barY = -math.floor((rowH - thickness) / 2)
			frameHeight = rowH + standExtra + bottomH
		else
			topH = ((db.showStatus or db.showCountdown or ammoOn) and (math.max(fs, sfs) + GAP)) or 0
			barX = 0
			barY = -topH
			frameHeight = topH + thickness + standExtra + bottomH
		end
	end

	self.barLength = barLength
	self.barThick = barThick
	self.textW = textW
	root:SetSize(frameWidth, frameHeight)
	root:SetAlpha((db.opacity or 100) / 100)

	statusBar:ClearAllPoints()
	statusBar:SetPoint("TOPLEFT", root, "TOPLEFT", barX, barY)
	if vertical then
		statusBar:SetSize(thickness, width)
		statusBar:SetOrientation("VERTICAL")
	else
		statusBar:SetSize(width, thickness)
		statusBar:SetOrientation("HORIZONTAL")
	end
	if type(statusBar.SetStatusBarTexture) == "function" then
		pcall(statusBar.SetStatusBarTexture, statusBar, db.texture)
	end
	self.fillKey = nil

	-- track follows the bar
	self.track:ClearAllPoints()
	self.track:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
	self.track:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
	Tint(self.track, ns.Colour("track"))

	-- zone and divider
	self.zone:ClearAllPoints()
	self.divider:ClearAllPoints()
	if vertical then
		self.zone:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
		self.zone:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
		self.divider:SetPoint("TOPLEFT", self.zone, "BOTTOMLEFT", 0, 0)
		self.divider:SetPoint("TOPRIGHT", self.zone, "BOTTOMRIGHT", 0, 0)
		self.divider:SetHeight(1)
		self.sheen:ClearAllPoints()
		self.sheen:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
		self.sheen:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMLEFT", 0, 0)
		self.sheen:SetWidth(1)
		self.spark:SetSize(thickness * 2.4, math.max(6, thickness * 1.2))
		if type(self.spark.SetRotation) == "function" then
			self.spark:SetRotation(math.pi / 2)
		end
	else
		self.zone:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
		self.zone:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
		self.divider:SetPoint("TOPLEFT", self.zone, "TOPLEFT", 0, 0)
		self.divider:SetPoint("BOTTOMLEFT", self.zone, "BOTTOMLEFT", 0, 0)
		self.divider:SetWidth(1)
		self.sheen:ClearAllPoints()
		self.sheen:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
		self.sheen:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
		self.sheen:SetHeight(1)
		self.spark:SetSize(math.max(6, thickness * 1.2), thickness * 2.4)
		if type(self.spark.SetRotation) == "function" then
			self.spark:SetRotation(0)
		end
	end
	Tint(self.zone, ns.Colour("zone"))
	self.zone:SetAlpha(1)

	-- stand-still bar
	standBar:ClearAllPoints()
	self.standTrack:ClearAllPoints()
	self.standTrack:SetPoint("TOPLEFT", standBar, "TOPLEFT", 0, 0)
	self.standTrack:SetPoint("BOTTOMRIGHT", standBar, "BOTTOMRIGHT", 0, 0)
	Tint(self.standTrack, ns.Colour("track"))
	if type(standBar.SetStatusBarTexture) == "function" then
		pcall(standBar.SetStatusBarTexture, standBar, db.texture)
	end
	self.standOutline:ClearAllPoints()
	self.standOutline:SetPoint("TOPLEFT", standBar, "TOPLEFT", -1, 1)
	self.standOutline:SetPoint("BOTTOMRIGHT", standBar, "BOTTOMRIGHT", 1, -1)
	Tint(self.standOutline, 0, 0, 0, 1)
	if vertical then
		standBar:SetPoint("TOPLEFT", statusBar, "TOPRIGHT", 3, 0)
		standBar:SetSize(standH, width)
		standBar:SetOrientation("VERTICAL")
	else
		standBar:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", 0, -3)
		standBar:SetSize(width, standH)
		standBar:SetOrientation("HORIZONTAL")
	end
	standBar:SetShown(db.showStandBar and true or false)
	self.standOutline:SetShown(db.showStandBar and true or false)

	-- borders
	for _, texture in pairs(self.borders) do
		texture:SetShown(db.showBorder and true or false)
	end
	Tint(self.borders.top, 0, 0, 0, 1)
	Tint(self.borders.bottom, 0, 0, 0, 1)
	Tint(self.borders.left, 0, 0, 0, 1)
	Tint(self.borders.right, 0, 0, 0, 1)

	self.spark:SetShown(db.showSpark and true or false)

	-- fonts
	ApplyFont(self.statusText, fs)
	ApplyFont(self.countdownText, fs)
	ApplyFont(self.infoText, sfs)
	ApplyFont(self.ammoText, sfs)
	ApplyFont(self.rangeText, sfs)
	SetTextColour(self.infoText, MUTED[1], MUTED[2], MUTED[3], MUTED[4])

	-- text anchors
	local status, countdown, info, ammoIcon, ammoText = self.statusText, self.countdownText, self.infoText, self.ammoIcon, self.ammoText
	status:ClearAllPoints()
	countdown:ClearAllPoints()
	info:ClearAllPoints()
	ammoIcon:ClearAllPoints()
	ammoIcon:SetSize(sfs, sfs)
	ammoText:ClearAllPoints()

	if vertical then
		local x = thickness + 6 + standExtra
		local rowY = 0
		if db.showStatus then
			status:SetPoint("TOPLEFT", root, "TOPLEFT", x, rowY)
			status:SetWidth(textW)
			status:SetJustifyH("LEFT")
			rowY = rowY - (fs + 3)
		end
		if db.showCountdown then
			countdown:SetPoint("TOPLEFT", root, "TOPLEFT", x, rowY)
			countdown:SetWidth(textW)
			countdown:SetJustifyH("LEFT")
			rowY = rowY - (fs + 3)
		end
		if ammoOn then
			ammoIcon:SetPoint("TOPLEFT", root, "TOPLEFT", x, rowY)
			ammoText:SetPoint("LEFT", ammoIcon, "RIGHT", 3, 0)
			ammoText:SetWidth(ammoTextW)
			ammoText:SetJustifyH("LEFT")
			rowY = rowY - (sfs + 3)
		end
		info:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 0)
		info:SetWidth(textW)
		info:SetJustifyH("LEFT")
		self.rangeRowY = rowY + 3
	elseif layout == "row" then
		local left = db.showStatus and (statusW + 6) or 0
		status:SetPoint("RIGHT", statusBar, "LEFT", -6, 0)
		status:SetWidth(statusW)
		status:SetJustifyH("RIGHT")
		countdown:SetPoint("LEFT", statusBar, "RIGHT", 6, 0)
		countdown:SetWidth(countW)
		countdown:SetJustifyH("LEFT")
		local ammoOffset = 6 + (db.showCountdown and (countW + 6) or 0)
		ammoIcon:SetPoint("LEFT", statusBar, "RIGHT", ammoOffset, 0)
		ammoText:SetPoint("LEFT", ammoIcon, "RIGHT", 3, 0)
		ammoText:SetWidth(ammoTextW)
		ammoText:SetJustifyH("LEFT")
		info:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", 0, -(GAP + standExtra))
		info:SetWidth(width)
		info:SetJustifyH("LEFT")
		if db.rangePosition == "belowLeft" then
			info:ClearAllPoints()
			info:SetPoint("TOPRIGHT", statusBar, "BOTTOMRIGHT", 0, -(GAP + standExtra))
			info:SetJustifyH("RIGHT")
		end
		self.rangeRowY = nil
	else
		status:SetPoint("BOTTOMLEFT", statusBar, "TOPLEFT", 0, GAP)
		status:SetWidth(math.max(1, width - countSlot - ammoSlot))
		status:SetJustifyH("LEFT")
		countdown:SetPoint("BOTTOMRIGHT", statusBar, "TOPRIGHT", 0, GAP)
		countdown:SetWidth(countW)
		countdown:SetJustifyH("RIGHT")
		ammoIcon:SetPoint("BOTTOMLEFT", statusBar, "TOPRIGHT", -(countSlot + ammoW), GAP)
		ammoText:SetPoint("LEFT", ammoIcon, "RIGHT", 3, 0)
		ammoText:SetWidth(ammoTextW)
		ammoText:SetJustifyH("LEFT")
		info:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", 0, -(GAP + standExtra))
		info:SetWidth(width)
		info:SetJustifyH("LEFT")
		if db.rangePosition == "belowLeft" then
			info:ClearAllPoints()
			info:SetPoint("TOPRIGHT", statusBar, "BOTTOMRIGHT", 0, -(GAP + standExtra))
			info:SetJustifyH("RIGHT")
		end
		self.rangeRowY = nil
	end

	-- range part anchors
	local rangePart = self.parts.range.frame
	rangePart:ClearAllPoints()
	rangePart:SetSize(1, sfs)
	self.rangeSide = "right"
	if vertical then
		rangePart:SetPoint("TOPLEFT", root, "TOPLEFT", thickness + 6 + standExtra, self.rangeRowY)
		self.rangeSide = "left"
	elseif db.rangePosition == "belowLeft" then
		rangePart:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", 0, -(GAP + standExtra))
		self.rangeSide = "left"
	elseif db.rangePosition == "right" then
		local push = layout == "row" and (6 + (db.showCountdown and (countW + 6) or 0) + (ammoOn and (ammoW + 6) or 0)) or 6
		rangePart:SetPoint("LEFT", statusBar, "RIGHT", push, 0)
	elseif db.rangePosition == "left" then
		local push = layout == "row" and (6 + (db.showStatus and (statusW + 6) or 0)) or 6
		rangePart:SetPoint("RIGHT", statusBar, "LEFT", -push, 0)
	else
		rangePart:SetPoint("TOPRIGHT", statusBar, "BOTTOMRIGHT", 0, -(GAP + standExtra))
	end

	local dot = self.rangeDot
	dot:SetSize(dotSize, dotSize)

	self.reserved = self.reserved or 0
	self.lastInfoWidth = nil
	self:ClearCache()
end

---------------------------------------------------------------------------
-- State computation
---------------------------------------------------------------------------

local function CountdownText(left, decimals)
	if not left then
		return nil
	end
	if decimals and decimals >= 2 then
		return string.format("%.2f", math.floor(left * 100 + 0.5) / 100)
	end
	return string.format("%.1f", math.floor(left * 10 + 0.5) / 10)
end

local function AutoState(now, demo)
	local db = ns.db
	local phase = ns.Phase(now, demo)
	if not phase then
		return nil
	end
	local moveColour = Colour("move")
	local standColour = Colour("stand")

	local state = {
		mode = "auto",
		demo = demo,
		phase = phase.phase,
		value = phase.fill,
		zoneFraction = phase.stand / phase.cycle,
		cycle = phase.cycle,
		need = phase.need,
		pulse = false,
	}
	local colour = phase.phase == "move" and moveColour or standColour
	state.r, state.g, state.b, state.a = colour[1], colour[2], colour[3], colour[4]

	if demo then
		state.status = phase.phase == "move" and "MOVE" or "STAND STILL"
		state.countdown = CountdownText(phase.left, 1)
		state.standProgress = phase.phase == "stand"
			and ((phase.elapsed - phase.moveUntil) / math.max(phase.stand, 0.001))
			or 1
		state.standColour = phase.phase == "move" and moveColour or standColour
		state.blinkStand = false
		return state
	end

	local shotTime, standStart, standLeft, progress, retryWait, grace = ns.StandStill(now, phase.cycle, phase.need)
	state.shotTime, state.standStart, state.standLeft, state.standProgress = shotTime, standStart, standLeft, progress
	-- A move in the last 0.1 s before the shot no longer stops it: no STOP then.
	state.moving = ns.move.moving and not grace
	state.known = ns.move.known
	state.held = ns.range.held

	if phase.phase == "move" then
		state.status = "MOVE"
		state.countdown = CountdownText(phase.left, 1)
	elseif phase.phase == "stand" then
		state.status = "STAND STILL"
		state.countdown = CountdownText((retryWait and standLeft) or phase.left, 1)
	else
		if state.held == "close" then
			state.status = "TOO CLOSE"
			state.pulse = true
			state.heldUp = true
		elseif state.held == "far" then
			state.status = "OUT OF RANGE"
			state.pulse = true
			state.heldUp = true
		elseif state.known and state.moving then
			state.status = "STOP"
			state.pulse = true
		elseif state.known then
			state.status = "STAND STILL"
			if standLeft and standLeft > 0 then
				state.countdown = CountdownText(standLeft, 2)
			else
				state.pulse = true
			end
		else
			state.status = "STAND STILL"
			state.pulse = true
		end
	end

	-- stand-still bar
	if phase.phase == "late" then
		if state.heldUp then
			state.standProgress = 1
			state.standColour = standColour
			state.blinkStand = false
		elseif state.moving then
			state.standProgress = 0
			state.standColour = standColour
			state.blinkStand = false
		elseif state.known then
			if shotTime and standLeft and standLeft > 0 then
				state.standProgress = progress or 0
				state.standColour = standColour
				state.blinkStand = false
			else
				state.standProgress = 1
				state.standColour = standColour
				state.blinkStand = true
			end
		else
			state.standProgress = 0
			state.standColour = standColour
			state.blinkStand = false
		end
	elseif phase.phase == "move" then
		state.standProgress = 1
		if state.known and state.moving then
			state.standColour = { GREY[1], GREY[2], GREY[3], GREY[4] }
		else
			state.standColour = moveColour
		end
		state.blinkStand = false
	else
		state.standProgress = progress or 0
		state.standColour = standColour
		state.blinkStand = false
	end

	return state
end

local function MeleeState(now)
	local db = ns.db
	local timing = ns.timing
	local cycle = timing.meleeSpeed or 2
	local elapsed = now - (timing.lastMelee or now)
	if elapsed < 0 then
		elapsed = 0
	end
	local left = math.max(0, cycle - elapsed)
	local colour = Colour("melee")
	return {
		mode = "melee",
		phase = "melee",
		value = math.min(1, elapsed / cycle),
		zoneFraction = 0,
		cycle = cycle,
		status = "MELEE",
		countdown = CountdownText(left, 1),
		r = colour[1],
		g = colour[2],
		b = colour[3],
		a = colour[4],
		pulse = false,
		standProgress = 0,
		standColour = Colour("stand"),
		blinkStand = false,
	}
end

local function TooCloseState()
	local standColour = Colour("stand")
	local speed = ns.timing.speed
	local need = ns.Need()
	return {
		mode = "tooClose",
		phase = "tooClose",
		value = 0,
		zoneFraction = speed and (math.min(need, speed) / speed) or 0,
		status = "TOO CLOSE",
		countdown = nil,
		r = standColour[1],
		g = standColour[2],
		b = standColour[3],
		a = standColour[4],
		pulse = false,
		standProgress = 0,
		standColour = standColour,
		blinkStand = false,
	}
end

function bar:ResolveMode(now, demo)
	if demo then
		return "auto"
	end
	local db = ns.db
	if ns.MeleeActive(now) then
		return "melee"
	end
	if db.showMelee and ns.range.held == "close" and ns.InCombat() and not ns.timing.autoRepeat then
		return "tooClose"
	end
	return "auto"
end

function bar:ComputeState(mode, now, demo)
	if mode == "melee" then
		return MeleeState(now)
	elseif mode == "tooClose" then
		return TooCloseState()
	end
	return AutoState(now, demo)
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

function bar:SetFill(r, g, b, a)
	local statusBar = self.statusBar
	local db = ns.db
	local key = string.format("%.3f %.3f %.3f %.3f", r, g, b, a or 1)
	if self.fillKey == key then
		return
	end
	self.fillKey = key

	if type(statusBar.SetStatusBarColor) == "function" then
		pcall(statusBar.SetStatusBarColor, statusBar, r, g, b, a or 1)
	end
	if type(statusBar.SetGradient) == "function" then
		local orientation = self.vertical and "VERTICAL" or "HORIZONTAL"
		if db.gradient then
			local dark = { r * 0.72, g * 0.72, b * 0.72, a or 1 }
			local light = { r, g, b, a or 1 }
			local ok = pcall(statusBar.SetGradient, statusBar, orientation, dark, light)
			if ok then
				return
			end
		else
			pcall(statusBar.SetGradient, statusBar, orientation, { r, g, b, a or 1 }, { r, g, b, a or 1 })
		end
	end
end

function bar:UpdateZone(fraction)
	local length = self.barLength or 0
	local thick = self.barThick or 0
	local pixels = length * (fraction or 0)
	local show = pixels >= 0.5 and (fraction or 0) > 0
	local key = string.format("%s %.2f", tostring(show), pixels)
	if self.zoneKey ~= key then
		self.zoneKey = key
		if show and self.vertical then
			self.zone:SetWidth(thick)
			self.zone:SetHeight(pixels)
		elseif show then
			self.zone:SetHeight(thick)
			self.zone:SetWidth(pixels)
		end
		self.zone:SetShown(show)
		self.divider:SetShown(show)
	end
	Tint(self.zone, ns.Colour("zone"))
end

function bar:UpdateSpark(value, pulse, now)
	local db = ns.db
	if not db.showSpark then
		if self.sparkShown ~= false then
			self.sparkShown = false
			self.spark:Hide()
		end
		return
	end
	local alpha = pulse and (0.45 + 0.45 * math.sin(now * 9)) or 0.9
	self.spark:SetAlpha(alpha)
	self.spark:ClearAllPoints()
	local offset = (self.barLength or 0) * (value or 0)
	if self.vertical then
		self.spark:SetPoint("CENTER", self.statusBar, "BOTTOM", 0, offset)
	else
		self.spark:SetPoint("CENTER", self.statusBar, "LEFT", offset, 0)
	end
	if self.sparkShown ~= true then
		self.sparkShown = true
		self.spark:Show()
	end
end

function bar:UpdateFlash(dt)
	local db = ns.db
	if not db.showFlash then
		self.flashAlpha = 0
	elseif self.flashAlpha and self.flashAlpha > 0 then
		self.flashAlpha = math.max(0, self.flashAlpha - 2.2 * (dt or 0))
	end
	self.flash:SetAlpha(self.flashAlpha or 0)
end

function ns.RequestFlash(alpha)
	bar.flashAlpha = math.max(bar.flashAlpha or 0, alpha or 0)
end

function bar:ApplyView(view, now, dt)
	local db = ns.db
	local status = self.statusText
	local countdown = self.countdownText

	self.statusBar:SetValue(math.max(0, math.min(1, view.value or 0)))
	self:SetFill(view.r or 1, view.g or 1, view.b or 1, view.a or 1)
	self:UpdateZone(view.zoneFraction)

	self.drawValue = view.value
	self.drawR, self.drawG, self.drawB = view.r, view.g, view.b

	-- status text
	if db.showStatus and view.status then
		SetText(status, view.status)
		SetTextColour(status, view.r or 1, view.g or 1, view.b or 1, 1)
		SetTextAlpha(status, view.statusAlpha or 1)
		if status.hsfShown ~= true then
			status.hsfShown = true
			status:Show()
		end
		self.shownStatus = view.status
	else
		if status.hsfShown ~= false then
			status.hsfShown = false
			status:Hide()
		end
		self.shownStatus = nil
	end

	-- countdown
	if db.showCountdown and view.countdown then
		SetText(countdown, view.countdown)
		local r, g, b, a = ns.Colour("text")
		SetTextColour(countdown, r, g, b, a)
		SetTextAlpha(countdown, view.countdownAlpha or 1)
		if countdown.hsfShown ~= true then
			countdown.hsfShown = true
			countdown:Show()
		end
		self.shownCountdown = view.countdown
	else
		if countdown.hsfShown ~= false then
			countdown.hsfShown = false
			countdown:Hide()
		end
		self.shownCountdown = nil
	end

	self:UpdateStandBar(view, now)
	self:UpdateSpark(view.value, view.pulse, now)
	self:UpdateFlash(dt)
end

function bar:UpdateStandBar(view, now)
	local db = ns.db
	local standBar = self.standBar
	if not db.showStandBar then
		if self.standShown ~= false then
			self.standShown = false
			standBar:Hide()
		end
		return
	end
	if self.standShown ~= true then
		self.standShown = true
		standBar:Show()
	end

	standBar:SetValue(math.max(0, math.min(1, view.standProgress or 0)))
	local colour = view.standColour or Colour("stand")
	if type(standBar.SetStatusBarColor) == "function" then
		standBar:SetStatusBarColor(colour[1], colour[2], colour[3], colour[4] or 1)
	end
	if view.blinkStand then
		standBar:SetAlpha(0.35 + 0.65 * (0.5 + 0.5 * math.cos(now * 10)))
	else
		standBar:SetAlpha(1)
	end
end

function bar:TransitionState(state, dt)
	local trans = self.trans
	trans.t = trans.t + (dt or 0) / 0.2
	local b = math.min(1, trans.t)
	local s = Smooth(b)
	local value = trans.value + ((state.value or 0) - trans.value) * s
	local zone = trans.zone + ((state.zoneFraction or 0) - trans.zone) * s
	local r = trans.r + ((state.r or 1) - trans.r) * s
	local g = trans.g + ((state.g or 1) - trans.g) * s
	local bcol = trans.b + ((state.b or 1) - trans.b) * s
	local a = trans.a + ((state.a or 1) - trans.a) * s

	local view = {
		value = value,
		zoneFraction = zone,
		r = r,
		g = g,
		b = bcol,
		a = a,
		pulse = state.pulse,
		standProgress = state.standProgress,
		standColour = state.standColour,
		blinkStand = state.blinkStand,
		status = state.status,
		countdown = state.countdown,
		statusAlpha = 1,
		countdownAlpha = 1,
	}

	local sameLabel = trans.oldStatus and state.status and trans.oldStatus == state.status
	if not sameLabel then
		local alpha = math.abs(1 - 2 * b)
		if b >= 0.5 then
			view.status = state.status
		else
			view.status = trans.oldStatus
		end
		view.statusAlpha = alpha
	end
	local sameCountdown = trans.oldCountdown == state.countdown
	if not sameCountdown then
		local alpha = math.abs(1 - 2 * b)
		if b >= 0.5 then
			view.countdown = state.countdown
		else
			view.countdown = trans.oldCountdown
		end
		view.countdownAlpha = alpha
	end

	if b >= 1 then
		self.trans = nil
		view.status = state.status
		view.countdown = state.countdown
		view.statusAlpha = 1
		view.countdownAlpha = 1
		self:ClearCache()
	end
	return view
end

function bar:BeginTransition(state)
	self.trans = {
		t = 0,
		value = self.drawValue or 0,
		r = self.drawR or 1,
		g = self.drawG or 1,
		b = self.drawB or 1,
		a = 1,
		zone = self.drawZone or 0,
		oldStatus = self.shownStatus,
		oldCountdown = self.shownCountdown,
	}
end

---------------------------------------------------------------------------
-- Info line, ammo slot and range part
---------------------------------------------------------------------------

local function InfoText(mode, demo)
	local db = ns.db
	if mode == "melee" then
		if db.showSpeed then
			return string.format("%.2fs melee", ns.timing.meleeSpeed or 2)
		end
		return ""
	end
	local parts = {}
	if db.showSpeed then
		if demo then
			parts[#parts + 1] = string.format("%.2fs", ns.T.DEMO_CYCLE)
		elseif ns.timing.speed then
			parts[#parts + 1] = string.format("%.2fs", ns.timing.speed)
		end
	end
	if db.showShots then
		local shots
		if demo then
			shots = 4
		else
			shots = ns.ShotsToKill()
		end
		if shots then
			parts[#parts + 1] = (shots == 1) and "~1 shot" or string.format("~%d shots", shots)
		end
	end
	return table.concat(parts, "   ")
end

function bar:UpdateInfo(mode, demo)
	local db = ns.db
	local text = InfoText(mode, demo)
	local info = self.infoText
	local sfs = db.smallFontSize
	local reserved = 0

	if self.rangeBelow and self.parts.range.visible and (db.showSpeed or db.showShots) then
		local rangeText = self.rangeText
		local width = 0
		if type(rangeText.GetStringWidth) == "function" then
			local ok, value = pcall(rangeText.GetStringWidth, rangeText)
			width = (ok and tonumber(value)) or 0
		end
		reserved = width + (self.dotSize or 5) + 4
		self.reserved = self.reserved or 0
		if reserved > self.reserved then
			self.reserved = reserved
		elseif reserved < self.reserved - sfs * 2 then
			self.reserved = reserved
		end
		reserved = self.reserved
	end

	local fullWidth = (self.layout == "vertical") and (self.textW or 0) or (self.barLength or 0)
	local width = fullWidth - reserved
	local hide = false
	if reserved > 0 and width < sfs * 2 then
		hide = true
	end
	width = math.max(1, width)
	if self.infoWidth ~= width then
		self.infoWidth = width
		info:SetWidth(width)
	end
	SetText(info, text)
	SetTextAlpha(info, hide and 0 or 1)
	if hide then
		info:Hide()
	else
		info:Show()
	end
end

function bar:UpdateAmmoSlot(demo)
	local db = ns.db
	local mode = db.ammoDisplay
	if mode == "off" then
		self.ammoIcon:Hide()
		self.ammoText:Hide()
		return
	end

	local coloured
	local icon
	if demo then
		if mode == "count" then
			coloured = "|cff40d8601200|r"
		else
			coloured = "|cffa6d96a60%|r"
		end
	else
		local ammo = ns.ammo
		coloured = ammo.text
		icon = ammo.icon
	end

	if icon then
		self.ammoIcon:SetTexture(icon)
		self.ammoIcon:Show()
	else
		self.ammoIcon:Hide()
	end
	SetText(self.ammoText, coloured)
	if coloured then
		self.ammoText:Show()
	else
		self.ammoText:Hide()
	end
end

function bar:UpdateRangePart(now, demo, timerAlpha, dt)
	local db = ns.db
	local part = self.parts.range
	local state
	local label
	local distance

	if demo then
		state = "in"
		label = "In range"
		local mode = db.rangeDistance
		if mode == "bracket" then
			distance = "20-25 yd"
		elseif mode == "estimate" then
			distance = "~23 yd"
		end
	else
		state = ns.range.state
		if state then
			if db.rangeText then
				label = ns.RANGE_WORDS[state]
			end
			if db.rangeDistance ~= "off" then
				distance = ns.range.distance
			end
		end
	end

	local show = state and (demo or timerAlpha > 0.02 or (db.rangeWhenIdle and ns.isHunter))
	if not show then
		part.visible = false
		UpdateFade(part, false, dt)
		return
	end

	local colour = ns.RANGE_COLOURS[state]
	if not colour then
		part.visible = false
		UpdateFade(part, false, dt)
		return
	end

	local text = nil
	if label and distance then
		text = label .. "  " .. distance
	elseif label then
		text = label
	elseif distance then
		text = distance
	end

	local rangeText = self.rangeText
	SetText(rangeText, text or "")
	SetTextColour(rangeText, colour[1], colour[2], colour[3], 1)

	local dot = self.rangeDot
	Tint(dot, colour[1], colour[2], colour[3], 1)

	local anchorKey = string.format("%s|%s", self.rangeSide or "right", (text and text ~= "") and "text" or "empty")
	if self.rangeAnchorKey ~= anchorKey then
		self.rangeAnchorKey = anchorKey
		rangeText:SetJustifyH(self.rangeSide == "left" and "LEFT" or "RIGHT")
		rangeText:ClearAllPoints()
		dot:ClearAllPoints()
		if self.rangeSide == "left" then
			local shift = 0
			if text and text ~= "" then
				shift = (self.dotSize or 5) + 4
			end
			rangeText:SetPoint("LEFT", part.frame, "LEFT", shift, 0)
			dot:SetPoint("LEFT", part.frame, "LEFT", 0, 0)
		else
			rangeText:SetPoint("RIGHT", part.frame, "RIGHT", 0, 0)
			if text and text ~= "" then
				dot:SetPoint("RIGHT", rangeText, "LEFT", -4, 0)
			else
				dot:SetPoint("RIGHT", part.frame, "RIGHT", 0, 0)
			end
		end
	end

	part.visible = true
	UpdateFade(part, true, dt)
end

---------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------

function bar:TimerVisible(mode, state, demo)
	if demo then
		return true
	end
	if mode == "melee" or mode == "tooClose" then
		return true
	end
	if ns.timing.running then
		return true
	end
	if ns.timing.lastShot and state and state.phase ~= "late" then
		return true
	end
	return false
end

function bar:Update(now, dt)
	local db = ns.db
	if not db then
		return
	end
	local demo = ns.demoActive and true or false
	local active = ns.isHunter or demo
	if not active then
		UpdateFade(self.parts.timer, false, dt)
		UpdateFade(self.parts.range, false, dt)
		return
	end

	local mode = self:ResolveMode(now, demo)
	local state = self:ComputeState(mode, now, demo)
	if not state then
		if self.parts.timer.alpha > 0.02 then
			self.statusBar:SetValue(0)
		end
		UpdateFade(self.parts.timer, false, dt)
		UpdateFade(self.parts.range, false, dt)
		return
	end

	local visible = self:TimerVisible(mode, state, demo)
	local selfAlpha = UpdateFade(self.parts.timer, visible, dt)

	if self.trans and not visible then
		self.trans = nil
		self:ClearCache()
	end

	if mode ~= self.mode then
		if not self.trans and self.parts.timer.alpha > 0.02 and self.everPainted then
			self:BeginTransition(state)
		end
		self.mode = mode
	end

	local view
	if self.trans then
		view = self:TransitionState(state, dt)
	else
		view = state
	end

	self:ApplyView(view, now, dt)
	self.drawZone = view.zoneFraction
	self.everPainted = true

	self:UpdateRangePart(now, demo, selfAlpha, dt)
	self:UpdateInfo(mode, demo)
	self:UpdateAmmoSlot(demo)
end

function ns.BarOnUpdate(elapsed)
	local db = ns.db
	if not db or not bar.frame then
		return
	end
	local now = GetTime()
	local dt = elapsed or 0
	if dt > 0.25 then
		dt = 0.25
	end
	ns.UpdateLatency(now)
	ns.PollMovement(now)
	ns.UpdateRange(now)
	ns.UpdateAverageShot(now)
	ns.UpdateAmmo(now)
	bar:Update(now, dt)
end

---------------------------------------------------------------------------
-- Hooks used by the options window
---------------------------------------------------------------------------

function ns.SetDemo(open)
	ns.demoActive = open and true or false
	bar:SetLocked(not ns.demoActive)
	if ns.demoActive and bar.frame then
		bar.frame:Show()
	end
end

function ns.OnSettingChanged()
	if bar.frame then
		bar:Layout()
	end
	ns.RefreshPins()
end

function ns.ResetPosition()
	ns.db.point = nil
	ns.ApplyPosition()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function IsHunter()
	if type(UnitClass) ~= "function" then
		return false
	end
	local ok, _, token = pcall(UnitClass, "player")
	if not ok or ns.IsSecret(token) then
		return false
	end
	return token == "HUNTER"
end
ns.IsHunter = IsHunter

local function Register(frame, event)
	pcall(frame.RegisterEvent, frame, event)
end

local events = CreateFrame("Frame", nil, UIParent)
ns.eventFrame = events

local EVENT_LIST = {
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"PLAYER_ENTERING_WORLD",
	"PLAYER_SWING",
	"START_AUTOREPEAT_SPELL",
	"STOP_AUTOREPEAT_SPELL",
	"PLAYER_ENTER_COMBAT",
	"PLAYER_LEAVE_COMBAT",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_STARTED_MOVING",
	"PLAYER_STOPPED_MOVING",
	"UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_RANGEDDAMAGE",
	"UNIT_ATTACK_SPEED",
	"BAG_UPDATE_DELAYED",
	"PLAYER_EQUIPMENT_CHANGED",
	"ZONE_CHANGED_NEW_AREA",
}

for _, event in ipairs(EVENT_LIST) do
	Register(events, event)
end

-- A jump out of Feign Death restarts the swing too (a post-hook: no taint).
if type(hooksecurefunc) == "function" and type(JumpOrAscendStart) == "function" then
	pcall(hooksecurefunc, "JumpOrAscendStart", function()
		if ns.db and ns.OnFeignMove then
			ns.OnFeignMove(GetTime())
		end
	end)
end

function ns.OnEvent(event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= ADDON then
			return
		end
		if ns.db then
			return
		end
		ns.LoadSaved()
		ns.isHunter = IsHunter()
		ns.BuildBar()
		return
	end

	if not ns.db then
		return
	end
	local now = GetTime()

	if event == "PLAYER_LOGIN" then
		ns.isHunter = IsHunter()
		ns.RequestDistanceItems()
		ns.UpdateAmmo(now)
	elseif event == "PLAYER_ENTERING_WORLD" then
		ns.isHunter = IsHunter()
		ns.ResetMovement(now)
		ns.UpdateAmmo(now)
		ns.SetupPins()
		ns.RefreshPins()
	elseif event == "PLAYER_SWING" then
		local duration, swingType = ...
		swingType = ns.PlainNumber(swingType)
		local types = Enum and Enum.PlayerSwingType
		local ranged = (types and types.Ranged) or 2
		local mainHand = (types and types.MainHand) or 0
		local offHand = (types and types.OffHand) or 1
		if swingType == ranged then
			ns.OnRangedSwing(duration)
			ns.RequestFlash(0.35)
		elseif swingType == mainHand or swingType == offHand then
			ns.OnMeleeSwing(duration)
			if ns.db.showMelee then
				ns.RequestFlash(0.25)
			end
		end
	elseif event == "START_AUTOREPEAT_SPELL" then
		ns.SetAutoRepeat(true)
	elseif event == "STOP_AUTOREPEAT_SPELL" then
		ns.SetAutoRepeat(false)
	elseif event == "PLAYER_ENTER_COMBAT" then
		ns.SetMeleeAuto(true)
	elseif event == "PLAYER_LEAVE_COMBAT" or event == "PLAYER_REGEN_ENABLED" then
		ns.SetMeleeAuto(false)
	elseif event == "PLAYER_STARTED_MOVING" then
		ns.OnMovementEvent(true, now)
	elseif event == "PLAYER_STOPPED_MOVING" then
		ns.OnMovementEvent(false, now)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...
		if unit == "player" then
			ns.OnSpellSucceeded(spellID)
		end
	elseif event == "UNIT_RANGEDDAMAGE" then
		local unit = ...
		if unit == "player" then
			ns.OnAttackSpeedChange("R")
		end
	elseif event == "UNIT_ATTACK_SPEED" then
		local unit = ...
		if unit == "player" then
			ns.OnAttackSpeedChange("A")
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		ns.ammo.last = 0
		ns.UpdateAmmo(now)
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		local slot = ...
		if slot == 18 or slot == 0 then
			ns.RefreshPins()
		end
		ns.ammo.last = 0
		ns.UpdateAmmo(now)
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		ns.RefreshPins()
	end
end

events:SetScript("OnEvent", function(_, event, ...)
	ns.OnEvent(event, ...)
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local SLASH_COMMANDS = {
	[""] = "toggle",
	reset = "reset",
	range = "range",
	moving = "moving",
	timing = "timing",
	probe = "probe",
	lock = "lock",
	unlock = "unlock",
	move = "move",
}

local function SlashHandler(input)
	if not ns.db then
		return
	end
	local command = (input or ""):match("^%s*(.-)%s*$"):lower()
	local action = SLASH_COMMANDS[command] or "toggle"

	if action == "toggle" then
		if ns.ToggleOptions then
			ns.ToggleOptions()
		end
	elseif action == "reset" then
		ns.ResetPosition()
		ns.Print("Position reset.")
	elseif action == "range" then
		ns.range.last = 0
		ns.UpdateRange(GetTime())
		ns.ReportRange()
	elseif action == "moving" then
		ns.ReportMovement()
	elseif action == "timing" then
		ns.ReportTiming()
	elseif action == "probe" then
		ns.ReportProbe()
	elseif action == "lock" then
		bar:SetLocked(true)
		ns.Print("Locked.")
	elseif action == "unlock" then
		bar:SetLocked(false)
		ns.Print("Unlocked: drag the bar where you want it. Type /hsf lock to lock.")
	elseif action == "move" then
		if bar.locked then
			bar:SetLocked(false)
			ns.Print("Unlocked: drag the bar where you want it. Type /hsf lock to lock.")
		else
			bar:SetLocked(true)
			ns.Print("Locked.")
		end
	end
end

SLASH_HUNTERSWINGFOREVER1 = "/hsf"
SLASH_HUNTERSWINGFOREVER2 = "/hunterswing"
SlashCmdList["HUNTERSWINGFOREVER"] = SlashHandler
