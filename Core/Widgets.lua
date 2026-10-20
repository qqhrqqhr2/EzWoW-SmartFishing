--===========================================================================
-- EzWoW - Smart Fishing
-- Core/Widgets.lua : Reusable Virtual Scroll List, Stat Card & Setting Row Factory
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local WidgetBuilder = ns.WidgetBuilder or {}
ns.WidgetBuilder = WidgetBuilder
local StyleService = ns.Style

local ROW_H = 36

function WidgetBuilder.buildRow(parent)
    local rowEntry = CreateFrame("Button", nil, parent)
    rowEntry:SetHeight(ROW_H)

    rowEntry.bg = rowEntry:CreateTexture(nil, "BACKGROUND")
    rowEntry.bg:SetAllPoints()
    rowEntry.bg:SetColorTexture(0, 0, 0, 0)

    rowEntry.mark = rowEntry:CreateTexture(nil, "ARTWORK")
    rowEntry.mark:SetPoint("TOPLEFT")
    rowEntry.mark:SetPoint("BOTTOMLEFT")
    rowEntry.mark:SetWidth(2)
    rowEntry.mark:SetColorTexture(unpack(StyleService.accent))

    rowEntry.icon = rowEntry:CreateTexture(nil, "ARTWORK")
    rowEntry.icon:SetSize(24, 24)
    rowEntry.icon:SetPoint("LEFT", 8, 0)
    StyleService:Round(rowEntry, rowEntry.icon)

    rowEntry.right = StyleService:Text(rowEntry, 12)
    rowEntry.right:SetPoint("TOPRIGHT", -8, -6)
    rowEntry.right:SetJustifyH("RIGHT")

    rowEntry.right2 = StyleService:Text(rowEntry, 10, StyleService.muted)
    rowEntry.right2:SetPoint("TOPRIGHT", rowEntry.right, "BOTTOMRIGHT", 0, -3)
    rowEntry.right2:SetJustifyH("RIGHT")

    rowEntry.title = StyleService:Text(rowEntry, 12)
    rowEntry.title:SetPoint("TOPLEFT", rowEntry.icon, "TOPRIGHT", 10, 1)
    rowEntry.title:SetPoint("RIGHT", rowEntry.right, "LEFT", -8, 0)

    rowEntry.sub = StyleService:Text(rowEntry, 10, StyleService.muted)
    rowEntry.sub:SetPoint("TOPLEFT", rowEntry.title, "BOTTOMLEFT", 0, -4)
    rowEntry.sub:SetPoint("RIGHT", rowEntry.right2, "LEFT", -8, 0)

    rowEntry.track = rowEntry:CreateTexture(nil, "ARTWORK")
    rowEntry.track:SetHeight(3)
    rowEntry.track:SetPoint("BOTTOMLEFT", rowEntry.icon, "BOTTOMRIGHT", 10, 1)
    rowEntry.track:SetPoint("RIGHT", -64, 0)
    rowEntry.track:SetColorTexture(1, 1, 1, 0.07)

    rowEntry.fill = rowEntry:CreateTexture(nil, "OVERLAY")
    rowEntry.fill:SetHeight(3)
    rowEntry.fill:SetPoint("LEFT", rowEntry.track, "LEFT")
    rowEntry.fill:SetColorTexture(unpack(StyleService.accent))

    rowEntry:SetScript("OnEnter", function(self)
        if not self.data.selected then self.bg:SetColorTexture(unpack(StyleService.hover)) end
        if self.data.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.data.itemID)
            if self.data.hint then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.data.hint, unpack(StyleService.accent))
            end
            GameTooltip:Show()
        end
    end)
    rowEntry:SetScript("OnLeave", function(self)
        if not self.data.selected then self.bg:SetColorTexture(0, 0, 0, 0) end
        GameTooltip:Hide()
    end)
    rowEntry:SetScript("OnClick", function(self)
        if self.data.onClick then self.data.onClick(self.data) end
    end)
    return rowEntry
end

