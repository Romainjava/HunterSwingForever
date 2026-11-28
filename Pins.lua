local ADDON, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
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
local WEAPON_AMMO = { [2] = "arrow", [18] = "arrow", [3] = "bullet" }

local CITY_ZONE = {
	[1453] = 1429,
	[1455] = 1426,
	[1457] = 1438,
	[1454] = 1411,
	[1456] = 1412,
	[1458] = 1420,
}

local MINIMAP_DIAMETERS = {
	indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
	outdoor = { [0] = 466.6667, [1] = 400, [2] = 333.3333, [3] = 266.6667, [4] = 200, [5] = 133.3333 },
}

local PIN_START_SCALE = 1.0
local PIN_END_SCALE = 1.2
local WORLD_MERGE_PX = 12
local VIEW_PAD = 0.2

ns.VENDOR_ICONS = ICONS
ns.VENDOR_FACTIONS = FACTIONS

local reported = {}
local resolveCache = {}
local rectCache = {}
local mapBoundsCache = {}
local vendorWorldCache = {}
local visibleCache = { key = nil, list = {}, wanted = nil }

local function ReportError(what, message)
	local text = tostring(message)
	if reported[what .. text] then
		return
	end
	reported[what .. text] = true
	ns.Print("Ammo vendor " .. what .. " pins failed: " .. text)
end

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

local function CreateFrameUnder(kind, parent)
	local frame = CreateFrame(kind)
	if parent and type(frame.SetParent) == "function" then
		frame:SetParent(parent)
	end
	return frame
end

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

function ns.MapName(mapID)
	return ns.vendorMaps and ns.vendorMaps[mapID]
end

function ns.ResolveMapID(mapID)
	if resolveCache[mapID] ~= nil then
		return resolveCache[mapID]
	end
	local resolved = mapID
	local info = MapInfo(mapID)
	local validDirect = info and ns.PlainNumber(info.mapID) == mapID
	if not validDirect then
		local name = ns.MapName(mapID)
		local func = C_Map and C_Map.GetMapChildrenInfo
		if name and type(func) == "function" then
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
	local instant = C_Item and C_Item.GetItemInfoInstant
	if type(instant) == "function" then
		local okInfo, _, _, _, _, _, classID, subclassID = pcall(instant, itemID)
		if okInfo and classID == 2 then
			return WEAPON_AMMO[subclassID]
		end
	end
	local info = ns.ItemInfo(itemID)
	if not info or info.classID ~= 2 then
		return nil
	end
	return WEAPON_AMMO[info.subclassID]
end

function ns.WantedAmmoKinds(weaponKind)
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
	local kind = weaponKind
	if kind == nil then
		kind = WeaponKind()
	end
	if kind then
		return { [kind] = true }
	end
	return { arrow = true, bullet = true }
end

local function VendorIconKind(vendor, wanted)
	if wanted then
		if wanted.bullet and not wanted.arrow then
			return "bullet"
		end
		if wanted.arrow and not wanted.bullet then
			return "arrow"
		end
	end
	return vendor.kind
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

local function VisibleVendorsCached()
	local db = ns.db
	if not db or not ns.vendorRows then
		return {}, nil, "-"
	end
	local weapon = WeaponKind()
	local side = FactionGroup()
	local key = table.concat({
		db.vendorNeutral and "1" or "0",
		db.vendorOtherFaction and "1" or "0",
		tostring(db.vendorAmmo or "weapon"),
		tostring(weapon or "-"),
		tostring(side or "-"),
	}, ":")
	if visibleCache.key == key then
		return visibleCache.list, visibleCache.wanted, key
	end
	local wanted = ns.WantedAmmoKinds(weapon)
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
	visibleCache.key = key
	visibleCache.list = out
	visibleCache.wanted = wanted
	return out, wanted, key
end

function ns.VisibleVendors()
	local list = VisibleVendorsCached()
	return list
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
	local north, west = PosXY(point)
	if not north or not west then
		return nil
	end
	return continent, north, west
end

local function VendorWorldPos(vendor)
	local cached = vendorWorldCache[vendor]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		return cached[1], cached[2], cached[3]
	end
	local mapID = ns.ResolveMapID(vendor.mapId) or vendor.mapId
	local continent, north, west = WorldPos(mapID, vendor.x, vendor.y)
	if continent and north and west then
		vendorWorldCache[vendor] = { continent, north, west }
		return continent, north, west
	end
	vendorWorldCache[vendor] = false
	return nil
