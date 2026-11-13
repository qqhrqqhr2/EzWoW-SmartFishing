--===========================================================================
-- EzWoW - Smart Fishing
-- UI/MapPins.lua : WorldMap Fishing Spot Pin Mixin & Canvas Data Provider
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local WorldMapPinProvider = ns.WorldMapPinProvider or {}
ns.WorldMapPinProvider = WorldMapPinProvider
local L = ns.L
local StyleService = ns.Style

local TEMPLATE = "EzWoW_SmartFishingPinTemplate"
local MAX_TOOLTIP_FISH = 8

local RING = {
    own    = { 0.07, 0.08, 0.10, 0.95 },
    shared = { 0.80, 0.62, 0.25, 0.95 },
    pool   = { 0.30, 0.58, 1.00, 1 },
    zone   = { 0.27, 0.78, 0.88, 0.95 },
    water  = { 0.20, 0.55, 0.75, 0.9 },
}
local SIZE = { own = 20, shared = 18, pool = 18, zone = 26, water = 20 }

EzWoW_SmartFishingPinMixin = CreateFromMixins(MapCanvasPinMixin)

function EzWoW_SmartFishingPinMixin:OnLoad()
    
    if self.Label then return end
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1.0, 1.3)
    StyleService:Round(self, self.Ring)
    StyleService:Round(self, self.Icon)

    self.Label = self:CreateFontString(nil, "OVERLAY")
    self.Label:SetFont(StyleService.font, 11, "OUTLINE")
    self.Label:SetPoint("TOP", self, "BOTTOM", 0, -1)
end

function EzWoW_SmartFishingPinMixin:RingColor(highlight)
    local themeColor = highlight and StyleService.accent or RING[self.entry.kind or "own"]
    self.Ring:SetColorTexture(themeColor[1], themeColor[2], themeColor[3], themeColor[4] or 1)
end

function EzWoW_SmartFishingPinMixin:OnAcquired(entry)
    self.entry = entry
    local kind = entry.kind or "own"
    local filter = ns.settings.filterFish
    local iconID
    self:SetAlpha(1)
    self.Label:Hide()

    if kind == "pool" then
        iconID = entry.poolType.fish
        self:SetAlpha(0.9)
    elseif kind == "zone" then
        iconID = filter
        self.Label:SetText(string.format("%.0f%%", entry.pct))
        self.Label:SetTextColor(unpack(StyleService.accent))
        self.Label:Show()
    elseif kind == "water" then
        iconID = entry.id
        self:SetAlpha(0.9)
        self.Label:SetText(string.format("%.0f%%", entry.pct))
        self.Label:SetTextColor(unpack(StyleService.accent))
        self.Label:Show()
    else
        local spot = entry.spot
        if filter then
            iconID = filter
            local rate = (spot.fish[filter] or 0) / math.max(1, ns:GetTotalCatchesAtSpot(spot))
            self:SetAlpha(0.55 + 0.45 * rate) 
        else
            iconID = ns:GetTopCaughtFishList(spot)
        end
    end

    self.Icon:SetTexture(iconID and ns:ItemIcon(iconID) or StyleService.ICON_INNER)
    
    local inset = (kind == "pool") and 3 or 2
    self.Icon:ClearAllPoints()
    self.Icon:SetPoint("TOPLEFT", inset, -inset)
    self.Icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    local size = SIZE[kind] * (ns.settings.pinScale or 1)
    if entry.child and kind ~= "zone" then size = size * 0.7 end
    self:SetSize(size, size)
    self:RingColor(false)
    self:SetPosition(entry.x, entry.y)
end

function WorldMapPinProvider.addFishLines(fish, total, filter)
    for index, recordEntry in ipairs(ns:GetSortedFishBreakdown(fish)) do
        if index > MAX_TOOLTIP_FISH then break end
        local left = "|T" .. ns:ItemIcon(recordEntry.id) .. ":14:14:0:0:64:64:5:59:5:59|t " .. ns:ItemName(recordEntry.id)
        local pct = string.format("%.0f%%", recordEntry.count / total * 100)
        if recordEntry.id == filter then
            GameTooltip:AddDoubleLine(left, pct, 1, 1, 1, StyleService.accent[1], StyleService.accent[2], StyleService.accent[3])
        else
            GameTooltip:AddDoubleLine(left, pct, 1, 1, 1, 0.7, 0.72, 0.76)
        end
    end
