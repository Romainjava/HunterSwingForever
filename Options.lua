local ADDON, ns = ...

local options = {
	refreshers = {},
}
ns.options = options

local COLUMN_WIDTH = 270

local function AttachTooltip(widget, titleText, bodyText)
	if not bodyText then
		return
	end
	if type(widget.HookScript) ~= "function" then
		return
	end
	widget:HookScript("OnEnter", function(self)
		local tip = _G.GameTooltip
		if not tip then
			return
		end
		tip:SetOwner(self, "ANCHOR_RIGHT")
		tip:AddLine(titleText, 1, 1, 1)
		tip:AddLine(bodyText, nil, nil, nil, true)
		tip:Show()
	end)
	widget:HookScript("OnLeave", function()
		local tip = _G.GameTooltip
		if tip then
			tip:Hide()
		end
	end)
end

local function AddHeading(parent, x, y, text)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(text)
	local line = parent:CreateTexture(nil, "ARTWORK")
	if type(line.SetColorTexture) == "function" then
		line:SetColorTexture(1, 0.82, 0, 0.25)
	else
		line:SetTexture("Interface\\Buttons\\WHITE8X8")
		line:SetVertexColor(1, 0.82, 0, 0.25)
	end
	line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	line:SetSize(COLUMN_WIDTH, 1)
	return label
end

local function AddCheckbox(parent, x, y, labelText, key, tooltip)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	if check.Text then
		check.Text:SetText("")
	end
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	label:SetText(labelText)

	check:SetScript("OnClick", function(self)
		ns.db[key] = self:GetChecked() and true or false
		ns.OnSettingChanged()
	end)
	check.Refresh = function()
		check:SetChecked(ns.db[key] and true or false)
	end
	options.refreshers[#options.refreshers + 1] = check.Refresh
	AttachTooltip(check, labelText, tooltip)
	return check
end

local function AddSlider(parent, x, y, labelText, key, minValue, maxValue, step, suffix)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(labelText)

	local function Format(value)
		return tostring(math.floor(value + 0.5)) .. (suffix or "")
	end

	local slider, valueText
	local ok, created = pcall(CreateFrame, "Slider", nil, parent, "MinimalSliderWithSteppersTemplate")
	if ok and created then
		slider = created
		slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 4, y - 14)
		slider:SetSize(230, 20)
		valueText = slider.Text
	end
	if not slider then
		slider = CreateFrame("Slider", nil, parent)
		slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y - 18)
		slider:SetSize(210, 16)
		slider:SetOrientation("HORIZONTAL")
		if slider.Low then
			slider.Low:SetText("")
		end
		if slider.High then
			slider.High:SetText("")
		end
		if slider.Text then
			slider.Text:SetText("")
		end
		valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
	end

	slider:SetMinMaxValues(minValue, maxValue)
	if type(slider.SetValueStep) == "function" then
		slider:SetValueStep(step)
	end
	if type(slider.SetObeyStepOnDrag) == "function" then
		slider:SetObeyStepOnDrag(true)
	end

	local function ShowValue(value)
		if valueText then
			valueText:SetText(Format(value))
		end
	end

	slider:SetScript("OnValueChanged", function(self, value)
		if self.hsfUpdating then
			return
		end
		local snapped = math.floor(value / step + 0.5) * step
		if self.hsfLast == snapped then
			return
		end
		self.hsfLast = snapped
		ns.db[key] = snapped
		ShowValue(snapped)
		ns.OnSettingChanged()
	end)

	slider.Refresh = function()
		local value = ns.db[key]
		if type(value) ~= "number" then
			value = minValue
		end
		slider.hsfUpdating = true
		slider:SetValue(value)
		slider.hsfUpdating = false
		slider.hsfLast = value
		ShowValue(value)
	end
	options.refreshers[#options.refreshers + 1] = slider.Refresh
	AttachTooltip(slider, labelText)
	return slider
end

local function AddStepper(parent, x, y, key, list)
	local prev = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	prev:SetSize(28, 22)
	prev:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 15)
	prev:SetText("<")

	local next = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	next:SetSize(28, 22)
	next:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 242, y - 15)
	next:SetText(">")

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOP", parent, "TOPLEFT", x + 135, y - 20)
	label:SetWidth(200)
	label:SetJustifyH("CENTER")

	local function Show()
		label:SetText(ns.ChoiceLabel(list, ns.db[key]))
	end

	local function Step(direction)
		local value = ns.NextChoice(list, ns.db[key], direction)
		ns.db[key] = value
		Show()
		ns.OnSettingChanged()
	end

	prev:SetScript("OnClick", function()
		Step(-1)
	end)
	next:SetScript("OnClick", function()
		Step(1)
	end)

	local refresh = function()
		Show()
	end
	options.refreshers[#options.refreshers + 1] = refresh
	Show()
	return label
end

local function AddChoice(parent, x, y, key, list, tooltip)
	local dropdown
	local ok, created = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and created then
		dropdown = created
	end
	if not dropdown then
		AddStepper(parent, x, y, key, list)
		return
	end

	dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
	dropdown:SetSize(260, 32)

	local function Show()
		dropdown:SetText(ns.ChoiceLabel(list, ns.db[key]), nil, 1, 1, 1)
	end

	if type(dropdown.SetupMenu) == "function" then
		pcall(dropdown.SetupMenu, dropdown, function(_, root)
			for _, entry in ipairs(list) do
				local value = entry.value
				root:CreateRadio(entry.label, function()
					return ns.db[key] == value
				end, function()
					ns.db[key] = value
					Show()
					ns.OnSettingChanged()
				end)
			end
		end)
	end

	local refresh = function()
		Show()
	end
	options.refreshers[#options.refreshers + 1] = refresh
	Show()
	AttachTooltip(dropdown, nil, tooltip)
	return dropdown
end

local function OpenColourPicker(swatch, key, withAlpha)
	local picker = _G.ColorPickerFrame
	if not picker then
		return
	end
	local colour = ns.db.colors[key]
	local r, g, b = colour[1], colour[2], colour[3]
	local a = colour[4] or 1

	local function Apply()
		local nr, ng, nb = picker:GetColorRGB()
		local na = a
		if withAlpha and type(picker.GetColorAlpha) == "function" then
			na = picker:GetColorAlpha() or a
		end
		ns.db.colors[key] = { nr, ng, nb, withAlpha and na or a }
		swatch.Refresh()
		ns.OnSettingChanged()
	end

	if type(picker.SetupColorPickerAndShow) == "function" then
		picker:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			opacity = a,
			hasOpacity = withAlpha,
			swatchFunc = Apply,
			opacityFunc = Apply,
			cancelFunc = function()
				ns.db.colors[key] = { r, g, b, a }
				swatch.Refresh()
				ns.OnSettingChanged()
			end,
		})
	elseif type(picker.SetColorRGB) == "function" then
		picker:SetColorRGB(r, g, b)
		if withAlpha and type(picker.SetColorAlpha) == "function" then
			picker:SetColorAlpha(a)
		end
		picker.swatchFunc = Apply
		picker.opacityFunc = Apply
		picker.cancelFunc = function()
			ns.db.colors[key] = { r, g, b, a }
			swatch.Refresh()
			ns.OnSettingChanged()
		end
		picker:Show()
	end
