--===========================================================================
-- EzWoW - Smart Fishing
-- UI/MapLegend.lua : WorldMap Zone Fish Drop-Rate & Pool Legend Overlay
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local ZoneDropRateLegend = ns.ZoneDropRateLegend or {}
ns.ZoneDropRateLegend = ZoneDropRateLegend
local L = ns.L
local StyleService = ns.Style

local rowWidgets = 8
local frameWidth = 272
local legend

function ZoneDropRateLegend.buildRow(parent, i)
    local rowEntry = CreateFrame("Button", nil, parent)
    rowEntry:SetHeight(20)
    rowEntry:SetPoint("TOPLEFT", 6, -62 - (i - 1) * 20)
    rowEntry:SetPoint("RIGHT", -6, 0)

    rowEntry.bg = rowEntry:CreateTexture(nil, "BACKGROUND")
    rowEntry.bg:SetAllPoints()
    rowEntry.bg:SetColorTexture(0, 0, 0, 0)

    rowEntry.icon = rowEntry:CreateTexture(nil, "ARTWORK")
    rowEntry.icon:SetSize(16, 16)
    rowEntry.icon:SetPoint("LEFT", 4, 0)
    StyleService:Round(rowEntry, rowEntry.icon)

    rowEntry.pct = StyleService:Text(rowEntry, 11, StyleService.muted)
    rowEntry.pct:SetPoint("RIGHT", -4, 0)
    rowEntry.pct:SetJustifyH("RIGHT")

    rowEntry.name = StyleService:Text(rowEntry, 11)
    rowEntry.name:SetPoint("LEFT", rowEntry.icon, "RIGHT", 7, 0)
    rowEntry.name:SetPoint("RIGHT", rowEntry.pct, "LEFT", -6, 0)

    rowEntry:SetScript("OnEnter", function(self)
        if not self.selected then self.bg:SetColorTexture(unpack(StyleService.hover)) end
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.hint or "", unpack(StyleService.accent))
            GameTooltip:AddLine("EzWoW - Smart Fishing", unpack(StyleService.muted))
            GameTooltip:Show()
        end
    end)
    rowEntry:SetScript("OnLeave", function(self)
        if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end
        GameTooltip:Hide()
    end)
    rowEntry:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    return rowEntry
end

