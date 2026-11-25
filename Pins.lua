-- Hunter Swing Forever by Illusion
-- Unit 7: ammo vendor pins on the world map and the minimap.
local ADDON, ns = ...

local PIN_TEMPLATE = "HunterSwingForeverPinTemplate"
ns.PIN_TEMPLATE = PIN_TEMPLATE

local ICONS = {
	arrow = "Interface\\Icons\\INV_Ammo_Arrow_02",
	bullet = "Interface\\Icons\\INV_Ammo_Bullet_02",
}
local FACTIONS = {
	A = { 0.27, 0.55, 1 },
	H = { 0.92, 0.22, 0.2 },
	N = { 1, 0.82, 0.25 },
}
local FACTION_LABELS = { A = "Alliance", H = "Horde", N = "Neutral" }

ns.VENDOR_ICONS = ICONS
ns.VENDOR_FACTIONS = FACTIONS

local reported = {}

local function ReportError(what, message)
	local text = tostring(message)
	if reported[what .. text] then
		return
	end
	reported[what .. text] = true
	ns.Print("Ammo vendor " .. what .. " pins failed: " .. text)
end

---------------------------------------------------------------------------
-- Map helpers
---------------------------------------------------------------------------

local function MapInfo(mapID)
	local func = C_Map and C_Map.GetMapInfo
	if type(func) ~= "function" then
		return nil
	end
	local ok, info = pcall(func, mapID)
	if not ok or type(info) ~= "table" then
		return nil
	end
	return info
end
ns.GetMapInfo = MapInfo

local function NormaliseName(name)
	if type(name) ~= "string" then
		return nil
	end
	local text = name:lower()
	text = text:gsub("^the ", "")
	text = text:gsub("[%s%-']", "")
	return text
end

local resolveCache = {}

function ns.MapName(mapID)
	return ns.vendorMaps and ns.vendorMaps[mapID]
end

function ns.ResolveMapID(mapID)
	if resolveCache[mapID] ~= nil then
		return resolveCache[mapID]
	end
	local name = ns.MapName(mapID)
	local resolved = mapID
	local info = MapInfo(mapID)
	local nameKnown = info and not ns.IsSecret(info.name) and NormaliseName(info.name) == NormaliseName(name)
	if not nameKnown and name then
		local func = C_Map and C_Map.GetMapChildrenInfo
		if type(func) == "function" then
			local ok, children = pcall(func, 947, nil, true)
			if ok and type(children) == "table" then
				local wanted = NormaliseName(name)
				for _, child in ipairs(children) do
					local childName = (not ns.IsSecret(child.name)) and child.name or nil
					if wanted and NormaliseName(childName) == wanted then
						resolved = child.mapID
						break
					end
				end
			end
		end
	end
	resolveCache[mapID] = resolved
	return resolved
end

local function FactionGroup()
	local ok, group = ns.SafeCall(_G.UnitFactionGroup, "player")
	if not ok or ns.IsSecret(group) or type(group) ~= "string" then
		return nil
	end
	if group == "Alliance" then
		return "A"
	end
	if group == "Horde" then
		return "H"
	end
	return nil
end

local function WeaponKind()
	local ok, value = ns.SafeCall(_G.GetInventoryItemID, "player", 18)
	local itemID = ok and ns.PlainNumber(value) or nil
	if not itemID then
		return nil
	end
	local info = ns.ItemInfo(itemID)
	if not info or info.classID ~= 2 then
		return nil
	end
	if info.subclassID == 2 or info.subclassID == 18 then
		return "arrow"
	end
	if info.subclassID == 3 then
		return "bullet"
	end
	return nil
end

function ns.WantedAmmoKinds()
	local mode = ns.db and ns.db.vendorAmmo or "weapon"
	if mode == "arrow" then
		return { arrow = true }
	end
	if mode == "bullet" then
		return { bullet = true }
	end
	if mode == "both" then
		return { arrow = true, bullet = true }
	end
	local kind = WeaponKind()
	if kind then
		return { [kind] = true }
	end
	return { arrow = true, bullet = true }
end

local function RowKinds(vendor)
	local kinds = {}
	for _, itemID in ipairs(vendor.items) do
		local item = ns.vendorItems[itemID]
		if item then
			kinds[item.kind] = true
		end
	end
	return kinds
