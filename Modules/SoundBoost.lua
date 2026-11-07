--===========================================================================
-- EzWoW - Smart Fishing
-- Modules/SoundBoost.lua : Louder sound effects only while your line is out
--===========================================================================
-- The game can't make one sound louder, and it doesn't tell addons when a fish
-- bites. So while you are fishing (cast -> reel in) the sound-effect volume is
-- raised and music/ambience are muted; the moment fishing ends, your own values
-- come back. They are kept in the saved file too, so a crash can't lose them.
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall

local SoundBoost = {}
ns.SoundBoost = SoundBoost
local L = ns.L

local MEDIA = "Interface\\AddOns\\EzWoW-SmartFishing\\Media\\"
local CVARS = { "Sound_MasterVolume", "Sound_SFXVolume", "Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_EnableSFX", "Sound_EnableSoundWhenGameIsInBG" }
local fishing = false
local generation = 0

local function getCVar(name)
    local ok, value = pcall(GetCVar, name)
    if ok then return value end
    return nil
end

local function setCVar(name, value)
    pcall(function()
        local current = GetCVar(name)
        if current ~= nil and current ~= tostring(value) then SetCVar(name, value) end
    end)
end

local function settings() return ns.settings or {} end

function SoundBoost.Volume()
    local v = tonumber(settings().soundBoostVolume) or 1
    return math.max(0.1, math.min(2, v))
end

-- Puts the player's own sound settings back (if this addon changed them).
function SoundBoost.Restore()
    local saved = ns.db and ns.db.soundBefore
    if type(saved) ~= "table" then return end
    for _, name in ipairs(CVARS) do
        if saved[name] ~= nil then setCVar(name, saved[name]) end
    end
    ns.db.soundBefore = nil
end

function SoundBoost.Apply()
    if not ns.db then return end
    local s = settings()
    if not s.soundBoost then
        SoundBoost.Restore()
        return
    end
    if type(ns.db.soundBefore) ~= "table" then
        local saved = {}
        for _, name in ipairs(CVARS) do saved[name] = getCVar(name) end
        ns.db.soundBefore = saved
    end
    setCVar("Sound_EnableSFX", 1)
    setCVar("Sound_EnableSoundWhenGameIsInBG", 1)
    local saved = ns.db.soundBefore
    -- older saves (before the master volume was kept) get it now, before it changes
    if saved.Sound_MasterVolume == nil then saved.Sound_MasterVolume = getCVar("Sound_MasterVolume") end
    local level = SoundBoost.Volume()
    setCVar("Sound_SFXVolume", string.format("%.2f", math.min(1, level)))
    -- above 100%: sound effects are already at the top, so the master volume goes up
    -- from your own value towards 100% (200% = master at 100%)
    local baseMaster = tonumber(saved.Sound_MasterVolume) or 1
    if level > 1 then
        setCVar("Sound_MasterVolume", string.format("%.2f", baseMaster + (1 - baseMaster) * (level - 1)))
    elseif saved.Sound_MasterVolume ~= nil then
        setCVar("Sound_MasterVolume", saved.Sound_MasterVolume)
    end
    if s.soundQuiet ~= false then
        setCVar("Sound_MusicVolume", 0)
        setCVar("Sound_AmbienceVolume", 0)
    else
        setCVar("Sound_MusicVolume", saved.Sound_MusicVolume)
        setCVar("Sound_AmbienceVolume", saved.Sound_AmbienceVolume)
    end
end

function SoundBoost.IsFishing() return fishing end

-- Settings changed from the HUD or the options window.
function SoundBoost.Refresh()
    if fishing then SoundBoost.Apply() else SoundBoost.Restore() end
    if ns.RefreshSoundControls then ns.RefreshSoundControls() end
end

ns:SubscribeAddonEvent("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if ns.CoerceSafeString(unit) ~= "player" or not (ns.IsFishingSpell and ns.IsFishingSpell(spellID)) then return end
    fishing = true
    generation = generation + 1
    SoundBoost.Apply()
end)

ns:SubscribeAddonEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(unit)
    if ns.CoerceSafeString(unit) ~= "player" or not fishing then return end
    fishing = false
    -- a short wait so a quick re-cast doesn't make the music jump back and forth
    local mine = generation
    C_Timer.After(1.5, function()
        if not fishing and generation == mine then SoundBoost.Restore() end
    end)
