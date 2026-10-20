--===========================================================================
-- EzWoW - Smart Fishing
-- Core/Init.lua : Event Bus, Safe Value Coercers, SavedVariables & Slash Commands
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local CoreBootstrap = ns.CoreBootstrap or {}
ns.CoreBootstrap = CoreBootstrap
local L = ns.L

ns.name = "EzWoW - Smart Fishing"

local DEFAULTS = {
    oneButton = true,   
    key = "SPACE",      
    autoLure = true,    
    showPins = true,    
    setSoftInteract = true, 
    combatSwap = true,  
    reequipPole = true, 
    showHUD = true,     
    hudScale = 1.0,     
    pinScale = 1.0,     
    sessionIdle = 15,   
    newFishAlert = true, 
    autoLoot = true,    
    expandInteract = true, 
    minimapButton = true, 
    mapButton = true,   
    mapButtonAutoAlign = true, 
    showPools = true,   
    showExpected = true, 
    showLegend = true,  
    itemTooltip = true, 
    language = "auto",  
    legendCollapsed = true, 
    shareCatches = true, 
    receiveShared = true, 
    showShared = true,  
    minimapAngle = 200, 
}

local containerFrame = CreateFrame("Frame")
local EVENT_DISPATCH_TABLE = {}

function ns:SubscribeAddonEvent(event, fn)
    if not EVENT_DISPATCH_TABLE[event] then
        EVENT_DISPATCH_TABLE[event] = {}
        if not event:match("^AM_") then
            containerFrame:RegisterEvent(event)
        end
    end
    table.insert(EVENT_DISPATCH_TABLE[event], fn)
end

function ns:PublishAddonEvent(event, ...)
    local itemList = EVENT_DISPATCH_TABLE[event]
    if not itemList then return end
    for _, fn in ipairs(itemList) do
        local isCallOk, errorObj = pcall(fn, ...)
        if not isCallOk then geterrorhandler()(errorObj) end
    end
end

containerFrame:SetScript("OnEvent", function(_, event, ...)
    ns:PublishAddonEvent(event, ...)
end)

function CoreBootstrap.pass(isCallOk, ...)
    if isCallOk then return ... end
end

function ns.UnwrapSafeValue(fn, ...)
    if type(fn) ~= "function" then return end
    return CoreBootstrap.pass(pcall(fn, ...))
end

function ns.IsReadableValue(v)
    if v == nil then return false end
    if issecretvalue then
        local isCallOk, secret = pcall(issecretvalue, v)
        if not isCallOk or secret then return false end
    end
    if canaccessvalue then
        local isCallOk, can = pcall(canaccessvalue, v)
        if not isCallOk or not can then return false end
    end
    return true
end

function ns.CoerceSafeString(v) if ns.IsReadableValue(v) and type(v) == "string" then return v end end
function ns.CoerceSafeNumber(v) if ns.IsReadableValue(v) and type(v) == "number" and v == v then return v end end

function ns:Print(msg)
    print("|cff60cea3[EzWoW - Smart Fishing]|r " .. tostring(msg))
end

ns:SubscribeAddonEvent("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    if type(EzWoW_SmartFishingDB) ~= "table" then
        if type(EzWoW_SmartFishingDB) == "table" then
            EzWoW_SmartFishingDB = EzWoW_SmartFishingDB
        else
            EzWoW_SmartFishingDB = {}
        end
    end
    EzWoW_SmartFishingDB = EzWoW_SmartFishingDB
    local savedDB = EzWoW_SmartFishingDB
    savedDB.version = 1
    savedDB.spots = savedDB.spots or {}       
    savedDB.settings = savedDB.settings or {}
    for entryKey, v in pairs(DEFAULTS) do
        if savedDB.settings[entryKey] == nil then savedDB.settings[entryKey] = v end
    end
    ns.db = savedDB
    ns.settings = savedDB.settings
    
    ns:ApplyLanguage(savedDB.settings.language)
    ns:PublishAddonEvent("AM_DB_READY")
end)

function CoreBootstrap.formatBooleanStateLabel(v) return v and L["|cff00ff00켜짐|r"] or L["|cffff4040꺼짐|r"] end

function CoreBootstrap.toggleBooleanOption(key, label)
    ns.settings[key] = not ns.settings[key]
    ns:Print(label .. ": " .. CoreBootstrap.formatBooleanStateLabel(ns.settings[key]))
    ns:PublishAddonEvent("AM_SETTINGS_CHANGED", key)
end

