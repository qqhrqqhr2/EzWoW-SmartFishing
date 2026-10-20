--===========================================================================
-- EzWoW - Smart Fishing
-- UI/OptionsWindow.lua : EzWoW Style Settings Dialog, Reset Popups & Blizzard Panel
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SettingsDialog = ns.SettingsDialog or {}
ns.SettingsDialog = SettingsDialog
local L = ns.L
local StyleService = ns.Style

local configFrame
local BlizzardOptionsCanvas

local Theme = {
    bg      = { 0.071, 0.094, 0.122, 0.97 },
    bgSub   = { 0.114, 0.157, 0.192, 0.96 },
    bgHover = { 0.165, 0.227, 0.278, 0.98 },
    border  = { 0.204, 0.298, 0.357, 1.00 },
    accent  = { 0.376, 0.808, 0.639, 1.00 }, 
    text    = { 0.929, 0.957, 0.969, 1.00 },
    muted   = { 0.655, 0.725, 0.773, 1.00 },
}

function SettingsDialog.resolveKeyList()
    return {
        { "SPACE", L["스페이스"] },
        { "F", "F" }, { "G", "G" }, { "R", "R" }, { "T", "T" }, { "V", "V" },
        { "BUTTON3", L["마우스 휠 클릭"] },
        { "BUTTON4", L["마우스 4번 버튼"] },
        { "BUTTON5", L["마우스 5번 버튼"] },
    }
end

