-------------------------------------------------------------------------------
-- High Fidelity World Map -- Bootstrap
-- Wires up events and hooks once Ace3 initializes the addon.
--
-- /hfwm             - toggle on / off
-- /hfwm on|off      - explicit enable / disable
-- /hfwm bg NAME     - map background: default | ocean | hybrid
-- /hfwm options     - open the options panel
-- /hfwm cave        - the cave map window (on|off|show|hide|reset|alpha N|indoors)
-- /hfwm remember    - remember world map zoom+pan across close/reopen
-- /hfwm zoom        - additional (closer) world map zoom levels
-- /hfwm clarity     - higher-detail Kalimdor/Eastern Kingdoms/Azeroth maps
--                     (off by default; may render slower)
-- /hfwm debug       - print diagnostic info for current map
-------------------------------------------------------------------------------
local addonName, ns = ...
local addon = ns.addon

local Config       = ns.Config
local Renderer      = ns.Renderer
local Commands      = ns.Commands
local Options       = ns.Options
local Cave          = ns.Cave
local CaveRenderer  = ns.CaveRenderer
local MapMemory     = ns.MapMemory
local ZoomLevels    = ns.ZoomLevels
local ResetView     = ns.ResetView
local KeepCentered  = ns.KeepCentered
local ToggleButton  = ns.ToggleButton
local Coords       = ns.Coords
local MapLabels    = ns.MapLabels
local P              = ns.P

-- Key Bindings entry for the cave window toggle (Bindings.xml); the same
-- action Alt+M is bound to below, so it can be moved to a gamepad button.
BINDING_HEADER_HFWMFOREVER = "High Fidelity World Map"
_G["BINDING_NAME_CLICK HFWMForeverCaveKeybind:LeftButton"] = "Toggle cave window"

--- Fires once, right after SavedVariables load. Same timing ADDON_LOADED
--- used to mark.
function addon:OnInitialize()
    Config:InitDB()
end