end

local function MapWorldBounds(mapID)
	local cached = mapBoundsCache[mapID]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		return cached[1], cached[2], cached[3], cached[4], cached[5]
	end
	local c0, n0, w0 = WorldPos(mapID, 0, 0)
	local c1, n1, w1 = WorldPos(mapID, 1, 1)
	if not (c0 and c1 and c0 == c1 and n0 and w0 and n1 and w1) or w0 == w1 or n0 == n1 then
		mapBoundsCache[mapID] = false
		return nil
	end
	mapBoundsCache[mapID] = { c0, n0, w0, n1, w1 }
	return c0, n0, w0, n1, w1
end

local function MapRectOnMap(vendorMap, shownMap)
	local key = tostring(vendorMap) .. ":" .. tostring(shownMap)
	local cached = rectCache[key]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		return cached[1], cached[2], cached[3], cached[4]
	end

	local cityInside = CITY_ZONE[vendorMap] == shownMap
	local inside = cityInside
	if not inside then
		local current = vendorMap
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
	end
	if not inside then
		rectCache[key] = false
		return nil
	end

	local l, r, t, b
	local rectFunc = C_Map and C_Map.GetMapRectOnMap
	if type(rectFunc) == "function" then
		local ok, left, right, top, bottom = pcall(rectFunc, vendorMap, shownMap)
		if ok then
			local pl = ns.PlainNumber(left)
			local pr = ns.PlainNumber(right)
			local pt = ns.PlainNumber(top)
			local pb = ns.PlainNumber(bottom)
			if pl and pr and pt and pb and pr > pl and pb > pt then
				l, r, t, b = pl, pr, pt, pb
			end
		end
	end

	if not l and cityInside then
		local vc, vn0, vw0, vn1, vw1 = MapWorldBounds(vendorMap)
		local sc, sn0, sw0, sn1, sw1 = MapWorldBounds(shownMap)
		if vc and sc and vc == sc then
			local dw = sw0 - sw1
			local dn = sn0 - sn1
			local wl = (sw0 - vw0) / dw
			local wr = (sw0 - vw1) / dw
			local wt = (sn0 - vn0) / dn
			local wb = (sn0 - vn1) / dn
			if wr > wl and wb > wt and wl < 1 and wr > 0 and wt < 1 and wb > 0 then
				l, r, t, b = wl, wr, wt, wb
			end
		end
	end

	if not l then
		rectCache[key] = false
		return nil
	end
	rectCache[key] = { l, r, t, b }
	return l, r, t, b
end

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

local function OpenMapAPIReady()
	local api = rawget(_G, "OpenMapAPI")
	if type(api) ~= "table" or type(api.IsStitched) ~= "function" then
		return nil
	end
	local ok, stitched = pcall(api.IsStitched)
	if ok and stitched == true then
		return api
	end
	return nil
end

function ns.PinClick(pin, button)
	if button and button ~= "LeftButton" then
		return
	end
	if pin.isMinimap then
		ns.TryWaypoint(pin.vendors and pin.vendors[1])
		return
	end
	if pin.homeMap then
		local api = OpenMapAPIReady()
		local vendor = pin.vendors and pin.vendors[1]
		if api and vendor and type(api.WorldFromMap) == "function" and type(api.ShowWorld) == "function" then
			local okPos, u, v = pcall(api.WorldFromMap, pin.homeMap, vendor.x, vendor.y)
			if okPos and ns.PlainNumber(u) and ns.PlainNumber(v) then
				local okGlide, glided = pcall(api.ShowWorld, u, v, 8)
				if okGlide and glided then
					return
				end
			end
		end
		if not Locked() and WorldMapFrame and type(WorldMapFrame.SetMapID) == "function" then
			pcall(WorldMapFrame.SetMapID, WorldMapFrame, pin.homeMap)
			return
		end
	end
	ns.TryWaypoint(pin.vendors and pin.vendors[1])
end

local world = {
	host = nil,
	canvas = nil,
	pins = {},
	used = 0,
	shown = false,
	builtOnce = false,
	dirty = true,
	mapID = nil,
	stitched = false,
	width = 0,
	height = 0,
	scale = 1,
	zoom = 0,
	pinScale = 1,
	alpha = 1,
	winX0 = 0,
	winY0 = 0,
	winX1 = 0,
	winY1 = 0,
	winW = 0,
	filterKey = nil,
	hovered = nil,
	pressed = nil,
	passPending = false,
	levelPending = false,
	events = nil,
}
ns.world = world

