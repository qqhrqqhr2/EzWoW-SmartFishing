--===========================================================================
-- EzWoW - Smart Fishing
-- Modules/CatchLog.lua : Live Fishing Session Tracker, Spot Aggregator & Map Projector
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local CatchSessionLogger = ns.CatchSessionLogger or {}
ns.CatchSessionLogger = CatchSessionLogger
local L = ns.L

local MERGE_RADIUS = 0.015

local RECENT_MAX = 100

local lastLootTime = 0
local pendingCast      
local castSerial = 0

ns:SubscribeAddonEvent("AM_DB_READY", function()
    local savedDB = ns.db
    savedDB.journal = savedDB.journal or {}   
    savedDB.recent = savedDB.recent or {}     
    savedDB.totals = savedDB.totals or { casts = 0, catches = 0, missed = 0 }
    savedDB.session = savedDB.session or nil
end)

function CatchSessionLogger.newSession()
    local stateFlag = { start = time(), last = time(), casts = 0, catches = 0, missed = 0, fish = {} }
    ns.db.session = stateFlag
    return stateFlag
end

function ns:Session()
    local stateFlag = ns.db and ns.db.session
    if not stateFlag then return nil end
    if time() - (stateFlag.last or 0) > (ns.settings.sessionIdle or 15) * 60 then return nil end
    return stateFlag
end

function ns:EndSession()
    ns.db.session = nil
    ns:PublishAddonEvent("AM_DATA_CHANGED")
end

function ns:ResetSession()
    CatchSessionLogger.newSession()
    ns:PublishAddonEvent("AM_DATA_CHANGED")
end

function CatchSessionLogger.activeSession()
    return ns:Session() or CatchSessionLogger.newSession()
end

function CatchSessionLogger.locateSpot(spots, x, y)
    local best, bestDist
    for _, stateFlag in ipairs(spots) do
        local dxVal, dyVal = stateFlag.x - x, stateFlag.y - y
        local dataEntry = math.sqrt(dxVal * dxVal + dyVal * dyVal)
        if dataEntry <= MERGE_RADIUS and (not bestDist or dataEntry < bestDist) then
            best, bestDist = stateFlag, dataEntry
        end
    end
    return best
end

function ns:AddCatch(mapID, x, y, items)
    local savedDB = ns.db
    local spots = savedDB.spots[mapID]
    if not spots then
        spots = {}
        savedDB.spots[mapID] = spots
    end

    local spot = CatchSessionLogger.locateSpot(spots, x, y)
    if not spot then
        spot = { x = x, y = y, n = 0, fish = {} }
        table.insert(spots, spot)
    end
    spot.x = (spot.x * spot.n + x) / (spot.n + 1)
    spot.y = (spot.y * spot.n + y) / (spot.n + 1)
    spot.n = spot.n + 1
    spot.last = time()
    local sub = ns.CoerceSafeString(ns.UnwrapSafeValue(GetSubZoneText))
    if sub and sub ~= "" then spot.sub = sub end

    local session = CatchSessionLogger.activeSession()
    session.last = time()
    session.catches = session.catches + 1
    savedDB.totals.catches = savedDB.totals.catches + 1

    local currentTime = time()
    for itemID, qty in pairs(items) do
        spot.fish[itemID] = (spot.fish[itemID] or 0) + qty
        session.fish[itemID] = (session.fish[itemID] or 0) + qty

        local subIndex = savedDB.journal[itemID]
        if not subIndex then
            subIndex = { n = 0, first = currentTime, firstMap = mapID }
            savedDB.journal[itemID] = subIndex
            ns:PublishAddonEvent("AM_NEW_FISH", itemID)
        end
        subIndex.n = subIndex.n + qty
        subIndex.last = currentTime
        subIndex.lastMap = mapID

        table.insert(savedDB.recent, 1, { id = itemID, q = qty, t = currentTime, m = mapID, x = x, y = y, sub = spot.sub })
    end
    while #savedDB.recent > RECENT_MAX do table.remove(savedDB.recent) end

    ns:PublishAddonEvent("AM_CATCH", mapID, x, y, items)
    ns:PublishAddonEvent("AM_DATA_CHANGED")
