--===========================================================================
-- EzWoW - Smart Fishing
-- Modules/FishingCast.lua : Double-Right-Click Secure Casting, Lure & Bobber Soft-Target
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local DoubleClickCastEngine = ns.DoubleClickCastEngine or {}
ns.DoubleClickCastEngine = DoubleClickCastEngine

local FISHING_IDS = { 131474, 7620, 7731, 7732, 18248 }
local FISHING_SET = {}
for _, entityID in ipairs(FISHING_IDS) do FISHING_SET[entityID] = true end

local LURES = {
    { id = 6533, bonus = 100 }, 
    { id = 6532, bonus = 75 },  
    { id = 7307, bonus = 75 },  
    { id = 6811, bonus = 50 },  
    { id = 6530, bonus = 50 },  
    { id = 6529, bonus = 25 },  
}

local ownerFrame = CreateFrame("Frame", "EzWoW_SmartFishingBindingOwner")
local castButton = CreateFrame("Button", "EzWoW_SmartFishingCastButton", UIParent, "SecureActionButtonTemplate")
castButton:RegisterForClicks("AnyUp", "AnyDown")
castButton:SetAttribute("type", "macro")
castButton:Hide()

local mode           
local channeling = false

function DoubleClickCastEngine.resolveFishingSpellName()
    for _, entityID in ipairs(FISHING_IDS) do
        if IsPlayerSpell(entityID) then
            return C_Spell.GetSpellName(entityID)
        end
    end
    return C_Spell.GetSpellName(7620)
end

function DoubleClickCastEngine.hasFishingSpell(spellID)
    spellID = ns.CoerceSafeNumber(spellID)
    if spellID and FISHING_SET[spellID] then return true end
    local displayName = spellID and C_Spell.GetSpellName(spellID)
    return displayName ~= nil and displayName == DoubleClickCastEngine.resolveFishingSpellName()
end

ns.IsFishingSpell = DoubleClickCastEngine.hasFishingSpell

function ns:FishingSkill()
    if not GetProfessions then return nil end
    local isCallOk, _, _, _, fishing = pcall(GetProfessions)
    if not isCallOk or not fishing then return nil end
    local ok2, _, _, rank, maxRank, _, _, _, modifier = pcall(GetProfessionInfo, fishing)
    if not ok2 or not rank then return nil end
    return rank, maxRank, modifier or 0
end

function ns:LureRemaining()
    local containsMain, expiration = GetWeaponEnchantInfo()
    if containsMain and expiration then return expiration / 1000 end
end