local function PassRightButton(pin)
	if type(pin.SetPassThroughButtons) ~= "function" then
		return
	end
	if Locked() then
		world.passPending = true
		return
	end
	pcall(pin.SetPassThroughButtons, pin, "RightButton")
	pin.passThroughSet = true
end

local function BuildPinLook(pin)
	pin.Ring = pin:CreateTexture(nil, "BACKGROUND")
	pin.Ring:SetAllPoints(pin)
	pin.Ring:SetTexture(WHITE)

	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2)
	pin.Icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)
	pin.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	pin.Count = pin:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	pin.Count:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 5, -3)

	pin.Hover = pin:CreateTexture(nil, "OVERLAY")
	pin.Hover:SetAllPoints(pin)
	pin.Hover:SetTexture(WHITE)
	pin.Hover:SetVertexColor(1, 1, 1, 0.25)
	if type(pin.Hover.SetBlendMode) == "function" then
		pin.Hover:SetBlendMode("ADD")
	end
	pin.Hover:Hide()
end

local function AcquireWorldPin(index)
	local pin = world.pins[index]
	if pin then
		return pin
	end
	pin = CreateFrameUnder("Frame", world.host)
	pin.isMinimap = false
	pin.pinSize = 18
	pin:SetSize(18, 18)
	pin:EnableMouse(true)
	BuildPinLook(pin)
	pin:SetScript("OnEnter", function(self)
		world.hovered = self
		if self.Hover then
			self.Hover:Show()
		end
		ns.ShowPinTooltip(self)
	end)
	pin:SetScript("OnLeave", function(self)
		if world.hovered == self then
			world.hovered = nil
		end
		if self.Hover then
			self.Hover:Hide()
		end
		ns.HidePinTooltip()
	end)
	PassRightButton(pin)
	pin:Hide()
	world.pins[index] = pin
	return pin
end

local function HideWorldPins(fromIndex)
	for index = fromIndex, #world.pins do
		local pin = world.pins[index]
		if pin == world.hovered then
			world.hovered = nil
			ns.HidePinTooltip()
		end
		if pin.Hover then
			pin.Hover:Hide()
		end
		pin:Hide()
	end
end

local function WorldPinScale()
	local canvasScale = world.scale > 0 and world.scale or 1
	local s = (PIN_START_SCALE + (PIN_END_SCALE - PIN_START_SCALE) * world.zoom) * world.pinScale / canvasScale
	if s < 0.01 then
		s = 0.01
	end
	return s
end

local function WorldPinLevel(map, canvas, api)
	local level = 2100
	if map and type(map.GetPinFrameLevelsManager) == "function" then
		local okMgr, mgr = pcall(map.GetPinFrameLevelsManager, map)
		if okMgr and mgr and type(mgr.GetValidFrameLevel) == "function" then
			local okLvl, val = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_AREA_POI")
			local plain = okLvl and ns.PlainNumber(val) or nil
			if plain then
				level = plain
			end
		end
	elseif canvas and type(canvas.GetFrameLevel) == "function" then
		local okLvl, val = pcall(canvas.GetFrameLevel, canvas)
		local plain = okLvl and ns.PlainNumber(val) or nil
		if plain then
			level = plain + 10
		end
	end
	if api and type(api.ArtTopLevel) == "function" then
		local okTop, top = pcall(api.ArtTopLevel)
		local plain = okTop and ns.PlainNumber(top) or nil
		if plain and plain + 2 > level then
			level = plain + 2
		end
	end
	return level
end

local function PlaceWorldPin(pin, s)
	local canvas = world.canvas
	if not canvas then
		return
	end
	pin:SetScale(s)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", canvas, "TOPLEFT", (pin.nx * world.width) / s, -(pin.ny * world.height) / s)
end

local function RescaleWorldPins()
	local s = WorldPinScale()
	for index = 1, world.used do
		PlaceWorldPin(world.pins[index], s)
	end
end

local function ApplyWorldAlpha()
	local alpha = world.alpha or 1
	for index = 1, world.used do
		local pin = world.pins[index]
		if type(pin.SetAlpha) == "function" then
			pin:SetAlpha(alpha)
		end
	end
