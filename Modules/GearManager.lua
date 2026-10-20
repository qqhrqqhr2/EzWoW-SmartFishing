--===========================================================================
-- EzWoW - Smart Fishing
-- Modules/GearManager.lua : Best Fishing Pole Scanner & One-Click Weapon Set Swapper
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local FishingGearManager = ns.FishingGearManager or {}
ns.FishingGearManager = FishingGearManager
local L = ns.L

local equipTargetItemSlot = (C_Item and C_Item.EquipItemByName) or EquipItemByName

local swappedForCombat = false

ns:SubscribeAddonEvent("AM_DB_READY", function()
    local savedDB = ns.db
    savedDB.gear = savedDB.gear or {}
    savedDB.gear.fishing, savedDB.gear.normal = nil, nil 
    savedDB.gear.weapons = savedDB.gear.weapons or {}   
end)

function FishingGearManager.isItemInPlayerBags(itemID)
    return itemID and (C_Item.GetItemCount(itemID) > 0)
end

ns:SubscribeAddonEvent("PLAYER_EQUIPMENT_CHANGED", function(slot)
    if not ns.db then return end
    if slot ~= 16 and slot ~= 17 and slot ~= nil then return end
    if ns:HasPole() then
        ns.db.gear.pole = GetInventoryItemID("player", 16) or ns.db.gear.pole
    else
        ns.db.gear.weapons[16] = GetInventoryItemID("player", 16)
        ns.db.gear.weapons[17] = GetInventoryItemID("player", 17)
    end
end)

ns:SubscribeAddonEvent("PLAYER_REGEN_DISABLED", function()
    if not ns.settings or not ns.settings.combatSwap or not ns:HasPole() then return end
    local boxWidth = ns.db.gear.weapons
    if not FishingGearManager.isItemInPlayerBags(boxWidth[16]) then return end
    equipTargetItemSlot(boxWidth[16], 16)
    if FishingGearManager.isItemInPlayerBags(boxWidth[17]) then equipTargetItemSlot(boxWidth[17], 17) end
    swappedForCombat = true
end)

ns:SubscribeAddonEvent("PLAYER_REGEN_ENABLED", function()
    if not swappedForCombat then return end
    swappedForCombat = false
    if ns.settings.reequipPole and FishingGearManager.isItemInPlayerBags(ns.db.gear.pole) and not ns:HasPole() then
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then equipTargetItemSlot(ns.db.gear.pole, 16) end
        end)
    end
end)

local POLE_BONUS = {
    [6256] = 0,    
    [12225] = 3,   
    [6365] = 5,    
    [6366] = 15,   
    [6367] = 20,   
    [19022] = 25,  
    [19970] = 35,  
}

function FishingGearManager.tooltipBonus(itemID)
    if not C_TooltipInfo or not C_TooltipInfo.GetItemByID then return 0 end
    local isCallOk, payloadData = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not isCallOk or not payloadData or not payloadData.lines then return 0 end
    for _, line in ipairs(payloadData.lines) do
        local extractSafeTooltipText = line.leftText
        if extractSafeTooltipText and (extractSafeTooltipText:find("낚시") or extractSafeTooltipText:find("Fishing") or extractSafeTooltipText:find("Angeln") or extractSafeTooltipText:find("Pêche") or extractSafeTooltipText:find("Pesca") or extractSafeTooltipText:find("釣魚")) then
            local nodeEntry = tonumber(extractSafeTooltipText:match("%+(%d+)"))
            if nodeEntry then return nodeEntry end
        end
    end
    return 0
end

function FishingGearManager.resolvePoleBonus(itemID)
    return POLE_BONUS[itemID] or FishingGearManager.tooltipBonus(itemID)
end

function FishingGearManager.hasPoleItem(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return (classID == 2 and subClassID == 20) or (classID == 19 and subClassID == 10)
end

function FishingGearManager.resolveBestPoleInBags()
    local bestID, bestBonus
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local entityID = C_Container.GetContainerItemID(bag, slot)
            if FishingGearManager.hasPoleItem(entityID) then
                local buttonWidget = FishingGearManager.resolvePoleBonus(entityID)
                if not bestBonus or buttonWidget > bestBonus then bestID, bestBonus = entityID, buttonWidget end
            end
        end
    end
    return bestID, bestBonus
end

function ns:EquipBestPole()
    local bagID, bagBonus = FishingGearManager.resolveBestPoleInBags()
    local worn = GetInventoryItemID("player", 16)
    if ns:HasPole() then
        
        if bagID and bagBonus > FishingGearManager.resolvePoleBonus(worn) then
            equipTargetItemSlot(bagID, 16)
            ns:Print(L["더 좋은 낚싯대로 바꿨어요: "] .. ns:ItemName(bagID))
        else
            ns:EquipWeapons()
        end
        return
    end
    if not bagID then
        ns:Print(L["가방에 낚싯대가 없어요."])
        return
    end
    equipTargetItemSlot(bagID, 16)
    ns:Print(string.format(L["%s 착용 (낚시 +%d)"], ns:ItemName(bagID), bagBonus))
end

function ns:EquipWeapons()
    local boxWidth = ns.db.gear.weapons
    if FishingGearManager.isItemInPlayerBags(boxWidth[16]) then
        equipTargetItemSlot(boxWidth[16], 16)
        if FishingGearManager.isItemInPlayerBags(boxWidth[17]) then equipTargetItemSlot(boxWidth[17], 17) end
        return true
    end
    ns:Print(L["돌아갈 무기를 가방에서 찾지 못했어요."])
    return false
end

function ns:StopFishing()
    local stateFlag = ns:Session()
    if stateFlag and stateFlag.catches > 0 then
        local dur = math.max(0, stateFlag.last - stateFlag.start)
        ns:Print(L["낚시를 마쳤어요. 이번 세션: %d마리 · %s"]:format(stateFlag.catches, ns:FormatDuration(dur)))
    end
    ns:EndSession()
    if ns:HasPole() then ns:EquipWeapons() end
end