function SettingsDialog.definePopups()
    StaticPopupDialogs["WOWSMARTFISHING_RELOAD"] = {
        text = L["언어를 바꾸려면 UI를 다시 불러와야 해요. 지금 다시 불러올까요?"],
        button1 = L["다시 불러오기"], button2 = L["나중에"],
        OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    StaticPopupDialogs["EZWOWSMARTFISHING_RESET_ZONE"] = {
        text = L["현재 지역의 낚시 지점 기록을 지울까요?"],
        button1 = YES, button2 = NO,
        OnAccept = function()
            local mapID = C_Map.GetBestMapForUnit("player")
            if mapID then ns.db.spots[mapID] = nil end
            ns:Print(L["현재 지역 낚시 지점 기록을 지웠어요."])
            ns:PublishAddonEvent("AM_DATA_CHANGED")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    StaticPopupDialogs["EZWOWSMARTFISHING_RESET_ALL"] = {
        text = L["모든 낚시 기록(지점, 기록, 도감, 세션)을 지울까요?\n되돌릴 수 없어요."],
        button1 = YES, button2 = NO,
        OnAccept = function()
            local db = ns.db
            wipe(db.spots)
            wipe(db.recent)
            wipe(db.journal)
            db.totals = { casts = 0, catches = 0, missed = 0 }
            db.session = nil
            ns:Print(L["모든 낚시 기록을 지웠어요."])
            ns:PublishAddonEvent("AM_DATA_CHANGED")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
    }

    StaticPopupDialogs["EZWOWSMARTFISHING_RESET_SHARED"] = {
        text = L["다른 플레이어에게 공유받은 낚시 기록을 모두 지울까요?"],
        button1 = YES, button2 = NO,
        OnAccept = function() ns:ClearShared() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

function SettingsDialog.buildConfigWindow()
    if configFrame then return configFrame end
    SettingsDialog.definePopups()

    local windowFrame = CreateFrame("Frame", "EzWoW_SmartFishingConfig", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    windowFrame:SetSize(460, 650)
    windowFrame:SetPoint("CENTER")
    windowFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    windowFrame:SetToplevel(true)
    windowFrame:SetClampedToScreen(true)
    windowFrame:SetMovable(true)
    windowFrame:EnableMouse(true)
    if windowFrame.SetBackdrop then
        ns.UIKit:ApplyBackdrop(windowFrame, 1, 1)
        windowFrame:SetBackdropColor(unpack(Theme.bg))
        windowFrame:SetBackdropBorderColor(unpack(Theme.border))
    end
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoW_SmartFishingConfig") end

    local top = CreateFrame("Frame", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    top:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -1, -1)
    top:SetHeight(56)
    if top.SetBackdrop then
        top:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        top:SetBackdropColor(unpack(Theme.bgSub))
    end
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function() windowFrame:StartMoving() end)
    top:SetScript("OnDragStop", function() windowFrame:StopMovingOrSizing() end)

    local accentLine = top:CreateTexture(nil, "ARTWORK")
    accentLine:SetColorTexture(unpack(Theme.accent))
    accentLine:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(2)

    local titleIcon = top:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(28, 28)
    titleIcon:SetPoint("TOPLEFT", 14, -14)
    titleIcon:SetTexture(StyleService and StyleService.ICON or "Interface\\AddOns\\EzWoW-SmartFishing\\Media\\icon")

    local headingRegion = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headingRegion:SetPoint("TOPLEFT", 48, -11)
    headingRegion:SetText("EzWoW - Smart Fishing")
    headingRegion:SetTextColor(unpack(Theme.accent))

    local subtitleRegion = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleRegion:SetPoint("TOPLEFT", headingRegion, "BOTTOMLEFT", 0, -3)
    subtitleRegion:SetWidth(365)
    subtitleRegion:SetJustifyH("LEFT")
    subtitleRegion:SetTextColor(unpack(Theme.muted))
    subtitleRegion:SetText(L["낚싯대를 들고 있을 때 키 하나로 던지고, 찌가 물면 같은 키로 건져 올립니다."])

    local close = CreateFrame("Button", nil, top, BackdropTemplateMixin and "BackdropTemplate" or nil)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetFrameLevel(top:GetFrameLevel() + 3)
    if close.SetBackdrop then
        ns.UIKit:ApplyBackdrop(close, 1, 1)
        close:SetBackdropColor(unpack(Theme.bgSub))
        close:SetBackdropBorderColor(unpack(Theme.border))
    end
    local dismissTxt = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dismissTxt:SetPoint("CENTER", 0, 0)
    dismissTxt:SetText("X")
    dismissTxt:SetTextColor(unpack(Theme.muted))
    close:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.accent)) end
        dismissTxt:SetTextColor(unpack(Theme.text))
    end)
    close:SetScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(Theme.border)) end
        dismissTxt:SetTextColor(unpack(Theme.muted))
    end)
    close:SetScript("OnClick", function() windowFrame:Hide() end)

    local allChecks = {}
    local allSections = {}
    local allDynBtns = {}
    local steppers = {}
    local syncUI

    local CHECK_TOOLTIPS = {
        oneButton          = "낚싯대를 들고 있을 때 키 하나로 던지고, 찌가 물면 같은 키로 건져 올립니다.",
        autoLoot           = "낚은 물고기와 아이템을 전리품 창 없이 바로 가방에 넣습니다.",
        autoLure           = "낚싯대에 미끼가 없으면 원버튼을 눌렀을 때 가방에서 가장 좋은 미끼를 먼저 바릅니다.",
        setSoftInteract    = "게임의 상호작용 대상 설정을 켜서 찌를 자동으로 인식하게 합니다. 끄면 원버튼으로 건지기가 안 될 수 있어요.",
        expandInteract     = "찌가 멀리 떨어지거나 캐릭터 옆쪽에 있어도 인식되도록 상호작용 거리와 각도를 넓힙니다.\n그래도 인식이 안 되면 마우스를 찌에 올리고 키를 누르면 건져집니다.",
        combatSwap         = "낚싯대를 든 채로 전투가 시작되면 마지막에 들었던 무기로 바꿉니다.",
        reequipPole        = "전투 때문에 무기로 바꿨다면 전투가 끝난 뒤 낚싯대를 다시 듭니다.",
        showHUD            = "숙련도, 미끼 남은 시간, 이번 세션 기록을 보여주는 작은 창입니다.",
        showPins           = "세계지도에 내가 낚은 지점을 물고기 아이콘으로 표시합니다.",
        mapButton          = "세계지도에서 물고기별 낚시 지점을 고르는 버튼입니다. 버튼을 끌어서 원하는 곳으로 옮길 수 있어요.",
        mapButtonAutoAlign = "세계지도 버튼을 다른 지도 애드온 버튼들과 함께 왼쪽 아래에 세로로 자동 정렬합니다.",
        itemTooltip        = "물고기 툴팁에 잘 잡히는 지역, 물고기 떼 위치, 내가 낚은 수를 덧붙입니다.",
        minimapButton      = "미니맵 옆 버튼. 왼쪽 클릭: 가장 좋은 낚싯대 착용(들고 있으면 평소 무기로), 오른쪽 클릭: 설정",
        showLegend         = "지역 지도를 열면 그 지역에서 일반 낚시로 잡히는 물고기와 확률을 목록으로 보여줍니다.\n대륙 지도에서 물고기를 고르면 그 물고기가 잘 잡히는 지역 순위를 보여줘요.",
        showPools          = "물고기 떼가 나타나는 자리를 지도에 파란 테두리 핀으로 표시합니다.\n대륙 지도에서는 물고기를 골랐을 때만 표시돼요.",
        showExpected       = "세계지도에서 물고기를 고르면 그 물고기가 나오는 지역마다 확률을 표시합니다.",
        newFishAlert       = "도감에 없던 물고기를 처음 낚으면 소리와 채팅으로 알려줍니다.",
        shareCatches       = "같은 애드온을 쓰는 길드원·파티원에게 낚은 위치와 물고기를 보냅니다.",
        receiveShared      = "길드원·파티원이 보낸 낚시 위치를 받아서 저장합니다.",
        showShared         = "공유받은 낚시 지점을 금색 테두리 핀으로 표시합니다.",
    }

    local function createSectionDivider(y, resolveTextOr)
        local resolvedValue = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resolvedValue:SetPoint("TOPLEFT", 20, y)
        resolvedValue:SetTextColor(unpack(Theme.accent))
        local line = windowFrame:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.204, 0.298, 0.357, 0.85)
        line:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 20, y - 18)
        line:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -20, y - 18)
        line:SetHeight(1)
        allSections[#allSections + 1] = { fs = resolvedValue, labelSource = resolveTextOr }
        return resolvedValue
    end

    local function createStyledButton(x, y, w, h, resolveTextOr, isAccent, onClick)
        local buttonWidget = CreateFrame("Button", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        buttonWidget:SetSize(w, h)
        buttonWidget:SetPoint("TOPLEFT", x, y)
        if buttonWidget.SetBackdrop then
            ns.UIKit:ApplyBackdrop(buttonWidget, 1, 1)
        end
        local function applyNormalButtonLook()
            if not buttonWidget.SetBackdropColor then return end
            if isAccent then
                buttonWidget:SetBackdropColor(0.12, 0.22, 0.19, 0.96)
                buttonWidget:SetBackdropBorderColor(unpack(Theme.accent))
            else
                buttonWidget:SetBackdropColor(unpack(Theme.bgSub))
                buttonWidget:SetBackdropBorderColor(unpack(Theme.border))
            end
        end
        applyNormalButtonLook()
        local formatLocalizedLabel = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        formatLocalizedLabel:SetPoint("CENTER")
        formatLocalizedLabel:SetTextColor(unpack(isAccent and Theme.accent or Theme.text))
        if type(resolveTextOr) == "function" then
            formatLocalizedLabel:SetText(resolveTextOr())
            allDynBtns[#allDynBtns + 1] = { fs = formatLocalizedLabel, labelSource = resolveTextOr }
        elseif type(resolveTextOr) == "string" and resolveTextOr ~= "" and resolveTextOr ~= "-" and resolveTextOr ~= "+" then
            formatLocalizedLabel:SetText(L[resolveTextOr] or resolveTextOr)
            allDynBtns[#allDynBtns + 1] = { fs = formatLocalizedLabel, labelSource = resolveTextOr }
        else
            formatLocalizedLabel:SetText(resolveTextOr or "")
        end
        buttonWidget.label = formatLocalizedLabel
        buttonWidget:SetScript("OnEnter", function()
            if buttonWidget.SetBackdropColor then
                buttonWidget:SetBackdropColor(0.18, 0.27, 0.31, 1)
                buttonWidget:SetBackdropBorderColor(unpack(Theme.accent))
            end
        end)
        buttonWidget:SetScript("OnLeave", applyNormalButtonLook)
        buttonWidget:SetScript("OnMouseDown", function() formatLocalizedLabel:SetPoint("CENTER", 1, -1) end)
        buttonWidget:SetScript("OnMouseUp", function() formatLocalizedLabel:SetPoint("CENTER", 0, 0) end)
        buttonWidget:SetScript("OnClick", onClick)
        return buttonWidget
    end

    local function createStyledCheckbox(x, y, w, rawKey, key)
        local themeColor = CreateFrame("CheckButton", nil, windowFrame, "UICheckButtonTemplate")
        themeColor:SetSize(24, 24)
        themeColor:SetPoint("TOPLEFT", x, y)
        themeColor.key = key
        themeColor.rawKey = rawKey
        themeColor:SetScript("OnClick", function(self)
            ns.settings[key] = self:GetChecked() and true or false
            ns:PublishAddonEvent("AM_SETTINGS_CHANGED", key)
            syncUI()
        end)
        local displayText = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        displayText:SetPoint("LEFT", themeColor, "RIGHT", 4, 0)
        displayText:SetWidth(w or 180)
        displayText:SetJustifyH("LEFT")
        displayText:SetTextColor(unpack(Theme.text))
        displayText:SetText(L[rawKey] or rawKey)
        themeColor.labelFS = displayText
        themeColor:SetScript("OnEnter", function(self)
            local tipKey = CHECK_TOOLTIPS[key]
            if tipKey and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(displayText:GetText() or "", Theme.accent[1], Theme.accent[2], Theme.accent[3])
                GameTooltip:AddLine(L[tipKey] or tipKey, 0.85, 0.90, 0.94, true)
                GameTooltip:Show()
            end
        end)
        themeColor:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        allChecks[#allChecks + 1] = themeColor
        return themeColor
    end

    local function createValueStepper(x, y, rawLabelKey, key, minV, maxV, step, fmt)
        local lbl = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", x, y - 4)
        lbl:SetWidth(115)
        lbl:SetJustifyH("LEFT")
        lbl:SetTextColor(unpack(Theme.muted))
        lbl:SetText(L[rawLabelKey] or rawLabelKey)

        local minus = createStyledButton(x + 118, y, 22, 20, "-", false, function()
            local entryValue = math.max(minV, math.floor(((ns.settings[key] or 1) - step) / step + 0.5) * step)
            ns.settings[key] = entryValue
            ns:PublishAddonEvent("AM_SETTINGS_CHANGED", key)
            syncUI()
        end)
        local valFS = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valFS:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        valFS:SetWidth(42)
        valFS:SetJustifyH("CENTER")
        valFS:SetTextColor(unpack(Theme.text))

        local plus = createStyledButton(x + 184, y, 22, 20, "+", false, function()
            local entryValue = math.min(maxV, math.floor(((ns.settings[key] or 1) + step) / step + 0.5) * step)
            ns.settings[key] = entryValue
            ns:PublishAddonEvent("AM_SETTINGS_CHANGED", key)
            syncUI()
        end)
        steppers[#steppers + 1] = { key = key, lbl = lbl, rawLabelKey = rawLabelKey, valFS = valFS, fmt = fmt }
    end

    createSectionDivider(-70, "낚시")
    local langBtn = createStyledButton(250, -66, 190, 20, "", false, function(_, button)
        local order = ns.LANGUAGE_ORDER or { "auto", "koKR", "enUS" }
        local currentState = ns.settings.language or "auto"
        local entryIndex = 1
        for index, code in ipairs(order) do
            if code == currentState then entryIndex = index; break end
        end
        if button == "RightButton" then
            entryIndex = entryIndex - 1; if entryIndex < 1 then entryIndex = #order end
        else
            entryIndex = entryIndex + 1; if entryIndex > #order then entryIndex = 1 end
        end
        ns:SetLanguage(order[entryIndex])
        syncUI()
    end)
    langBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    createStyledCheckbox(18, -94, 180, "원버튼 낚시", "oneButton")
    createStyledCheckbox(232, -94, 180, "자동 획득", "autoLoot")
    createStyledCheckbox(18, -120, 180, "미끼 자동 사용", "autoLure")
    createStyledCheckbox(232, -120, 180, "찌 자동 인식", "setSoftInteract")
    createStyledCheckbox(18, -146, 180, "찌 인식 범위 넓히기", "expandInteract")

    local keyBtn = createStyledButton(236, -148, 204, 22, "", false, function(_, button)
        local klVal = SettingsDialog.resolveKeyList()
        local currentState = ns.settings.key or "SPACE"
        local entryIndex = 1
        for index, entryKey in ipairs(klVal) do
            if entryKey[1] == currentState then entryIndex = index; break end
        end
        if button == "RightButton" then
            entryIndex = entryIndex - 1; if entryIndex < 1 then entryIndex = #klVal end
        else
            entryIndex = entryIndex + 1; if entryIndex > #klVal then entryIndex = 1 end
        end
        ns.settings.key = klVal[entryIndex][1]
        ns:PublishAddonEvent("AM_SETTINGS_CHANGED", "key")
        syncUI()
    end)
    keyBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    createSectionDivider(-182, "장비")
    createStyledCheckbox(18, -206, 180, "전투가 시작되면 무기로 교체", "combatSwap")
    createStyledCheckbox(232, -206, 180, "전투가 끝나면 낚싯대 다시 들기", "reequipPole")

    createStyledButton(20, -236, 204, 24, function() return L["낚싯대 / 평소 무기"] .. " (" .. L["바꾸기"] .. ")" end, false, function()
        ns:EquipBestPole()
    end)
    createStyledButton(236, -236, 204, 24, function() return L["낚시 기록 창"] .. " (/ezsf)" end, false, function()
        ns:ToggleWindow("session")
    end)

    createSectionDivider(-272, "화면")
    createStyledCheckbox(18, -296, 180, "낚싯대를 들면 세션 창 표시", "showHUD")
    createStyledCheckbox(232, -296, 180, "지도에 낚시 지점 표시", "showPins")
    createStyledCheckbox(18, -322, 180, "세계지도에 물고기 선택 버튼 표시", "mapButton")
    createStyledCheckbox(232, -322, 180, "세계지도 버튼 좌하단 자동 정렬", "mapButtonAutoAlign")
    createStyledCheckbox(18, -348, 180, "아이템 툴팁에 잡히는 곳 표시", "itemTooltip")
    createStyledCheckbox(232, -348, 180, "미니맵 버튼 표시", "minimapButton")
    createStyledCheckbox(18, -374, 180, "세계지도에 일반 낚시 어종 목록 표시", "showLegend")
    createStyledCheckbox(232, -374, 180, "물고기 떼 출현 지점 표시", "showPools")
    createStyledCheckbox(18, -400, 180, "물고기가 나오는 지역과 확률 표시", "showExpected")
    createStyledCheckbox(232, -400, 180, "처음 낚은 물고기 알림", "newFishAlert")

    createValueStepper(20, -432, "세션 창 크기", "hudScale", 0.7, 1.5, 0.05, function(entryValue) return string.format("%d%%", entryValue * 100 + 0.5) end)
    createValueStepper(234, -432, "지도 핀 크기", "pinScale", 0.6, 1.6, 0.05, function(entryValue) return string.format("%d%%", entryValue * 100 + 0.5) end)

    createSectionDivider(-466, function() return L["공유"] .. " · " .. L["기록"] end)
    createStyledCheckbox(18, -490, 180, "낚은 위치를 길드·파티에 공유", "shareCatches")
    createStyledCheckbox(232, -490, 180, "다른 플레이어의 공유 받기", "receiveShared")
    createStyledCheckbox(18, -516, 180, "공유받은 위치 지도에 표시", "showShared")

    createStyledButton(236, -518, 204, 22, function() return L["내 낚시 기록 전체"] .. " " .. L["보내기"] end, false, function()
        ns:SendAllRecords()
    end)

    createStyledButton(20, -548, 134, 22, function() return L["현재 지역 낚시 지점"] .. " " .. L["지우기"] end, false, function()
        StaticPopup_Show("EZWOWSMARTFISHING_RESET_ZONE")
    end)
    createStyledButton(163, -548, 134, 22, function() return L["공유받은 기록"] .. " " .. L["지우기"] end, false, function()
        StaticPopup_Show("EZWOWSMARTFISHING_RESET_SHARED")
    end)
    createStyledButton(306, -548, 134, 22, function() return L["모든 낚시 기록"] .. " " .. L["전부 지우기"] end, false, function()
        StaticPopup_Show("EZWOWSMARTFISHING_RESET_ALL")
    end)

    createStyledButton(20, -586, 204, 28, function() return L["세계지도 버튼 위치"] .. " · " .. L["아이콘"] .. " " .. L["처음 위치로"] end, false, function()
        ns:ResetMapButton()
        if syncUI then syncUI() end
    end)
    createStyledButton(236, -586, 204, 28, "후원하기", true, function()
        ns:ShowDonate()
    end)

    local hint = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 10)
    hint:SetTextColor(unpack(Theme.muted))
    hint:SetText(L["/ezsf key 로 변경"])

    local footerRegion = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerRegion:SetPoint("BOTTOMRIGHT", -20, 10)
    footerRegion:SetText("EzWoW - Smart Fishing · /ezsf")
    footerRegion:SetTextColor(unpack(Theme.muted))

    syncUI = function()
        subtitleRegion:SetText(L["낚싯대를 들고 있을 때 키 하나로 던지고, 찌가 물면 같은 키로 건져 올립니다."])
        hint:SetText(L["/ezsf key 로 변경"])
        for _, sec in ipairs(allSections) do
            if type(sec.labelSource) == "function" then
                sec.fs:SetText(sec.labelSource())
            else
                sec.fs:SetText(L[sec.labelSource] or sec.labelSource)
            end
        end
        for _, db in ipairs(allDynBtns) do
            if type(db.labelSource) == "function" then
                db.fs:SetText(db.labelSource())
            else
                db.fs:SetText(L[db.labelSource] or db.labelSource)
            end
        end
        for _, themeColor in ipairs(allChecks) do
            if themeColor.rawKey then
                themeColor.labelFS:SetText(L[themeColor.rawKey] or themeColor.rawKey)
            end
            themeColor:SetChecked(ns.settings[themeColor.key] and true or false)
        end
        for _, stateEntry in ipairs(steppers) do
            if stateEntry.rawLabelKey and stateEntry.lbl then
                stateEntry.lbl:SetText(L[stateEntry.rawLabelKey] or stateEntry.rawLabelKey)
            end
            stateEntry.valFS:SetText(stateEntry.fmt(ns.settings[stateEntry.key] or 1))
        end
        local lang = ns.settings.language or "auto"
        local langText = lang == "auto" and L["자동 (게임 언어)"] or (ns.LANGUAGE_NAMES and ns.LANGUAGE_NAMES[lang]) or lang
        langBtn.label:SetText(L["언어"] .. ": " .. langText .. " ▼")

        local lookupKey = ns.settings.key or "SPACE"
        local keyText = lookupKey
        for _, entryKey in ipairs(SettingsDialog.resolveKeyList()) do
            if entryKey[1] == lookupKey then keyText = entryKey[2]; break end
        end
        keyBtn.label:SetText(L["원버튼 키"] .. ": " .. keyText .. " ▼")
    end

    windowFrame.RefreshUI = syncUI
    windowFrame:SetScript("OnShow", syncUI)
    syncUI()
    windowFrame:Hide()
    configFrame = windowFrame
    return windowFrame
end

function SettingsDialog.constructMainFrame()
    SettingsDialog.definePopups()
    if BlizzardOptionsCanvas then return end
    local panelFrameEntry = CreateFrame("Frame", "EzWoW_SmartFishingOptionsPanel", UIParent)
    panelFrameEntry.name = "EzWoW - Smart Fishing"
    BlizzardOptionsCanvas = panelFrameEntry

    local iconTex = panelFrameEntry:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(32, 32)
    iconTex:SetPoint("TOPLEFT", 18, -18)
    iconTex:SetTexture(StyleService and StyleService.ICON or "Interface\\AddOns\\EzWoW-SmartFishing\\Media\\icon")

    local headingRegion = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    headingRegion:SetPoint("LEFT", iconTex, "RIGHT", 10, 0)
    headingRegion:SetText("EzWoW - Smart Fishing")
    headingRegion:SetTextColor(unpack(Theme.accent))

    local desc = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", iconTex, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetText(L["낚싯대를 들고 있을 때 키 하나로 던지고, 찌가 물면 같은 키로 건져 올립니다."])

    local launchBtn = CreateFrame("Button", nil, panelFrameEntry, BackdropTemplateMixin and "BackdropTemplate" or nil)
    launchBtn:SetSize(220, 28)
    launchBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    if launchBtn.SetBackdrop then
        ns.UIKit:ApplyBackdrop(launchBtn, 1, 1)
        launchBtn:SetBackdropColor(Theme.accent[1] * 0.22, Theme.accent[2] * 0.22, Theme.accent[3] * 0.22, 0.96)
        launchBtn:SetBackdropBorderColor(unpack(Theme.accent))
    end
    local launchLabel = launchBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    launchLabel:SetPoint("CENTER")
    launchLabel:SetTextColor(unpack(Theme.accent))
    launchLabel:SetText((L["설정"] or "설정") .. " (/ezsf)")
    function launchBtn:SetText(displayText) launchLabel:SetText(displayText or "") end
    launchBtn:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(unpack(Theme.bgHover))
            self:SetBackdropBorderColor(unpack(Theme.accent))
        end
    end)
    launchBtn:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(Theme.accent[1] * 0.22, Theme.accent[2] * 0.22, Theme.accent[3] * 0.22, 0.96)
            self:SetBackdropBorderColor(unpack(Theme.accent))
        end
    end)
    launchBtn:SetScript("OnMouseDown", function() launchLabel:SetPoint("CENTER", 1, -1) end)
    launchBtn:SetScript("OnMouseUp", function() launchLabel:SetPoint("CENTER", 0, 0) end)
    launchBtn:SetScript("OnClick", function()
        ns:OpenSettings()
    end)

    local hint = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", launchBtn, "BOTTOMLEFT", 0, -14)
    hint:SetTextColor(unpack(Theme.muted))

    function panelFrameEntry:RefreshTexts()
        local hasKo = (L["설정"] == "설정")
        desc:SetText(L["낚싯대를 들고 있을 때 키 하나로 던지고, 찌가 물면 같은 키로 건져 올립니다."])
        launchBtn:SetText((L["설정"] or "설정") .. " (/ezsf)")
        hint:SetText(hasKo and "채팅창에 /ezsf 또는 /ezsf config를 입력해도 열립니다." or "Type /ezsf or /ezsf config in chat to open settings.")
    end
    panelFrameEntry:SetScript("OnShow", function(self) self:RefreshTexts() end)
    panelFrameEntry:RefreshTexts()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local isCallOk, categoryKey = pcall(Settings.RegisterCanvasLayoutCategory, panelFrameEntry, panelFrameEntry.name)
        if isCallOk and categoryKey then pcall(Settings.RegisterAddOnCategory, categoryKey) end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panelFrameEntry)
    end
end

function ns:OpenSettings()
    local windowFrame = SettingsDialog.buildConfigWindow()
    windowFrame:SetShown(not windowFrame:IsShown())
    if windowFrame:IsShown() then windowFrame:Raise() end
end

ns:SubscribeAddonEvent("AM_DB_READY", function()
    pcall(SettingsDialog.constructMainFrame)
end)

ns:SubscribeAddonEvent("AM_NEW_FISH", function(itemID)
    if not ns.settings.newFishAlert then return end
    ns:Print(L["새 물고기 발견! "] .. ns:ItemName(itemID))
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end)

function ns:SetLanguage(code)
    ns.settings.language = code
    if ns.ApplyLanguage then
        ns:ApplyLanguage(code)
    end
    SettingsDialog.definePopups()
    if configFrame and configFrame.RefreshUI then
        configFrame.RefreshUI()
    end
    if BlizzardOptionsCanvas and BlizzardOptionsCanvas.RefreshTexts then
        BlizzardOptionsCanvas:RefreshTexts()
    end
    if ns.UpdateMapLegend then
        ns:UpdateMapLegend()
    end
    if ns.RefreshDonateLocale then
        ns:RefreshDonateLocale()
    end
    if _G.EzWoW_SmartFishingHUD and _G.EzWoW_SmartFishingHUD.Update and _G.EzWoW_SmartFishingHUD:IsShown() then
        _G.EzWoW_SmartFishingHUD:Update()
    end
    if _G.EzWoW_SmartFishingWindow and _G.EzWoW_SmartFishingWindow.Refresh and _G.EzWoW_SmartFishingWindow:IsShown() then
        _G.EzWoW_SmartFishingWindow:Refresh()
    end
    ns:PublishAddonEvent("AM_DATA_CHANGED")
    ns:Print(L["애드온 언어: %s"]:format(code == "auto" and L["자동 (게임 언어)"] or ns.LANGUAGE_NAMES[code]))
end

ns:SubscribeAddonEvent("AM_SETTINGS_CHANGED", function(key)
    if key == "language" then ns:SetLanguage(ns.settings.language) end
end)