end

local function ViewRect(canvas, canvasW, canvasH)
	local scroll = canvas and type(canvas.GetParent) == "function" and canvas:GetParent() or nil
	if not scroll or canvasW <= 0 or canvasH <= 0 then
		return 0, 0, 1, 1
	end
	if type(canvas.GetLeft) ~= "function" or type(scroll.GetLeft) ~= "function" then
		return 0, 0, 1, 1
	end
	local okC, cl, ct, cs = pcall(function()
		return canvas:GetLeft(), canvas:GetTop(), canvas:GetEffectiveScale()
	end)
	local okS, fl, ft, fr, fb, fs = pcall(function()
		return scroll:GetLeft(), scroll:GetTop(), scroll:GetRight(), scroll:GetBottom(), scroll:GetEffectiveScale()
	end)
	if not (okC and okS) then
		return 0, 0, 1, 1
	end
	cl, ct, cs = ns.PlainNumber(cl), ns.PlainNumber(ct), ns.PlainNumber(cs)
	fl, ft, fr, fb, fs = ns.PlainNumber(fl), ns.PlainNumber(ft), ns.PlainNumber(fr), ns.PlainNumber(fb), ns.PlainNumber(fs)
	if not (cl and ct and cs and cs > 0 and fl and ft and fr and fb and fs and fr > fl and ft > fb) then
		return 0, 0, 1, 1
	end
	local kx = 1 / (canvasW * cs)
	local ky = 1 / (canvasH * cs)
	return (fl * fs - cl * cs) * kx, (ct * cs - ft * fs) * ky, (fr * fs - cl * cs) * kx, (ct * cs - fb * fs) * ky
end

local function AddWorldGroup(groups, entry, pxW, pxH)
	local mergeSq = WORLD_MERGE_PX * WORLD_MERGE_PX
	for _, group in ipairs(groups) do
		if group.faction == entry.faction and group.small == entry.small then
			local dx = (group.x - entry.x) * pxW
			local dy = (group.y - entry.y) * pxH
			if dx * dx + dy * dy <= mergeSq then
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

local function ReadWorldView()
	local map = WorldMapFrame
	local canvas = world.canvas
	if not map or not canvas then
		return nil
	end
	local okID, rawID = pcall(map.GetMapID, map)
	local mapID = okID and ns.PlainNumber(rawID) or nil
	local w = type(canvas.GetWidth) == "function" and ns.PlainNumber(canvas:GetWidth()) or 0
	local h = type(canvas.GetHeight) == "function" and ns.PlainNumber(canvas:GetHeight()) or 0
	local scale = type(map.GetCanvasScale) == "function" and ns.PlainNumber(map:GetCanvasScale()) or 1
	if not scale or scale <= 0 then
		scale = 1
	end
	local zoom = 0
	if type(map.GetCanvasZoomPercent) == "function" and (type(map.HasZoomLevels) ~= "function" or map:HasZoomLevels()) then
		local okZ, z = pcall(map.GetCanvasZoomPercent, map)
		zoom = okZ and ns.PlainNumber(z) or 0
		if zoom < 0 then
			zoom = 0
		elseif zoom > 1 then
			zoom = 1
		end
	end
	local pinScale = type(map.GetGlobalPinScale) == "function" and ns.PlainNumber(map:GetGlobalPinScale()) or 1
	if not pinScale or pinScale <= 0 then
		pinScale = 1
	end
	local alpha = type(map.GetGlobalAlpha) == "function" and ns.PlainNumber(map:GetGlobalAlpha()) or 1
	if not alpha then
		alpha = 1
	end
	local api = OpenMapAPIReady()
	return mapID, w or 0, h or 0, scale, zoom, pinScale, alpha, api
end

