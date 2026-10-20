--===========================================================================
-- EzWoW - Smart Fishing
-- Core/Style.lua : EzWoW Style Panel, FontString, Divider & Toggle Styler
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local ThemeStyler = ns.ThemeStyler or {}
ns.ThemeStyler = ThemeStyler
local L = ns.L

local StyleService = {}
ns.Style = StyleService

StyleService.bg      = { 0.071, 0.094, 0.122, 0.96 }
StyleService.bgSub   = { 0.114, 0.157, 0.192, 0.94 }
StyleService.border  = { 0.204, 0.298, 0.357, 0.90 }
StyleService.line    = { 0.204, 0.298, 0.357, 0.45 }
StyleService.hover   = { 0.376, 0.808, 0.639, 0.10 }
StyleService.accent  = { 0.376, 0.808, 0.639, 1.00 }
StyleService.text    = { 0.929, 0.957, 0.969, 1.00 }
StyleService.muted   = { 0.655, 0.725, 0.773, 1.00 }
StyleService.font    = STANDARD_TEXT_FONT

StyleService.CIRCLE  = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
StyleService.WHITE   = "Interface\\Buttons\\WHITE8x8"

StyleService.ICON       = "Interface\\AddOns\\EzWoW-SmartFishing\\Media\\icon"
StyleService.ICON_INNER = "Interface\\AddOns\\EzWoW-SmartFishing\\Media\\icon_inner"

function StyleService:Panel(frame, bg, border)
    frame:SetBackdrop({ bgFile = StyleService.WHITE, edgeFile = StyleService.WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(bg or StyleService.bg))
    frame:SetBackdropBorderColor(unpack(border or StyleService.border))
end

function StyleService:Text(parent, size, color, layer)
    local labelRegion = parent:CreateFontString(nil, layer or "OVERLAY")
    labelRegion:SetFont(StyleService.font, size or 12, "")
    labelRegion:SetTextColor(unpack(color or StyleService.text))
    labelRegion:SetJustifyH("LEFT")
    labelRegion:SetWordWrap(false)
    return labelRegion
end

function StyleService:Line(parent, layer)
    local resolvedValue = parent:CreateTexture(nil, layer or "ARTWORK")
    resolvedValue:SetColorTexture(unpack(StyleService.line))
    resolvedValue:SetHeight(1)
    return resolvedValue
end

function StyleService:Round(parent, texture)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(StyleService.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

function StyleService:Toggle(parent, onChange)
    local buttonWidget = CreateFrame("Button", nil, parent)
    buttonWidget:SetSize(30, 16)

    buttonWidget.track = buttonWidget:CreateTexture(nil, "BACKGROUND")
    buttonWidget.track:SetAllPoints()

    buttonWidget.knob = buttonWidget:CreateTexture(nil, "ARTWORK")
    buttonWidget.knob:SetSize(12, 12)
    buttonWidget.knob:SetColorTexture(1, 1, 1, 1)
    StyleService:Round(buttonWidget, buttonWidget.knob)

    function buttonWidget:SetOn(on)
        self.on = on and true or false
        self.track:SetColorTexture(unpack(self.on and StyleService.accent or StyleService.border))
        self.knob:ClearAllPoints()
        self.knob:SetPoint(self.on and "RIGHT" or "LEFT", self.on and -2 or 2, 0)
    end

    buttonWidget:SetScript("OnClick", function(self)
        self:SetOn(not self.on)
        onChange(self.on)
    end)
    return buttonWidget
end

function ns:ItemName(itemID, plain)
    local displayName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
        or (GetItemInfo and select(1, GetItemInfo(itemID)))
    if not displayName then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return L["불러오는 중..."]
    end
    if plain then return displayName end
    local quality = (C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID))
        or (GetItemInfo and select(3, GetItemInfo(itemID)))
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then return color.hex .. displayName .. "|r" end
    return displayName
end

function ns:ItemIcon(itemID)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
        or (GetItemIcon and GetItemIcon(itemID))
        or (GetItemInfoInstant and select(5, GetItemInfoInstant(itemID)))
        or StyleService.ICON_INNER
end
