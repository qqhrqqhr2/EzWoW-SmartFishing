--===========================================================================
-- EzWoW - Smart Fishing
-- UI/HUD.lua : Compact Live Fishing Skill, Lure Timer & Session Catch HUD
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local LiveFishingHUD = ns.LiveFishingHUD or {}
ns.LiveFishingHUD = LiveFishingHUD
local L = ns.L
local StyleService = ns.Style

local hud

function LiveFishingHUD.buildHUD()
    local windowFrame = CreateFrame("Button", "EzWoW_SmartFishingHUD", UIParent, "BackdropTemplate")
    StyleService:Panel(windowFrame)
    windowFrame:SetSize(236, 84)
    windowFrame:SetFrameStrata("MEDIUM")
    windowFrame:SetClampedToScreen(true)
    windowFrame:SetMovable(true)
    windowFrame:RegisterForDrag("LeftButton")
    windowFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local coordPos = ns.db.hudPos
    if coordPos then
        windowFrame:SetPoint(coordPos[1], UIParent, coordPos[2], coordPos[3], coordPos[4])
    else
        windowFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end

    windowFrame:SetScript("OnDragStart", windowFrame.StartMoving)
    windowFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local anchorTarget, _, relativePoint, coordX, coordY = self:GetPoint()
        ns.db.hudPos = { anchorTarget, relativePoint, coordX, coordY }
    end)
    windowFrame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns:OpenSettings() else ns:ToggleWindow("session") end
    end)
    windowFrame:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("EzWoW - Smart Fishing", unpack(StyleService.accent))
        GameTooltip:AddLine(L["왼쪽 클릭: 기록 창"], 0.929, 0.957, 0.969)
        GameTooltip:AddLine(L["오른쪽 클릭: 설정"], 0.655, 0.725, 0.773)
        GameTooltip:AddLine(L["드래그: 아이콘 위치 이동"], 0.655, 0.725, 0.773)
        GameTooltip:Show()
    end)
    windowFrame:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.border))
        GameTooltip:Hide()
    end)

    windowFrame.skill = StyleService:Text(windowFrame, 11, StyleService.muted)
    windowFrame.skill:SetPoint("TOPLEFT", 10, -9)
    windowFrame.lure = StyleService:Text(windowFrame, 11, StyleService.muted)
    windowFrame.lure:SetPoint("TOPRIGHT", -10, -9)
    windowFrame.lure:SetJustifyH("RIGHT")

    local labelKeys = { "시간", "낚음", "성공률", "시간당" }
    windowFrame.vals = {}
    windowFrame.lbls = {}
    local cellW = (236 - 20) / 4
    for index, lookupKey in ipairs(labelKeys) do
        local entryValue = StyleService:Text(windowFrame, 14)
        entryValue:SetPoint("TOPLEFT", 10 + (index - 1) * cellW, -26)
        local leftPos = StyleService:Text(windowFrame, 9, StyleService.muted)
        leftPos:SetPoint("TOPLEFT", entryValue, "BOTTOMLEFT", 0, -2)
        leftPos:SetText(L[lookupKey])
        leftPos.key = lookupKey
        windowFrame.vals[index] = entryValue
        windowFrame.lbls[index] = leftPos
    end

    local line = StyleService:Line(windowFrame)
    line:SetPoint("BOTTOMLEFT", 0, 24)
    line:SetPoint("BOTTOMRIGHT", 0, 24)

    windowFrame.lastIcon = windowFrame:CreateTexture(nil, "ARTWORK")
    windowFrame.lastIcon:SetSize(14, 14)
    windowFrame.lastIcon:SetPoint("BOTTOMLEFT", 10, 5)
    StyleService:Round(windowFrame, windowFrame.lastIcon)
    
    windowFrame.stop = CreateFrame("Button", nil, windowFrame, "BackdropTemplate")
    StyleService:Panel(windowFrame.stop, { 1, 1, 1, 0.04 }, StyleService.border)
    windowFrame.stop:SetHeight(18)
    windowFrame.stop:SetPoint("BOTTOMRIGHT", -6, 3)
    windowFrame.stop.t = StyleService:Text(windowFrame.stop, 10)
    windowFrame.stop.t:SetPoint("CENTER")
    windowFrame.stop.t:SetJustifyH("CENTER")
    windowFrame.stop.t:SetText(L["낚시 종료"])
    windowFrame.stop:SetWidth(windowFrame.stop.t:GetStringWidth() + 16)
    windowFrame.stop:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.85, 0.40, 0.40, 1)
        self.t:SetTextColor(1, 0.75, 0.75)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["낚시 종료"], 1, 1, 1)
        GameTooltip:AddLine(L["이번 세션을 마치고 평소 무기로 바꿉니다."], unpack(StyleService.muted))
        GameTooltip:Show()
    end)
    windowFrame.stop:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(StyleService.border))
        self.t:SetTextColor(unpack(StyleService.text))
        GameTooltip:Hide()
    end)
    windowFrame.stop:SetScript("OnClick", function() ns:StopFishing() end)

    windowFrame.last = StyleService:Text(windowFrame, 11)
    windowFrame.last:SetPoint("LEFT", windowFrame.lastIcon, "RIGHT", 6, 0)
    windowFrame.last:SetPoint("RIGHT", windowFrame.stop, "LEFT", -6, 0)

    function windowFrame:Update()
        for _, leftPos in ipairs(self.lbls or {}) do
            leftPos:SetText(L[leftPos.key])
        end
        if self.stop and self.stop.t then
            self.stop.t:SetText(L["낚시 종료"])
            self.stop:SetWidth(self.stop.t:GetStringWidth() + 16)
        end
        local stateFlag = ns:Session()
        local catches, casts = stateFlag and stateFlag.catches or 0, stateFlag and stateFlag.casts or 0
        local dur = 0
        if stateFlag then
            dur = (time() - stateFlag.last > 60) and (stateFlag.last - stateFlag.start) or (time() - stateFlag.start)
        end
        self.vals[1]:SetText(ns:FormatDuration(dur))
        self.vals[2]:SetText(catches)
        self.vals[3]:SetText(casts > 0 and string.format("%.0f%%", catches / casts * 100) or "-")
        self.vals[4]:SetText(dur > 60 and string.format("%.0f", catches / dur * 3600) or "-")

        local rank, maxRank, mod = ns:FishingSkill()
        if rank then
            local _, need = ns:ExpectedHere(C_Map.GetBestMapForUnit("player"))
            local mine = rank + (mod or 0)
            local colorRGB = (need and mine < need) and "|cffd9a066" or "|cffeeeff2"
            self.skill:SetText(string.format(L["숙련 %s%d|r%s%s"], colorRGB, mine,
                (mod and mod > 0) and ("|cff8c94a3(+" .. mod .. ")|r") or "",
                need and ("  |cff8c94a3" .. L["권장 %d"]:format(need) .. "|r") or ""))
        else
            self.skill:SetText(L["낚시"])
        end

        local lure = ns:LureRemaining()
        if lure then
            self.lure:SetText(L["미끼 %s"]:format("|cff45c7e0" .. ns:FormatDuration(lure) .. "|r"))
        else
            self.lure:SetText(L["|cffd9a066미끼 없음|r"])
        end

        local rowEntry = ns.db.recent[1]
        if rowEntry and stateFlag and rowEntry.t >= stateFlag.start then
            self.lastIcon:SetTexture(ns:ItemIcon(rowEntry.id))
            self.lastIcon:Show()
            self.last:SetText(ns:ItemName(rowEntry.id))
        else
            self.lastIcon:Hide()
            self.last:SetText(L["|cff8c94a3낚시를 시작해 보세요|r"])
            self.last:SetPoint("LEFT", windowFrame, "BOTTOMLEFT", 10, 12)
        end
        if self.lastIcon:IsShown() then
            self.last:SetPoint("LEFT", self.lastIcon, "RIGHT", 6, 0)
        end

        if ns.bobberFound == false then
            self.lastIcon:Hide()
            self.last:SetPoint("LEFT", self, "BOTTOMLEFT", 10, 12)
            self.last:SetText(L["|cffd9a066찌 인식 안 됨 · 마우스를 찌에 올리고 키를 누르세요|r"])
        end
    end

    local elapsed = 0
    windowFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        self:Update()
    end)
    windowFrame:Hide()
    return windowFrame
end

function LiveFishingHUD.refreshVisibility()
    if not ns.settings then return end
    local show = ns.settings.showHUD and ns:HasPole()
    if show and not hud then hud = LiveFishingHUD.buildHUD() end
    if hud then
        hud:SetScale(ns.settings.hudScale or 1)
        hud:SetShown(show)
        if show then hud:Update() end
    end
end

ns:SubscribeAddonEvent("PLAYER_ENTERING_WORLD", LiveFishingHUD.refreshVisibility)
ns:SubscribeAddonEvent("PLAYER_EQUIPMENT_CHANGED", LiveFishingHUD.refreshVisibility)
ns:SubscribeAddonEvent("AM_SETTINGS_CHANGED", function(lookupKey)
    if lookupKey == "showHUD" or lookupKey == "hudScale" then LiveFishingHUD.refreshVisibility() end
end)
ns:SubscribeAddonEvent("AM_BOBBER_CHANGED", function()
    if hud and hud:IsShown() then hud:Update() end
end)
ns:SubscribeAddonEvent("AM_DATA_CHANGED", function()
    if hud and hud:IsShown() then hud:Update() end
end)