function ns.BuildWorldMapPins()
	world.dirty = false
	local map = WorldMapFrame
	local canvas = world.canvas
	if not map or not canvas or not world.host then
		return
	end

	local db = ns.db
	if not db or not db.vendorPins or not ns.isHunter then
		world.used = 0
		HideWorldPins(1)
		return
	end

	local okBuild, buildError = pcall(function()
		local mapID = world.mapID
		if not mapID or world.width <= 0 or world.height <= 0 then
			world.used = 0
			HideWorldPins(1)
			return
		end

		local info = MapInfo(mapID)
		local mapType = info and info.mapType
		local continent = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
		if mapType and mapType < continent then
			world.used = 0
			HideWorldPins(1)
			return
		end
		local isContinent = mapType == continent
		if isContinent and not db.vendorContinent then
			world.used = 0
			HideWorldPins(1)
			return
		end

		local vx0, vy0, vx1, vy1 = ViewRect(canvas, world.width, world.height)
		local vw = math.max(0.01, vx1 - vx0)
		local vh = math.max(0.01, vy1 - vy0)
		local padX = vw * VIEW_PAD
		local padY = vh * VIEW_PAD
		local x0, y0, x1, y1 = vx0 - padX, vy0 - padY, vx1 + padX, vy1 + padY
		world.winX0, world.winY0, world.winX1, world.winY1 = x0, y0, x1, y1
		world.winW = vw

		local api = world.stitched and OpenMapAPIReady() or nil
		local useOpenMap = api and type(api.CanvasFromWorldPos) == "function"
		local visibleVendors, wanted, filterKey = VisibleVendorsCached()
		world.filterKey = filterKey

		local normalSize = isContinent and 13 or 18
		local pxW = world.width * world.scale
		local pxH = world.height * world.scale
		local groups = {}

		if useOpenMap then
			for _, vendor in ipairs(visibleVendors) do
				local cont, north, west = VendorWorldPos(vendor)
				if cont and north and west then
					local okPos, cx, cy = pcall(api.CanvasFromWorldPos, cont, north, west)
					cx = okPos and ns.PlainNumber(cx) or nil
					cy = okPos and ns.PlainNumber(cy) or nil
					if cx and cy and cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 then
						local vendorMap = ns.ResolveMapID(vendor.mapId) or vendor.mapId
						local small = isContinent
						local homeMap = isContinent and vendorMap or nil
						AddWorldGroup(groups, {
							x = cx,
							y = cy,
							faction = vendor.faction,
							kind = VendorIconKind(vendor, wanted),
							small = small,
							homeMap = homeMap,
							vendor = vendor,
						}, pxW, pxH)
					end
				end
			end
		else
			local cx0 = math.max(0, x0)
			local cy0 = math.max(0, y0)
			local cx1 = math.min(1, x1)
			local cy1 = math.min(1, y1)
			for _, vendor in ipairs(visibleVendors) do
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
				if x and y and x >= cx0 and x <= cx1 and y >= cy0 and y <= cy1 then
					AddWorldGroup(groups, {
						x = x,
						y = y,
						faction = vendor.faction,
						kind = VendorIconKind(vendor, wanted),
						small = small,
						homeMap = homeMap,
						vendor = vendor,
					}, pxW, pxH)
				end
			end
		end

		local s = WorldPinScale()
		local level = WorldPinLevel(map, canvas, api)
		local locked = Locked()
		local alpha = world.alpha or 1

		for index, group in ipairs(groups) do
			local pin = AcquireWorldPin(index)
			pin.vendors = group.vendors
			pin.faction = group.faction
			pin.kind = group.kind
			pin.small = group.small
			pin.homeMap = group.homeMap
			pin.pinSize = group.small and 13 or normalSize
			pin.nx = group.x
			pin.ny = group.y
			ns.RenderPin(pin)
			if pin.hsfLevel ~= level and type(pin.SetFrameLevel) == "function" then
				if locked then
					world.levelPending = true
				else
					pcall(pin.SetFrameLevel, pin, level)
					pin.hsfLevel = level
				end
			end
			if type(pin.SetAlpha) == "function" then
				pin:SetAlpha(alpha)
			end
			PlaceWorldPin(pin, s)
			pin:Show()
		end
		world.used = #groups
		world.builtOnce = true
		HideWorldPins(world.used + 1)
	end)

	if not okBuild then
		world.used = 0
		HideWorldPins(1)
		ReportError("map", buildError)
	end
end

local function ViewportStale()
	if world.width <= 0 or world.height <= 0 then
		return false
	end
	local vx0, vy0, vx1, vy1 = ViewRect(world.canvas, world.width, world.height)
	if vx0 < world.winX0 or vy0 < world.winY0 or vx1 > world.winX1 or vy1 > world.winY1 then
		return true
	end
	local vw = vx1 - vx0
	if world.winW > 0 and (vw < world.winW * 0.5 or vw > world.winW * 2.0) then
		return true
	end
	return false
end

