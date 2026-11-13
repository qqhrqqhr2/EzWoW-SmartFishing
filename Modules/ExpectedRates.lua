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

-- Catches seen in the game (own and shared) move the built-in chances toward
-- what is really caught here: the built-in table counts like PRIOR catches, and
-- nothing changes before MIN_SEEN catches. Catches next to a known fish school
-- are left out, since a school gives its own fish.
local PRIOR, MIN_SEEN = 60, 20
local SCHOOL_RADIUS = 0.012

local schoolSpots = {}
local schoolFlag = setmetatable({}, { __mode = "k" })
function DropRateCalculator.nearSchool(mapID, spot)
    local known = schoolFlag[spot]
    if known ~= nil then return known end
    local list = schoolSpots[mapID]
    if list == nil then
        list = false
        local raw = dungeonCatalog.pools and dungeonCatalog.pools[mapID]
        if type(raw) == "table" then
            list = {}
            for index = 1, #raw, 3 do list[#list + 1] = { raw[index + 1] / 100, raw[index + 2] / 100 } end
        end
        schoolSpots[mapID] = list
    end
    local near = false
    if list then
        local r2 = SCHOOL_RADIUS * SCHOOL_RADIUS
        for _, pos in ipairs(list) do
            local dx, dy = pos[1] - spot.x, pos[2] - spot.y
            if dx * dx + dy * dy <= r2 then near = true break end
        end
    end
    schoolFlag[spot] = near
    return near
end

-- caught counts on one map; with subName only own catches made in that subzone
function DropRateCalculator.seenOnMap(mapID, subName)
    local counts, total = {}, 0
    local function add(spots, needSub)
        if type(spots) ~= "table" then return end
        for _, spot in ipairs(spots) do
            if type(spot) == "table" and type(spot.fish) == "table" and type(spot.x) == "number" and type(spot.y) == "number"
                and (not needSub or spot.sub == subName)
                and not DropRateCalculator.nearSchool(mapID, spot) then
                for itemID, n in pairs(spot.fish) do
                    if type(itemID) == "number" and type(n) == "number" and n > 0 then
                        counts[itemID] = (counts[itemID] or 0) + n
                        total = total + n
                    end
                end
            end
        end
    end
    local savedDB = ns.db
    if savedDB and mapID then
        add(savedDB.spots and savedDB.spots[mapID], subName ~= nil)
        if subName == nil then add(savedDB.shared and savedDB.shared[mapID], false) end
    end
    return counts, total
end

function DropRateCalculator.toMap(f)
    local resolvedValue = {}
    for index = 1, #f, 2 do resolvedValue[f[index]] = f[index + 1] end
    return resolvedValue
end

-- built-in chances (percent) mixed with the catches seen; returns the table and
-- how many catches went into it (0 = built-in only)
function DropRateCalculator.blend(f, mapID, subName)
    local out = DropRateCalculator.toMap(f)
    local counts, total = DropRateCalculator.seenOnMap(mapID, subName)
    if total < MIN_SEEN then return out, 0 end
    local scale = 100 / (PRIOR + total)
    for itemID, pct in pairs(out) do out[itemID] = PRIOR * pct / 100 * scale end
    for itemID, n in pairs(counts) do out[itemID] = (out[itemID] or 0) + n * scale end
    return out, total
end

local zoneCache, subCache = {}, {}

function ns:ExpectedZone(mapID)
    local zoneRef = mapID and dungeonCatalog.zones[mapID]
    if not zoneRef then return nil end
    local cached = zoneCache[mapID]
    if not cached then
        local fish, seen = DropRateCalculator.blend(zoneRef.f, mapID)
        cached = { fish = fish, seen = seen }
        zoneCache[mapID] = cached
    end
    return cached.fish, zoneRef.s, cached.seen
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

