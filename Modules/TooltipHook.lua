--===========================================================================
-- EzWoW - Smart Fishing
-- Modules/TooltipHook.lua : Fish Item Tooltip Catch Count & Top Zone Hook
--===========================================================================
local _, ns = ...

-- The "EzWoW - ..." name line at the end of tooltip additions is drawn small.
-- Shared by the EzWoW addons: the first one loaded sets it up.
if not (_G.EzWoWTooltipTagSizer and (tonumber(_G.EzWoWTooltipTagSizer.version) or 0) >= 4) then
    local sizer = {}
    sizer.version = 4
    _G.EzWoWTooltipTagSizer = sizer
    local smallFont
    local original = setmetatable({}, { __mode = "k" })   -- font string -> its own font object
    local function tagFont()
        if not smallFont and CreateFont then
            smallFont = _G.EzWoWTooltipTagFont or CreateFont("EzWoWTooltipTagFont")
            smallFont:CopyFontObject(GameTooltipTextSmall or GameTooltipText)
            local path, _, flags = smallFont:GetFont()
            if path then smallFont:SetFont(path, 8, flags) end
        end
        return smallFont
    end
    local function isTag(text)
        if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return false end
        return text:find("^EzWoW %- ") ~= nil
    end
    -- the size goes on the line itself too: a size another addon put on the
    -- line (a font addon) would stay over the font object otherwise
    local function setSize(fs, font)
        if not (font and font.GetFont and fs.SetFont) then return end
        local path, size, flags = font:GetFont()
        if path and size then fs:SetFont(path, size, flags or "") end
    end
    local function fit(fs, tag)
        if not fs then return end
        if tag then
            if not original[fs] then original[fs] = fs:GetFontObject() or GameTooltipText end
            if tagFont() then
                fs:SetFontObject(smallFont)
                setSize(fs, smallFont)
            end
            fs:SetTextColor(0.5, 0.5, 0.5)
        elseif original[fs] then
            fs:SetFontObject(original[fs])
            setSize(fs, original[fs])
            original[fs] = nil
        end
    end
    function sizer.Refit(tip)
        local name = tip and tip.GetName and tip:GetName()
        if type(name) ~= "string" then return end
        local ok, count = pcall(tip.NumLines, tip)
        if not ok or type(count) ~= "number" or (issecretvalue and issecretvalue(count)) then return end
        for i = 1, count do
            local right = _G[name .. "TextRight" .. i]
            if right then fit(right, isTag(right:GetText())) end
            -- line 1 is the tooltip's title: a left "EzWoW - ..." there stays big
            local left = _G[name .. "TextLeft" .. i]
            if left then fit(left, i > 1 and isTag(left:GetText())) end
        end
    end
    local function restore(tip)
        local name = tip and tip.GetName and tip:GetName()
        if type(name) ~= "string" then return end
        local rightPrefix, leftPrefix = name .. "TextRight", name .. "TextLeft"
        for fs, font in pairs(original) do
            local fsName = fs.GetName and fs:GetName()
            if type(fsName) == "string" and (fsName:find(rightPrefix, 1, true) == 1 or fsName:find(leftPrefix, 1, true) == 1) then
                fs:SetFontObject(font)
                setSize(fs, font)
                original[fs] = nil
            end
        end
    end
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if tip then
            pcall(hooksecurefunc, tip, "Show", function(self) pcall(sizer.Refit, self) end)
            pcall(tip.HookScript, tip, "OnTooltipCleared", function(self) pcall(restore, self) end)
        end
    end
end
local ipairs, min, format, tconcat = ipairs, math.min, string.format, table.concat

local TooltipCatchAdvisor = ns.TooltipCatchAdvisor or {}
ns.TooltipCatchAdvisor = TooltipCatchAdvisor

local L = ns.L
local MAX_DISPLAYED_ZONES = 3

-- Attribution line under this addon's block: once per tooltip display, only when lines were added.
local TAG_TITLE = ns.name or "EzWoW - Smart Fishing"
local taggedTooltips = setmetatable({}, { __mode = "k" })
local tagClearHooked = setmetatable({}, { __mode = "k" })