end

function EzWoW_SmartFishingPinMixin:OnMouseEnter()
    local entry = self.entry
    if not entry then return end
    self:RingColor(true)
    local kind = entry.kind or "own"
    local filter = ns.settings.filterFish
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

    if kind == "zone" then
        GameTooltip:AddLine(ns:MapName(entry.mapID), 1, 1, 1)
        GameTooltip:AddLine(string.format(L["%s 예상 확률 %.1f%%"], ns:ItemName(filter), entry.pct), unpack(StyleService.muted))
        if entry.skill then
            GameTooltip:AddLine(L["권장 숙련 %d"]:format(entry.skill), unpack(StyleService.muted))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["클릭하면 이 지역 지도로 이동"], unpack(StyleService.muted))
    elseif kind == "water" then
        GameTooltip:AddLine(entry.place or ns:MapName(entry.mapID), 1, 1, 1)
        if filter then
            GameTooltip:AddLine(string.format(L["%s 예상 확률 %.1f%%"], ns:ItemName(filter), entry.pct), unpack(StyleService.muted))
        else
            local list = {}
            for id, p in pairs(entry.fish or {}) do list[#list + 1] = { id = id, p = p } end
            table.sort(list, function(a, b) return a.p > b.p end)
            for index = 1, math.min(MAX_TOOLTIP_FISH, #list) do
                local row = list[index]
                if row.p < 0.5 then break end
                local left = "|T" .. ns:ItemIcon(row.id) .. ":14:14:0:0:64:64:5:59:5:59|t " .. ns:ItemName(row.id)
                GameTooltip:AddDoubleLine(left, string.format("%.0f%%", row.p), 1, 1, 1, 0.7, 0.72, 0.76)
            end
        end
        if entry.skill then
            GameTooltip:AddLine(L["권장 숙련 %d"]:format(entry.skill), unpack(StyleService.muted))
        end
        if not filter then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["클릭: 지도에서 이 물고기 지점 보기"], unpack(StyleService.muted))
        end
    elseif kind == "pool" then
        GameTooltip:AddLine(ns:PoolLabel(entry.poolType), 1, 1, 1)
        GameTooltip:AddLine(L["물고기 떼가 나타나는 자리 (기본 데이터)"], unpack(StyleService.muted))
        if entry.child then GameTooltip:AddLine(ns:MapName(entry.mapID), unpack(StyleService.muted)) end
    else
        local spot = entry.spot
        local titleStr = spot.sub
        if entry.child then
            titleStr = ns:MapName(entry.mapID) .. (spot.sub and (" · " .. spot.sub) or "")
        end
        GameTooltip:AddLine(titleStr or L["낚시 지점"], 1, 1, 1)
        if kind == "shared" then
            GameTooltip:AddLine(string.format(L["다른 플레이어 기록 · %d번 낚음"], spot.n), StyleService.accent[1], StyleService.accent[2], StyleService.accent[3])
        else
            GameTooltip:AddLine(string.format(L["내 기록 · %d번 낚음"], spot.n), unpack(StyleService.muted))
        end
        GameTooltip:AddLine(" ")
        WorldMapPinProvider.addFishLines(spot.fish, ns:GetTotalCatchesAtSpot(spot), filter)
        if entry.child then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["클릭하면 이 지역 지도로 이동"], unpack(StyleService.muted))
        end
    end
    
    GameTooltip:AddDoubleLine(" ", "EzWoW - Smart Fishing", 0, 0, 0, 0.5, 0.5, 0.5)
    GameTooltip:Show()
    if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
end

function EzWoW_SmartFishingPinMixin:OnMouseLeave()
    self:RingColor(false)
    GameTooltip:Hide()
end

function EzWoW_SmartFishingPinMixin:SetPassThroughButtons(...)
    if InCombatLockdown() then return end
    getmetatable(self).__index.SetPassThroughButtons(self, ...)
end

function EzWoW_SmartFishingPinMixin:OnMouseClickAction(button)
    if button ~= "LeftButton" or not self.entry then return end
    if self.entry.kind == "water" then
        -- the spot's most likely fish: show only that fish
        if not ns.settings.filterFish and self.entry.id then ns:SetFishFilter(self.entry.id) end
        return
    end
    if self.entry.child then
        ns:GoToMap(self.entry.mapID)
    end
