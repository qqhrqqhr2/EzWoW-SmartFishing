--===========================================================================
-- EzWoW - Smart Fishing
-- UI/MapLegend.lua : WorldMap Zone Fish Drop-Rate & Pool Legend Overlay
--===========================================================================
local ADDON, ns = ...
-- frames made on the World Map are made without a parent and put in after
-- (Libs/EzWoWGamePad MakeFrame: keeps the game's gamepad cursor untainted)
local CreateFrame = (ns.GamePad and ns.GamePad.MakeFrame) or CreateFrame
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local ZoneDropRateLegend = ns.ZoneDropRateLegend or {}
ns.ZoneDropRateLegend = ZoneDropRateLegend
local L = ns.L
local StyleService = ns.Style

-- Everything is in this one panel (no extra menu): every fish of the map with its
-- chance and own catch count, the fish schools, and on a continent the zones and
-- other continents of a chosen fish. A long list scrolls with the mouse wheel.
local ROW_H = 20
local TOP_PAD = 62
local MIN_ROWS, MAX_ROWS = 6, 24
local frameWidth = 300
local POOL_COLOR = "|cff60cea3"
local MUTED_HEX = "|cff8c94a3"
local legend

function ZoneDropRateLegend.buildRow(parent, i)
    local rowEntry = CreateFrame("Button", nil, parent)
    rowEntry:SetHeight(ROW_H)
    rowEntry:SetPoint("TOPLEFT", 6, -TOP_PAD - (i - 1) * ROW_H)
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
        if self.isHeader then return end
        if not self.selected then self.bg:SetColorTexture(unpack(StyleService.hover)) end
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.hint or "", unpack(StyleService.accent))
            if self.hint2 then GameTooltip:AddLine(self.hint2, 0.85, 0.86, 0.90, true) end
            GameTooltip:AddDoubleLine(" ", "EzWoW - Smart Fishing", 0, 0, 0, 0.5, 0.5, 0.5)
            GameTooltip:Show()
            if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
        end
    end)
    rowEntry:SetScript("OnLeave", function(self)
        if self.isHeader then return end
        if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end
        GameTooltip:Hide()
    end)
    rowEntry:SetScript("OnClick", function(self)
        if not self.isHeader and self.onClick then self.onClick() end
    end)
    return rowEntry
end

function ZoneDropRateLegend.toggleMapPins()
    ns.settings.showPins = not ns.settings.showPins
    ns:PublishAddonEvent("AM_SETTINGS_CHANGED", "showPins")
end

