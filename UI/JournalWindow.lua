--===========================================================================
-- EzWoW - Smart Fishing
-- UI/JournalWindow.lua : 4-Tab Fishing Session, Recent Catches, Encyclopedia & Zone Window
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local FishingJournalWindow = ns.FishingJournalWindow or {}
ns.FishingJournalWindow = FishingJournalWindow
local L = ns.L
local StyleService = ns.Style

local frameWidth, frameHeight = 320, 520
local PAD = 14
function FishingJournalWindow.buildJournalTabButtons() return {
    { key = "session", label = L["세션"] },
    { key = "recent",  label = L["기록"] },
    { key = "journal", label = L["도감"] },
    { key = "zone",    label = L["지역"] },
} end

local windowFrame

function FishingJournalWindow.formatElapsedSecondsAgo(t)
    local dataEntry = time() - t
    if dataEntry < 60 then return L["방금"] end
    if dataEntry < 3600 then return L["%d분 전"]:format(math.floor(dataEntry / 60)) end
    if dataEntry < 86400 then return L["%d시간 전"]:format(math.floor(dataEntry / 3600)) end
    return date("%m/%d", t)
end

function FishingJournalWindow.formatPercentageString(a, b)
    if not b or b == 0 then return "-" end
    return string.format("%.0f%%", a / b * 100)
end

function FishingJournalWindow.assembleSession(page)
    local labels = { L["시간"], L["던짐"], L["낚음"], L["놓침"], L["성공률"], L["시간당"] }
    local gap = 6
    local boxWidth = (frameWidth - PAD * 2 - gap * 2) / 3
    page.stats = {}
    for index, formatLocalizedLabel in ipairs(labels) do
        local tile = StyleService:Stat(page, formatLocalizedLabel)
        tile:SetSize(boxWidth, 50)
        local columnIndex, rowWidget = (index - 1) % 3, math.floor((index - 1) / 3)
        tile:SetPoint("TOPLEFT", columnIndex * (boxWidth + gap), -rowWidget * (50 + gap))
        page.stats[index] = tile
    end

    page.skill = StyleService:Text(page, 11, StyleService.muted)
    page.skill:SetPoint("TOPLEFT", 0, -120)
    page.lure = StyleService:Text(page, 11, StyleService.muted)
    page.lure:SetPoint("TOPRIGHT", 0, -120)
    page.lure:SetJustifyH("RIGHT")

    local line = StyleService:Line(page)
    line:SetPoint("TOPLEFT", -PAD, -142)
    line:SetPoint("TOPRIGHT", PAD, -142)

    page.head = StyleService:Text(page, 12)
    page.head:SetPoint("TOPLEFT", 0, -154)
    page.head:SetText(L["이번 세션에 잡은 것"])

    page.reset = StyleService:Button(page, L["새 세션"], function() ns:ResetSession() end)
    page.reset:SetPoint("TOPRIGHT", 0, -149)
    page.reset:SetHeight(22)

    page.list = StyleService:List(page)
    page.list:SetPoint("TOPLEFT", -6, -182)
    page.list:SetPoint("BOTTOMRIGHT", 6, 0)
    page.list:SetEmptyText(L["낚싯대를 들고 낚시를 시작하면\n이번 세션 기록이 여기에 쌓여요."])

    function page:Tick()
        local stateFlag = ns:Session()
        local casts, catches, missed = stateFlag and stateFlag.casts or 0, stateFlag and stateFlag.catches or 0, stateFlag and stateFlag.missed or 0
        local dur = stateFlag and (math.max(stateFlag.last, time()) - stateFlag.start) or 0
        if stateFlag and time() - stateFlag.last > 60 then dur = stateFlag.last - stateFlag.start end 
        local perHour = dur > 60 and (catches / dur * 3600) or 0
        local entryValue = {
            ns:FormatDuration(dur), casts, catches, missed,
            FishingJournalWindow.formatPercentageString(catches, casts), dur > 60 and string.format("%.0f", perHour) or "-",
        }
        for index, tile in ipairs(self.stats) do tile.value:SetText(entryValue[index]) end

        local rank, maxRank, mod = ns:FishingSkill()
        if rank then
            local bonus = (mod and mod > 0) and ("  |cff45c7e0+" .. mod .. "|r") or ""
            self.skill:SetText(string.format(L["낚시 숙련 |cffeeeff2%d / %d|r%s"], rank, maxRank, bonus))
        else
            self.skill:SetText("")
        end
        local lure = ns:LureRemaining()
        if lure then
            self.lure:SetText(L["미끼 %s"]:format("|cff45c7e0" .. ns:FormatDuration(lure) .. "|r"))
        else
            self.lure:SetText(ns:HasPole() and L["미끼 없음"] or "")
        end
    end

    function page:Refresh()
        self:Tick()
        local stateFlag = ns:Session()
        local payloadData = {}
        if stateFlag then
            local itemList = ns:GetSortedFishBreakdown(stateFlag.fish)
            local grandTotal = 0
            for _, recordEntry in ipairs(itemList) do grandTotal = grandTotal + recordEntry.count end
            for _, recordEntry in ipairs(itemList) do
                payloadData[#payloadData + 1] = {
                    itemID = recordEntry.id, icon = ns:ItemIcon(recordEntry.id), title = ns:ItemName(recordEntry.id),
                    bar = recordEntry.count / itemList[1].count,
                    right = FishingJournalWindow.formatPercentageString(recordEntry.count, grandTotal), right2 = L["%d마리"]:format(recordEntry.count),
                }
            end
        end
        self.list:SetData(payloadData)
    end