function DoubleClickCastEngine.hasPole(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    
    return (classID == 2 and subClassID == 20) or (classID == 19 and subClassID == 10)
end

function DoubleClickCastEngine.containsPole()
    return DoubleClickCastEngine.hasPole(GetInventoryItemID("player", 16)) or DoubleClickCastEngine.hasPole(GetInventoryItemID("player", 28))
end

function ns:HasPole() return DoubleClickCastEngine.containsPole() end

function DoubleClickCastEngine.resolveBestLure()
    for _, lure in ipairs(LURES) do
        if C_Item.GetItemCount(lure.id) > 0 then return lure end
    end
end

function DoubleClickCastEngine.needsLure()
    if not ns.settings.autoLure then return false end
    local containsMainHandEnchant = GetWeaponEnchantInfo()
    if containsMainHandEnchant then return false end
    return DoubleClickCastEngine.resolveBestLure() ~= nil
end

function DoubleClickCastEngine.assembleMacro()
    if DoubleClickCastEngine.needsLure() then
        local lure = DoubleClickCastEngine.resolveBestLure()
        return "/use item:" .. lure.id .. "\n/use 16"
    end
    local displayName = DoubleClickCastEngine.resolveFishingSpellName()
    if displayName then return "/cast " .. displayName end
    return ""
end

function DoubleClickCastEngine.assignMode(newMode)
    if InCombatLockdown() then return end
    if newMode == mode then return end
    ClearOverrideBindings(ownerFrame)
    local lookupKey = ns.settings and ns.settings.key or "SPACE"
    if newMode == "cast" then
        SetOverrideBindingClick(ownerFrame, true, lookupKey, "EzWoW_SmartFishingCastButton", "LeftButton")
    elseif newMode == "interact" then
        SetOverrideBinding(ownerFrame, true, lookupKey, "INTERACTTARGET")
    elseif newMode == "mouseover" then
        
        SetOverrideBinding(ownerFrame, true, lookupKey, "INTERACTMOUSEOVER")
    end
    mode = newMode
end

local BOBBER_ID = "35591"

function DoubleClickCastEngine.resolveBobberTargeted()
    local guid = ns.CoerceSafeString(ns.UnwrapSafeValue(UnitGUID, "softinteract"))
    if not guid then return false end
    local kind, _, _, _, _, entityID = strsplit("-", guid)
    if kind ~= "GameObject" then return false end
    if entityID == BOBBER_ID then return true end
    local displayName = ns.CoerceSafeString(ns.UnwrapSafeValue(UnitName, "softinteract"))
    return displayName ~= nil and (displayName:find("찌") or displayName:find("Bobber") or displayName:find("Schwimmer") or displayName:find("Flotteur") or displayName:find("Corcho") or displayName:find("浮標")) ~= nil
end

ns.bobberFound = nil

function DoubleClickCastEngine.refreshActiveView()
    if not ns.settings or InCombatLockdown() then return end
    if not ns.settings.oneButton or not DoubleClickCastEngine.containsPole() then
        DoubleClickCastEngine.assignMode(nil)
        return
    end
    if channeling then
        ns.bobberFound = DoubleClickCastEngine.resolveBobberTargeted()
        DoubleClickCastEngine.assignMode(ns.bobberFound and "interact" or "mouseover")
    else
        ns.bobberFound = nil
        castButton:SetAttribute("macrotext", DoubleClickCastEngine.assembleMacro())
        DoubleClickCastEngine.assignMode("cast")
    end
end
ns.RefreshFishing = DoubleClickCastEngine.refreshActiveView

function DoubleClickCastEngine.assignCVarSafe(displayName, value)
    pcall(function()
        if GetCVar(displayName) ~= nil and GetCVar(displayName) ~= tostring(value) then SetCVar(displayName, value) end
    end)
end

-- Original CVar values are kept account-wide so turning the option off
-- (or disabling the addon's option) puts the player's own settings back.
local SOFT_INTERACT_CVARS = {
    { name = "SoftTargetInteract", value = 3, option = "setSoftInteract" },
    { name = "SoftTargetInteractRange", value = 30, option = "expandInteract" },
    { name = "SoftTargetInteractArc", value = 2, option = "expandInteract" },
}

function DoubleClickCastEngine.cvarBackup()
    local savedDB = _G.EzWoW_SmartFishingDB
    if type(savedDB) ~= "table" then return nil end
    savedDB.cvarBackup = type(savedDB.cvarBackup) == "table" and savedDB.cvarBackup or {}
    return savedDB.cvarBackup
end

function DoubleClickCastEngine.commitSoftInteract()
    if InCombatLockdown() then
        DoubleClickCastEngine.softInteractPending = true
        return
    end
    DoubleClickCastEngine.softInteractPending = nil
    local backup = DoubleClickCastEngine.cvarBackup()
    if not backup then return end
    local master = ns.settings.setSoftInteract
    for _, cv in ipairs(SOFT_INTERACT_CVARS) do
        local wanted = master and ns.settings[cv.option]
        local okRead, current = pcall(GetCVar, cv.name)
        if okRead and current ~= nil then
            if wanted then
                if backup[cv.name] == nil and current ~= tostring(cv.value) then
                    backup[cv.name] = current
                end
                DoubleClickCastEngine.assignCVarSafe(cv.name, cv.value)
            elseif backup[cv.name] ~= nil then
                DoubleClickCastEngine.assignCVarSafe(cv.name, backup[cv.name])
                backup[cv.name] = nil
            end
        end
    end
end

ns:SubscribeAddonEvent("AM_DB_READY", function()
    ns:SubscribeAddonEvent("PLAYER_ENTERING_WORLD", function()
        DoubleClickCastEngine.commitSoftInteract()
        DoubleClickCastEngine.refreshActiveView()
    end)
end)

ns:SubscribeAddonEvent("AM_SETTINGS_CHANGED", function(lookupKey)
    if lookupKey == "setSoftInteract" or lookupKey == "expandInteract" then DoubleClickCastEngine.commitSoftInteract() end
    if lookupKey == "key" then
        DoubleClickCastEngine.assignMode(nil) 
    end
    DoubleClickCastEngine.refreshActiveView()
end)

ns:SubscribeAddonEvent("PLAYER_EQUIPMENT_CHANGED", DoubleClickCastEngine.refreshActiveView)
ns:SubscribeAddonEvent("BAG_UPDATE_DELAYED", DoubleClickCastEngine.refreshActiveView)
ns:SubscribeAddonEvent("UNIT_INVENTORY_CHANGED", function(unit) if unit == "player" then DoubleClickCastEngine.refreshActiveView() end end)
ns:SubscribeAddonEvent("PLAYER_REGEN_ENABLED", function()
    if DoubleClickCastEngine.softInteractPending then DoubleClickCastEngine.commitSoftInteract() end
    DoubleClickCastEngine.refreshActiveView()
end)

ns:SubscribeAddonEvent("PLAYER_REGEN_DISABLED", function()
    ClearOverrideBindings(ownerFrame)
    mode = nil
end)

local watcher = CreateFrame("Frame")
local elapsedAcc = 0
watcher:Hide()
watcher:SetScript("OnUpdate", function(self, dt)
    elapsedAcc = elapsedAcc + dt
    if elapsedAcc < 0.15 then return end
    elapsedAcc = 0
    if not channeling then self:Hide() return end
    local before = ns.bobberFound
    DoubleClickCastEngine.refreshActiveView()
    if before ~= ns.bobberFound then ns:PublishAddonEvent("AM_BOBBER_CHANGED") end
end)

ns:SubscribeAddonEvent("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if ns.CoerceSafeString(unit) ~= "player" or not DoubleClickCastEngine.hasFishingSpell(spellID) then return end
    channeling = true
    DoubleClickCastEngine.refreshActiveView()
    watcher:Show()
    ns:PublishAddonEvent("AM_BOBBER_CHANGED")
end)

ns:SubscribeAddonEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(unit, _, spellID)
    if ns.CoerceSafeString(unit) ~= "player" or not channeling then return end
    channeling = false
    DoubleClickCastEngine.refreshActiveView()
    ns:PublishAddonEvent("AM_BOBBER_CHANGED")
end)