local function tooltipLineCount(tooltipFrame)
    if type(tooltipFrame.NumLines) ~= "function" then return nil end
    local ok, n = pcall(tooltipFrame.NumLines, tooltipFrame)
    if not ok or (issecretvalue and issecretvalue(n)) or type(n) ~= "number" then return nil end
    return n
end

local function tagTooltip(tooltipFrame)
    if taggedTooltips[tooltipFrame] or type(tooltipFrame.AddDoubleLine) ~= "function" then return end
    if not tagClearHooked[tooltipFrame] and type(tooltipFrame.HookScript) == "function" then
        tagClearHooked[tooltipFrame] = true
        pcall(tooltipFrame.HookScript, tooltipFrame, "OnTooltipCleared", function(self) taggedTooltips[self] = nil end)
    end
    taggedTooltips[tooltipFrame] = true
    tooltipFrame:AddDoubleLine(" ", TAG_TITLE, 0, 0, 0, 0.5, 0.5, 0.5)
end

function TooltipCatchAdvisor.OnTooltipItem(tooltipFrame, tooltipData)
    if not ns.settings or not ns.settings.itemTooltip then return end
    if tooltipFrame ~= GameTooltip and tooltipFrame ~= ItemRefTooltip then return end
    local linesBefore = tooltipLineCount(tooltipFrame)
    TooltipCatchAdvisor.AddItemLines(tooltipFrame, tooltipData)
    local linesAfter = tooltipLineCount(tooltipFrame)
    if linesBefore and linesAfter and linesAfter > linesBefore then tagTooltip(tooltipFrame) end
end

function TooltipCatchAdvisor.AddItemLines(tooltipFrame, tooltipData)

    local itemID = tooltipData and ns.CoerceSafeNumber(tooltipData.id)
    if not itemID then return end

    local zoneList = ns:ZonesForFish(itemID)
    local poolList = ns:PoolZonesForFish(itemID)
    if (not zoneList[1] or zoneList[1].pct < 1) and not poolList[1] then
        return
    end

    local extTooltip = _G.EzWoW_Tooltip
    local hasExternalSource = extTooltip
        and extTooltip.db and extTooltip.db.item and extTooltip.db.item.showSourceInfo ~= false
        and extTooltip.ItemSourceDB and extTooltip.ItemSourceDB[itemID]

    local journalRecord = ns.db and ns.db.journal and ns.db.journal[itemID]
    if hasExternalSource then
        if journalRecord and journalRecord.n and journalRecord.n > 0 then
            tooltipFrame:AddLine(L["내가 낚은 수: %d"]:format(journalRecord.n), 0.55, 0.58, 0.64)
        end
        return
    end

    tooltipFrame:AddLine(" ")

    local renderedCount = 0
    for _, zoneInfo in ipairs(zoneList) do
        if renderedCount >= MAX_DISPLAYED_ZONES or zoneInfo.pct < 1 then break end
        local zoneMeta = ns.Data.zones[zoneInfo.mapID]
        local skillSuffix = (zoneMeta and zoneMeta.s) and ("  |cff8c94a3" .. zoneMeta.s .. "|r") or ""
        tooltipFrame:AddDoubleLine(
            ns:MapName(zoneInfo.mapID) .. skillSuffix,
            format("%.0f%%", zoneInfo.pct),
            0.85, 0.86, 0.90, 1.0, 1.0, 1.0
        )
        renderedCount = renderedCount + 1
    end

    if poolList[1] then
        local poolMapNames = {}
        for idx = 1, min(2, #poolList) do
            poolMapNames[#poolMapNames + 1] = ns:MapName(poolList[idx].mapID)
        end
        tooltipFrame:AddLine(L["물고기 떼: %s"]:format(tconcat(poolMapNames, ", ")), 0.43, 0.64, 1.0)
    end

    if journalRecord then
        tooltipFrame:AddLine(L["내가 낚은 수: %d"]:format(journalRecord.n), 0.55, 0.58, 0.64)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, TooltipCatchAdvisor.OnTooltipItem)
end