end

ns:SubscribeAddonEvent("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if ns.CoerceSafeString(unit) ~= "player" or not ns.db or not ns.IsFishingSpell(spellID) then return end
    local session = CatchSessionLogger.activeSession()
    session.casts = session.casts + 1
    session.last = time()
    ns.db.totals.casts = ns.db.totals.casts + 1
    castSerial = castSerial + 1
    pendingCast = castSerial
    ns:PublishAddonEvent("AM_DATA_CHANGED")
end)

ns:SubscribeAddonEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(unit)
    if ns.CoerceSafeString(unit) ~= "player" or not pendingCast then return end
    local serial = pendingCast
    
    C_Timer.After(1.2, function()
        if pendingCast ~= serial then return end
        pendingCast = nil
        local session = ns:Session()
        if session then session.missed = session.missed + 1 end
        ns.db.totals.missed = ns.db.totals.missed + 1
        ns:PublishAddonEvent("AM_DATA_CHANGED")
    end)
end)

ns:SubscribeAddonEvent("LOOT_READY", function()
    if not ns.db or not ns.UnwrapSafeValue(IsFishingLoot) then return end

    local currentTime = GetTime()
    if currentTime - lastLootTime < 1.5 then return end

    local items, any = {}, false
    for slot = 1, (ns.CoerceSafeNumber(ns.UnwrapSafeValue(GetNumLootItems)) or 0) do
        local link = ns.CoerceSafeString(ns.UnwrapSafeValue(GetLootSlotLink, slot))
        if link then
            local itemID = ns.CoerceSafeNumber(ns.UnwrapSafeValue(C_Item.GetItemInfoInstant, link))
            local _, _, quantity = ns.UnwrapSafeValue(GetLootSlotInfo, slot)
            quantity = ns.CoerceSafeNumber(quantity)
            if itemID then
                items[itemID] = (items[itemID] or 0) + (quantity or 1)
                any = true
            end
        end
    end
    if not any then return end

    pendingCast = nil
    lastLootTime = currentTime

    local mapID = ns.CoerceSafeNumber(ns.UnwrapSafeValue(C_Map.GetBestMapForUnit, "player"))
    local coordPos = mapID and ns.UnwrapSafeValue(C_Map.GetPlayerMapPosition, mapID, "player")
    local x, y
    if coordPos then
        local pxVal, pyVal = ns.UnwrapSafeValue(coordPos.GetXY, coordPos)
        x, y = ns.CoerceSafeNumber(pxVal), ns.CoerceSafeNumber(pyVal)
    end
    if not x or (x == 0 and y == 0) then
        
        mapID, x, y = mapID or 0, 0, 0
    end
    ns:AddCatch(mapID, x, y, items)
end)

ns:SubscribeAddonEvent("LOOT_READY", function(isAutoLoot)
    if not ns.settings or not ns.settings.autoLoot or isAutoLoot then return end
    if not ns.UnwrapSafeValue(IsFishingLoot) then return end
    for slot = (ns.CoerceSafeNumber(ns.UnwrapSafeValue(GetNumLootItems)) or 0), 1, -1 do
        LootSlot(slot)
    end
end)

function ns:GetTotalCatchesAtSpot(spot)
    local grandTotal = 0
    for _, themeColor in pairs(spot.fish) do grandTotal = grandTotal + themeColor end
    return grandTotal
end

function ns:GetTopCaughtFishList(spot)
    local bestID, bestCount = nil, 0
    for entityID, themeColor in pairs(spot.fish) do
        if themeColor > bestCount then bestID, bestCount = entityID, themeColor end
    end
    return bestID, bestCount
end

function ns:GetSortedFishBreakdown(fishTable)
    local itemList = {}
    for entityID, themeColor in pairs(fishTable) do
        table.insert(itemList, { id = entityID, count = themeColor })
    end
    table.sort(itemList, function(a, b) return a.count > b.count end)
    return itemList