SLASH_EZWOWSMARTFISHING1 = "/ezsf"
SLASH_EZWOWSMARTFISHING2 = "/ezsf"
SLASH_EZWOWSMARTFISHING3 = "/스마트낚시"
SlashCmdList.EZWOWSMARTFISHING = function(msg)
    local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        ns:ToggleWindow()
    elseif cmd == "onebutton" or cmd == "원버튼" then
        CoreBootstrap.toggleBooleanOption("oneButton", L["원버튼 낚시"])
    elseif cmd == "lure" or cmd == "미끼" then
        CoreBootstrap.toggleBooleanOption("autoLure", L["자동 미끼"])
    elseif cmd == "pins" or cmd == "핀" then
        CoreBootstrap.toggleBooleanOption("showPins", L["지도 핀"])
    elseif cmd == "key" or cmd == "키" then
        if arg == "" then
            ns:Print(L["현재 원버튼 키: %s  (예: /ezsf key F)"]:format(ns.settings.key))
            return
        end
        ns.settings.key = arg:upper()
        ns:Print(L["원버튼 키를 %s(으)로 바꿨습니다."]:format(ns.settings.key))
        ns:PublishAddonEvent("AM_SETTINGS_CHANGED", "key")
    elseif cmd == "lang" or cmd == "언어" then
        local codes = {
            ko = "koKR", kr = "koKR", kokr = "koKR",
            en = "enUS", enus = "enUS", engb = "enUS",
            de = "deDE", dede = "deDE",
            fr = "frFR", frfr = "frFR",
            es = "esES", eses = "esES", esmx = "esES",
            ru = "ruRU", ruru = "ruRU",
            cn = "zhCN", zhcn = "zhCN",
            tw = "zhTW", zhtw = "zhTW", zh = "zhTW",
            auto = "auto",
        }
        local code = codes[arg:lower()] or (ns.LANGUAGE_NAMES[arg] and arg)
        if not code then
            ns:Print(L["사용법: /ezsf lang auto | ko | en | de | fr | es | ru | cn | tw"])
            return
        end
        ns:SetLanguage(code)
    elseif cmd == "donate" or cmd == "후원" then
        ns:ShowDonate()
    elseif cmd == "config" or cmd == "설정" then
        ns:OpenSettings()
    elseif cmd == "gear" or cmd == "장비" or cmd == "pole" then
        ns:EquipBestPole()
    elseif cmd == "hud" then
        CoreBootstrap.toggleBooleanOption("showHUD", L["세션 창"])
    elseif cmd == "session" or cmd == "세션" then
        ns:ResetSession()
        ns:Print(L["새 낚시 세션을 시작했어요."])
    elseif cmd == "reset" or cmd == "초기화" then
        local mapID = C_Map.GetBestMapForUnit("player")
        if arg == "all" or arg == "전체" then
            wipe(ns.db.spots)
            ns:Print(L["모든 낚시 기록을 지웠습니다."])
        elseif mapID then
            ns.db.spots[mapID] = nil
            ns:Print(L["현재 지역 낚시 기록을 지웠습니다."])
        end
        ns:PublishAddonEvent("AM_DATA_CHANGED")
    else
        ns:Print(L["명령어:"])
        print(L["  /ezsf — 낚시 기록 창 열기/닫기"])
        print(L["  /ezsf config — 설정 열기 (게임 설정 > 애드온)"])
        print(L["  /ezsf onebutton — 원버튼 낚시 켜기/끄기"])
        print(L["  /ezsf key F — 원버튼 키 변경 (기본 SPACE)"])
        print(L["  /ezsf lure — 자동 미끼 켜기/끄기"])
        print(L["  /ezsf pins — 세계지도 핀 켜기/끄기"])
        print(L["  /ezsf pole — 가장 좋은 낚싯대 착용 / 평소 무기로"])
        print(L["  /ezsf hud — 세션 창 켜기/끄기"])
        print(L["  /ezsf session — 새 세션 시작"])
        print(L["  /ezsf reset — 현재 지역 지점 기록 삭제 (/ezsf reset all: 전체)"])
        print(L["  /ezsf lang en — 애드온 언어 변경 (auto, ko, en, de, fr, es, ru, cn, tw)"])
        print(L["  /ezsf donate — 후원 링크"])
    end
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
CoreBootstrap.PublishAddonEvent = ns.PublishAddonEvent
CoreBootstrap.CoerceSafeNumber = ns.CoerceSafeNumber
CoreBootstrap.SubscribeAddonEvent = ns.SubscribeAddonEvent
CoreBootstrap.IsReadableValue = ns.IsReadableValue
CoreBootstrap.UnwrapSafeValue = ns.UnwrapSafeValue
CoreBootstrap.CoerceSafeString = ns.CoerceSafeString