function ZoneDropRateLegend.buildLegend(anchor)
    local container = WorldMapFrame:GetCanvasContainer()
    local windowFrame = CreateFrame("Frame", "EzWoW_SmartFishingMapLegend", container, "BackdropTemplate")
    StyleService:Panel(windowFrame, StyleService.bg, StyleService.border)
    windowFrame:SetWidth(frameWidth)
    windowFrame:SetFrameLevel(anchor:GetFrameLevel() + 10)
    windowFrame:EnableMouse(true)

    local headerBg = windowFrame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", 1, -1)
    headerBg:SetPoint("TOPRIGHT", -1, -1)
    headerBg:SetHeight(29)
    headerBg:SetColorTexture(unpack(StyleService.bgSub))

    local headerLine = windowFrame:CreateTexture(nil, "ARTWORK")
    headerLine:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", headerBg, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(unpack(StyleService.accent))

    windowFrame.closeBtn = CreateFrame("Button", nil, windowFrame, "BackdropTemplate")
    StyleService:Panel(windowFrame.closeBtn, StyleService.bg, StyleService.border)
    windowFrame.closeBtn:SetSize(20, 20)
    windowFrame.closeBtn:SetPoint("TOPRIGHT", -5, -5)
    windowFrame.closeBtn.t = StyleService:Text(windowFrame.closeBtn, 12, StyleService.muted)
    windowFrame.closeBtn.t:SetPoint("CENTER", 0, 0)
    windowFrame.closeBtn.t:SetJustifyH("CENTER")
    windowFrame.closeBtn.t:SetText("X")
    windowFrame.closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.accent))
        self.t:SetTextColor(unpack(StyleService.text))
    end)
    windowFrame.closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.border))
        self.t:SetTextColor(unpack(StyleService.muted))
    end)
    windowFrame.closeBtn:SetScript("OnClick", function()
        ns.settings.legendCollapsed = true
        ns:UpdateMapLegend()
    end)

    windowFrame.cfgBtn = CreateFrame("Button", nil, windowFrame, "BackdropTemplate")
    StyleService:Panel(windowFrame.cfgBtn, StyleService.bg, StyleService.border)
    windowFrame.cfgBtn:SetSize(40, 20)
    windowFrame.cfgBtn:SetPoint("RIGHT", windowFrame.closeBtn, "LEFT", -3, 0)
    windowFrame.cfgBtn.t = StyleService:Text(windowFrame.cfgBtn, 10, StyleService.text)
    windowFrame.cfgBtn.t:SetPoint("CENTER", 0, 0)
    windowFrame.cfgBtn.t:SetJustifyH("CENTER")
    windowFrame.cfgBtn.t:SetText(L["설정"])
    windowFrame.cfgBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.accent))
        self.t:SetTextColor(unpack(StyleService.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("EzWoW - Smart Fishing", unpack(StyleService.accent))
        GameTooltip:AddLine(L["왼쪽 클릭"] .. ": " .. L["설정"] .. " (/ezsf config)", 0.929, 0.957, 0.969)
        GameTooltip:Show()
    end)
    windowFrame.cfgBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.border))
        self.t:SetTextColor(unpack(StyleService.text))
        GameTooltip:Hide()
    end)
    windowFrame.cfgBtn:SetScript("OnClick", function()
        if ns.OpenSettings then ns:OpenSettings() end
    end)

    windowFrame.title = StyleService:Text(windowFrame, 12, StyleService.accent)
    windowFrame.title:SetPoint("TOPLEFT", 10, -8)
    windowFrame.title:SetPoint("RIGHT", windowFrame.cfgBtn, "LEFT", -6, 0)

    windowFrame.filterBtn = CreateFrame("Button", nil, windowFrame, "BackdropTemplate")
    StyleService:Panel(windowFrame.filterBtn, StyleService.bgSub, StyleService.border)
    windowFrame.filterBtn:SetSize(72, 20)
    windowFrame.filterBtn:SetPoint("TOPRIGHT", -6, -35)
    windowFrame.filterBtn.t = StyleService:Text(windowFrame.filterBtn, 10, StyleService.accent)
    windowFrame.filterBtn.t:SetPoint("CENTER", 0, 0)
    windowFrame.filterBtn.t:SetJustifyH("CENTER")
    windowFrame.filterBtn.t:SetText(L["물고기 선택"] .. " ▾")
    windowFrame.filterBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["물고기별 낚시 지점"], 1, 1, 1)
        GameTooltip:Show()
    end)
    windowFrame.filterBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.border))
        GameTooltip:Hide()
    end)
    windowFrame.filterBtn:SetScript("OnClick", function(self)
        if ns.OpenFishMenu then ns.OpenFishMenu(self) end
    end)

    windowFrame.resetFilterBtn = CreateFrame("Button", nil, windowFrame, "BackdropTemplate")
    StyleService:Panel(windowFrame.resetFilterBtn, StyleService.bgSub, StyleService.border)
    windowFrame.resetFilterBtn:SetSize(42, 20)
    windowFrame.resetFilterBtn:SetPoint("RIGHT", windowFrame.filterBtn, "LEFT", -3, 0)
    windowFrame.resetFilterBtn.t = StyleService:Text(windowFrame.resetFilterBtn, 10, StyleService.text)
    windowFrame.resetFilterBtn.t:SetPoint("CENTER", 0, 0)
    windowFrame.resetFilterBtn.t:SetJustifyH("CENTER")
    windowFrame.resetFilterBtn.t:SetText(L["모든 물고기"])
    windowFrame.resetFilterBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.accent))
        self.t:SetTextColor(unpack(StyleService.accent))
    end)
    windowFrame.resetFilterBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.border))
        self.t:SetTextColor(unpack(StyleService.text))
    end)
    windowFrame.resetFilterBtn:SetScript("OnClick", function()
        ns:SetFishFilter(nil)
    end)
    windowFrame.resetFilterBtn:Hide()

    windowFrame.sub = StyleService:Text(windowFrame, 10, StyleService.muted)
    windowFrame.sub:SetPoint("TOPLEFT", 10, -39)
    windowFrame.sub:SetPoint("RIGHT", windowFrame.filterBtn, "LEFT", -6, 0)

    windowFrame.line = StyleService:Line(windowFrame)
    windowFrame.line:SetPoint("TOPLEFT", 6, -58)
    windowFrame.line:SetPoint("TOPRIGHT", -6, -58)

    windowFrame.rows = {}
    for i = 1, rowWidgets do windowFrame.rows[i] = ZoneDropRateLegend.buildRow(windowFrame, i) end

    windowFrame.foot = StyleService:Text(windowFrame, 9, StyleService.muted)
    windowFrame.foot:SetPoint("BOTTOMLEFT", 10, 6)
    windowFrame.foot:SetPoint("RIGHT", -10, 0)
    return windowFrame