end

local function AddSwatch(parent, x, y, labelText, key, withAlpha)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(18, 18)
	button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	local border = button:CreateTexture(nil, "BACKGROUND")
	if type(border.SetColorTexture) == "function" then
		border:SetColorTexture(0.6, 0.6, 0.6, 1)
	else
		border:SetTexture("Interface\\Buttons\\WHITE8X8")
		border:SetVertexColor(0.6, 0.6, 0.6, 1)
	end
	border:SetAllPoints(button)

	local fill = button:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", button, "RIGHT", 6, 0)
	label:SetText(labelText)

	button.Refresh = function()
		local colour = ns.db.colors[key]
		if type(colour) == "table" then
			if type(fill.SetColorTexture) == "function" then
				fill:SetColorTexture(colour[1], colour[2], colour[3], 1)
			else
				fill:SetTexture("Interface\\Buttons\\WHITE8X8")
				fill:SetVertexColor(colour[1], colour[2], colour[3], 1)
			end
		end
	end
	button:SetScript("OnClick", function()
		OpenColourPicker(button, key, withAlpha)
	end)
	options.refreshers[#options.refreshers + 1] = button.Refresh
	button.Refresh()
	return button
end

local function TryCreateFrame(template)
	if template then
		local ok, frame = pcall(CreateFrame, "Frame", "HunterSwingForeverOptions", UIParent, template)
		if ok and frame then
			return frame
		end
	end
	return CreateFrame("Frame", "HunterSwingForeverOptions", UIParent)
end

local function BuildWindow()
	if options.frame then
		return options.frame
	end

	local frame = TryCreateFrame("DefaultPanelFlatTemplate")
	if not (frame.NineSlice or frame.Bg or frame.Inset) then
		frame = CreateFrame("Frame", "HunterSwingForeverOptions", UIParent)
	end
	options.frame = frame

	frame:SetSize(890, 580)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)

	if not (frame.NineSlice or frame.Bg or frame.Inset) then
		local background = frame:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints(frame)
		if type(background.SetColorTexture) == "function" then
			background:SetColorTexture(0.05, 0.05, 0.06, 0.94)
		else
			background:SetTexture("Interface\\Buttons\\WHITE8X8")
			background:SetVertexColor(0.05, 0.05, 0.06, 0.94)
		end
	end

	if frame.TitleText then
		frame.TitleText:SetText("Hunter Swing Forever")
	else
		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
		title:SetText("Hunter Swing Forever")
	end

	if not frame.CloseButton then
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	end

	local escapeList = _G.UISpecialFrames
	if type(escapeList) == "table" and type(tinsert) == "function" then
		tinsert(escapeList, "HunterSwingForeverOptions")
	end

	frame:SetScript("OnHide", function()
		ns.SetDemo(false)
	end)

	local resetPosition = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetPosition:SetSize(120, 22)
	resetPosition:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
	resetPosition:SetText("Reset position")
	resetPosition:SetScript("OnClick", function()
		ns.ResetPosition()
		ns.OnSettingChanged()
	end)

	local resetAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetAll:SetSize(140, 22)
	resetAll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 144, 14)
	resetAll:SetText("Reset all settings")
	resetAll:SetScript("OnClick", function()
		ns.ResetSaved()
		if frame.Refresh then
			frame:Refresh()
		end
		ns.OnSettingChanged()
	end)

	local done = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	done:SetSize(90, 22)
	done:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
	done:SetText("Done")
	done:SetScript("OnClick", function()
		frame:Hide()
	end)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, 42)
	hint:SetText("Drag the bar to move it while this window is open.")

	local function NewColumn(x)
		return { frame = frame, x = x, y = -34 }
	end

	local function Heading(column, text, extra)
		AddHeading(column.frame, column.x, column.y, text)
		column.y = column.y - (extra or 30)
	end

	local function CheckRow(column, firstKey, firstLabel, firstTip, secondKey, secondLabel, secondTip)
		AddCheckbox(column.frame, column.x, column.y - 4, firstLabel, firstKey, firstTip)
		if secondKey then
			AddCheckbox(column.frame, column.x + 135, column.y - 4, secondLabel, secondKey, secondTip)
		end
		column.y = column.y - 24
	end

	local function Slider(column, key, label, minValue, maxValue, step, suffix)
		AddSlider(column.frame, column.x, column.y, label, key, minValue, maxValue, step, suffix)
		column.y = column.y - 36
	end

	local function Choice(column, key, list, tooltip)
		AddChoice(column.frame, column.x, column.y, key, list, tooltip)
		column.y = column.y - 38
	end

	local function Swatches(column, firstKey, firstLabel, firstAlpha, secondKey, secondLabel, secondAlpha)
		AddSwatch(column.frame, column.x, column.y, firstLabel, firstKey, firstAlpha)
		if secondKey then
			AddSwatch(column.frame, column.x + 135, column.y, secondLabel, secondKey, secondAlpha)
		end
		column.y = column.y - 24
	end

	local left = NewColumn(16)
	Heading(left, "Layout & size")
	Choice(left, "layout", ns.LAYOUTS)
	Slider(left, "width", "Length", 100, 500, 5)
	Slider(left, "barHeight", "Thickness", 4, 40, 1)
	Slider(left, "opacity", "Opacity", 20, 100, 5, "%")
	Slider(left, "windowExtra", "Stand-still window adjust", -200, 300, 10, " ms")
	Heading(left, "Timing")
	CheckRow(left, "addPing", "Add my ping to the window", "Your 'stopped moving' reaches the server one ping later, so the red window grows by your world latency. Used until the addon has measured your real stand-still time on a few shots.")
	CheckRow(left, "retryModel", "0.5 s retry", "A shot refused because you were still moving is tried again 0.5 s later: the bar waits for that retry instead of predicting a shot you cannot make.",
		"hasteWindup", "Haste wind-up", "Rapid Fire and Quick Shots shorten the 0.5 s wind-up, so the red window and the learned stand-still time shrink with it.")
	CheckRow(left, "meleeResetsRanged", "Melee restarts the timer", "A main-hand or off-hand swing starts a new Auto Shot swing, so the bar counts from that swing instead of waiting on a late shot.",
		"feignResetsRanged", "Feign Death restarts", "After Feign Death, your first move or jump restarts the Auto Shot swing at the weapon's base speed + 0.15 s.")
	Heading(left, "Ammo vendors on the map")
	CheckRow(left, "vendorPins", "World map", "Every NPC that sells arrows or bullets, coloured by faction. Hover for what they sell, click for a waypoint.",
		"vendorMinimap", "Minimap", "The same vendors on the minimap when they are near you. Hidden in combat. Click one for a waypoint.")
	CheckRow(left, "vendorContinent", "Continent maps", "Also show them, smaller, on Kalimdor and the Eastern Kingdoms.",
		"vendorNeutral", "|cffffd140Neutral|r", "Goblin towns, Argent Dawn, Cenarion Circle and the like: open to both sides.")
	CheckRow(left, "vendorOtherFaction", "Other faction", "Also show the other side's vendors. They will not sell to you. Your own side is always shown.")
	Choice(left, "vendorAmmo", ns.VENDOR_AMMO_MODES)

	local middle = NewColumn(310)
	Heading(middle, "Text")
	Choice(middle, "font", ns.FONTS)
	Choice(middle, "outline", ns.OUTLINES)
	Slider(middle, "fontSize", "Font size", 8, 28, 1)
	Slider(middle, "smallFontSize", "Small font size (info, range)", 6, 20, 1)
	Heading(middle, "Colors")
	Swatches(middle, "move", "Move", false, "stand", "Stand still", false)
	Swatches(middle, "zone", "Window", true, "track", "Background", true)
	Swatches(middle, "text", "Countdown", false, "melee", "Melee", false)
	Choice(middle, "texture", ns.TEXTURES)

	local right = NewColumn(604)
	Heading(right, "Show")
	CheckRow(right, "showStatus", "Status text", "MOVE / STAND STILL / STOP.", "showCountdown", "Countdown", "Seconds left in the current phase.")
	CheckRow(right, "showSpeed", "Weapon speed", "Your ranged speed from the last shot, haste included.",
		"showShots", "Shots to kill", "Estimated Auto Shots to kill your target: its health divided by your average shot (armor and crits left out). Shown only when the game lets addons read the target's health; /hsf probe tells you.")
	CheckRow(right, "showSpark", "Spark", nil, "showFlash", "Flash on shot", nil)
	CheckRow(right, "showBorder", "Border", nil, "gradient", "Gradient fill", nil)
	CheckRow(right, "showMelee", "Melee & too close", "In melee range the bar stays up: while you swing it times your melee swings (MELEE, handy for Raptor Strike); otherwise it tells you to back off (TOO CLOSE).",
		"showStandBar", "Stand-still bar", "A slim second bar under the main one. Red: stand still; it fills from the moment you must stand (or the moment you stop, if you stop late) and is full as the arrow or bullet leaves. Then it turns solid green: the shot is away, move. Grey once you are moving. The time is measured on your own shots; /hsf timing shows it. Colours follow Move and Stand still.")
	Choice(right, "ammoDisplay", ns.AMMO_MODES)
	Heading(right, "Range check", 52)
	CheckRow(right, "rangeEnabled", "Enabled", "In range / Too close (dead zone) / Out of range for a hostile target.",
		"rangeText", "Show text", "In range / Too close / Out of range. Off: only the coloured dot and the distance.")
	CheckRow(right, "rangeCombatOnly", "Only in combat", nil,
		"rangeWhenIdle", "When not shooting", "Also show it while Auto Shot is off, so you can check before you pull.")
	Choice(right, "rangePosition", ns.RANGE_POSITIONS)
	Choice(right, "rangeDistance", ns.DISTANCE_MODES)

	function frame:Refresh()
		for _, refresh in ipairs(options.refreshers) do
			pcall(refresh)
		end
		ns.OnSettingChanged()
	end

	return frame