function ZoneDropRateLegend.buildLegend(anchor)
    local windowFrame = CreateFrame("Frame", "EzWoW_SmartFishingMapLegend", WorldMapFrame, "BackdropTemplate")
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

    windowFrame.pinsBtn = CreateFrame("Button", nil, windowFrame, "BackdropTemplate")
    StyleService:Panel(windowFrame.pinsBtn, StyleService.bg, StyleService.border)
    windowFrame.pinsBtn:SetSize(56, 20)
    windowFrame.pinsBtn:SetPoint("RIGHT", windowFrame.cfgBtn, "LEFT", -3, 0)
    windowFrame.pinsBtn.t = StyleService:Text(windowFrame.pinsBtn, 10, StyleService.text)
    windowFrame.pinsBtn.t:SetPoint("CENTER", 0, 0)
    windowFrame.pinsBtn.t:SetJustifyH("CENTER")
    windowFrame.pinsBtn.t:SetText(ns.settings.showPins and L["핀 숨김"] or L["핀 표시"])
    windowFrame.pinsBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.accent))
        self.t:SetTextColor(unpack(StyleService.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["지도에 낚시 지점 표시"], unpack(StyleService.accent))
        GameTooltip:AddDoubleLine(" ", "EzWoW - Smart Fishing", 0, 0, 0, 0.5, 0.5, 0.5)
        GameTooltip:Show()
        if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
    end)
    windowFrame.pinsBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.border))
        self.t:SetTextColor(unpack(StyleService.text))
        GameTooltip:Hide()
    end)
    windowFrame.pinsBtn:SetScript("OnClick", ZoneDropRateLegend.toggleMapPins)

    windowFrame.title = StyleService:Text(windowFrame, 12, StyleService.accent)
    windowFrame.title:SetPoint("TOPLEFT", 10, -8)
    windowFrame.title:SetPoint("RIGHT", windowFrame.pinsBtn, "LEFT", -6, 0)

    windowFrame.resetFilterBtn = CreateFrame("Button", nil, windowFrame, "BackdropTemplate")
    StyleService:Panel(windowFrame.resetFilterBtn, StyleService.bgSub, StyleService.border)
    windowFrame.resetFilterBtn:SetSize(42, 20)
    windowFrame.resetFilterBtn:SetPoint("TOPRIGHT", -6, -35)
    windowFrame.resetFilterBtn.t = StyleService:Text(windowFrame.resetFilterBtn, 10, StyleService.text)
    windowFrame.resetFilterBtn.t:SetPoint("CENTER", 0, 0)
    windowFrame.resetFilterBtn.t:SetJustifyH("CENTER")
    windowFrame.resetFilterBtn.t:SetText(L["모든 물고기"])
    windowFrame.resetFilterBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.accent))
        self.t:SetTextColor(unpack(StyleService.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["선택 해제 (모든 물고기 보기)"], 1, 1, 1)
        GameTooltip:AddDoubleLine(" ", "EzWoW - Smart Fishing", 0, 0, 0, 0.5, 0.5, 0.5)
        GameTooltip:Show()
        if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
    end)
    windowFrame.resetFilterBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.border))
        self.t:SetTextColor(unpack(StyleService.text))
        GameTooltip:Hide()
    end)
    windowFrame.resetFilterBtn:SetScript("OnClick", function()
        ns:SetFishFilter(nil)
    end)
    windowFrame.resetFilterBtn:Hide()

    windowFrame.sub = StyleService:Text(windowFrame, 10, StyleService.muted)
    windowFrame.sub:SetPoint("TOPLEFT", 10, -39)
    windowFrame.sub:SetPoint("RIGHT", windowFrame, "RIGHT", -10, 0)

    windowFrame.line = StyleService:Line(windowFrame)
    windowFrame.line:SetPoint("TOPLEFT", 6, -58)
    windowFrame.line:SetPoint("TOPRIGHT", -6, -58)

    windowFrame.rows = {}

    windowFrame.track = windowFrame:CreateTexture(nil, "ARTWORK")
    windowFrame.track:SetWidth(3)
    windowFrame.track:SetColorTexture(1, 1, 1, 0.06)
    windowFrame.track:Hide()
    windowFrame.thumb = windowFrame:CreateTexture(nil, "OVERLAY")
    windowFrame.thumb:SetWidth(3)
    windowFrame.thumb:SetColorTexture(StyleService.accent[1], StyleService.accent[2], StyleService.accent[3], 0.7)
    windowFrame.thumb:Hide()

    -- the footer line pages through a long list (also reachable without a wheel)
    windowFrame.more = CreateFrame("Button", nil, windowFrame)
    windowFrame.more:SetPoint("BOTTOMLEFT", 6, 2)
    windowFrame.more:SetPoint("BOTTOMRIGHT", -6, 2)
    windowFrame.more:SetHeight(18)
    windowFrame.more:SetScript("OnClick", function() ZoneDropRateLegend.pageDown() end)
    windowFrame.more:Hide()

    windowFrame.foot = StyleService:Text(windowFrame, 9, StyleService.muted)
    windowFrame.foot:SetPoint("BOTTOMLEFT", 10, 6)
    windowFrame.foot:SetPoint("RIGHT", -10, 0)

    windowFrame.offset = 0
    windowFrame.items = {}
    windowFrame:EnableMouseWheel(true)
    windowFrame:SetScript("OnMouseWheel", function(_, delta)
        ZoneDropRateLegend.scrollBy(-(delta or 0) * 3)
    end)
    return windowFrame