end

function ZoneDropRateLegend.assignRow(rowEntry, d)
    rowEntry.itemID, rowEntry.onClick, rowEntry.hint = d.itemID, d.onClick, d.hint
    rowEntry.icon:SetTexture(d.icon)
    rowEntry.name:SetText(d.name)
    rowEntry.pct:SetText(d.pct)
    rowEntry.selected = d.selected
    if d.selected then
        rowEntry.bg:SetColorTexture(StyleService.accent[1], StyleService.accent[2], StyleService.accent[3], 0.14)
        rowEntry.pct:SetTextColor(unpack(StyleService.accent))
    else
        rowEntry.bg:SetColorTexture(0, 0, 0, 0)
        rowEntry.pct:SetTextColor(unpack(StyleService.muted))
    end
    rowEntry:Show()
end

function ZoneDropRateLegend.formatPercentageString(p)
    if p >= 10 then return string.format("%.0f%%", p) end
    return string.format("%.1f%%", p)
end

function ns:UpdateMapLegend()
    if not legend then return end
    if legend.cfgBtn and legend.cfgBtn.t then legend.cfgBtn.t:SetText(L["설정"]) end
    if legend.filterBtn and legend.filterBtn.t then legend.filterBtn.t:SetText(L["물고기 선택"] .. " ▾") end
    if legend.resetFilterBtn and legend.resetFilterBtn.t then legend.resetFilterBtn.t:SetText(L["모든 물고기"]) end
    local set = ns.settings
    if not set.showLegend or not set.showPins or not set.mapButton or not WorldMapFrame:IsShown() then
        legend:Hide()
        return
    end

    local collapsed = set.legendCollapsed
    if collapsed then legend:Hide() return end

    local mapID = WorldMapFrame:GetMapID()
    local filter = set.filterFish
    local payloadData = {}
    local footText = ""

    if legend.resetFilterBtn then
        legend.resetFilterBtn:SetShown(filter ~= nil)
        legend.sub:ClearAllPoints()
        legend.sub:SetPoint("TOPLEFT", 10, -39)
        legend.sub:SetPoint("RIGHT", filter and legend.resetFilterBtn or legend.filterBtn, "LEFT", -6, 0)
    end

    if ns.Data.zones[mapID] then
        
        local fish, skill, sub
        if mapID == C_Map.GetBestMapForUnit("player") then
            fish, skill, sub = ns:ExpectedHere(mapID)
        else
            fish, skill = ns:ExpectedZone(mapID)
        end
        legend.title:SetText(sub or ns:MapName(mapID))
        legend.sub:SetText(skill and L["권장 숙련 %d"]:format(skill) or L["일반 낚시"])

        local itemList = {}
        for entityID, p in pairs(fish or {}) do itemList[#itemList + 1] = { id = entityID, p = p } end
        table.sort(itemList, function(a, b) return a.p > b.p end)
        for i = 1, math.min(rowWidgets, #itemList) do
            local recordEntry = itemList[i]
            payloadData[i] = {
                itemID = recordEntry.id, icon = ns:ItemIcon(recordEntry.id), name = ns:ItemName(recordEntry.id), pct = ZoneDropRateLegend.formatPercentageString(recordEntry.p),
                selected = filter == recordEntry.id,
                hint = L["클릭: 지도에서 이 물고기 기록·물고기 떼만 보기"],
                onClick = function() ns:SetFishFilter(filter == recordEntry.id and nil or recordEntry.id) end,
            }
        end
        if #itemList > rowWidgets then
            footText = string.format(L["외 %d가지 · 확률은 예상치"], #itemList - rowWidgets)
        end
    elseif filter then
        
        legend.title:SetText(ns:ItemName(filter, true))
        legend.sub:SetText(L["일반 낚시 확률이 높은 지역"])
        local nodeEntry = 0
        for _, zoneRef in ipairs(ns:ZonesForFish(filter)) do
            if ns:GetChildZoneBoundaryRect(zoneRef.mapID, mapID) then
                nodeEntry = nodeEntry + 1
                if nodeEntry <= rowWidgets then
                    local zdVal = ns.Data.zones[zoneRef.mapID]
                    payloadData[nodeEntry] = {
                        icon = ns:ItemIcon(filter),
                        name = ns:MapName(zoneRef.mapID) .. ((zdVal and zdVal.s) and ("  |cff8c94a3" .. zdVal.s .. "|r") or ""),
                        pct = ZoneDropRateLegend.formatPercentageString(zoneRef.pct),
                        onClick = function() ns:GoToMap(zoneRef.mapID) end,
                    }
                end
            end
        end
        if nodeEntry == 0 then
            footText = L["이 대륙에는 기본 데이터가 없어요"]
        end
    else
        
        local itemList = {}
        for entityID, p in pairs(ns:ExpectedOnMap(mapID)) do
            if p >= 1 then itemList[#itemList + 1] = { id = entityID, p = p } end
        end
        table.sort(itemList, function(a, b) return a.p > b.p end)
        legend.title:SetText(ns:MapName(mapID))
        legend.sub:SetText(L["물고기를 누르면 잡히는 지역이 보여요"])
        for i = 1, math.min(rowWidgets, #itemList) do
            local recordEntry = itemList[i]
            payloadData[i] = {
                itemID = recordEntry.id, icon = ns:ItemIcon(recordEntry.id), name = ns:ItemName(recordEntry.id),
                pct = L["최대 %s"]:format(ZoneDropRateLegend.formatPercentageString(recordEntry.p)),
                hint = L["클릭: 이 물고기가 잡히는 지역 보기"],
                onClick = function() ns:SetFishFilter(recordEntry.id) end,
            }
        end
        if #itemList > rowWidgets then
            footText = L["외 %d가지 · 지도 버튼에서 전체 보기"]:format(#itemList - rowWidgets)
        end
    end

    if #payloadData == 0 and footText == "" then
        footText = L["이 지역은 일반 낚시 정보가 없어요"]
    end

    legend.sub:Show()
    legend.line:Show()
    for i, rowEntry in ipairs(legend.rows) do
        if payloadData[i] then ZoneDropRateLegend.assignRow(rowEntry, payloadData[i]) else rowEntry:Hide() end
    end
    legend.foot:SetText(footText)
    legend.foot:SetShown(footText ~= "")
    local bottomPad = (footText ~= "") and 22 or 6
    legend:SetHeight(62 + #payloadData * 20 + bottomPad)
    legend:Show()
end

function ns:PlaceMapLegend(button, isDocked)
    if not legend then return end
    local coordPos = ns.settings.mapButtonPos or { 0.5, 0.05 }
    local autoAlign = not ns.settings or ns.settings.mapButtonAutoAlign ~= false
    legend:ClearAllPoints()
    if isDocked or autoAlign or (coordPos[1] and coordPos[1] < 0.25) then
        legend:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 6, 0)
    elseif coordPos[2] < 0.5 then
        legend:SetPoint("BOTTOM", button, "TOP", 0, 6)
    else
        legend:SetPoint("TOP", button, "BOTTOM", 0, -6)
    end
end

function ns:CreateMapLegend(button)
    legend = ZoneDropRateLegend.buildLegend(button)
    ns:PlaceMapLegend(button)
end

function ZoneDropRateLegend.updateFrameOnTick() ns:UpdateMapLegend() end
local KEYS = { showLegend = true, showPins = true, mapButton = true, filterFish = true }
ns:SubscribeAddonEvent("AM_SETTINGS_CHANGED", function(key) if KEYS[key] then ZoneDropRateLegend.updateFrameOnTick() end end)
ns:SubscribeAddonEvent("ZONE_CHANGED", ZoneDropRateLegend.updateFrameOnTick)
ns:SubscribeAddonEvent("ZONE_CHANGED_NEW_AREA", ZoneDropRateLegend.updateFrameOnTick)
