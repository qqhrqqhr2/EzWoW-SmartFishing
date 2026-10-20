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

-- The weapons worn just before the pole goes on are saved per character
-- (so /reload or relogging with the pole in hand still knows them) and
-- cleared once the main hand holds no pole again.
local lastWeapons = {}    -- what was worn the last time the main hand held no pole
local poleBeforeCombat    -- pole taken off by the combat swap

function FishingGearManager.characterKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

function FishingGearManager.savedWeapons()
    local store = ns.db and ns.db.weaponsBeforePole
    return store and store[FishingGearManager.characterKey()]
end

function FishingGearManager.rememberWeapons(set)
    if not ns.db then return end
    ns.db.weaponsBeforePole = ns.db.weaponsBeforePole or {}
    ns.db.weaponsBeforePole[FishingGearManager.characterKey()] = set and set[16] and { [16] = set[16], [17] = set[17] } or nil
end

ns:SubscribeAddonEvent("AM_DB_READY", function()
    ns.db.gear = nil   -- old format: last weapons rewritten on every equipment change
end)

function FishingGearManager.isItemInPlayerBags(itemID)
    return itemID and (C_Item.GetItemCount(itemID) > 0)
end

function FishingGearManager.poleInMainHand()
    return FishingGearManager.hasPoleItem(GetInventoryItemID("player", 16))
end

-- Clickable item link when cached, plain name otherwise
function FishingGearManager.itemText(itemID)
    if not itemID then return "" end
    local link = (C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(itemID)))
        or (GetItemInfo and select(2, GetItemInfo(itemID)))
    return link or ns:ItemName(itemID)
end

function FishingGearManager.weaponSetText(set)
    local parts = {}
    if set and set[16] then parts[#parts + 1] = FishingGearManager.itemText(set[16]) end
    if set and set[17] then parts[#parts + 1] = FishingGearManager.itemText(set[17]) end
    return #parts > 0 and table.concat(parts, ", ") or L["맨손"]
end

function FishingGearManager.wornWeapons()
    return { [16] = GetInventoryItemID("player", 16), [17] = GetInventoryItemID("player", 17) }
end

ns:SubscribeAddonEvent("PLAYER_EQUIPMENT_CHANGED", function(slot)
    if slot ~= 16 and slot ~= 17 and slot ~= nil then return end
    if FishingGearManager.poleInMainHand() then
        -- pole put on by hand (drag / macro): fall back to the last weapons seen
        if not FishingGearManager.savedWeapons() and lastWeapons[16] then
            FishingGearManager.rememberWeapons(lastWeapons)
            ns:Print(string.format(L["낚싯대 착용 전 장비를 기억했어요: %s"], FishingGearManager.weaponSetText(lastWeapons)))
        end
    elseif ns.db then
        lastWeapons = FishingGearManager.wornWeapons()
        if not poleBeforeCombat then FishingGearManager.rememberWeapons(nil) end
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
    -- set first: the swap's equipment events must not clear the saved weapons
    poleBeforeCombat = GetInventoryItemID("player", 16)
    local saved = FishingGearManager.savedWeapons()
    if FishingGearManager.equipWeaponSet(saved) then
        ns:Print(string.format(L["전투 시작: %s 벗고 %s 착용"], FishingGearManager.itemText(poleBeforeCombat), FishingGearManager.weaponSetText(saved)))
    else
        poleBeforeCombat = nil
    end
end)

ns:SubscribeAddonEvent("PLAYER_REGEN_ENABLED", function()
    local pole = poleBeforeCombat
    if not pole then return end
    poleBeforeCombat = nil
    if ns.settings.reequipPole and FishingGearManager.isItemInPlayerBags(pole) and not FishingGearManager.poleInMainHand() then
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                equipTargetItemSlot(pole, 16)
                ns:Print(string.format(L["전투 끝: 다시 %s 착용"], FishingGearManager.itemText(pole)))
            end
        end)
    elseif not FishingGearManager.poleInMainHand() then
        FishingGearManager.rememberWeapons(nil)   -- staying on weapons: back to normal
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
    local worn = FishingGearManager.wornWeapons()
    FishingGearManager.rememberWeapons(worn)
    equipTargetItemSlot(bagID, 16)
    if worn[16] then
        ns:Print(string.format(L["%s 벗고 %s 착용 (낚시 +%d). 낚시를 마치면 원래 장비로 돌아갑니다."],
            FishingGearManager.weaponSetText(worn), FishingGearManager.itemText(bagID), bagBonus))
    else
        ns:Print(string.format(L["%s 착용 (낚시 +%d)"], FishingGearManager.itemText(bagID), bagBonus))
    end
end

function ns:EquipWeapons()
    local saved = FishingGearManager.savedWeapons()
    local pole = GetInventoryItemID("player", 16)
    if FishingGearManager.equipWeaponSet(saved) then
        ns:Print(string.format(L["%s 벗고 원래 장비 %s 착용"], FishingGearManager.itemText(pole), FishingGearManager.weaponSetText(saved)))
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
    if FishingGearManager.poleInMainHand() then ns:EquipWeapons() end
end
