--===========================================================================
-- EzWoW - Smart Fishing
-- Modules/TooltipHook.lua : Fish Item Tooltip Catch Count & Top Zone Hook
--===========================================================================
local _, ns = ...
local ipairs, min, format, tconcat = ipairs, math.min, string.format, table.concat

local TooltipCatchAdvisor = ns.TooltipCatchAdvisor or {}
ns.TooltipCatchAdvisor = TooltipCatchAdvisor

local L = ns.L
local MAX_DISPLAYED_ZONES = 3

function TooltipCatchAdvisor.OnTooltipItem(tooltipFrame, tooltipData)
    if not ns.settings or not ns.settings.itemTooltip then return end
    if tooltipFrame ~= GameTooltip and tooltipFrame ~= ItemRefTooltip then return end

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
    tooltipFrame:AddLine("EzWoW - Smart Fishing", 0.27, 0.78, 0.88)

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
