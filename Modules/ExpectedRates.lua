--===========================================================================
-- EzWoW - Smart Fishing
-- Modules/ExpectedRates.lua : Zone & School Expected Catch Probability Calculator
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local DropRateCalculator = ns.DropRateCalculator or {}
ns.DropRateCalculator = DropRateCalculator
local L = ns.L

local dungeonCatalog = ns.Data

function DropRateCalculator.toMap(f)
    local resolvedValue = {}
    for index = 1, #f, 2 do resolvedValue[f[index]] = f[index + 1] end
    return resolvedValue
end

local zoneCache, subCache = {}, {}

function ns:ExpectedZone(mapID)
    local zoneRef = mapID and dungeonCatalog.zones[mapID]
    if not zoneRef then return nil end
    zoneCache[mapID] = zoneCache[mapID] or DropRateCalculator.toMap(zoneRef.f)
    return zoneCache[mapID], zoneRef.s
end

local subByName 
function DropRateCalculator.assembleSubIndex()
    subByName = {}
    for areaID, recordEntry in pairs(dungeonCatalog.subzones) do
        local apiInfo = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
        local displayName = type(apiInfo) == "table" and apiInfo.name or apiInfo
        if displayName and displayName ~= "" then
            subByName[recordEntry.m] = subByName[recordEntry.m] or {}
            subByName[recordEntry.m][displayName] = areaID
        end
    end
end

function ns:ExpectedHere(mapID)
    local sub = ns.CoerceSafeString(ns.UnwrapSafeValue(GetSubZoneText))
    if sub and sub ~= "" then
        if not subByName then DropRateCalculator.assembleSubIndex() end
        local areaID = subByName[mapID] and subByName[mapID][sub]
        local recordEntry = areaID and dungeonCatalog.subzones[areaID]
        if recordEntry then
            subCache[areaID] = subCache[areaID] or DropRateCalculator.toMap(recordEntry.f)
            local _, zoneSkill = ns:ExpectedZone(mapID)
            return subCache[areaID], recordEntry.s or zoneSkill, sub
        end
    end
    local fish, skill = ns:ExpectedZone(mapID)
    return fish, skill, nil
end