end

function ns.VisibleVendors()
	local db = ns.db
	if not db or not ns.vendorRows then
		return {}
	end
	local wanted = ns.WantedAmmoKinds()
	local side = FactionGroup()
	local out = {}
	for _, vendor in ipairs(ns.vendorRows) do
		local draw
		if vendor.faction == "N" then
			draw = db.vendorNeutral
		elseif not side then
			draw = true
		elseif vendor.faction == side then
			draw = true
		else
			draw = db.vendorOtherFaction
		end
		if draw then
			local kinds = RowKinds(vendor)
			if wanted.arrow and kinds.arrow or wanted.bullet and kinds.bullet then
				out[#out + 1] = vendor
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Waypoints and chat
---------------------------------------------------------------------------

function ns.SetWaypoint(mapID, x, y)
	local canSet = C_Map and C_Map.CanSetUserWaypointOnMap
	if type(canSet) == "function" then
		local ok, allowed = pcall(canSet, mapID)
		if not ok or allowed == false then
			return false
		end
	end
	local create = UiMapPoint and UiMapPoint.CreateFromCoordinates
	local setUser = C_Map and C_Map.SetUserWaypoint
	if type(create) ~= "function" or type(setUser) ~= "function" then
		return false
	end
	local okCreate, point = pcall(create, mapID, x, y)
	if not okCreate or not point then
		return false
	end
	local okSet = pcall(setUser, point)
	if not okSet then
		return false
	end
	local superTrack = C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint
	if type(superTrack) == "function" then
		pcall(superTrack, true)
	end
	return true
end

function ns.TryWaypoint(vendor)
	if not vendor then
		return
	end
	local mapID = ns.ResolveMapID(vendor.mapId) or vendor.mapId
	local x, y = vendor.x * 100, vendor.y * 100
	if ns.SetWaypoint(mapID, vendor.x, vendor.y) then
		ns.Print(string.format("Waypoint set: %s (%.1f, %.1f).", vendor.name, x, y))
	else
		local zone = ns.MapName(vendor.mapId) or "this zone"
		ns.Print(string.format("%s is at %.1f, %.1f in %s.", vendor.name, x, y, zone))
	end
end

---------------------------------------------------------------------------
-- The pin itself
---------------------------------------------------------------------------

function ns.SetupPin(pin)
	pin.SetPassThroughButtons = function() end
	if pin.hsfInitialised then
		ns.RenderPin(pin)
		return
	end
	pin.hsfInitialised = true

	if type(pin.SetScalingLimits) == "function" then
		pcall(pin.SetScalingLimits, pin, 1, 1.0, 1.2)
	end
	if type(pin.UseFrameLevelType) == "function" then
		pcall(pin.UseFrameLevelType, pin, "PIN_FRAME_LEVEL_AREA_POI")
	end
	if type(pin.RegisterForClicks) == "function" then
		pcall(pin.RegisterForClicks, pin, "LeftButtonUp", "RightButtonUp")
	end
	if type(pin.EnableMouse) == "function" then
		pin:EnableMouse(true)
	end

	ns.RenderPin(pin)
end

function ns.RenderPin(pin)
	local size = pin.pinSize or 18
	if type(pin.SetSize) == "function" then
		pin:SetSize(size, size)
	end
	local colour = FACTIONS[pin.faction] or FACTIONS.N
	if pin.Ring and pin.Ring.SetVertexColor then
		pin.Ring:SetVertexColor(colour[1], colour[2], colour[3], 1)
	end
	if pin.Icon and pin.Icon.SetTexture then
		pin.Icon:SetTexture(ICONS[pin.kind] or ICONS.arrow)
		if pin.Icon.SetTexCoord then
			pin.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
	end
	if pin.Count and pin.Count.SetText then
		local count = pin.vendors and #pin.vendors or 0
		pin.Count:SetText(count > 1 and tostring(count) or "")
	end
	if pin.Hover and pin.Hover.SetAlpha then
		pin.Hover:SetAlpha(0)
	end
end

function ns.ShowPinTooltip(pin)
	local tip = _G.GameTooltip
	if not tip then
		return
	end
	local vendors = pin.vendors or {}
	if #vendors == 0 then
		return
	end
	tip:SetOwner(pin, "ANCHOR_RIGHT")

	if #vendors == 1 then
		local vendor = vendors[1]
		local colour = FACTIONS[vendor.faction] or FACTIONS.N
		tip:SetText(vendor.name, 1, 1, 1)
		tip:AddLine(FACTION_LABELS[vendor.faction] or "Neutral", colour[1], colour[2], colour[3])
		for _, itemID in ipairs(vendor.items) do
			local item = ns.vendorItems[itemID]
			if item then
				tip:AddDoubleLine(item.name, "level " .. tostring(item.level), 0.9, 0.9, 0.9, 0.6, 0.6, 0.6)
			end
		end
		local note = (ns.vendorNotes and ns.vendorNotes[vendor.npc]) or vendor.note
		if note then
			tip:AddLine(note, 1, 0.5, 0.3, true)
		end
		local zone = ns.MapName(vendor.mapId) or "this zone"
		tip:AddLine(string.format("%s  %.1f, %.1f", zone, vendor.x * 100, vendor.y * 100), 0.6, 0.6, 0.6)
		if pin.homeMap then
			tip:AddLine("Click: open " .. zone, 0.5, 0.8, 1)
		else
			tip:AddLine("Click: set a waypoint", 0.5, 0.8, 1)
		end
	else
		tip:SetText(string.format("%d ammo vendors", #vendors), 1, 1, 1)
		local colour = FACTIONS[pin.faction] or FACTIONS.N
		tip:AddLine(FACTION_LABELS[pin.faction] or "Neutral", colour[1], colour[2], colour[3])
		for _, vendor in ipairs(vendors) do
			tip:AddLine(vendor.name, 0.9, 0.9, 0.9)
			local names = {}
			for _, itemID in ipairs(vendor.items) do
				local item = ns.vendorItems[itemID]
				if item then
					names[#names + 1] = item.name
				end
			end
			tip:AddLine(table.concat(names, ", "), 0.6, 0.6, 0.6, true)
			local note = (ns.vendorNotes and ns.vendorNotes[vendor.npc]) or vendor.note
			if note then
				tip:AddLine(note, 1, 0.5, 0.3, true)
			end
		end
		if pin.homeMap then
			tip:AddLine("Click: open " .. (ns.MapName(pin.homeMap) or "this zone"), 0.5, 0.8, 1)
		else
			tip:AddLine("Click: set a waypoint to " .. vendors[1].name, 0.5, 0.8, 1)
		end
	end

	tip:Show()
end

function ns.HidePinTooltip()
	local tip = _G.GameTooltip
	if tip and tip.Hide then
		tip:Hide()
	end
end

function ns.PinClick(pin, button)
	if button ~= "LeftButton" then
		return
	end
	if pin.isMinimap then
		ns.TryWaypoint(pin.vendors and pin.vendors[1])
		return
	end
	if pin.homeMap and pin.map and type(pin.map.SetMapID) == "function" then
		pcall(pin.map.SetMapID, pin.map, pin.homeMap)
		return
	end
	ns.TryWaypoint(pin.vendors and pin.vendors[1])
end

function HunterSwingForever_PinOnLoad(pin)
	ns.SetupPin(pin)
end

function HunterSwingForever_PinOnClick(pin, button)
	ns.PinClick(pin, button)
end

function HunterSwingForever_PinOnEnter(pin)
	if pin.Hover and pin.Hover.SetAlpha then
		pin.Hover:SetAlpha(1)
	end
	ns.ShowPinTooltip(pin)
end

function HunterSwingForever_PinOnLeave(pin)
	if pin.Hover and pin.Hover.SetAlpha then
		pin.Hover:SetAlpha(0)
	end
	ns.HidePinTooltip()
end

---------------------------------------------------------------------------
-- World map data provider
---------------------------------------------------------------------------

local pending = false

local function MapRectOnMap(vendorMap, shownMap)
	local rectFunc = C_Map and C_Map.GetMapRectOnMap
	if type(rectFunc) ~= "function" then
		return nil
	end
	local current = vendorMap
	local inside = false
	for _ = 1, 4 do
		local info = MapInfo(current)
		local parent = info and info.parentMapID
		if not parent or parent == 0 then
			break
		end
		if parent == shownMap then
			inside = true
			break
		end
		current = parent
	end
	if not inside then
		return nil
	end
	local ok, left, right, top, bottom = pcall(rectFunc, vendorMap, shownMap)
	if not ok then
		return nil
	end
	local l = ns.PlainNumber(left)
	local r = ns.PlainNumber(right)
	local t = ns.PlainNumber(top)
	local b = ns.PlainNumber(bottom)
	if not (l and r and t and b) then
		return nil
	end
	return l, r, t, b
end

local function AddGroup(groups, entry, reach)
	for _, group in ipairs(groups) do
		if group.faction == entry.faction and group.small == entry.small then
			local dx = (group.x - entry.x) * 1.5
			local dy = group.y - entry.y
			if dx * dx + dy * dy <= reach * reach then
				local count = group.count
				group.x = (group.x * count + entry.x) / (count + 1)
				group.y = (group.y * count + entry.y) / (count + 1)
				group.count = count + 1
				group.vendors[#group.vendors + 1] = entry.vendor
				if group.homeMap ~= entry.homeMap then
					group.homeMap = nil
				end
				return
			end
		end
	end
	groups[#groups + 1] = {
		x = entry.x,
		y = entry.y,
		faction = entry.faction,
		kind = entry.kind,
		small = entry.small,
		homeMap = entry.homeMap,
		count = 1,
		vendors = { entry.vendor },
	}
end

function ns.BuildWorldMapPins()
	if not WorldMapFrame or type(WorldMapFrame.GetMap) ~= "function" then
		return
	end
	local map = WorldMapFrame:GetMap()
	if not map or type(map.RemoveAllPinsByTemplate) ~= "function" then
		return
	end

	local okClear, clearError = pcall(map.RemoveAllPinsByTemplate, map, PIN_TEMPLATE)
	if not okClear then
		ReportError("map", clearError)
		return
	end

	if not ns.db or not ns.db.vendorPins or not ns.isHunter then
		return
	end

	local okBuild, buildError = pcall(function()
		local mapID = type(map.GetMapID) == "function" and map:GetMapID() or nil
		if not mapID then
			return
		end
		local info = MapInfo(mapID)
		local mapType = info and info.mapType
		local continent = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
		if mapType and mapType < continent then
			return
		end
		local isContinent = mapType == continent
		if isContinent and not ns.db.vendorContinent then
			return
		end

		local normalSize = isContinent and 13 or 18
		local groups = {}
		for _, vendor in ipairs(ns.VisibleVendors()) do
			local vendorMap = ns.ResolveMapID(vendor.mapId) or vendor.mapId
			local x, y, small, homeMap
			if vendorMap == mapID then
				x, y = vendor.x, vendor.y
				small = false
			else
				local left, right, top, bottom = MapRectOnMap(vendorMap, mapID)
				if left then
					x = left + vendor.x * (right - left)
					y = top + vendor.y * (bottom - top)
					small = true
					homeMap = vendorMap
				end
			end
			if x and y then
				AddGroup(groups, {
					x = x,
					y = y,
					faction = vendor.faction,
					kind = vendor.kind,
					small = small,
					homeMap = homeMap,
					vendor = vendor,
				}, small and 0.022 or 0.012)
			end
		end

		for _, group in ipairs(groups) do
			pcall(function()
				local pin = map:AcquirePin(PIN_TEMPLATE)
				if not pin then
					return
				end
				pin.map = map
				pin.mapID = mapID
				pin.vendors = group.vendors
				pin.faction = group.faction
				pin.kind = group.kind
				pin.small = group.small
				pin.homeMap = group.homeMap
				pin.pinSize = group.small and 13 or normalSize
				pin.isMinimap = false
				ns.SetupPin(pin)
				pin:SetPosition(group.x, group.y)
			end)
		end
	end)

	if not okBuild then
		ReportError("map", buildError)
	end
end

local function ScheduleWorldMapBuild()
	if pending then
		return
	end
	pending = true
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(0, function()
			pending = false
			ns.BuildWorldMapPins()
		end)
	else
		pending = false
	end
end

local provider = {}

function provider:GetMap()
	local frame = self.frame
	if frame and type(frame.GetMap) == "function" then
		return frame:GetMap()
	end
	return nil
end

function provider:RemoveAllData()
	local map = self:GetMap()
	if map and type(map.RemoveAllPinsByTemplate) == "function" then
		pcall(map.RemoveAllPinsByTemplate, map, PIN_TEMPLATE)
	end
end

-- Never build pins here: the map runs this inside a secure execution range.
function provider:RefreshAllData()
	ScheduleWorldMapBuild()
end

function provider:OnMapChanged()
	ScheduleWorldMapBuild()
end

function ns.AttachWorldMap()
	if ns.worldMapAttached then
		return
	end
	if not WorldMapFrame or type(WorldMapFrame.AddDataProvider) ~= "function" then
		return
	end
	ns.worldMapAttached = true

	local instance
	if type(CreateFromMixins) == "function" and type(MapCanvasDataProviderMixin) == "table" then
		instance = CreateFromMixins(MapCanvasDataProviderMixin)
	else
		instance = {}
	end
	for key, value in pairs(provider) do
		instance[key] = value
	end
	instance.frame = WorldMapFrame
	ns.worldMapProvider = instance

	local ok = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, instance)
	if not ok then
		ns.worldMapAttached = false
	end
end

function ns.RefreshPins()
	ns.minimapDirty = true
	if WorldMapFrame and type(WorldMapFrame.IsShown) == "function" and WorldMapFrame:IsShown() then
		ScheduleWorldMapBuild()
	end
end

---------------------------------------------------------------------------
-- Minimap pins
---------------------------------------------------------------------------

local mini = {
	pins = {},
	acc = 0,
	driver = nil,
}
ns.minimap = mini

local function Locked()
	local ok, value = ns.SafeCall(_G.InCombatLockdown)
	if not ok then
		return false
	end
	if ns.IsSecret(value) then
		return true
	end
	return value == true
end

local function PosXY(point)
	if not point then
		return nil
	end
	if type(point.GetXY) == "function" then
		local ok, x, y = pcall(point.GetXY, point)
		if ok then
			return ns.PlainNumber(x), ns.PlainNumber(y)
		end
		return nil
	end
	return ns.PlainNumber(point.x), ns.PlainNumber(point.y)
end

local function WorldPos(mapID, x, y)
	local func = C_Map and C_Map.GetWorldPosFromMapPos
	local vector = CreateVector2D and CreateVector2D(x, y) or nil
	if type(func) ~= "function" or not vector then
		return nil
	end
	local ok, continent, point = pcall(func, mapID, vector)
	if not ok or not point then
		return nil
	end
	local wx, wy = PosXY(point)
	if not wx or not wy then
		return nil
	end
	return continent, wx, wy
end

local function PlayerWorld()
	local best = C_Map and C_Map.GetBestMapForUnit
	local position = C_Map and C_Map.GetPlayerMapPosition
	if type(best) ~= "function" or type(position) ~= "function" then
		return nil
	end
	local okMap, mapID = pcall(best, "player")
	if not okMap or not mapID then
		return nil
	end
	local okPos, point = pcall(position, mapID, "player")
	if not okPos or not point then
		return nil
	end
	local px, py = PosXY(point)
	if not px or not py then
		return nil
	end
	return WorldPos(mapID, px, py)
end

local function NewMinimapPin()
	local pin = CreateFrame("Button", nil, Minimap, PIN_TEMPLATE)
	pin.isMinimap = true
	pin.pinSize = 14
	pin:SetSize(14, 14)
	pin:SetFrameStrata("HIGH")
	if Minimap and type(Minimap.GetFrameLevel) == "function" then
		pin:SetFrameLevel(Minimap:GetFrameLevel() + 20)
	end
	pin:Hide()
	return pin
end

local function HideMinimapPins()
	for _, pin in ipairs(mini.pins) do
		pin:Hide()
	end
end

function ns.UpdateMinimapPins(elapsed)
	mini.acc = mini.acc + (elapsed or 0)
	if mini.acc < 0.1 then
		return
	end
	mini.acc = 0

	if not ns.db or not ns.db.vendorMinimap or not ns.isHunter then
		HideMinimapPins()
		return
	end
	if not Minimap or type(Minimap.IsShown) ~= "function" or not Minimap:IsShown() then
		HideMinimapPins()
		return
	end
	if Locked() then
		HideMinimapPins()
		return
	end

	local okRun, runError = pcall(function()
		local playerContinent, playerX, playerY = PlayerWorld()
		if not playerContinent or not playerX or not playerY then
			HideMinimapPins()
			return
		end

		local radiusFunc = C_Minimap and C_Minimap.GetViewRadius
		local okRadius, radius = ns.SafeCall(radiusFunc)
		radius = okRadius and ns.PlainNumber(radius) or nil
		if not radius or radius <= 0 then
			HideMinimapPins()
			return
		end

		local width = ns.PlainNumber(Minimap:GetWidth())
		local height = ns.PlainNumber(Minimap:GetHeight())
		if not width or not height or width <= 0 or height <= 0 then
			HideMinimapPins()
			return
		end

		local facing = 0
		local rotate = GetCVar and GetCVar("rotateMinimap")
		if not ns.IsSecret(rotate) and rotate == "1" then
			local okFacing, value = ns.SafeCall(_G.GetPlayerFacing)
			local plain = okFacing and ns.PlainNumber(value) or nil
			if plain then
				facing = plain
			end
		end
		local c = math.cos(facing)
		local s = math.sin(facing)

		local size = 14
		local limitX = width / 2 - size / 2 - 2
		local limitY = height / 2 - size / 2 - 2
		local square = GetMinimapShape and GetMinimapShape() == "SQUARE"

		local candidates = {}
		for _, vendor in ipairs(ns.VisibleVendors()) do
			local mapID = ns.ResolveMapID(vendor.mapId) or vendor.mapId
			local continent, vx, vy = WorldPos(mapID, vendor.x, vendor.y)
			if continent and vx and vy and continent == playerContinent then
				local east = playerX - vx
				local south = playerY - vy
				local x = (east * c - south * s) / radius * width / 2
				local y = (-east * s - south * c) / radius * height / 2
				local visible
				if limitX > 0 and limitY > 0 then
					if square then
						visible = math.abs(x) <= limitX and math.abs(y) <= limitY
					else
						visible = (x / limitX) * (x / limitX) + (y / limitY) * (y / limitY) <= 1
					end
				end
				if visible then
					candidates[#candidates + 1] = { vendor = vendor, faction = vendor.faction, x = x, y = y }
				end
			end
		end

		local groups = {}
		for _, candidate in ipairs(candidates) do
			local merged = false
			for _, group in ipairs(groups) do
				if group.faction == candidate.faction then
					local dx = group.x - candidate.x
					local dy = group.y - candidate.y
					if dx * dx + dy * dy <= 12.6 * 12.6 then
						local count = group.count
						group.x = (group.x * count + candidate.x) / (count + 1)
						group.y = (group.y * count + candidate.y) / (count + 1)
						group.count = count + 1
						group.vendors[#group.vendors + 1] = candidate.vendor
						merged = true
						break
					end
				end
			end
			if not merged then
				groups[#groups + 1] = {
					x = candidate.x,
					y = candidate.y,
					faction = candidate.faction,
					kind = candidate.vendor.kind,
					count = 1,
					vendors = { candidate.vendor },
				}
			end
		end

		for index, group in ipairs(groups) do
			local pin = mini.pins[index]
			if not pin then
				pin = NewMinimapPin()
				mini.pins[index] = pin
			end
			pin.vendors = group.vendors
			pin.faction = group.faction
			pin.kind = group.kind
			pin.small = false
			pin.homeMap = nil
			pin.pinSize = 14
			pin.isMinimap = true
			ns.SetupPin(pin)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", Minimap, "CENTER", group.x, group.y)
			pin:Show()
		end
		for index = #groups + 1, #mini.pins do
			mini.pins[index]:Hide()
		end
	end)

	if not okRun then
		HideMinimapPins()
		ReportError("minimap", runError)
	end
end

function ns.BuildMinimap()
	if mini.driver then
		return
	end
	local driver = CreateFrame("Frame", nil, UIParent)
	driver:SetScript("OnUpdate", function(_, elapsed)
		ns.UpdateMinimapPins(elapsed)
	end)
	mini.driver = driver
end

function ns.SetupPins()
	ns.BuildMinimap()
	ns.AttachWorldMap()
	ns.minimapDirty = true
end
