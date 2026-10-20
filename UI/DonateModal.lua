--===========================================================================
-- EzWoW - Smart Fishing
-- UI/DonateModal.lua : Copyable Support Link Dialog
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SupportLinkModal = ns.SupportLinkModal or {}
ns.SupportLinkModal = SupportLinkModal
local L = ns.L
local StyleService = ns.Style

ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"

local containerFrame

function SupportLinkModal.createPrimaryWidget()
    local windowFrame = CreateFrame("Frame", "EzWoW_SmartFishingDonate", UIParent, "BackdropTemplate")
    StyleService:Panel(windowFrame)
    windowFrame:SetSize(340, 150)
    windowFrame:SetPoint("CENTER", 0, 120)
    ns.UIKit:ElevateModal(windowFrame, 260)
    windowFrame:EnableMouse(true)
    windowFrame:SetMovable(true)
    windowFrame:RegisterForDrag("LeftButton")
    windowFrame:SetScript("OnDragStart", windowFrame.StartMoving)
    windowFrame:SetScript("OnDragStop", windowFrame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "EzWoW_SmartFishingDonate")

    windowFrame.logo = windowFrame:CreateTexture(nil, "ARTWORK")
    windowFrame.logo:SetSize(26, 26)
    windowFrame.logo:SetPoint("TOPLEFT", 14, -14)
    windowFrame.logo:SetTexture(StyleService.ICON)
    StyleService:Round(windowFrame, windowFrame.logo)

    windowFrame.title = StyleService:Text(windowFrame, 14)
    windowFrame.title:SetPoint("LEFT", windowFrame.logo, "RIGHT", 10, 0)
    windowFrame.title:SetText(L["후원하기"])

    windowFrame.text = StyleService:Text(windowFrame, 11, StyleService.muted)
    windowFrame.text:SetPoint("TOPLEFT", 14, -50)
    windowFrame.text:SetPoint("RIGHT", -14, 0)
    windowFrame.text:SetWordWrap(true)
    windowFrame.text:SetText(L["도움이 되셨다면 후원해 주세요! 아래 주소를 복사(Ctrl+C)해서 브라우저에 붙여 넣으세요."])

    local editBox = CreateFrame("EditBox", nil, windowFrame, "BackdropTemplate")
    StyleService:Panel(editBox, { 0, 0, 0, 0.35 }, StyleService.accent)
    editBox:SetHeight(26)
    editBox:SetFrameLevel(windowFrame:GetFrameLevel() + 5)
    editBox:SetPoint("BOTTOMLEFT", 14, 14)
    editBox:SetPoint("BOTTOMRIGHT", -14, 14)
    editBox:SetFont(StyleService.font, 12, "")
    editBox:SetTextColor(1, 1, 1)
    editBox:SetTextInsets(8, 8, 0, 0)
    editBox:SetAutoFocus(false)
    
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(ns.DONATE_URL) self:HighlightText() end
    end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    editBox:SetScript("OnEscapePressed", function() windowFrame:Hide() end)
    editBox:SetScript("OnEnterPressed", function() windowFrame:Hide() end)
    windowFrame.box = editBox

    local close = CreateFrame("Button", nil, windowFrame)
    close:SetSize(22, 22)
    close:SetFrameLevel(windowFrame:GetFrameLevel() + 5)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.t = StyleService:Text(close, 16, StyleService.muted)
    close.t:SetPoint("CENTER")
    close.t:SetText("×")
    close:SetScript("OnEnter", function(self) self.t:SetTextColor(unpack(StyleService.text)) end)
    close:SetScript("OnLeave", function(self) self.t:SetTextColor(unpack(StyleService.muted)) end)
    close:SetScript("OnClick", function() windowFrame:Hide() end)

    windowFrame:SetScript("OnShow", function(self)
        self.title:SetText(L["후원하기"])
        self.text:SetText(L["도움이 되셨다면 후원해 주세요! 아래 주소를 복사(Ctrl+C)해서 브라우저에 붙여 넣으세요."])
        self.box:SetText(ns.DONATE_URL)
        self.box:SetFocus()
        self.box:HighlightText()
    end)
    windowFrame:Hide()
    return windowFrame
end

function ns:ShowDonate()
    containerFrame = containerFrame or SupportLinkModal.createPrimaryWidget()
    ns.UIKit:ElevateModal(containerFrame, 260)
    containerFrame:Show()
    if containerFrame.Raise then containerFrame:Raise() end
end

function ns:RefreshDonateLocale()
    if containerFrame then
        containerFrame.title:SetText(L["후원하기"])
        containerFrame.text:SetText(L["도움이 되셨다면 후원해 주세요! 아래 주소를 복사(Ctrl+C)해서 브라우저에 붙여 넣으세요."])
    end
end