end

function ns.OpenOptions()
	if not ns.db then
		return
	end
	local frame = BuildWindow()
	ns.SetDemo(true)
	frame:Refresh()
	frame:Show()
	if type(frame.Raise) == "function" then
		frame:Raise()
	end
end

function ns.CloseOptions()
	if options.frame then
		options.frame:Hide()
	end
end

function ns.ToggleOptions()
	if options.frame and type(options.frame.IsShown) == "function" and options.frame:IsShown() then
		ns.CloseOptions()
	else
		ns.OpenOptions()
	end
end

local function BuildBlizzardPage()
	if options.page then
		return options.page
	end
	local supported = type(_G.Settings) == "table"
		and type(Settings.RegisterCanvasLayoutCategory) == "function"
		and type(Settings.RegisterAddOnCategory) == "function"
	if not supported then
		return nil
	end

	local page = CreateFrame("Frame", nil, UIParent)
	page.name = "Hunter Swing Forever"
	options.page = page

	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
	title:SetText("Hunter Swing Forever")

	local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	button:SetSize(160, 24)
	button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	button:SetText("Open settings")
	button:SetScript("OnClick", function()
		ns.OpenOptions()
	end)

	local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -8)
	hint:SetText("Size, fonts, colours and the range check. Also: /hsf")

	local category = Settings.RegisterCanvasLayoutCategory(page, "Hunter Swing Forever")
	Settings.RegisterAddOnCategory(category)
	options.category = category
	return page
end

local okPage = pcall(BuildBlizzardPage)
if not okPage then
	options.page = nil
end