--- Fires at PLAYER_LOGIN, once every addon has initialized. Same timing
--- PLAYER_LOGIN used to mark.
function addon:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    self:RegisterEvent("MAP_EXPLORATION_UPDATED")

    local canvas = WorldMapFrame.ScrollContainer.Child
    Config.overlayFrame = CreateFrame(
        "Frame", "HFWMForeverOverlay", canvas)
    Config.overlayFrame:SetAllPoints(canvas)
    Config.overlayFrame:SetFrameLevel(canvas:GetFrameLevel() + 500)
    Config.overlayFrame:EnableMouse(false)
    Config:InitMapHost()

    -- The cave map window is built lazily by CaveRenderer the first time a
    -- cave is entered, parented to Config:MapWidgetParent() (WorldMapFrame, or
    -- the gamepad-UI host) rather than the canvas so it doesn't pan or zoom
    -- with the map under it.

    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        Config.lastMapID = nil
        Renderer:Refresh(true)
        Cave:UpdateState()
        MapLabels:Refresh()
    end)

    if MapCanvasDetailLayerMixin
       and MapCanvasDetailLayerMixin.RefreshDetailTiles then
        hooksecurefunc(
            MapCanvasDetailLayerMixin, "RefreshDetailTiles", function()
                Cave:UpdateState()
            end)
    end

    WorldMapFrame:HookScript("OnShow", function()
        Config.caveEscHidden = false
        CaveRenderer:SetMapOpen(true)
        Config.lastMapID = nil
        Renderer:Refresh(true)
        Cave:UpdateState()
        MapLabels:Refresh()
    end)
    WorldMapFrame:HookScript("OnHide", function()
        CaveRenderer:SetMapOpen(false)
    end)
    CaveRenderer:SetMapOpen(WorldMapFrame:IsShown() and true or false)
    -- ESC, when no other panes are open, reaches the game menu. The cave
    -- window slots in ahead of it there -- the same place in the close
    -- order the Toggle Game Menu key works through: if the cave window is
    -- the last pane standing, ESC closes it (and does not open the menu,
    -- one press one action). With other panes up, the client closes those
    -- first and the game menu (this hook) never fires.
    if GameMenuFrame then
        GameMenuFrame:HookScript("OnShow", function()
            if not CaveRenderer:IsShown() then return end
            -- Gamepad UI: HideUIPanel from this (addon) hook runs Blizzard's
            -- focus/binding code tainted, which blocks the protected
            -- SetPreferredGamepadInteractTarget. The cave window has its own
            -- gamepad close binding instead (see CaveRenderer).
            if Config:IsGamepadUI() then return end
            HideUIPanel(GameMenuFrame)
            -- Just hide it: no suppression and no Remember State write, so
            -- reopening the map brings the window back as it was.
            Config.caveEscHidden = true
            CaveRenderer:HideCave()
        end)
    end
    -- Alt+M: toggle the cave window. The client's own keybind machinery
    -- (a hidden named button bound via SetBindingClick), so it fires from a
    -- hardware event, works in combat, and the player can re-bind or clear
    -- it in the standard keybindings UI. Re-asserted each login: character
    -- keybindings are saved per character and a hardware event is required
    -- to set one, which this is (PLAYER_LOGIN runs on one).
    local keyBtn = CreateFrame("Button", "HFWMForeverCaveKeybind", UIParent,
        "InsecureActionButtonTemplate")
    keyBtn:RegisterForClicks("AnyDown")
    keyBtn:SetScript("OnClick", function()
        if not Cave:IsEnabledHere() then
            return
        end
        if CaveRenderer:IsShown() then
            -- X-button behaviour: a close, not a hide (contrast the ESC
            -- hook above): suppress this cave, record it for Remember State,
            -- and offer the reopen icon.
            Cave:SuppressCurrent()
            CaveRenderer:HideCave()
            Cave:UpdateState()
        else
            Cave:ForceShow()
        end
    end)
    keyBtn:Hide()
    SetBindingClick("ALT-M", keyBtn:GetName(), "LeftButton")
    -- Character sheet and other side panels: the kept-open cave window
    -- moves aside rather than sit under them.
    -- Deferred: addon code run synchronously in Blizzard's panel show/hide
    -- chain taints it (same gamepad block as the GameMenuFrame hook above).
    hooksecurefunc("ShowUIPanel", function() C_Timer.After(0, function() CaveRenderer:Repin() end) end)
    hooksecurefunc("HideUIPanel", function() C_Timer.After(0, function() CaveRenderer:Repin() end) end)

    Config.overlayFrame:SetScript("OnSizeChanged", function()
        Renderer:ScheduleRefresh()
    end)

    -- The cave window is sized as a fraction of the map frame, so it needs
    -- relayout whenever the map is maximised or restored.
    WorldMapFrame:HookScript("OnSizeChanged", function()
        CaveRenderer:Relayout()
    end)

    Cave:Start()
    MapMemory:Start()
    ZoomLevels:Start()
    KeepCentered:Start()
    ResetView:Start()
    ToggleButton:Start()
    Coords:Start()

    Commands:Register()
    -- After Commands, so a Lua error while probing the client's options
    -- APIs still leaves the slash commands working.
    Options:Init()
    P("Loaded. /hfwm to toggle, /hfwm options for settings.")
end

--- Warm the texture cache for the player's zone (Renderer:Preload), on
--- login and every loading screen. Never by opening the map: a toggle from
--- addon code makes the map's first open of the session run tainted, so its
--- pin pools, mapID and panel layout stay tainted and the next open in combat
--- blocks SetPassThroughButtons (ADDON_ACTION_BLOCKED, issue #20).
function addon:PLAYER_ENTERING_WORLD()
    Renderer:Preload()
end

--- Fog of War's own reveal (Renderer's DrawExploredPiece) needs to hear
--- about newly-explored ground while the map is open. Only meaningful
--- while Fog of War is on and the map is shown; both checks avoid a full
--- Refresh on every step the player takes.
function addon:MAP_EXPLORATION_UPDATED()
    -- Next frame: Blizzard's own exploration provider handles this event
    -- too, and Fog of War reads its pins rather than refreshing them.
    C_Timer.After(0, function()
        if WorldMapFrame:IsShown() and (Config:FogOfWarEnabled()
            or Config:WorldFogOfWarEnabled(WorldMapFrame:GetMapID())) then
            Renderer:Refresh(true)
        end
    end)
end