end)

ns:SubscribeAddonEvent("AM_DB_READY", function()
    -- left over from a crash or disconnect while fishing
    SoundBoost.Restore()
end)
ns:SubscribeAddonEvent("PLAYER_LOGOUT", function()
    fishing = false
    SoundBoost.Restore()
end)
ns:SubscribeAddonEvent("AM_SETTINGS_CHANGED", function(key)
    if key == "soundBoost" or key == "soundQuiet" or key == "soundBoostVolume" then SoundBoost.Refresh() end
end)

-----------------------------------------------------------------------------
-- Small volume panel on the right of the fishing HUD
-----------------------------------------------------------------------------
local panel

function ns.AttachSoundControls(hud)
    local Style = ns.Style
    panel = CreateFrame("Frame", nil, hud, "BackdropTemplate")
    Style:Panel(panel)
    panel:SetSize(48, hud:GetHeight())
    panel:SetPoint("TOPLEFT", hud, "TOPRIGHT", 3, 0)

    local function smallButton(text, onClick)
        local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
        Style:Panel(b, { 1, 1, 1, 0.04 }, Style.border)
        b:SetSize(40, 18)
        b.t = Style:Text(b, 11)
        b.t:SetPoint("CENTER")
        b.t:SetJustifyH("CENTER")
        b.t:SetText(text)
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(unpack(Style.accent))
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["낚시 소리"], unpack(Style.accent))
            GameTooltip:AddLine(L["낚시를 던져 기다리는 동안만 효과음을 키웁니다."], 0.929, 0.957, 0.969, true)
            GameTooltip:AddLine(L["클릭: 켜기/끄기 · +/-: 크기"], unpack(Style.muted))
            GameTooltip:AddLine(L["100%를 넘기면 주 음량까지 올립니다."], unpack(Style.muted))
            GameTooltip:AddDoubleLine(" ", "EzWoW - Smart Fishing", 0, 0, 0, 0.5, 0.5, 0.5)
            GameTooltip:Show()
            if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
        end)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(unpack(Style.border))
            GameTooltip:Hide()
        end)
        return b
    end

    local function changeVolume(delta)
        local v = math.floor((SoundBoost.Volume() + delta) * 10 + 0.5) / 10
        ns.settings.soundBoostVolume = math.max(0.1, math.min(2, v))
        if not ns.settings.soundBoost then ns.settings.soundBoost = true end
        ns:PublishAddonEvent("AM_SETTINGS_CHANGED", "soundBoostVolume")
    end

    panel.plus = smallButton("+", function() changeVolume(0.1) end)
    panel.plus:SetPoint("TOP", 0, -5)
    panel.value = Style:Text(panel, 11)
    panel.value:SetPoint("TOP", panel.plus, "BOTTOM", 0, -4)
    panel.value:SetJustifyH("CENTER")
    panel.minus = smallButton("-", function() changeVolume(-0.1) end)
    panel.minus:SetPoint("TOP", panel.value, "BOTTOM", 0, -4)
    panel.toggle = smallButton("", function()
        ns.settings.soundBoost = not ns.settings.soundBoost
        ns:PublishAddonEvent("AM_SETTINGS_CHANGED", "soundBoost")
    end)
    panel.toggle:SetPoint("BOTTOM", 0, 3)
    -- speaker icon instead of a word: waves = on, cross = off
    panel.toggle.icon = panel.toggle:CreateTexture(nil, "ARTWORK")
    panel.toggle.icon:SetSize(14, 14)
    panel.toggle.icon:SetPoint("CENTER")
    ns.RefreshSoundControls()
end

function ns.RefreshSoundControls()
    if not panel then return end
    local on = settings().soundBoost and true or false
    local Style = ns.Style
    panel.value:SetText(math.floor(SoundBoost.Volume() * 100 + 0.5) .. "%")
    panel.value:SetTextColor(unpack(on and Style.text or Style.muted))
    panel.toggle.t:SetText("")
    panel.toggle.icon:SetTexture(MEDIA .. (on and "SpeakerOn" or "SpeakerOff"))
    panel.toggle.icon:SetVertexColor(unpack(on and Style.accent or Style.muted))
end
