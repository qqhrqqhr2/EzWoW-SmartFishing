--===========================================================================
-- EzWoW - Smart Fishing
-- UI/MinimapButton.lua : Draggable Minimap Button & Addon Compartment Handler
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local MinimapLauncherButton = ns.MinimapLauncherButton or {}
ns.MinimapLauncherButton = MinimapLauncherButton
local L = ns.L
local StyleService = ns.Style

local button
local grabDX, grabDY = 0, 0

local function GetMinimapRadius()
    local r = ((Minimap and Minimap:GetWidth()) or 140) / 2 + 5
    if r < 60 or r > 140 then r = 75 end
    return r
end

function MinimapLauncherButton.refreshPosition()
    if not button or not Minimap then return end
    button:SetScale(1)
    button:ClearAllPoints()
    if ns.settings and ns.settings.minimapFreeX and ns.settings.minimapFreeY then
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.settings.minimapFreeX, ns.settings.minimapFreeY)
        return
    end
    local angle = math.rad((ns.settings and ns.settings.minimapAngle) or 200)
    local radius = GetMinimapRadius()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function MinimapLauncherButton.onDragUpdate(self)
    local btn = self or button
    if not btn or not Minimap or not ns.settings then return end
    local bScale = btn:GetEffectiveScale() or 1
    local mScale = Minimap:GetEffectiveScale() or 1
    local rawX, rawY = GetCursorPosition()
    local curX, curY = rawX / bScale + grabDX, rawY / bScale + grabDY

    local mxVal, myVal = Minimap:GetCenter()
    if mxVal and myVal then
        local curMX = (curX * bScale) / mScale
        local curMY = (curY * bScale) / mScale
        local dx, dy = curMX - mxVal, curMY - myVal
        local dist = math.sqrt(dx * dx + dy * dy)
        local ringRadius = GetMinimapRadius()
        if dist <= ringRadius + 28 then
            ns.settings.minimapFreeX = nil
            ns.settings.minimapFreeY = nil
            ns.settings.minimapAngle = math.deg(math.atan2(dy, dx)) % 360
            MinimapLauncherButton.refreshPosition()
            return
        end
    end

    local uiW = (UIParent and UIParent:GetWidth()) or 1920
    local uiH = (UIParent and UIParent:GetHeight()) or 1080
    if curX < 16 then curX = 16 elseif curX > uiW - 16 then curX = uiW - 16 end
    if curY < 16 then curY = 16 elseif curY > uiH - 16 then curY = uiH - 16 end
    ns.settings.minimapFreeX = curX
    ns.settings.minimapFreeY = curY
    MinimapLauncherButton.refreshPosition()
end

function MinimapLauncherButton.buildButton()
    local buttonWidget = CreateFrame("Button", "EzWoW_SmartFishingMinimapButton", Minimap)
    buttonWidget:SetSize(31, 31)
    buttonWidget:SetScale(1)
    buttonWidget:SetFrameStrata("MEDIUM")
    buttonWidget:SetFrameLevel(8)
    buttonWidget:SetClampedToScreen(true)
    buttonWidget:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    buttonWidget:RegisterForDrag("LeftButton")
    buttonWidget:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local backdropTex = buttonWidget:CreateTexture(nil, "BACKGROUND")
    backdropTex:SetSize(20, 20)
    backdropTex:SetPoint("TOPLEFT", 7, -5)
    backdropTex:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    buttonWidget.icon = buttonWidget:CreateTexture(nil, "ARTWORK")
    buttonWidget.icon:SetSize(18, 18)
    buttonWidget.icon:SetPoint("TOPLEFT", 7, -6)
    buttonWidget.icon:SetTexture(StyleService.ICON_INNER)
    StyleService:Round(buttonWidget, buttonWidget.icon)

    local borderTex = buttonWidget:CreateTexture(nil, "OVERLAY")
    borderTex:SetSize(53, 53)
    borderTex:SetPoint("TOPLEFT")
    borderTex:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    buttonWidget:SetScript("OnClick", function(self, mouse)
        if self.dragging then return end
        if mouse == "RightButton" then
            ns:OpenSettings()
        else
            ns:EquipBestPole()
        end
    end)
    buttonWidget:SetScript("OnDragStart", function(self)
        self:SetScale(1)
        self.dragging = true
        GameTooltip:Hide()
        local bScale = self:GetEffectiveScale() or 1
        local rawX, rawY = GetCursorPosition()
        local cx, cy = rawX / bScale, rawY / bScale
        local bx, by = self:GetCenter()
        if bx and by then
            grabDX = bx - cx
            grabDY = by - cy
        else
            grabDX, grabDY = 0, 0
        end
        self:SetScript("OnUpdate", MinimapLauncherButton.onDragUpdate)
    end)
    buttonWidget:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.dragging = false
    end)
    buttonWidget:SetScript("OnEnter", function(self)
        if self.dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("EzWoW - Smart Fishing", unpack(StyleService.accent))
        GameTooltip:AddLine(L["왼쪽 클릭"] .. ": " .. (ns:HasPole() and L["평소 무기로"] or L["낚싯대 착용"]), 0.929, 0.957, 0.969)
        GameTooltip:AddLine(L["오른쪽 클릭"] .. ": " .. L["설정"], 0.655, 0.725, 0.773)
        GameTooltip:AddLine(L["드래그: 아이콘 위치 이동"], 0.655, 0.725, 0.773)
        GameTooltip:Show()
    end)
    buttonWidget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return buttonWidget
end

function MinimapLauncherButton.refreshMinimapButton()
    if not ns.settings then return end
    if ns.settings.minimapButton then
        button = button or MinimapLauncherButton.buildButton()
        MinimapLauncherButton.refreshPosition()
        button:Show()
    elseif button then
        button:Hide()
    end
end

ns:SubscribeAddonEvent("AM_DB_READY", MinimapLauncherButton.refreshMinimapButton)
ns:SubscribeAddonEvent("AM_SETTINGS_CHANGED", function(key)
    if key == "minimapButton" then MinimapLauncherButton.refreshMinimapButton() end
end)

function EzWoW_SmartFishing_OnAddonCompartmentClick(_, mouse)
    if mouse == "RightButton" then ns:OpenSettings() else ns:EquipBestPole() end
end

function ns:ResetMinimapButton()
    if not self.settings then return end
    self.settings.minimapButton = true
    self.settings.minimapAngle = 200
    self.settings.minimapFreeX = nil
    self.settings.minimapFreeY = nil
    MinimapLauncherButton.refreshMinimapButton()
end