local byFish
local sortedZonesByFishCache = {}
local expectedOnMapCache = {}
function ns:ZonesForFish(itemID)
    if itemID and sortedZonesByFishCache[itemID] then
        return sortedZonesByFishCache[itemID]
    end
    if not byFish then
        byFish = {}
        local function add(mapID, f)
            for index = 1, #f, 2 do
                local entityID, anchorTarget = f[index], f[index + 1]
                byFish[entityID] = byFish[entityID] or {}
                if not byFish[entityID][mapID] or byFish[entityID][mapID] < anchorTarget then byFish[entityID][mapID] = anchorTarget end
            end
        end
        for mapID, zoneRef in pairs(dungeonCatalog.zones) do add(mapID, zoneRef.f) end
        for _, recordEntry in pairs(dungeonCatalog.subzones) do add(recordEntry.m, recordEntry.f) end
    end
    local outputList = {}
    for mapID, anchorTarget in pairs(byFish[itemID] or {}) do outputList[#outputList + 1] = { mapID = mapID, pct = anchorTarget } end
    table.sort(outputList, function(a, b) return a.pct > b.pct end)
    if itemID then sortedZonesByFishCache[itemID] = outputList end
    return outputList
end

function ns:ExpectedOnMap(mapID)
    if mapID and expectedOnMapCache[mapID] then
        return expectedOnMapCache[mapID]
    end
    local outputList = {}
    local own = ns:ExpectedZone(mapID)
    if own then
        for entityID, anchorTarget in pairs(own) do outputList[entityID] = anchorTarget end
        if mapID then expectedOnMapCache[mapID] = outputList end
        return outputList
    end
    for zoneID, zoneRef in pairs(dungeonCatalog.zones) do
        if ns:GetChildZoneBoundaryRect(zoneID, mapID) then
            for index = 1, #zoneRef.f, 2 do
                local entityID, anchorTarget = zoneRef.f[index], zoneRef.f[index + 1]
                if not outputList[entityID] or outputList[entityID] < anchorTarget then outputList[entityID] = anchorTarget end
            end
        end
    end
    if mapID then expectedOnMapCache[mapID] = outputList end
    return outputList
end

function ns:PoolsOnMap(mapID, filterFish)
    local outputList = {}
    for zoneID, itemList in pairs(dungeonCatalog.pools) do
        local hasChild = zoneID ~= mapID
        if not hasChild or filterFish then
            for index = 1, #itemList, 3 do
                local resolvedValue = dungeonCatalog.poolTypes[itemList[index]]
                if resolvedValue and (not filterFish or resolvedValue.fish == filterFish) then
                    local coordX, coordY, child = ns:ProjectSubzoneCoordsToParentMap(zoneID, mapID, itemList[index + 1] / 100, itemList[index + 2] / 100)
                    if coordX then
                        outputList[#outputList + 1] = { kind = "pool", poolType = resolvedValue, x = coordX, y = coordY, mapID = zoneID, child = child }
                    end
                end
            end
        end
    end
    return outputList
end

function DropRateCalculator.resolveKindLabel(kind)
    local resolvedValue = {
    wreckage = L["떠다니는 잔해"],
    debris = L["떠다니는 부유물"],
    oil = L["기름 웅덩이"],
    water = L["정기의 물 웅덩이"],
    muddy = L["흙탕물"],
    }
    return resolvedValue[kind]
end
function ns:PoolLabel(resolvedValue)
    if resolvedValue.kind ~= "school" and DropRateCalculator.resolveKindLabel(resolvedValue.kind) then return DropRateCalculator.resolveKindLabel(resolvedValue.kind) end
    if resolvedValue.fish then return L["%s 떼"]:format(ns:ItemName(resolvedValue.fish, true)) end
    return L["물고기 떼"]
end

local continentCache = {}
function ns:ResolveContinentMapID(mapID)
    if not mapID then return nil end
    if continentCache[mapID] ~= nil then return continentCache[mapID] or nil end
    local entityID, guard, found = mapID, 0, false
    while entityID and entityID ~= 0 and guard < 10 do
        local apiInfo = C_Map.GetMapInfo(entityID)
        if not apiInfo then break end
        if Enum and Enum.UIMapType and apiInfo.mapType == Enum.UIMapType.Continent then found = entityID break end
        entityID = apiInfo.parentMapID
        guard = guard + 1
    end
    continentCache[mapID] = found
    return found or nil
end

local byContinent
function ns:FishByContinent()
    if byContinent then return byContinent end
    local tmp = {}
    local function add(mapID, f)
        local themeColor = ns:ResolveContinentMapID(mapID)
        if not themeColor then return end
        tmp[themeColor] = tmp[themeColor] or {}
        for index = 1, #f, 2 do
            local entityID, anchorTarget = f[index], f[index + 1]
            if anchorTarget >= 1 and (not tmp[themeColor][entityID] or tmp[themeColor][entityID] < anchorTarget) then tmp[themeColor][entityID] = anchorTarget end
        end
    end
    for mapID, zoneRef in pairs(dungeonCatalog.zones) do add(mapID, zoneRef.f) end
    for _, recordEntry in pairs(dungeonCatalog.subzones) do add(recordEntry.m, recordEntry.f) end
    byContinent = {}
    for themeColor, fish in pairs(tmp) do
        local itemList = {}
        for entityID, anchorTarget in pairs(fish) do itemList[#itemList + 1] = { id = entityID, pct = anchorTarget } end
        table.sort(itemList, function(a, b) return a.pct > b.pct end)
        byContinent[#byContinent + 1] = { continent = themeColor, fish = itemList }
    end
    table.sort(byContinent, function(a, b) return a.continent < b.continent end)
    return byContinent
end

function ns:PoolTypesOnMap(mapID)
    local counts = {}
    for zoneID, itemList in pairs(dungeonCatalog.pools) do
        if zoneID == mapID or ns:GetChildZoneBoundaryRect(zoneID, mapID) then
            for index = 1, #itemList, 3 do
                local resolvedValue = itemList[index]
                counts[resolvedValue] = (counts[resolvedValue] or 0) + 1
            end
        end
    end
    local outputList = {}
    for resolvedValue, nodeEntry in pairs(counts) do
        if dungeonCatalog.poolTypes[resolvedValue] and dungeonCatalog.poolTypes[resolvedValue].fish then outputList[#outputList + 1] = { type = dungeonCatalog.poolTypes[resolvedValue], count = nodeEntry } end
    end
    table.sort(outputList, function(a, b) return a.count > b.count end)
    return outputList
end

local poolsByFish
function ns:PoolZonesForFish(itemID)
    if not poolsByFish then
        poolsByFish = {}
        for zoneID, itemList in pairs(dungeonCatalog.pools) do
            for index = 1, #itemList, 3 do
                local resolvedValue = dungeonCatalog.poolTypes[itemList[index]]
                if resolvedValue and resolvedValue.fish then
                    poolsByFish[resolvedValue.fish] = poolsByFish[resolvedValue.fish] or {}
                    poolsByFish[resolvedValue.fish][zoneID] = (poolsByFish[resolvedValue.fish][zoneID] or 0) + 1
                end
            end
        end
    end
    local outputList = {}
    for mapID, nodeEntry in pairs(poolsByFish[itemID] or {}) do outputList[#outputList + 1] = { mapID = mapID, count = nodeEntry } end
    table.sort(outputList, function(a, b) return a.count > b.count end)
    return outputList
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
DropRateCalculator.ResolveContinentMapID = ns.ResolveContinentMapID