-- returns chances, recommended skill, subzone name (when the subzone has its own
-- row) and the number of seen catches mixed in
function ns:ExpectedHere(mapID)
    local sub = ns.CoerceSafeString(ns.UnwrapSafeValue(GetSubZoneText))
    if sub and sub ~= "" then
        if not subByName then DropRateCalculator.assembleSubIndex() end
        local areaID = subByName[mapID] and subByName[mapID][sub]
        local recordEntry = areaID and dungeonCatalog.subzones[areaID]
        if recordEntry then
            local cached = subCache[areaID]
            if not cached then
                local fish, seen = DropRateCalculator.blend(recordEntry.f, recordEntry.m, sub)
                cached = { fish = fish, seen = seen }
                subCache[areaID] = cached
            end
            local _, zoneSkill = ns:ExpectedZone(mapID)
            return cached.fish, recordEntry.s or zoneSkill, sub, cached.seen
        end
    end
    local fish, skill, seen = ns:ExpectedZone(mapID)
    return fish, skill, nil, seen
end

local byFish, skillByFish, minSkill
local sortedZonesByFishCache = {}
local expectedOnMapCache = {}

-- per fish: best chance on every map (with the recommended skill of the place that
-- gives it) and the lowest recommended skill of any place where it is caught
function DropRateCalculator.indexFish()
    byFish, skillByFish, minSkill = {}, {}, {}
    local minAny = {}
    local function add(mapID, fish, skill)
        for entityID, anchorTarget in pairs(fish) do
            local row = byFish[entityID]
            if not row then
                row = {}
                byFish[entityID], skillByFish[entityID] = row, {}
            end
            local current = row[mapID]
            local skills = skillByFish[entityID]
            if not current or current < anchorTarget
                or (current == anchorTarget and skill and (skills[mapID] or math.huge) > skill) then
                row[mapID] = anchorTarget
                skills[mapID] = skill
            end
            if skill then
                if anchorTarget >= 1 and (not minSkill[entityID] or minSkill[entityID] > skill) then minSkill[entityID] = skill end
                if not minAny[entityID] or minAny[entityID] > skill then minAny[entityID] = skill end
            end
        end
    end
    for mapID, zoneRef in pairs(dungeonCatalog.zones) do add(mapID, ns:ExpectedZone(mapID) or {}, zoneRef.s) end
    for _, recordEntry in pairs(dungeonCatalog.subzones) do
        local zoneRef = dungeonCatalog.zones[recordEntry.m]
        add(recordEntry.m, DropRateCalculator.toMap(recordEntry.f), recordEntry.s or (zoneRef and zoneRef.s))
    end
    -- a fish only ever seen at small chances still gets a skill
    for entityID, skill in pairs(minAny) do
        if not minSkill[entityID] then minSkill[entityID] = skill end
    end
end

