--===========================================================================
-- EzWoW - Smart Fishing
-- UI/MapDockButton.lua : WorldMap Dock Button & Fish Filter Dropdown Menu
--===========================================================================
local ADDON, ns = ...
-- frames made on the World Map are made without a parent and put in after
-- (Libs/EzWoWGamePad MakeFrame: keeps the game's gamepad cursor untainted)
local CreateFrame = (ns.GamePad and ns.GamePad.MakeFrame) or CreateFrame
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local WorldMapFilterButton = ns.WorldMapFilterButton or {}
ns.WorldMapFilterButton = WorldMapFilterButton
local L = ns.L
local StyleService = ns.Style

local button

function ns:SetFishFilter(itemID)
    ns.settings.filterFish = itemID
    ns:PublishAddonEvent("AM_SETTINGS_CHANGED", "filterFish")
end

function WorldMapFilterButton.moveMap(mapID, open)
    -- with the gamepad on, a map opened or moved by addon code taints the
    -- gamepad navigation (Libs/EzWoWGamePad): left to the player
    if ns.GamePad and ns.GamePad.IsActive() then return end
    if open and not WorldMapFrame:IsShown() then
        if OpenWorldMap then OpenWorldMap(mapID) else ToggleWorldMap() end
    end
    if mapID and WorldMapFrame:IsShown() then WorldMapFrame:SetMapID(mapID) end
end

function ns:GoToMap(mapID, open)
    WorldMapFilterButton.moveMap(mapID, open)
end

function ns:ShowFishOnMap(itemID, mapID)
    ns:SetFishFilter(itemID)
    if not ns.settings.showPins then
        ns.settings.showPins = true
        ns:PublishAddonEvent("AM_SETTINGS_CHANGED", "showPins")
    end
    ns:GoToMap(mapID, true)
end

function WorldMapFilterButton.resolveCurrentMapID()
    return WorldMapFrame:GetMapID()
end

function WorldMapFilterButton.refreshLabel()
    if not button then return end
    local filter = ns.settings.filterFish
    button.icon:SetTexture(StyleService.ICON)
    if not ns.settings.showPins then
        button.icon:SetAlpha(0.55)
    else
        button.icon:SetAlpha(1.0)
    end
    if button.fishBadge then
        if filter and ns.settings.showPins then
            button.fishBadge:SetTexture(ns:ItemIcon(filter))
            button.fishBadge:Show()
            if button.fishBadgeBg then button.fishBadgeBg:Show() end
        else
            button.fishBadge:Hide()
            if button.fishBadgeBg then button.fishBadgeBg:Hide() end
        end
    end
    button.label:SetText("")
    button:SetSize(28, 28)
    button.clear:Hide()
end
ns.UpdateMapButton = WorldMapFilterButton.refreshLabel

-----------------------------------------------------------------------------
-- Has Auto Align
-----------------------------------------------------------------------------

function WorldMapFilterButton.hasAutoAlign()
    return not ns.settings or ns.settings.mapButtonAutoAlign ~= false
end

function WorldMapFilterButton.cycleFish(delta)
    local itemList = ns:FishMenuList(WorldMapFilterButton.resolveCurrentMapID())
    if #itemList == 0 then return end
    local currentState, entryIndex = ns.settings.filterFish, 0
    for index, recordEntry in ipairs(itemList) do if recordEntry.id == currentState then entryIndex = index break end end
    entryIndex = entryIndex - delta
    if entryIndex < 1 then entryIndex = #itemList elseif entryIndex > #itemList then entryIndex = 1 end
    ns:SetFishFilter(itemList[entryIndex].id)
end

function ns:FishMenuList(mapID)
    local expected = ns:ExpectedOnMap(mapID)
    local own = ns:FishOnMap(mapID)
    local visitedMap, itemList = {}, {}
    for id, anchorTarget in pairs(expected) do
        if anchorTarget >= 1 or own[id] then
            visitedMap[id] = true
            itemList[#itemList + 1] = { id = id, pct = anchorTarget, count = own[id] or 0 }
        end
    end
    for id, themeColor in pairs(own) do
        if not visitedMap[id] then itemList[#itemList + 1] = { id = id, count = themeColor } end
    end
    table.sort(itemList, function(a, b)
        local paVal, pbVal = a.pct or -1, b.pct or -1
        if paVal ~= pbVal then return paVal > pbVal end
        return a.count > b.count
    end)
    return itemList
end

function WorldMapFilterButton.buildButton()
    local container = WorldMapFrame:GetCanvasContainer()
    -- made on the map window and anchored to the canvas: a frame inside the
    -- canvas makes the map scroll when a gamepad cursor moves onto it
    local b = CreateFrame("Button", "EzWoW_SmartFishingMapButton", WorldMapFrame)
    b:SetSize(28, 28)
    b:SetFrameLevel(container:GetFrameLevel() + 500)
    b:RegisterForDrag("LeftButton")
    b:SetClampedToScreen(true)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(StyleService.ICON)
    b.icon:SetAllPoints()

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetTexture(StyleService.ICON)
    b.hl:SetAllPoints()
    b.hl:SetBlendMode("ADD")
    b.hl:SetAlpha(0.35)

    b.fishBadgeBg = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.fishBadgeBg:SetSize(14, 14)
    b.fishBadgeBg:SetPoint("BOTTOMRIGHT", 1, -1)
    b.fishBadgeBg:SetColorTexture(0.05, 0.07, 0.09, 0.95)
    StyleService:Round(b, b.fishBadgeBg)
    b.fishBadgeBg:Hide()

    b.fishBadge = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.fishBadge:SetSize(12, 12)
    b.fishBadge:SetPoint("CENTER", b.fishBadgeBg, "CENTER", 0, 0)
    StyleService:Round(b, b.fishBadge)
    b.fishBadge:Hide()

    b.label = StyleService:Text(b, 12)
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
    b.label:Hide()

    b.clear = CreateFrame("Button", nil, b, "BackdropTemplate")
    StyleService:Panel(b.clear)
    b.clear:SetSize(22, 28)
    b.clear:SetPoint("LEFT", b, "RIGHT", 4, 0)
    b.clear.t = StyleService:Text(b.clear, 14, StyleService.muted)
    b.clear.t:SetPoint("CENTER", 0, 1)
    b.clear.t:SetText("×")
    b.clear:SetScript("OnEnter", function(self)
        self.t:SetTextColor(unpack(StyleService.text))
        self:SetBackdropBorderColor(unpack(StyleService.accent))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["선택 해제 (모든 물고기 보기)"], 1, 1, 1)
        GameTooltip:AddDoubleLine(" ", "EzWoW - Smart Fishing", 0, 0, 0, 0.5, 0.5, 0.5)
        GameTooltip:Show()
        if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
    end)
    b.clear:SetScript("OnLeave", function(self)
        self.t:SetTextColor(unpack(StyleService.muted))
        self:SetBackdropBorderColor(unpack(StyleService.border))
        GameTooltip:Hide()
    end)
    b.clear:SetScript("OnClick", function() ns:SetFishFilter(nil) end)
    b.clear:Hide()

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("EzWoW - Smart Fishing", unpack(StyleService.accent))
        GameTooltip:AddLine(L["왼쪽 클릭: 낚시 목록 펼치기/접기"], 0.929, 0.957, 0.969)
        GameTooltip:AddLine(L["오른쪽 클릭: 아이콘 위치 초기화"], 0.655, 0.725, 0.773)
        GameTooltip:AddLine(L["드래그: 아이콘 위치 이동"], 0.655, 0.725, 0.773)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            ns.settings.mapButtonPos = nil
            ns.settings.mapButtonAutoAlign = true
            ns:PublishAddonEvent("AM_SETTINGS_CHANGED", "mapButtonAutoAlign")
            return
        end
        if not ns.settings.showPins or not ns.settings.showLegend then
            ns.settings.showPins = true
            ns.settings.showLegend = true
            ns.settings.legendCollapsed = false
            ns:PublishAddonEvent("AM_SETTINGS_CHANGED", "showPins")
        else
            ns.settings.legendCollapsed = not ns.settings.legendCollapsed
        end
        if not ns.settings.legendCollapsed and _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.CloseOthers then
            _G.EzWoWWorldMapDock:CloseOthers("EzWoW_SmartFishing")
        end
        ns:UpdateMapLegend()
    end)

    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        local dock = _G.EzWoWWorldMapDock
        local curX, curY, maxW, maxH = dock and dock:GetCursorCanvasXY(self)
        local btnCX, btnCY = dock and dock:GetButtonCanvasCenter(self)
        local grabDX = (btnCX and curX) and (btnCX - curX) or 0
        local grabDY = (btnCY and curY) and (btnCY - curY) or 0
        if btnCX and btnCY and maxW and maxH and maxW > 0 and maxH > 0 then
            ns.settings.mapButtonPos = {
                math.min(0.98, math.max(0.02, btnCX / maxW)),
                math.min(0.97, math.max(0.03, btnCY / maxH)),
            }
        end
        ns.settings.mapButtonAutoAlign = false
        if dock then dock:Layout() end
        self:SetScript("OnUpdate", function(btn)
            if dock and dock.GetCursorCanvasXY then
                local cx, cy, cw, ch = dock:GetCursorCanvasXY(btn)
                if not (cx and cy and cw and ch and cw > 0 and ch > 0) then return end
                local fxVal = math.min(0.98, math.max(0.02, (cx + grabDX) / cw))
                local fyVal = math.min(0.97, math.max(0.03, (cy + grabDY) / ch))
                ns.settings.mapButtonPos = { fxVal, fyVal }
                ns.PlaceMapButton(true)
                return
            end
            local calculateCanvasScale = btn:GetEffectiveScale()
            local cxVal, cyVal = GetCursorPosition()
            cxVal, cyVal = cxVal / calculateCanvasScale, cyVal / calculateCanvasScale
            local left, bottom, boxWidth, headerBar = container:GetRect()
            if not boxWidth or boxWidth == 0 or headerBar == 0 then return end
            local fxVal = math.min(0.98, math.max(0.02, (cxVal - left) / boxWidth))
            local fyVal = math.min(0.97, math.max(0.03, (cyVal - bottom) / headerBar))
            ns.settings.mapButtonPos = { fxVal, fyVal }
            ns.PlaceMapButton(true)
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if _G.EzWoWWorldMapDock then _G.EzWoWWorldMapDock:Layout() end
    end)
    container:HookScript("OnSizeChanged", function() ns.PlaceMapButton() end)
    return b
end

local DEFAULT_POS = { 0.5, 0.05 }

function ns.PlaceMapButton(skipDock)
    if not button then return end
    if not skipDock and _G.EzWoWWorldMapDock then
        _G.EzWoWWorldMapDock:Layout()
        return
    end
    local container = WorldMapFrame:GetCanvasContainer()
    local coordPos = ns.settings.mapButtonPos or DEFAULT_POS
    local boxWidth, headerBar = container:GetSize()
    button:SetSize(28, 28)
    button:ClearAllPoints()
    button:SetPoint("CENTER", container, "BOTTOMLEFT", coordPos[1] * boxWidth, coordPos[2] * headerBar)
    ns:PlaceMapLegend(button, false)
end

function ns:ResetMapButton()
    ns.settings.mapButton = true
    ns.settings.mapButtonPos = nil
    ns.settings.mapButtonAutoAlign = true
    if button then button:Show() end
    ns.PlaceMapButton()
    if ns.ResetMinimapButton then ns:ResetMinimapButton() end
    if ns.db then ns.db.hudPos = nil end
    if _G.EzWoW_SmartFishingHUD then
        _G.EzWoW_SmartFishingHUD:ClearAllPoints()
        _G.EzWoW_SmartFishingHUD:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
    ns:Print(L["지도 버튼 위치를 처음으로 되돌렸어요."])
end

ns:SubscribeAddonEvent("AM_DB_READY", function()
    button = WorldMapFilterButton.buildButton()
    ns:CreateMapLegend(button)
    button:SetShown(ns.settings.mapButton)
    if _G.EzWoWWorldMapDock then
        _G.EzWoWWorldMapDock:Register("EzWoW_SmartFishing", {
            order = 4,
            button = button,
            isAuto = WorldMapFilterButton.hasAutoAlign,
            isShown = function() return not ns.settings or ns.settings.mapButton ~= false end,
            closePanel = function()
                ns.settings.legendCollapsed = true
                ns:UpdateMapLegend()
            end,
            onDockedLayout = function(btn)
                ns:PlaceMapLegend(btn, true)
            end,
            onFreeLayout = function()
                ns.PlaceMapButton(true)
            end,
        })
    else
        ns.PlaceMapButton(true)
    end
    local function onMapChanged()
        WorldMapFilterButton.refreshLabel()
        ns:UpdateMapLegend()
    end
    -- map changes come in through post-hooks on the map. A map data provider would run
    -- inside the map's own update loop, and the game's pins made after it in that
    -- loop are then blocked in combat (SetPassThroughButtons).
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", onMapChanged)
    end
    WorldMapFrame:HookScript("OnShow", function()
        ns.PlaceMapButton()
        WorldMapFilterButton.refreshLabel()
        ns:UpdateMapLegend()
    end)
    WorldMapFilterButton.refreshLabel()
end)
ns:SubscribeAddonEvent("AM_SETTINGS_CHANGED", function(key)
    if key == "filterFish" or key == "showPins" then WorldMapFilterButton.refreshLabel() end
    if key == "mapButton" and button then
        button:SetShown(ns.settings.mapButton)
        if _G.EzWoWWorldMapDock then _G.EzWoWWorldMapDock:Layout() end
    end
    if key == "mapButtonAutoAlign" then
        ns.PlaceMapButton()
    end
end)
ns:SubscribeAddonEvent("AM_DATA_CHANGED", WorldMapFilterButton.refreshLabel)
local pending = false
ns:SubscribeAddonEvent("GET_ITEM_INFO_RECEIVED", function()
    if pending or not WorldMapFrame:IsShown() then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        WorldMapFilterButton.refreshLabel()
        ns:UpdateMapLegend()
    end)
end)