end

function ZoneDropRateLegend.ensureRows(count)
    for i = #legend.rows + 1, count do legend.rows[i] = ZoneDropRateLegend.buildRow(legend, i) end
end

function ZoneDropRateLegend.assignRow(rowEntry, d)
    rowEntry.itemID, rowEntry.onClick, rowEntry.hint, rowEntry.hint2 = d.itemID, d.onClick, d.hint, d.hint2
    rowEntry.isHeader = d.header and true or false
    if d.header then
        rowEntry.icon:Hide()
        rowEntry.name:ClearAllPoints()
        rowEntry.name:SetPoint("LEFT", 4, 0)
        rowEntry.name:SetPoint("RIGHT", rowEntry.pct, "LEFT", -6, 0)
        rowEntry.name:SetText(MUTED_HEX .. d.header .. "|r")
        rowEntry.pct:SetText(d.pct or "")
        rowEntry.pct:SetTextColor(unpack(StyleService.muted))
        rowEntry.selected = false
        rowEntry.bg:SetColorTexture(1, 1, 1, 0.03)
        rowEntry:Show()
        return
    end
    rowEntry.icon:Show()
    rowEntry.name:ClearAllPoints()
    rowEntry.name:SetPoint("LEFT", rowEntry.icon, "RIGHT", 7, 0)
    rowEntry.name:SetPoint("RIGHT", rowEntry.pct, "LEFT", -6, 0)
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
    if p < 0.1 then return "<0.1%" end
    if p >= 10 then return string.format("%.0f%%", p) end
    return string.format("%.1f%%", p)
end

-- recommended skill, orange when the player's fishing skill is below it
function ZoneDropRateLegend.skillText(skill)
    if not skill then return nil end
    local mine = legend and legend.mySkill
    local color = (mine and mine < skill) and "|cffd9a066" or MUTED_HEX
    return color .. L["숙련 %d"]:format(skill) .. "|r"
end

function ZoneDropRateLegend.skillHint(skill)
    if not skill then return nil end
    local text = L["권장 숙련 %d"]:format(skill)
    local mine = legend and legend.mySkill
    if mine then text = text .. "  (" .. L["지금 %d"]:format(mine) .. ")" end
    return text
end

-- right column: own catch count, recommended skill, then the chance
function ZoneDropRateLegend.rightText(p, count, upTo, skill)
    local parts = ""
    if count and count > 0 then parts = MUTED_HEX .. L["내 기록 %d"]:format(count) .. "|r" end
    local skillText = ZoneDropRateLegend.skillText(skill)
    if skillText then parts = (parts ~= "" and (parts .. "  ") or "") .. skillText end
    if p then
        local pctText = ZoneDropRateLegend.formatPercentageString(p)
        if upTo then pctText = L["최대 %s"]:format(pctText) end
        parts = (parts ~= "" and (parts .. "  ") or "") .. pctText
    end
    return parts
end