end

function ns:FormatDuration(sec)
    sec = math.max(0, math.floor(sec))
    local headerBar, matchRef, stateFlag = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if headerBar > 0 then return string.format("%d:%02d:%02d", headerBar, matchRef, stateFlag) end
    return string.format("%d:%02d", matchRef, stateFlag)
end

function ns:MapName(mapID)
    local apiInfo = mapID and mapID ~= 0 and C_Map.GetMapInfo(mapID)
    return apiInfo and apiInfo.name or L["알 수 없는 곳"]
end

local ancestorCache = {}
function CatchSessionLogger.hasAncestor(childID, ancestorID)
    local lookupKey = childID .. ":" .. ancestorID
    if ancestorCache[lookupKey] ~= nil then return ancestorCache[lookupKey] end
    local result = false
    local apiInfo = C_Map.GetMapInfo(childID)
    local guard = 0
    while apiInfo and apiInfo.parentMapID and apiInfo.parentMapID ~= 0 and guard < 10 do
        if apiInfo.parentMapID == ancestorID then result = true break end
        apiInfo = C_Map.GetMapInfo(apiInfo.parentMapID)
        guard = guard + 1
    end
    ancestorCache[lookupKey] = result
    return result
end

local rectCache = {}
function ns:GetChildZoneBoundaryRect(zoneID, mapID)
    if not zoneID or not mapID then return nil end 
    if zoneID == mapID or not CatchSessionLogger.hasAncestor(zoneID, mapID) then return nil end
    local lookupKey = zoneID .. ":" .. mapID
    local rowEntry = rectCache[lookupKey]
    if rowEntry == nil then
        local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(zoneID, mapID)
        if minX and maxX and maxX > minX then
            rowEntry = { minX, maxX, minY, maxY }
        else
            rowEntry = false
        end
        rectCache[lookupKey] = rowEntry
    end
    return rowEntry or nil
end

function ns:ProjectSubzoneCoordsToParentMap(zoneID, mapID, x, y)
    if zoneID == mapID then return x, y, false end
    local rowEntry = ns:GetChildZoneBoundaryRect(zoneID, mapID)
    if not rowEntry then return nil end
    return rowEntry[1] + x * (rowEntry[2] - rowEntry[1]), rowEntry[3] + y * (rowEntry[4] - rowEntry[3]), true
end

function ns:CollectSpots(mapID, source)
    local outputList = {}
    source = source or (ns.db and ns.db.spots)
    if not mapID or not source then return outputList end
    for zoneID, spots in pairs(source) do
        if zoneID ~= 0 then
            for _, stateFlag in ipairs(spots) do
                local x, y, child = ns:ProjectSubzoneCoordsToParentMap(zoneID, mapID, stateFlag.x, stateFlag.y)
                if x then
                    outputList[#outputList + 1] = { spot = stateFlag, x = x, y = y, mapID = zoneID, child = child }
                end
            end
        end
    end
    return outputList
end

function ns:FishOnMap(mapID)
    local fish, grandTotal, entryList = {}, 0, ns:CollectSpots(mapID)
    for _, recordEntry in ipairs(entryList) do
        for entityID, themeColor in pairs(recordEntry.spot.fish) do
            fish[entityID] = (fish[entityID] or 0) + themeColor
            grandTotal = grandTotal + themeColor
        end
    end
    return fish, grandTotal, #entryList
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
CatchSessionLogger.GetChildZoneBoundaryRect = ns.GetChildZoneBoundaryRect
CatchSessionLogger.ProjectSubzoneCoordsToParentMap = ns.ProjectSubzoneCoordsToParentMap
CatchSessionLogger.GetSortedFishBreakdown = ns.GetSortedFishBreakdown
CatchSessionLogger.GetTotalCatchesAtSpot = ns.GetTotalCatchesAtSpot
CatchSessionLogger.GetTopCaughtFishList = ns.GetTopCaughtFishList