function WidgetBuilder.fillRow(rowEntry, d)
    rowEntry.data = d
    rowEntry.icon:SetTexture(d.icon or StyleService.ICON_INNER)
    rowEntry.title:SetText(d.title or "")
    rowEntry.sub:SetText(d.sub or "")
    rowEntry.right:SetText(d.right or "")
    rowEntry.right2:SetText(d.right2 or "")

    local containsBar = d.bar ~= nil
    rowEntry.track:SetShown(containsBar)
    rowEntry.fill:SetShown(containsBar)
    rowEntry.sub:SetShown(not containsBar)
    if containsBar then
        local boxWidth = rowEntry.track:GetWidth()
        if not boxWidth or boxWidth <= 0 then boxWidth = 150 end
        rowEntry.fill:SetWidth(math.max(1, boxWidth * math.min(1, d.bar)))
    end

    rowEntry.mark:SetShown(d.selected and true or false)
    if d.selected then
        rowEntry.bg:SetColorTexture(StyleService.accent[1], StyleService.accent[2], StyleService.accent[3], 0.10)
    else
        rowEntry.bg:SetColorTexture(0, 0, 0, 0)
    end
    rowEntry:Show()
end

function StyleService:List(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, scrollFrame)
    child:SetSize(1, 1)
    scrollFrame:SetScrollChild(child)
    scrollFrame:SetScript("OnSizeChanged", function(self, boxWidth) child:SetWidth(boxWidth) end)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * ROW_H * 2)))
    end)

    scrollFrame.rows = {}
    scrollFrame.empty = StyleService:Text(child, 11, StyleService.muted)
    scrollFrame.empty:SetPoint("TOP", 0, -30)
    scrollFrame.empty:SetJustifyH("CENTER")
    scrollFrame.empty:SetWordWrap(true)
    scrollFrame.empty:SetWidth(240)

    function scrollFrame:SetEmptyText(text) self.empty:SetText(text) end

    function scrollFrame:SetData(list)
        for _, rowEntry in ipairs(self.rows) do rowEntry:Hide() end
        self.empty:SetShown(#list == 0)
        for index, d in ipairs(list) do
            local rowEntry = self.rows[index]
            if not rowEntry then
                rowEntry = WidgetBuilder.buildRow(child)
                rowEntry:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
                rowEntry:SetPoint("RIGHT", child, "RIGHT")
                self.rows[index] = rowEntry
            end
            WidgetBuilder.fillRow(rowEntry, d)
        end
        child:SetHeight(math.max(1, #list * ROW_H))
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        if (self:GetVerticalScroll() or 0) > maxScroll then self:SetVerticalScroll(maxScroll) end
    end
    return scrollFrame
end

function StyleService:Stat(parent, label)
    local windowFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    StyleService:Panel(windowFrame, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.06 })
    windowFrame.value = StyleService:Text(windowFrame, 16)
    windowFrame.value:SetPoint("TOPLEFT", 10, -8)
    windowFrame.label = StyleService:Text(windowFrame, 10, StyleService.muted)
    windowFrame.label:SetPoint("TOPLEFT", windowFrame.value, "BOTTOMLEFT", 0, -4)
    windowFrame.label:SetText(label)
    return windowFrame
end

function StyleService:Button(parent, text, onClick)
    local buttonWidget = CreateFrame("Button", nil, parent, "BackdropTemplate")
    StyleService:Panel(buttonWidget, { 1, 1, 1, 0.03 }, StyleService.border)
    buttonWidget:SetHeight(26)
    buttonWidget.t = StyleService:Text(buttonWidget, 12)
    buttonWidget.t:SetPoint("CENTER")
    buttonWidget.t:SetJustifyH("CENTER")
    function buttonWidget:SetLabel(s)
        self.t:SetText(s)
        self:SetWidth(self.t:GetStringWidth() + 24)
    end
    buttonWidget:SetLabel(text)
    buttonWidget:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(StyleService.accent)) end)
    buttonWidget:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(StyleService.border)) end)
    buttonWidget:SetScript("OnClick", onClick)
    return buttonWidget
end

function StyleService:SettingRow(parent, label, key)
    local rowWidget = CreateFrame("Frame", nil, parent)
    rowWidget:SetHeight(26)
    rowWidget.label = StyleService:Text(rowWidget, 12)
    rowWidget.label:SetPoint("LEFT")
    rowWidget.label:SetText(label)
    rowWidget.toggle = StyleService:Toggle(rowWidget, function(on)
        ns.settings[key] = on
        ns:PublishAddonEvent("AM_SETTINGS_CHANGED", key)
    end)
    rowWidget.toggle:SetPoint("RIGHT")
    rowWidget.key = key
    return rowWidget
end