-- fish of the expected table plus fish caught on this map that the table lacks
function ZoneDropRateLegend.collectFish(expected, mapID, minPct)
    local own = (ns.FishOnMap and ns:FishOnMap(mapID)) or {}
    local seen, list = {}, {}
    for id, p in pairs(expected or {}) do
        if p >= minPct or own[id] then
            seen[id] = true
            list[#list + 1] = { id = id, p = p, count = own[id] or 0 }
        end
    end
    for id, n in pairs(own) do
        if not seen[id] then list[#list + 1] = { id = id, count = n } end
    end
    table.sort(list, function(a, b)
        local pa, pb = a.p or -1, b.p or -1
        if pa ~= pb then return pa > pb end
        if a.count ~= b.count then return a.count > b.count end
        return a.id < b.id
    end)
    return list
end

-- Header buttons follow their text length (German / Russian are long) and
-- shrink the text only past a maximum, so they never overlap the title.
function ZoneDropRateLegend.fitHeaderButtons(frame)
    local kit = ns.UIKit
    if not (kit and kit.SizeButtonToText) then return end
    if frame.cfgBtn and frame.cfgBtn.t then kit:SizeButtonToText(frame.cfgBtn, frame.cfgBtn.t, 40, 84, 10) end
    if frame.pinsBtn and frame.pinsBtn.t then
        kit:SizeButtonToText(frame.pinsBtn, frame.pinsBtn.t, 56, 110, 10)
        frame:SetWidth(math.max(frameWidth, frame.cfgBtn:GetWidth() + frame.pinsBtn:GetWidth() + 141))
    end
    if frame.resetFilterBtn and frame.resetFilterBtn.t then kit:SizeButtonToText(frame.resetFilterBtn, frame.resetFilterBtn.t, 42, 90, 10) end
end

-- how many rows fit between the panel's anchor and the map edge it grows toward
function ZoneDropRateLegend.roomForRows()
    local container = WorldMapFrame:GetCanvasContainer()
    local anchor = legend.anchorButton
    local myScale = legend:GetEffectiveScale()
    local function inMine(frame, v)
        if not v or not myScale or myScale == 0 then return nil end
        return v * frame:GetEffectiveScale() / myScale
    end
    local room
    if container and anchor then
        local cTop, cBottom = inMine(container, container:GetTop()), inMine(container, container:GetBottom())
        if legend.growDown then
            local y = inMine(anchor, anchor:GetBottom())
            if y and cBottom then room = y - 6 - cBottom end
        else
            local y = inMine(anchor, legend.fromTop and anchor:GetTop() or anchor:GetBottom())
            if y and cTop then room = cTop - y - (legend.fromTop and 6 or 0) end
        end
    end
    if not room or room <= 0 then
        local h = container and container:GetHeight()
        room = (h and h > 0) and (h * 0.7) or 300
    end
    local rows = math.floor((room - TOP_PAD - 28) / ROW_H)
    return math.max(MIN_ROWS, math.min(MAX_ROWS, rows))
end

function ZoneDropRateLegend.render()
    local items, total = legend.items, #legend.items
    local visible = legend.visible or MIN_ROWS
    local shown = math.min(visible, total)
    local maxOffset = math.max(0, total - shown)
    if legend.offset > maxOffset then legend.offset = maxOffset end
    if legend.offset < 0 then legend.offset = 0 end
    local overflow = total > shown
    ZoneDropRateLegend.ensureRows(shown)
    for i, rowEntry in ipairs(legend.rows) do
        local d = i <= shown and items[legend.offset + i]
        if d then
            rowEntry:SetPoint("RIGHT", overflow and -10 or -6, 0)
            ZoneDropRateLegend.assignRow(rowEntry, d)
        else
            rowEntry:Hide()
        end
    end

    local footText = legend.info or ""
    if overflow then
        footText = string.format("%s  %d-%d / %d", L["휠로 넘겨 보기"], legend.offset + 1, legend.offset + shown, total)
        local trackH = shown * ROW_H
        legend.track:ClearAllPoints()
        legend.track:SetPoint("TOPRIGHT", -4, -TOP_PAD)
        legend.track:SetHeight(trackH)
        legend.track:Show()
        local thumbH = math.max(12, trackH * shown / total)
        local thumbY = (trackH - thumbH) * legend.offset / maxOffset
        legend.thumb:ClearAllPoints()
        legend.thumb:SetPoint("TOPRIGHT", -4, -TOP_PAD - thumbY)
        legend.thumb:SetHeight(thumbH)
        legend.thumb:Show()
    else
        legend.track:Hide()
        legend.thumb:Hide()
    end
    legend.more:SetShown(overflow)
    legend.foot:SetText(footText)
    legend.foot:SetShown(footText ~= "")
    local bottomPad = (footText ~= "") and 22 or 6
    legend:SetHeight(TOP_PAD + shown * ROW_H + bottomPad)
end

-- the rows show other fish after a scroll: a row's tooltip would be out of date
function ZoneDropRateLegend.dropRowTooltip()
    local owner = GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner()
    if owner and owner.GetParent and owner:GetParent() == legend then GameTooltip:Hide() end
end

function ZoneDropRateLegend.scrollBy(step)
    if not legend or not legend:IsShown() then return end
    local total, visible = #legend.items, legend.visible or MIN_ROWS
    if total <= visible then return end
    local offset = math.max(0, math.min(total - visible, legend.offset + step))
    if offset == legend.offset then return end
    legend.offset = offset
    ZoneDropRateLegend.dropRowTooltip()
    ZoneDropRateLegend.render()
end

function ZoneDropRateLegend.pageDown()
    if not legend then return end
    local total, visible = #legend.items, legend.visible or MIN_ROWS
    if total <= visible then return end
    if legend.offset + visible >= total then legend.offset = 0 else legend.offset = legend.offset + visible end
    ZoneDropRateLegend.dropRowTooltip()
    ZoneDropRateLegend.render()
end

function ZoneDropRateLegend.toggleFilter(itemID)
    local filter = ns.settings.filterFish
    ns:SetFishFilter(filter == itemID and nil or itemID)
end

-- a zone map: every fish with its chance, then the fish schools of the map
function ZoneDropRateLegend.zoneItems(mapID, filter, items)
    local fish, skill, sub, seen
    if mapID == C_Map.GetBestMapForUnit("player") then
        fish, skill, sub, seen = ns:ExpectedHere(mapID)
    else
        fish, skill, seen = ns:ExpectedZone(mapID)
    end
    legend.title:SetText(sub or ns:MapName(mapID))
    local subText = skill and L["권장 숙련 %d"]:format(skill) or L["일반 낚시"]
    -- the chances already include catches seen in the game
    if seen and seen > 0 then subText = subText .. "  " .. MUTED_HEX .. L["기록 %d회 반영"]:format(seen) .. "|r" end
    legend.sub:SetText(subText)

    local shown = {}
    for id in pairs(fish or {}) do shown[id] = true end
    local others = ns.OtherFishOnMap and ns:OtherFishOnMap(mapID, shown, sub ~= nil) or {}
    local otherSet = {}
    for _, entry in ipairs(others) do otherSet[entry.id] = true end
    local own = (ns.FishOnMap and ns:FishOnMap(mapID)) or {}

    for _, entry in ipairs(ZoneDropRateLegend.collectFish(fish, mapID, 0)) do
        local id = entry.id
        -- a fish caught here but given by another place is listed with that place below
        if entry.p or not otherSet[id] then
            local rowSkill = entry.p and skill or nil
            items[#items + 1] = {
                itemID = id, icon = ns:ItemIcon(id), name = ns:ItemName(id),
                pct = ZoneDropRateLegend.rightText(entry.p, entry.count, false, rowSkill),
                selected = filter == id,
                hint = L["클릭: 지도에서 이 물고기 기록·물고기 떼만 보기"],
                hint2 = ZoneDropRateLegend.skillHint(rowSkill),
                onClick = function() ZoneDropRateLegend.toggleFilter(id) end,
            }
        end
    end
    local pools = ns:PoolTypesOnMap(mapID)
    if #pools > 0 then
        items[#items + 1] = { header = L["물고기 떼"] }
        for _, pool in ipairs(pools) do
            local id = pool.type.fish
            items[#items + 1] = {
                itemID = id, icon = ns:ItemIcon(id), name = POOL_COLOR .. ns:PoolLabel(pool.type) .. "|r",
                pct = L["%d곳"]:format(pool.count),
                selected = filter == id,
                hint = L["클릭: 지도에서 이 물고기 기록·물고기 떼만 보기"],
                onClick = function() ZoneDropRateLegend.toggleFilter(id) end,
            }
        end
    end
    if #others > 0 then
        items[#items + 1] = { header = L["이 지도의 다른 곳"] }
        for _, entry in ipairs(others) do
            local id = entry.id
            local names = {}
            for i = 1, math.min(3, #entry.places) do names[#names + 1] = entry.places[i].name or "?" end
            local where = table.concat(names, ", ")
            if #entry.places > 3 then where = where .. " " .. L["외 %d곳"]:format(#entry.places - 3) end
            local hint2 = L["잡히는 곳: %s"]:format(where)
            local skillHint = ZoneDropRateLegend.skillHint(entry.s)
            if skillHint then hint2 = hint2 .. "\n" .. skillHint end
            items[#items + 1] = {
                itemID = id, icon = ns:ItemIcon(id), name = ns:ItemName(id),
                pct = ZoneDropRateLegend.rightText(entry.p, own[id] or 0, false, entry.s),
                selected = filter == id,
                hint = L["클릭: 지도에서 이 물고기 기록·물고기 떼만 보기"],
                hint2 = hint2,
                onClick = function() ZoneDropRateLegend.toggleFilter(id) end,
            }
        end
    end
end

-- a continent / world map with a fish chosen: its zones here, then other continents
function ZoneDropRateLegend.fishZoneItems(mapID, filter, items)
    legend.title:SetText(ns:ItemName(filter, true))
    legend.sub:SetText(L["일반 낚시 확률이 높은 지역"])
    local elsewhere = {}
    for _, zoneRef in ipairs(ns:ZonesForFish(filter)) do
        local zoneID = zoneRef.mapID
        if ns:GetChildZoneBoundaryRect(zoneID, mapID) then
            local zdVal = ns.Data.zones[zoneID]
            items[#items + 1] = {
                icon = ns:ItemIcon(filter),
                name = ns:MapName(zoneID),
                pct = ZoneDropRateLegend.rightText(zoneRef.pct, nil, false, zoneRef.s or (zdVal and zdVal.s)),
                onClick = function() ns:GoToMap(zoneID) end,
            }
        elseif zoneRef.pct >= 1 then
            local continent = ns:ResolveContinentMapID(zoneID)
            if continent and continent ~= mapID and (elsewhere[continent] or 0) < zoneRef.pct then
                elsewhere[continent] = zoneRef.pct
            end
        end
    end
    local others = {}
    for continent, pct in pairs(elsewhere) do others[#others + 1] = { id = continent, p = pct } end
    table.sort(others, function(a, b) return a.p > b.p end)
    for _, other in ipairs(others) do
        local continent = other.id
        items[#items + 1] = {
            icon = ns:ItemIcon(filter),
            name = MUTED_HEX .. L["다른 대륙: %s"]:format(ns:MapName(continent)) .. "|r",
            pct = L["최대 %s"]:format(ZoneDropRateLegend.formatPercentageString(other.p)),
            onClick = function() ns:GoToMap(continent) end,
        }
    end
    if #items == 0 then legend.info = L["이 대륙에는 기본 데이터가 없어요"] end
end

-- a continent / world map: every fish found here with its best chance
function ZoneDropRateLegend.continentItems(mapID, items)
    legend.title:SetText(ns:MapName(mapID))
    legend.sub:SetText(L["물고기를 누르면 잡히는 지역이 보여요"])
    for _, entry in ipairs(ZoneDropRateLegend.collectFish(ns:ExpectedOnMap(mapID), mapID, 1)) do
        local id = entry.id
        items[#items + 1] = {
            itemID = id, icon = ns:ItemIcon(id), name = ns:ItemName(id),
            pct = ZoneDropRateLegend.rightText(entry.p, entry.count, true, ns.FishSkill and ns:FishSkill(id)),
            hint = L["클릭: 이 물고기가 잡히는 지역 보기"],
            hint2 = ns.FishSkill and ns:FishSkill(id) and L["가장 낮은 권장 숙련 %d"]:format(ns:FishSkill(id)) or nil,
            onClick = function() ns:SetFishFilter(id) end,
        }
    end
end

function ns:UpdateMapLegend()
    if not legend then return end
    if legend.cfgBtn and legend.cfgBtn.t then legend.cfgBtn.t:SetText(L["설정"]) end
    if legend.pinsBtn and legend.pinsBtn.t then
        legend.pinsBtn.t:SetText(ns.settings.showPins and L["핀 숨김"] or L["핀 표시"])
    end
    if legend.resetFilterBtn and legend.resetFilterBtn.t then legend.resetFilterBtn.t:SetText(L["모든 물고기"]) end
    ZoneDropRateLegend.fitHeaderButtons(legend)
    local set = ns.settings
    if not set.showLegend or not set.mapButton or not WorldMapFrame:IsShown() then
        legend:Hide()
        return
    end

    local collapsed = set.legendCollapsed
    if collapsed then legend:Hide() return end

    local mapID = WorldMapFrame:GetMapID()
    local filter = set.filterFish
    local items = {}
    legend.info = nil
    legend.mySkill = nil
    if ns.FishingSkill then
        local rank, _, mod = ns:FishingSkill()
        if rank then legend.mySkill = rank + (mod or 0) end
    end

    legend.resetFilterBtn:SetShown(filter ~= nil)
    legend.sub:ClearAllPoints()
    legend.sub:SetPoint("TOPLEFT", 10, -39)
    if filter then
        legend.sub:SetPoint("RIGHT", legend.resetFilterBtn, "LEFT", -6, 0)
    else
        legend.sub:SetPoint("RIGHT", legend, "RIGHT", -10, 0)
    end

    local view
    if ns.Data.zones[mapID] then
        view = "zone"
        ZoneDropRateLegend.zoneItems(mapID, filter, items)
    elseif filter then
        view = "fish:" .. tostring(filter)
        ZoneDropRateLegend.fishZoneItems(mapID, filter, items)
    else
        view = "map"
        ZoneDropRateLegend.continentItems(mapID, items)
    end
    if #items == 0 and not legend.info then
        legend.info = L["이 지역은 일반 낚시 정보가 없어요"]
    end

    -- a new map or view starts at the top; picking a fish in the same list keeps the place
    local viewKey = tostring(mapID) .. ":" .. view
    if legend.viewKey ~= viewKey then
        legend.viewKey = viewKey
        legend.offset = 0
    end
    legend.items = items
    legend.sub:Show()
    legend.line:Show()
    legend:Show()
    legend.visible = ZoneDropRateLegend.roomForRows()
    ZoneDropRateLegend.render()
end

function ns:PlaceMapLegend(button, isDocked)
    if not legend then return end
    local coordPos = ns.settings.mapButtonPos or { 0.5, 0.05 }
    local autoAlign = not ns.settings or ns.settings.mapButtonAutoAlign ~= false
    legend.anchorButton = button
    legend:ClearAllPoints()
    if isDocked or autoAlign or (coordPos[1] and coordPos[1] < 0.25) then
        legend:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 6, 0)
        legend.growDown, legend.fromTop = false, false
    elseif coordPos[2] < 0.5 then
        legend:SetPoint("BOTTOM", button, "TOP", 0, 6)
        legend.growDown, legend.fromTop = false, true
    else
        legend:SetPoint("TOP", button, "BOTTOM", 0, -6)
        legend.growDown, legend.fromTop = true, false
    end
    -- the map was resized or the button moved: fit the list to the new room
    if legend:IsShown() and legend.items then
        legend.visible = ZoneDropRateLegend.roomForRows()
        ZoneDropRateLegend.render()
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
