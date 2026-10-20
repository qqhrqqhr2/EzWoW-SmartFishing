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

-- Weapons are not saved anywhere: the pair worn just before the pole went on
-- is remembered for this session and is what every "back to weapons" uses.
local weaponsBeforePole   -- { [16] = itemID, [17] = itemID } while a pole is in the main hand
local lastWeapons = {}    -- what was worn the last time the main hand held no pole
local poleBeforeCombat    -- pole taken off by the combat swap

ns:SubscribeAddonEvent("AM_DB_READY", function()
    ns.db.gear = nil   -- weapon/pole IDs used to be saved here
end)

function FishingGearManager.isItemInPlayerBags(itemID)
    return itemID and (C_Item.GetItemCount(itemID) > 0)
end

function FishingGearManager.poleInMainHand()
    return FishingGearManager.hasPoleItem(GetInventoryItemID("player", 16))
end

function FishingGearManager.wornWeapons()
    return { [16] = GetInventoryItemID("player", 16), [17] = GetInventoryItemID("player", 17) }
end

ns:SubscribeAddonEvent("PLAYER_EQUIPMENT_CHANGED", function(slot)
    if slot ~= 16 and slot ~= 17 and slot ~= nil then return end
    if FishingGearManager.poleInMainHand() then
        -- pole put on by hand (drag / macro): fall back to the last weapons seen
        if not weaponsBeforePole and lastWeapons[16] then
            weaponsBeforePole = { [16] = lastWeapons[16], [17] = lastWeapons[17] }
        end
    else
        weaponsBeforePole = nil
        lastWeapons = FishingGearManager.wornWeapons()
    end
end)

function FishingGearManager.equipWeaponSet(set)
    if not (set and FishingGearManager.isItemInPlayerBags(set[16])) then return false end
    equipTargetItemSlot(set[16], 16)
    if FishingGearManager.isItemInPlayerBags(set[17]) then equipTargetItemSlot(set[17], 17) end
    return true
end

ns:SubscribeAddonEvent("PLAYER_REGEN_DISABLED", function()
    if not ns.settings or not ns.settings.combatSwap or not FishingGearManager.poleInMainHand() then return end
    local pole = GetInventoryItemID("player", 16)
    if FishingGearManager.equipWeaponSet(weaponsBeforePole) then
        poleBeforeCombat = pole
    end
end)

ns:SubscribeAddonEvent("PLAYER_REGEN_ENABLED", function()
    local pole = poleBeforeCombat
    if not pole then return end
    poleBeforeCombat = nil
    if ns.settings.reequipPole and FishingGearManager.isItemInPlayerBags(pole) and not FishingGearManager.poleInMainHand() then
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then equipTargetItemSlot(pole, 16) end
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
        elseif FishingGearManager.poleInMainHand() then
            ns:EquipWeapons()
        end
        return
    end
    if not bagID then
        ns:Print(L["가방에 낚싯대가 없어요."])
        return
    end
    if not FishingGearManager.poleInMainHand() then
        weaponsBeforePole = FishingGearManager.wornWeapons()
    end
    equipTargetItemSlot(bagID, 16)
    ns:Print(string.format(L["%s 착용 (낚시 +%d)"], ns:ItemName(bagID), bagBonus))
end

function ns:EquipWeapons()
    if FishingGearManager.equipWeaponSet(weaponsBeforePole) then return true end
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
    if FishingGearManager.poleInMainHand() then ns:EquipWeapons() end
end