function ns:ZonesForFish(itemID)
    if itemID and sortedZonesByFishCache[itemID] then
        return sortedZonesByFishCache[itemID]
    end
    if not byFish then DropRateCalculator.indexFish() end
    local outputList = {}
    local skills = skillByFish[itemID] or {}
    for mapID, anchorTarget in pairs(byFish[itemID] or {}) do
        outputList[#outputList + 1] = { mapID = mapID, pct = anchorTarget, s = skills[mapID] }
    end
    table.sort(outputList, function(a, b) return a.pct > b.pct end)
    if itemID then sortedZonesByFishCache[itemID] = outputList end
    return outputList
end

-- lowest recommended skill of any place where the fish is caught (nil if unknown)
function ns:FishSkill(itemID)
    if not byFish then DropRateCalculator.indexFish() end
    return itemID and minSkill[itemID] or nil
end

-- Fish of this zone map that the shown table lacks: the subzones with their own
-- table (and the zone table itself when a subzone is shown). Each comes with its
-- best chance, the skill of that place and the places' names, best first.
function ns:OtherFishOnMap(mapID, shown, withZone)
    local zoneRef = mapID and dungeonCatalog.zones[mapID]
    local byId, outputList = {}, {}
    local function add(fish, skill, place)
        for entityID, anchorTarget in pairs(fish) do
            if anchorTarget >= 1 and not (shown and shown[entityID]) then
                local entry = byId[entityID]
                if not entry then
                    entry = { id = entityID, places = {} }
                    byId[entityID] = entry
                    outputList[#outputList + 1] = entry
                end
                entry.places[#entry.places + 1] = { name = place, p = anchorTarget, s = skill }
            end
        end
    end
    if withZone and zoneRef then add(ns:ExpectedZone(mapID) or {}, zoneRef.s, ns:MapName(mapID)) end
    for areaID, recordEntry in pairs(dungeonCatalog.subzones) do
        if recordEntry.m == mapID then
            local apiInfo = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
            local placeName = type(apiInfo) == "table" and apiInfo.name or apiInfo
            add(DropRateCalculator.toMap(recordEntry.f), recordEntry.s or (zoneRef and zoneRef.s), placeName)
        end
    end
    for _, entry in ipairs(outputList) do
        table.sort(entry.places, function(a, b)
            if a.p ~= b.p then return a.p > b.p end
            return (a.s or 0) < (b.s or 0)
        end)
        entry.p, entry.s = entry.places[1].p, entry.places[1].s
    end
    table.sort(outputList, function(a, b)
        if a.p ~= b.p then return a.p > b.p end
        return a.id < b.id
    end)
    return outputList
end

-- Spots on a zone map where the water of each fishing table lies (D.water): with
-- a fish chosen, the spots of the tables that give it; else every spot with its
-- table's most likely fish.
function ns:WaterSpotsOnMap(mapID, filterFish)
    local water = dungeonCatalog.water and dungeonCatalog.water[mapID]
    local zoneRef = mapID and dungeonCatalog.zones[mapID]
    local outputList = {}
    if type(water) ~= "table" or not zoneRef then return outputList end
    for tableArea, coords in pairs(water) do
        local fish, skill, place
        if tableArea == 0 then
            fish, skill = ns:ExpectedZone(mapID)
            place = ns:MapName(mapID)
        else
            local recordEntry = dungeonCatalog.subzones[tableArea]
            if recordEntry then
                fish = DropRateCalculator.toMap(recordEntry.f)
                skill = recordEntry.s or zoneRef.s
                local apiInfo = C_Map.GetAreaInfo and C_Map.GetAreaInfo(tableArea)
                place = type(apiInfo) == "table" and apiInfo.name or apiInfo
            end
        end
        if fish then
            local entityID, pct
            if filterFish then
                entityID, pct = filterFish, fish[filterFish]
            else
                for id, p in pairs(fish) do
                    if not pct or p > pct then entityID, pct = id, p end
                end
            end
            if entityID and pct and pct >= 0.5 then
                for index = 1, #coords, 2 do
                    outputList[#outputList + 1] = {
                        x = coords[index] / 100, y = coords[index + 1] / 100, id = entityID, pct = pct,
                        s = skill, place = place, fish = fish,
                    }
                end
            end
        end
    end
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
    for zoneID in pairs(dungeonCatalog.zones) do
        if ns:GetChildZoneBoundaryRect(zoneID, mapID) then
            for entityID, anchorTarget in pairs(ns:ExpectedZone(zoneID) or {}) do
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
    local function add(mapID, fish)
        local themeColor = ns:ResolveContinentMapID(mapID)
        if not themeColor then return end
        tmp[themeColor] = tmp[themeColor] or {}
        for entityID, anchorTarget in pairs(fish) do
            if anchorTarget >= 1 and (not tmp[themeColor][entityID] or tmp[themeColor][entityID] < anchorTarget) then tmp[themeColor][entityID] = anchorTarget end
        end
    end
    for mapID in pairs(dungeonCatalog.zones) do add(mapID, ns:ExpectedZone(mapID) or {}) end
    for _, recordEntry in pairs(dungeonCatalog.subzones) do add(recordEntry.m, DropRateCalculator.toMap(recordEntry.f)) end
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

-- new own or shared catches: the mixed chances are worked out again when next asked
ns:SubscribeAddonEvent("AM_DATA_CHANGED", function()
    zoneCache, subCache = {}, {}
    byFish, skillByFish, minSkill, byContinent = nil, nil, nil, nil
    sortedZonesByFishCache, expectedOnMapCache = {}, {}
end)

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
DropRateCalculator.ResolveContinentMapID = ns.ResolveContinentMapID
