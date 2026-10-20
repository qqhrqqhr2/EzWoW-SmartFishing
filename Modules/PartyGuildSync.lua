--===========================================================================
-- EzWoW - Smart Fishing
-- Modules/PartyGuildSync.lua : Throttled Addon-Channel Fishing Spot Synchronization
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local PartyGuildSpotSync = ns.PartyGuildSpotSync or {}
ns.PartyGuildSpotSync = PartyGuildSpotSync
local L = ns.L

local PREFIX = "EzWoWSmartFishSync"
local MERGE_RADIUS = 0.015
local MAX_SPOTS_PER_MAP = 400
local MAX_MSG = 240

local playerName

function PartyGuildSpotSync.resolveChannels()
    local itemList = {}
    if IsInGuild and IsInGuild() then itemList[#itemList + 1] = "GUILD" end
    if IsInRaid() then
        itemList[#itemList + 1] = "RAID"
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        itemList[#itemList + 1] = "PARTY"
    end
    return itemList
end

function PartyGuildSpotSync.transmitAddonSyncPayload(msg)
    for _, chVal in ipairs(PartyGuildSpotSync.resolveChannels()) do
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, chVal)
    end
end

local queue, sending = {}, false
function PartyGuildSpotSync.processNextQueuedBatch()
    local msg = table.remove(queue, 1)
    if not msg then sending = false return end
    PartyGuildSpotSync.transmitAddonSyncPayload(msg)
    C_Timer.After(0.35, PartyGuildSpotSync.processNextQueuedBatch)
end
function PartyGuildSpotSync.enqueueOutgoingSyncRecord(msg)
    queue[#queue + 1] = msg
    if not sending then sending = true PartyGuildSpotSync.processNextQueuedBatch() end
end

function PartyGuildSpotSync.locateSpot(spots, x, y)
    for _, stateFlag in ipairs(spots) do
        local dxVal, dyVal = stateFlag.x - x, stateFlag.y - y
        if dxVal * dxVal + dyVal * dyVal <= MERGE_RADIUS * MERGE_RADIUS then return stateFlag end
    end
end

function PartyGuildSpotSync.addShared(mapID, x, y, itemID, count, merge)
    local savedDB = ns.db
    savedDB.shared = savedDB.shared or {}
    local spots = savedDB.shared[mapID]
    if not spots then
        spots = {}
        savedDB.shared[mapID] = spots
    end
    local spot = PartyGuildSpotSync.locateSpot(spots, x, y)
    if not spot then
        if #spots >= MAX_SPOTS_PER_MAP then return end
        spot = { x = x, y = y, n = 0, fish = {} }
        spots[#spots + 1] = spot
    end
    local before = spot.fish[itemID] or 0
    if merge then
        spot.fish[itemID] = math.max(before, count)
    else
        spot.fish[itemID] = before + count
    end
    spot.n = spot.n + math.max(0, spot.fish[itemID] - before)
    spot.last = time()
end

function PartyGuildSpotSync.parseFiniteNumber(v, minV, maxV)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < minV or v > maxV then return nil end
    return v
end

local received = {} 
function PartyGuildSpotSync.allow(sender, n)
    local currentTime = GetTime()
    local rowEntry = received[sender]
    if not rowEntry or currentTime - rowEntry.t > 60 then rowEntry = { t = currentTime, n = 0 } received[sender] = rowEntry end
    rowEntry.n = rowEntry.n + n
    return rowEntry.n <= 2000
end

function PartyGuildSpotSync.onMessage(prefix, msg, channel, sender)
    prefix, msg, sender = ns.CoerceSafeString(prefix), ns.CoerceSafeString(msg), ns.CoerceSafeString(sender)
    if prefix ~= PREFIX or not msg or not sender or not ns.db or not ns.settings.receiveShared then return end
    if sender == playerName or Ambiguate(sender, "none") == UnitName("player") then return end
    local kind, rest = msg:match("^(%u)|(.*)$")
    if kind == "C" then
        local matchRef, x, y, item, priorityQueue = strsplit("|", rest)
        matchRef, x, y = PartyGuildSpotSync.parseFiniteNumber(matchRef, 1, 100000), PartyGuildSpotSync.parseFiniteNumber(x, 0, 1000), PartyGuildSpotSync.parseFiniteNumber(y, 0, 1000)
        item, priorityQueue = PartyGuildSpotSync.parseFiniteNumber(item, 1, 1000000), PartyGuildSpotSync.parseFiniteNumber(priorityQueue, 1, 50)
        if not (matchRef and x and y and item and priorityQueue) or not PartyGuildSpotSync.allow(sender, 1) then return end
        PartyGuildSpotSync.addShared(matchRef, x / 1000, y / 1000, item, priorityQueue, false)
        ns:PublishAddonEvent("AM_DATA_CHANGED")
    elseif kind == "S" then
        local matchRef, body = rest:match("^(%d+)|(.*)$")
        matchRef = PartyGuildSpotSync.parseFiniteNumber(matchRef, 1, 100000)
        if not matchRef or not body then return end
        local n = 0
        for sxVal, syVal, sitem, scVal in body:gmatch("(%d+),(%d+),(%d+),(%d+)") do
            local x, y = PartyGuildSpotSync.parseFiniteNumber(sxVal, 0, 1000), PartyGuildSpotSync.parseFiniteNumber(syVal, 0, 1000)
            local item, themeColor = PartyGuildSpotSync.parseFiniteNumber(sitem, 1, 1000000), PartyGuildSpotSync.parseFiniteNumber(scVal, 1, 100000)
            if x and y and item and themeColor then
                n = n + 1
                if not PartyGuildSpotSync.allow(sender, 1) then break end
                PartyGuildSpotSync.addShared(matchRef, x / 1000, y / 1000, item, themeColor, true)
            end
        end
        if n > 0 then ns:PublishAddonEvent("AM_DATA_CHANGED") end
    end
end

ns:SubscribeAddonEvent("AM_CATCH", function(mapID, x, y, items)
    if not ns.settings.shareCatches or mapID == 0 then return end
    for itemID, priorityQueue in pairs(items) do
        PartyGuildSpotSync.enqueueOutgoingSyncRecord(string.format("C|%d|%d|%d|%d|%d", mapID, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5), itemID, math.min(priorityQueue, 50)))
    end
end)

function ns:SendAllRecords()
    if #PartyGuildSpotSync.resolveChannels() == 0 then
        ns:Print(L["길드나 파티에 있어야 기록을 보낼 수 있어요."])
        return
    end
    local count = 0
    for mapID, spots in pairs(ns.db.spots) do
        if mapID ~= 0 then
            local head = "S|" .. mapID .. "|"
            local parts = {}
            local strLength = #head
            local function flush()
                if #parts > 0 then PartyGuildSpotSync.enqueueOutgoingSyncRecord(head .. table.concat(parts, ";")) end
                parts, strLength = {}, #head
            end
            for _, stateFlag in ipairs(spots) do
                for itemID, themeColor in pairs(stateFlag.fish) do
                    local part = string.format("%d,%d,%d,%d", math.floor(stateFlag.x * 1000 + 0.5), math.floor(stateFlag.y * 1000 + 0.5), itemID, themeColor)
                    if strLength + #part + 1 > MAX_MSG then flush() end
                    parts[#parts + 1] = part
                    strLength = strLength + #part + 1
                    count = count + 1
                end
            end
            flush()
        end
    end
    ns:Print(string.format(L["내 낚시 기록 %d건을 길드/파티에 보내는 중이에요."], count))
end

function ns:ClearShared()
    ns.db.shared = {}
    ns:Print(L["공유받은 낚시 기록을 지웠어요."])
    ns:PublishAddonEvent("AM_DATA_CHANGED")
end

function ns:SharedCount()
    local n = 0
    for _, spots in pairs(ns.db.shared or {}) do n = n + #spots end
    return n
end

ns:SubscribeAddonEvent("AM_DB_READY", function()
    ns.db.shared = ns.db.shared or {}
    playerName = (UnitName("player") or "Player") .. "-" .. ((GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "")
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end)
ns:SubscribeAddonEvent("CHAT_MSG_ADDON", PartyGuildSpotSync.onMessage)
