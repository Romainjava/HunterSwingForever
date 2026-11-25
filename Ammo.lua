-- Hunter Swing Forever by Illusion
-- Unit 5: ammo left (count, percentage, colour) and the equipped ammo kind.
local ADDON, ns = ...

local ammo = {
	count = nil,
	percent = nil,
	peak = 0,
	capacity = nil,
	kind = nil,
	icon = nil,
	text = nil,
	raw = nil,
	last = 0,
}
ns.ammo = ammo

local BANDS = {
	{ 70, "ff40d860" },
	{ 50, "ffa6d96a" },
	{ 30, "ffffc04d" },
	{ 15, "ffff8c2e" },
	{ 0, "fff23a3a" },
}
local NO_PERCENT = "ff9ea3aa"

local function AmmoColour(percent)
	if not percent then
		return NO_PERCENT
	end
	for _, band in ipairs(BANDS) do
		if percent >= band[1] then
			return band[2]
		end
	end
	return NO_PERCENT
end
ns.AmmoColour = AmmoColour

local function ItemInfo(itemID)
	if not itemID then
		return nil
	end
	local func = C_Item and C_Item.GetItemInfo
	if type(func) ~= "function" then
		return nil
	end
	local ok, name, _, _, _, _, itemType, itemSubType, stack, _, texture, _, classID, subclassID = pcall(func, itemID)
	if not ok then
		return nil
	end
	return {
		name = name,
		itemType = itemType,
		itemSubType = itemSubType,
		stack = stack,
		texture = texture,
		classID = classID,
		subclassID = subclassID,
	}
end

ns.ItemInfo = ItemInfo

local function StackSize(itemID)
	local func = C_Item and C_Item.GetItemMaxStackSizeByID
	if type(func) == "function" and itemID then
		local ok, value = pcall(func, itemID)
		local size = ok and ns.PlainNumber(value) or nil
		if size and size > 0 then
			return size
		end
	end
	local info = ItemInfo(itemID)
	local size = info and ns.PlainNumber(info.stack) or nil
	if size and size > 0 then
		return size
	end
	return 200
end

local function BagItemID(bag)
	local ok, value = ns.SafeCall(_G.GetInventoryItemID, "player", 19 + bag)
	if not ok then
		return nil
	end
	return ns.PlainNumber(value)
end

local function ContainerSlots(bag)
	local func = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
	local ok, value = ns.SafeCall(func, bag)
	if not ok then
		return nil
	end
	return ns.PlainNumber(value)
end

local function QuiverCapacity(ammoID)
	local stack = StackSize(ammoID)
	local slots = 0
	for bag = 1, 4 do
		local itemID = BagItemID(bag)
		if itemID then
			local info = ItemInfo(itemID)
			local isQuiver = info and (info.classID == 11 or info.itemType == "Quiver")
			if isQuiver then
				local count = ContainerSlots(bag)
				if count and count > 0 then
					slots = slots + count
				end
			end
		end
	end
	if slots > 0 then
		return slots * stack
	end
	return nil
end

local function EquippedAmmo()
	local ok, value = ns.SafeCall(_G.GetInventoryItemID, "player", 0)
	local itemID = ok and ns.PlainNumber(value) or nil
	local info = itemID and ItemInfo(itemID) or nil
	return itemID, info
end

local function AmmoKind(info)
	if not info then
		return nil
	end
	if info.classID == 6 and info.subclassID == 2 then
		return "arrow"
	end
	if info.classID == 6 and info.subclassID == 3 then
		return "bullet"
	end
	return nil
end

function ns.EquippedAmmoKind()
	local _, info = EquippedAmmo()
	return AmmoKind(info)
end

function ns.UpdateAmmo(now)
	if not ns.db then
		return
	end
	if now - ammo.last < 0.1 then
		return
	end
	ammo.last = now

	local okCount, countValue = ns.SafeCall(_G.GetInventoryItemCount, "player", 0)
	local count = okCount and ns.PlainNumber(countValue) or nil
	local previous = ammo.count
	ammo.count = count

	local itemID, info = EquippedAmmo()
	ammo.kind = AmmoKind(info)
	ammo.capacity = QuiverCapacity(itemID)

	local okTexture, texture = ns.SafeCall(_G.GetInventoryItemTexture, "player", 0)
	ammo.icon = (okTexture and not ns.IsSecret(texture) and type(texture) == "string") and texture or nil

	if count then
		if (previous and count > previous) or count > ammo.peak then
			ammo.peak = count
		end
	end

	local percent
	if count then
		local full = ammo.capacity or ammo.peak
		if count == 0 then
			percent = 0
		elseif full and full > 0 then
			percent = math.floor(math.min(1, count / full) * 100 + 0.5)
		end
	end
	ammo.percent = percent

	local mode = ns.db.ammoDisplay
	local raw, coloured
	if mode == "percent" then
		if percent then
			raw = string.format("%d%%", percent)
		end
	elseif mode == "count" then
		if count then
			raw = tostring(count)
		end
	end

	if raw then
		local colour = AmmoColour(percent)
		if not ammo.icon then
			if ammo.kind == "arrow" then
				raw = "Arrows " .. raw
			elseif ammo.kind == "bullet" then
				raw = "Bullets " .. raw
			else
				raw = "Ammo " .. raw
			end
		end
		coloured = "|c" .. colour .. raw .. "|r"
	end

	ammo.raw = raw
	ammo.text = coloured
end