end

-- Our map layer runs from post-hooks on the map instead of being registered
-- as a map data provider: a provider runs inside the map's own update loop,
-- and the game's pins made after it in that loop are then blocked in combat
-- (SetPassThroughButtons). The layer keeps the provider method names.
local function attachMapLayer(map, layer)
    layer.owningMap = map
    layer.GetMap = function() return map end
    local function run(method, ...)
        local fn = layer[method]
        if type(fn) == "function" then fn(layer, ...) end
    end
    hooksecurefunc(map, "OnMapChanged", function() run("OnMapChanged") end)
    for _, method in ipairs({ "OnCanvasScaleChanged", "OnCanvasSizeChanged", "SetGlobalAlpha" }) do
        if type(map[method]) == "function" then
            local target = method == "SetGlobalAlpha" and "OnGlobalAlphaChanged" or method
            hooksecurefunc(map, method, function() run(target) end)
        end
    end
    map:HookScript("OnShow", function() run("OnShow"); run("RefreshAllData", true) end)
    map:HookScript("OnHide", function() run("OnHide") end)
end

local MapDataProvider = CreateFromMixins(MapCanvasDataProviderMixin)

function MapDataProvider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

function WorldMapPinProvider.addSpots(map, mapID, source, kind, filter)
    for _, entry in ipairs(ns:CollectSpots(mapID, source)) do
        if not filter or entry.spot.fish[filter] then
            entry.kind = kind
            map:AcquirePin(TEMPLATE, entry)
        end
    end
end

function MapDataProvider:RefreshAllData()
    self:RemoveAllData()
    local set = ns.settings
    if not set or not set.showPins then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    local filter = set.filterFish

    if filter and set.showExpected then
        for _, zoneRef in ipairs(ns:ZonesForFish(filter)) do
            local rowEntry = ns:GetChildZoneBoundaryRect(zoneRef.mapID, mapID)
            if rowEntry and zoneRef.pct >= 0.5 then
                local zdVal = ns.Data.zones[zoneRef.mapID]
                map:AcquirePin(TEMPLATE, {
                    kind = "zone", mapID = zoneRef.mapID, child = true, pct = zoneRef.pct, skill = zoneRef.s or (zdVal and zdVal.s),
                    x = (rowEntry[1] + rowEntry[2]) / 2, y = (rowEntry[3] + rowEntry[4]) / 2,
                })
            end
        end
    end

    -- a zone map: the water where each fishing table applies (the chosen fish, or
    -- the most likely fish of every spot)
    if set.showExpected and ns.WaterSpotsOnMap then
        for _, spot in ipairs(ns:WaterSpotsOnMap(mapID, filter)) do
            spot.kind, spot.mapID, spot.skill = "water", mapID, spot.s
            map:AcquirePin(TEMPLATE, spot)
        end
    end

    if set.showPools then
        for _, entry in ipairs(ns:PoolsOnMap(mapID, filter)) do
            map:AcquirePin(TEMPLATE, entry)
        end
    end
    if set.showShared and ns.db.shared then
        WorldMapPinProvider.addSpots(map, mapID, ns.db.shared, "shared", filter)
    end
    WorldMapPinProvider.addSpots(map, mapID, ns.db.spots, "own", filter)
end

function ns:RefreshPins()
    if MapDataProvider:GetMap() and WorldMapFrame:IsShown() then
        MapDataProvider:RefreshAllData()
    end
end

ns:SubscribeAddonEvent("AM_DB_READY", function()
    if MapDataProvider.owningMap then return end
    attachMapLayer(WorldMapFrame, MapDataProvider)
    ns:RefreshPins()
end)
ns:SubscribeAddonEvent("AM_DATA_CHANGED", function() ns:RefreshPins() end)
local PIN_KEYS = { showPins = true, filterFish = true, pinScale = true, showPools = true, showShared = true, showExpected = true }
ns:SubscribeAddonEvent("AM_SETTINGS_CHANGED", function(key)
    if PIN_KEYS[key] then ns:RefreshPins() end
end)

_G.EzWoW_SmartFishingPinMixin = EzWoW_SmartFishingPinMixin