end

function FishingJournalWindow.assembleRecent(page)
    page.head = StyleService:Text(page, 12)
    page.head:SetPoint("TOPLEFT", 0, -2)
    page.head:SetText(L["최근에 낚은 기록"])
    page.info = StyleService:Text(page, 10, StyleService.muted)
    page.info:SetPoint("TOPRIGHT", 0, -4)
    page.info:SetJustifyH("RIGHT")

    page.list = StyleService:List(page)
    page.list:SetPoint("TOPLEFT", -6, -26)
    page.list:SetPoint("BOTTOMRIGHT", 6, 0)
    page.list:SetEmptyText(L["아직 기록이 없어요.\n물고기를 낚으면 시간과 위치가 남아요."])

    local function handleWidgetMouseClick(dataEntry)
        if dataEntry.mapID and dataEntry.mapID ~= 0 then ns:ShowFishOnMap(dataEntry.itemID, dataEntry.mapID) end
    end

    function page:Refresh()
        local payloadData = {}
        for _, rowEntry in ipairs(ns.db.recent) do
            local place = ns:MapName(rowEntry.m)
            if rowEntry.sub then place = place .. " · " .. rowEntry.sub end
            payloadData[#payloadData + 1] = {
                itemID = rowEntry.id, mapID = rowEntry.m, icon = ns:ItemIcon(rowEntry.id),
                title = ns:ItemName(rowEntry.id) .. ((rowEntry.q or 1) > 1 and ("  |cff8c94a3x" .. rowEntry.q .. "|r") or ""),
                sub = place,
                right = FishingJournalWindow.formatElapsedSecondsAgo(rowEntry.t),
                right2 = (rowEntry.m ~= 0) and string.format("%.0f, %.0f", rowEntry.x * 100, rowEntry.y * 100) or "",
                hint = (rowEntry.m ~= 0) and L["클릭: 지도에서 이 물고기 지점 보기"] or nil,
                onClick = handleWidgetMouseClick,
            }
        end
        self.info:SetText(#payloadData > 0 and L["%d개"]:format(#payloadData) or "")
        self.list:SetData(payloadData)
    end
end

function FishingJournalWindow.assembleJournal(page)
    page.head = StyleService:Text(page, 12)
    page.head:SetPoint("TOPLEFT", 0, -2)
    page.head:SetText(L["내 낚시 도감"])
    page.info = StyleService:Text(page, 10, StyleService.muted)
    page.info:SetPoint("TOPRIGHT", 0, -4)
    page.info:SetJustifyH("RIGHT")

    page.totals = StyleService:Text(page, 10, StyleService.muted)
    page.totals:SetPoint("TOPLEFT", 0, -22)

    page.list = StyleService:List(page)
    page.list:SetPoint("TOPLEFT", -6, -42)
    page.list:SetPoint("BOTTOMRIGHT", 6, 0)
    page.list:SetEmptyText(L["처음 낚은 물고기부터 도감에 등록돼요."])

    local function handleWidgetMouseClick(dataEntry)
        ns:ShowFishOnMap(dataEntry.itemID, dataEntry.mapID ~= 0 and dataEntry.mapID or nil)
    end

    function page:Refresh()
        local payloadData, kinds = {}, 0
        local itemList = {}
        for entityID, subIndex in pairs(ns.db.journal) do itemList[#itemList + 1] = { id = entityID, j = subIndex } end
        table.sort(itemList, function(a, b) return a.j.n > b.j.n end)
        for _, recordEntry in ipairs(itemList) do
            kinds = kinds + 1
            payloadData[#payloadData + 1] = {
                itemID = recordEntry.id, mapID = recordEntry.j.lastMap, icon = ns:ItemIcon(recordEntry.id),
                title = ns:ItemName(recordEntry.id),
                sub = L["처음: %s · %s"]:format(ns:MapName(recordEntry.j.firstMap), date("%m/%d", recordEntry.j.first)),
                right = tostring(recordEntry.j.n), right2 = L["마리"],
                hint = L["클릭: 지도에서 이 물고기 지점 보기"],
                onClick = handleWidgetMouseClick,
            }
        end
        local t = ns.db.totals
        self.info:SetText(L["%d종"]:format(kinds))
        self.totals:SetText(string.format(L["총 %d마리 · 던짐 %d · 성공률 %s"], t.catches, t.casts, FishingJournalWindow.formatPercentageString(t.catches, t.casts)))
        self.list:SetData(payloadData)
    end
end

function FishingJournalWindow.assembleZone(page)
    page.head = StyleService:Text(page, 12)
    page.head:SetPoint("TOPLEFT", 0, -2)
    page.info = StyleService:Text(page, 10, StyleService.muted)
    page.info:SetPoint("TOPRIGHT", 0, -4)
    page.info:SetJustifyH("RIGHT")

    page.list = StyleService:List(page)
    page.list:SetPoint("TOPLEFT", -6, -26)
    page.list:SetPoint("BOTTOMRIGHT", 6, 34)
    page.list:SetEmptyText(L["이 지역은 낚시 정보가 없어요.\n낚시를 하면 기록이 쌓여요."])

    page.hint = StyleService:Text(page, 10, StyleService.muted)
    page.hint:SetPoint("BOTTOMLEFT", 0, 6)
    page.hint:SetText(L["확률은 기본 데이터 예상치예요"])

    page.map = StyleService:Button(page, L["지도 열기"], function()
        ns:ShowFishOnMap(ns.settings.filterFish, page.mapID)
    end)
    page.map:SetPoint("BOTTOMRIGHT", 0, 0)

    local function handleWidgetMouseClick(dataEntry)
        if ns.settings.filterFish == dataEntry.itemID then
            ns:SetFishFilter(nil)
        else
            ns:ShowFishOnMap(dataEntry.itemID, page.mapID)
        end
    end

    function page:Refresh()
        local mapID = C_Map.GetBestMapForUnit("player")
        self.mapID = mapID
        local expected, skill, sub = ns:ExpectedHere(mapID)
        self.head:SetText(ns:MapName(mapID) .. (sub and ("  |cff8c94a3" .. sub .. "|r") or ""))

        local own, grandTotal, spots = ns:FishOnMap(mapID)
        local apiInfo = {}
        if skill then
            local rank, _, mod = ns:FishingSkill()
            local mine = rank and (rank + (mod or 0))
            local colorRGB = (mine and mine < skill) and "|cffd9a066" or "|cff45c7e0"
            apiInfo[#apiInfo + 1] = L["권장 숙련 %s"]:format(colorRGB .. skill .. "|r")
        end
        if grandTotal > 0 then apiInfo[#apiInfo + 1] = string.format(L["내 기록 %d마리"], grandTotal) end
        self.info:SetText(table.concat(apiInfo, " · "))

        local itemList, visitedMap = {}, {}
        for entityID, anchorTarget in pairs(expected or {}) do
            visitedMap[entityID] = true
            itemList[#itemList + 1] = { id = entityID, pct = anchorTarget, count = own[entityID] or 0 }
        end
        for entityID, themeColor in pairs(own) do
            if not visitedMap[entityID] then itemList[#itemList + 1] = { id = entityID, count = themeColor } end
        end
        table.sort(itemList, function(a, b)
            local paVal, pbVal = a.pct or -1, b.pct or -1
            if paVal ~= pbVal then return paVal > pbVal end
            return a.count > b.count
        end)
        local top = 0
        for _, recordEntry in ipairs(itemList) do top = math.max(top, recordEntry.pct or 0) end

        local payloadData = {}
        for _, recordEntry in ipairs(itemList) do
            payloadData[#payloadData + 1] = {
                itemID = recordEntry.id, icon = ns:ItemIcon(recordEntry.id), title = ns:ItemName(recordEntry.id),
                bar = recordEntry.pct and top > 0 and (recordEntry.pct / top) or 0,
                right = recordEntry.pct and string.format("%.1f%%", recordEntry.pct) or "-",
                right2 = recordEntry.count > 0 and L["내 기록 %d"]:format(recordEntry.count) or "",
                selected = ns.settings.filterFish == recordEntry.id,
                hint = L["클릭: 지도에 이 물고기 위치 표시"],
                onClick = handleWidgetMouseClick,
            }
        end
        self.list:SetData(payloadData)
    end
end

local BUILDERS = {
    session = FishingJournalWindow.assembleSession, recent = FishingJournalWindow.assembleRecent, journal = FishingJournalWindow.assembleJournal,
    zone = FishingJournalWindow.assembleZone,
}

function FishingJournalWindow.buildWindow()
    local windowFrameEntry = CreateFrame("Frame", "EzWoW_SmartFishingWindow", UIParent, "BackdropTemplate")
    StyleService:Panel(windowFrameEntry)
    windowFrameEntry:SetSize(frameWidth, frameHeight)
    windowFrameEntry:SetPoint("CENTER")
    windowFrameEntry:SetFrameStrata("MEDIUM")
    windowFrameEntry:SetClampedToScreen(true)
    windowFrameEntry:SetMovable(true)
    windowFrameEntry:EnableMouse(true)
    windowFrameEntry:RegisterForDrag("LeftButton")
    windowFrameEntry:SetScript("OnDragStart", windowFrameEntry.StartMoving)
    windowFrameEntry:SetScript("OnDragStop", windowFrameEntry.StopMovingOrSizing)
    tinsert(UISpecialFrames, "EzWoW_SmartFishingWindow") 

    windowFrameEntry.logo = windowFrameEntry:CreateTexture(nil, "ARTWORK")
    windowFrameEntry.logo:SetSize(26, 26)
    windowFrameEntry.logo:SetPoint("TOPLEFT", PAD, -PAD)
    windowFrameEntry.logo:SetTexture(StyleService.ICON)
    StyleService:Round(windowFrameEntry, windowFrameEntry.logo)

    windowFrameEntry.title = StyleService:Text(windowFrameEntry, 14)
    windowFrameEntry.title:SetPoint("TOPLEFT", windowFrameEntry.logo, "TOPRIGHT", 10, -1)
    windowFrameEntry.title:SetText(ns.name)

    windowFrameEntry.zone = StyleService:Text(windowFrameEntry, 11, StyleService.muted)
    windowFrameEntry.zone:SetPoint("TOPLEFT", windowFrameEntry.title, "BOTTOMLEFT", 0, -3)

    local close = CreateFrame("Button", nil, windowFrameEntry)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.t = StyleService:Text(close, 16, StyleService.muted)
    close.t:SetPoint("CENTER")
    close.t:SetText("×")
    close:SetScript("OnEnter", function(self) self.t:SetTextColor(unpack(StyleService.text)) end)
    close:SetScript("OnLeave", function(self) self.t:SetTextColor(unpack(StyleService.muted)) end)
    close:SetScript("OnClick", function() windowFrameEntry:Hide() end)

    local cfgBtn = StyleService:Button(windowFrameEntry, L["설정"], function() ns:OpenSettings() end)
    cfgBtn:SetHeight(22)
    cfgBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
    windowFrameEntry.cfgBtn = cfgBtn
    windowFrameEntry.title:SetPoint("RIGHT", cfgBtn, "LEFT", -8, 0)
    windowFrameEntry.title:SetJustifyH("LEFT")
    if windowFrameEntry.title.SetWordWrap then windowFrameEntry.title:SetWordWrap(false) end
    windowFrameEntry.zone:SetPoint("RIGHT", cfgBtn, "LEFT", -8, 0)
    windowFrameEntry.zone:SetJustifyH("LEFT")
    if windowFrameEntry.zone.SetWordWrap then windowFrameEntry.zone:SetWordWrap(false) end
    cfgBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("EzWoW - Smart Fishing", unpack(StyleService.accent))
        GameTooltip:AddLine(L["왼쪽 클릭"] .. ": " .. L["설정"] .. " (/ezsf config)", 0.929, 0.957, 0.969)
        GameTooltip:Show()
    end)
    cfgBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local tabButtons2 = FishingJournalWindow.buildJournalTabButtons()
    local tabW = (frameWidth - PAD * 2) / #tabButtons2
    windowFrameEntry.tabs, windowFrameEntry.pages = {}, {}
    for index, t in ipairs(tabButtons2) do
        local b = CreateFrame("Button", nil, windowFrameEntry)
        b:SetSize(tabW, 30)
        b:SetPoint("TOPLEFT", PAD + (index - 1) * tabW, -52)
        b.t = StyleService:Text(b, 12, StyleService.muted)
        b.t:SetPoint("CENTER")
        b.t:SetJustifyH("CENTER")
        b.t:SetText(t.label)
        b.bar = b:CreateTexture(nil, "OVERLAY")
        b.bar:SetHeight(2)
        b.bar:SetPoint("BOTTOMLEFT", 8, 0)
        b.bar:SetPoint("BOTTOMRIGHT", -8, 0)
        b.bar:SetColorTexture(unpack(StyleService.accent))
        b:SetScript("OnEnter", function(self) if windowFrameEntry.current ~= t.key then self.t:SetTextColor(unpack(StyleService.text)) end end)
        b:SetScript("OnLeave", function(self) if windowFrameEntry.current ~= t.key then self.t:SetTextColor(unpack(StyleService.muted)) end end)
        b:SetScript("OnClick", function() windowFrameEntry:SelectTab(t.key) end)
        b.key = t.key
        windowFrameEntry.tabs[index] = b

        local page = CreateFrame("Frame", nil, windowFrameEntry)
        page:SetPoint("TOPLEFT", PAD, -96)
        page:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        page:Hide()
        BUILDERS[t.key](page)
        windowFrameEntry.pages[t.key] = page
    end
    local tabLine = StyleService:Line(windowFrameEntry)
    tabLine:SetPoint("TOPLEFT", 0, -82)
    tabLine:SetPoint("TOPRIGHT", 0, -82)

    function windowFrameEntry:SelectTab(key)
        if not self.pages[key] then key = "session" end
        self.current = key
        ns.settings.tab = key
        local tabs = FishingJournalWindow.buildJournalTabButtons()
        for entryIndex, b in ipairs(self.tabs) do
            if tabs[entryIndex] then b.t:SetText(tabs[entryIndex].label) end
            local onVal = b.key == key
            b.t:SetTextColor(unpack(onVal and StyleService.text or StyleService.muted))
            b.bar:SetShown(onVal)
        end
        for entryKey, page in pairs(self.pages) do page:SetShown(entryKey == key) end
        self:Refresh()
    end

    function windowFrameEntry:Refresh()
        if self.cfgBtn and self.cfgBtn.t then
            self.cfgBtn.t:SetText(L["설정"])
            self.cfgBtn:SetWidth(self.cfgBtn.t:GetStringWidth() + 20)
        end
        local tabs = FishingJournalWindow.buildJournalTabButtons()
        for entryIndex, b in ipairs(self.tabs) do
            if tabs[entryIndex] then b.t:SetText(tabs[entryIndex].label) end
        end
        local mapID = C_Map.GetBestMapForUnit("player")
        self.zone:SetText(ns:MapName(mapID))
        local page = self.pages[self.current]
        if page and page.Refresh then page:Refresh() end
    end

    local elapsed = 0
    windowFrameEntry:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        if self.current == "session" then self.pages.session:Tick() end
    end)

    windowFrameEntry:SetScript("OnShow", function(self) self:SelectTab(self.current or ns.settings.tab or "session") end)
    windowFrameEntry:Hide()
    return windowFrameEntry
end

function ns:ToggleWindow(tab)
    if tab == "options" then
        ns:OpenSettings()
        return
    end
    windowFrame = windowFrame or FishingJournalWindow.buildWindow()
    if tab then
        
        if windowFrame:IsShown() and windowFrame.current == tab then
            windowFrame:Hide()
            return
        end
        windowFrame:Show()
        windowFrame:SelectTab(tab)
        return
    end
    windowFrame:SetShown(not windowFrame:IsShown())
end

local pending = false
function FishingJournalWindow.syncIfShown()
    if not windowFrame or not windowFrame:IsShown() or pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if windowFrame:IsShown() then windowFrame:Refresh() end
    end)
end
ns:SubscribeAddonEvent("AM_DATA_CHANGED", FishingJournalWindow.syncIfShown)
ns:SubscribeAddonEvent("AM_SETTINGS_CHANGED", FishingJournalWindow.syncIfShown)
ns:SubscribeAddonEvent("ZONE_CHANGED_NEW_AREA", FishingJournalWindow.syncIfShown)
ns:SubscribeAddonEvent("ZONE_CHANGED", FishingJournalWindow.syncIfShown)
ns:SubscribeAddonEvent("GET_ITEM_INFO_RECEIVED", FishingJournalWindow.syncIfShown)
ns:SubscribeAddonEvent("PLAYER_EQUIPMENT_CHANGED", FishingJournalWindow.syncIfShown)