local function WorldOnUpdate()
	local mapID, w, h, scale, zoom, pinScale, alpha, api = ReadWorldView()
	if mapID == nil and not world.shown then
		return
	end
	local stitched = api ~= nil
	local first = not world.shown
	local mapChanged = mapID ~= world.mapID or stitched ~= world.stitched
	local sized = w ~= world.width or h ~= world.height
	local scaled = scale ~= world.scale or zoom ~= world.zoom or pinScale ~= world.pinScale
	local faded = alpha ~= world.alpha

	world.mapID = mapID
	world.stitched = stitched
	world.width = w
	world.height = h
	world.scale = scale
	world.zoom = zoom
	world.pinScale = pinScale
	world.alpha = alpha

	if first then
		world.shown = true
		if world.dirty or not world.builtOnce or mapChanged or sized or ViewportStale() then
			ns.BuildWorldMapPins()
			return
		end
		if scaled then
			RescaleWorldPins()
		end
		if faded then
			ApplyWorldAlpha()
		end
		return
	end
	if world.dirty or mapChanged or sized then
		ns.BuildWorldMapPins()
		return
	end
	if ViewportStale() then
		ns.BuildWorldMapPins()
		return
	end
	if scaled then
		RescaleWorldPins()
	end
	if faded then
		ApplyWorldAlpha()
	end
end

local function WorldOnHide()
	if not world.shown then
		return
	end
	world.shown = false
	world.pressed = nil
	if world.hovered then
		if world.hovered.Hover then
			world.hovered.Hover:Hide()
		end
		world.hovered = nil
		ns.HidePinTooltip()
	end
end

function ns.AttachWorldMap()
	if ns.worldMapAttached then
		return
	end
	if not WorldMapFrame or type(WorldMapFrame.GetCanvas) ~= "function" then
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	if not canvas then
		return
	end
	ns.worldMapAttached = true
	world.canvas = canvas

	local host = CreateFrameUnder("Frame", canvas)
	host:SetScript("OnUpdate", WorldOnUpdate)
	host:SetScript("OnHide", WorldOnHide)
	world.host = host

	if not world.events then
		local ev = CreateFrame("Frame")
		pcall(ev.RegisterEvent, ev, "GLOBAL_MOUSE_DOWN")
		pcall(ev.RegisterEvent, ev, "GLOBAL_MOUSE_UP")
		pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
		ev:SetScript("OnEvent", function(_, event, button)
			if event == "GLOBAL_MOUSE_DOWN" then
				if button == "LeftButton" and world.hovered then
					world.pressed = world.hovered
				else
					world.pressed = nil
				end
			elseif event == "GLOBAL_MOUSE_UP" then
				local target = world.pressed
				world.pressed = nil
				if button == "LeftButton" and target and target == world.hovered
					and type(target.IsVisible) == "function" and target:IsVisible() then
					ns.PinClick(target, button)
				end
			elseif event == "PLAYER_REGEN_ENABLED" then
				if world.passPending then
					world.passPending = false
					for _, pin in ipairs(world.pins) do
						if not pin.passThroughSet then
							PassRightButton(pin)
						end
					end
				end
				if world.levelPending then
					world.levelPending = false
					world.dirty = true
				end
			end
		end)
		world.events = ev
	end
end

function ns.RefreshPins()
	ns.minimapDirty = true
	visibleCache.key = nil
	world.dirty = true
	if world.shown then
		ns.BuildWorldMapPins()
	end
end

local mini = {
	pins = {},
	acc = 0,
	driver = nil,
	lastCont = nil,
	lastNorth = nil,
	lastWest = nil,
	lastRadius = nil,
	lastFacing = nil,
	lastW = nil,
	lastH = nil,
	lastKey = nil,
}
ns.minimap = mini

local function PlayerWorld()
	local best = C_Map and C_Map.GetBestMapForUnit
	local position = C_Map and C_Map.GetPlayerMapPosition
	if type(best) ~= "function" or type(position) ~= "function" then
		return nil
	end
	local okMap, mapID = pcall(best, "player")
	mapID = okMap and ns.PlainNumber(mapID) or nil
	if not mapID then
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

local function MinimapViewRadius()
	local radiusFunc = C_Minimap and C_Minimap.GetViewRadius
	if type(radiusFunc) == "function" then
		local okRadius, radius = ns.SafeCall(radiusFunc)
		radius = okRadius and ns.PlainNumber(radius) or nil
		if radius and radius > 0 then
			return radius
		end
	end
	if Minimap and type(Minimap.GetZoom) == "function" then
		local okZoom, zoom = ns.SafeCall(Minimap.GetZoom, Minimap)
		zoom = okZoom and ns.PlainNumber(zoom) or nil
		if zoom then
			local mode = "outdoor"
			if type(GetCVar) == "function" then
				local okCvar, cvarZoom = pcall(GetCVar, "minimapZoom")
				if okCvar and not ns.IsSecret(cvarZoom) and tonumber(cvarZoom) ~= zoom then
					mode = "indoor"
				end
			end
			local diameter = MINIMAP_DIAMETERS[mode][zoom]
			if diameter and diameter > 0 then
				return diameter / 2
			end
		end
	end
	return nil
end

local function NewMinimapPin()
	local pin = CreateFrame("Button", nil, Minimap)
	pin.isMinimap = true
	pin.pinSize = 14
	pin:SetSize(14, 14)
	pin:SetFrameStrata("HIGH")
	if Minimap and type(Minimap.GetFrameLevel) == "function" then
		pin:SetFrameLevel(Minimap:GetFrameLevel() + 20)
	end
	pin:EnableMouse(true)
	pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	pin.Ring = pin:CreateTexture(nil, "BACKGROUND")
	pin.Ring:SetAllPoints(pin)
	pin.Ring:SetTexture(WHITE)

	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2)
	pin.Icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)
	pin.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	pin.Count = pin:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	pin.Count:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 5, -3)

	pin.Hover = pin:CreateTexture(nil, "HIGHLIGHT")
	pin.Hover:SetAllPoints(pin)
	pin.Hover:SetTexture(WHITE)
	pin.Hover:SetVertexColor(1, 1, 1, 0.25)
	if type(pin.Hover.SetBlendMode) == "function" then
		pin.Hover:SetBlendMode("ADD")
	end

	pin:SetScript("OnClick", function(self, button)
		ns.PinClick(self, button)
	end)
	pin:SetScript("OnEnter", function(self)
		ns.ShowPinTooltip(self)
	end)
	pin:SetScript("OnLeave", function()
		ns.HidePinTooltip()
	end)
	pin:Hide()
	return pin
end

local function HideMinimapPins()
	for _, pin in ipairs(mini.pins) do
		pin:Hide()
	end
	mini.lastCont = nil
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
		local playerContinent, playerNorth, playerWest = PlayerWorld()
		if not playerContinent or not playerNorth or not playerWest then
			HideMinimapPins()
			return
		end

		local radius = MinimapViewRadius()
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

		local visibleVendors, wanted, filterKey = VisibleVendorsCached()
		if not ns.minimapDirty
			and mini.lastCont == playerContinent
			and mini.lastRadius == radius
			and mini.lastW == width
			and mini.lastH == height
			and mini.lastKey == filterKey
			and mini.lastNorth and math.abs(mini.lastNorth - playerNorth) < 0.5
			and mini.lastWest and math.abs(mini.lastWest - playerWest) < 0.5
			and mini.lastFacing and math.abs(mini.lastFacing - facing) < 0.01 then
			return
		end
		ns.minimapDirty = false
		mini.lastCont = playerContinent
		mini.lastNorth = playerNorth
		mini.lastWest = playerWest
		mini.lastRadius = radius
		mini.lastFacing = facing
		mini.lastW = width
		mini.lastH = height
		mini.lastKey = filterKey

		local c = math.cos(facing)
		local s = math.sin(facing)

		local size = 14
		local limitX = width / 2 - size / 2 - 2
		local limitY = height / 2 - size / 2 - 2
		local square = GetMinimapShape and GetMinimapShape() == "SQUARE"

		local candidates = {}
		for _, vendor in ipairs(visibleVendors) do
			local continent, vendorNorth, vendorWest = VendorWorldPos(vendor)
			if continent and vendorNorth and vendorWest and continent == playerContinent then
				local east = playerWest - vendorWest
				local south = playerNorth - vendorNorth
				local rx = east * c - south * s
				local ry = east * s + south * c
				local x = rx / radius * (width / 2)
				local y = -ry / radius * (height / 2)
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
					kind = VendorIconKind(candidate.vendor, wanted),
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
			ns.RenderPin(pin)
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
