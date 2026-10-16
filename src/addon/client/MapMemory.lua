-------------------------------------------------------------------------------
-- HFWM-Forever Map Memory
--
-- Remembers the world map's zoom (scale) and pan (scroll position) across
-- closing and reopening it: the one job the separate PersistentWorldMap
-- addon (Interface/AddOns/PersistentWorldMap) is built around, folded in
-- here as a single opt-out instead of a second install. On by default via
-- Config.DEFAULTS.rememberMapZoomPan; toggle from Options or
-- `/hfwm remember on|off`.
--
-- Save: sampled every frame while the map is shown (an OnUpdate on a frame
-- hanging off the map), reading the same three values PersistentWorldMap
-- reads (scale / scroll X / scroll Y) off the ScrollContainer, tagged with
-- the mapID they belong to. Sampling rather than a pre-hook on the
-- container's OnHide (which nils those fields): replacing Blizzard's script
-- runs it from addon code, tainting everything it writes. Method-call
-- equivalents (GetCanvasScale etc.) are tried first, field as fallback.
--
-- Restore: a post-hook on ToggleWorldMap and ToggleQuestLog. WorldMapFrame's
-- own OnShow fires before mapID and layout have settled (PersistentWorldMap
-- calls this out explicitly), so the toggle functions are the reliable
-- point, not HookScript("OnShow", ...). Restores only when the map the
-- client opened is the one that was remembered, then instantly pans/zooms
-- to the remembered position. It never changes the map itself: SetMapID
-- from addon code taints WorldMapFrame.mapID for good, every data provider
-- reads it, and every pin created after that is tainted (clicking one
-- trips ADDON_ACTION_FORBIDDEN, e.g. CopyToClipboard on the waypoint pin;
-- issue #20). So a map other than the one the client opens (the player's
-- zone) is not carried over.
--
-- Also restored around: the map's own quest-list side-panel toggle
-- (WorldMapFrame.SidePanelToggle's Open/CloseButton), which resizes the
-- canvas -- and therefore re-centers/re-zooms it -- without ever closing
-- the map, so the ToggleWorldMap/ToggleQuestLog hooks never see it. A
-- post-hook on their OnClick restores the last frame's sample once
-- Blizzard's handler (and its re-centering) has run.
--
-- Not reproduced: PersistentWorldMap's auto-centering, double-click and
-- recenter button. Restoring writes WorldMapFrame.mapID and the scroll
-- container's fields from addon code, which taints them for the session;
-- Taint.lua contains the fallout (pins acquired in combat), engaged by the
-- first restore.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config    = ns.Config
local MapMemory  = ns.MapMemory

local WorldMapFrame    = _G.WorldMapFrame

-------------------------------------------------------------------------------
-- Field access with a method-call preference, mirroring the comment above.
-------------------------------------------------------------------------------

local function GetCanvasScale(sc)
    if sc.GetCanvasScale then
        local ok, v = pcall(sc.GetCanvasScale, sc)
        if ok and v then return v end
    end
    return sc.currentScale
end

local function GetScrollX(sc)
    if sc.GetCurrentScrollX then
        local ok, v = pcall(sc.GetCurrentScrollX, sc)
        if ok and v then return v end
    end
    return sc.currentScrollX
end

local function GetScrollY(sc)
    if sc.GetCurrentScrollY then
        local ok, v = pcall(sc.GetCurrentScrollY, sc)
        if ok and v then return v end
    end
    return sc.currentScrollY
end

-------------------------------------------------------------------------------
-- Remembered state
--
-- Session-only, same as PersistentWorldMap's own lastMapID/lastScale/
-- lastScrollX/lastScrollY locals: not written to SavedVariables, so a
-- /reload or relog starts fresh rather than carrying a stale position from
-- a previous session into a client that may not even show the same map on
-- login.
-------------------------------------------------------------------------------
local savedMapID, savedScale, savedScrollX, savedScrollY

-- Guards against saving a half-initialised ScrollContainer before the map
-- has ever actually been shown this session.
local firstShownAfterLogin = false

-- Off under the gamepad UI: restoring calls Blizzard's InstantPanAndZoom
-- from addon code, which leaves the scroll container's scale and
-- scroll fields tainted and breaks the map's own gamepad zoom/pan.
local function Enabled()
    return Config.db and Config.db.rememberMapZoomPan and not Config:IsGamepadUI()
end

local function SaveState()
    if not firstShownAfterLogin or not Enabled() then return end

    local sc = WorldMapFrame.ScrollContainer
    local mapID = WorldMapFrame:GetMapID()
    if not mapID or not sc then
        savedMapID = nil
        return
    end

    savedMapID   = mapID
    savedScale   = GetCanvasScale(sc)
    savedScrollX = GetScrollX(sc)
    savedScrollY = GetScrollY(sc)
end

local function RestoreState()
    if not Enabled() then return end
    if not (savedMapID and savedScale and savedScrollX and savedScrollY) then
        return
    end

    -- Not WorldMapFrame:OnMapChanged() afterwards: the zoom change refreshes
    -- pins through OnCanvasScaleChanged. Each extra call from here is one
    -- more tainted pass over every data provider and the quest log.
    if WorldMapFrame:GetMapID() ~= savedMapID then return end
    ns.Taint:Engage()

    local sc = WorldMapFrame.ScrollContainer
    if sc and sc.InstantPanAndZoom then
        pcall(sc.InstantPanAndZoom, sc, savedScale, savedScrollX, savedScrollY,
            true)
    end
end

--- Post-hook target for ToggleWorldMap/ToggleQuestLog: only meaningful once
--- the map is actually on screen, mirroring PersistentWorldMap's own
--- RestoreMap gate.
local function OnToggle()
    if not WorldMapFrame:IsShown() then return end
    firstShownAfterLogin = true
    RestoreState()
end

--- Post-hook for the map's own side-panel toggle buttons (the quest-list
--- arrow docked to the map's edge, WorldMapFrame.SidePanelToggle.OpenButton/
--- CloseButton). Opening or closing that panel resizes the map's canvas,
--- and the client's canvas layout code reacts by re-centering and
--- re-zooming it within the same click handler; this runs after that
--- handler and puts back the view sampled on the last frame before it.
local function HookSidePanelToggleButton(btn)
    if btn then btn:HookScript("OnClick", RestoreState) end
end

--- Discard the remembered position without touching the enabled setting.
--- Used when the feature is switched off from Options or `/hfwm remember
--- off`, so flipping it back on later doesn't reapply a stale spot.
function MapMemory:Clear()
    savedMapID, savedScale, savedScrollX, savedScrollY = nil, nil, nil, nil
end

--- Wire up the hooks. Called once from Core.lua's PLAYER_LOGIN handler,
--- after WorldMapFrame is guaranteed to exist, same timing every other
--- module here waits for.
function MapMemory:Start()
    hooksecurefunc("ToggleWorldMap", OnToggle)
    hooksecurefunc("ToggleQuestLog", OnToggle)

    -- Hangs off the map (or the gamepad-UI host): only runs while shown.
    local sampler = CreateFrame("Frame", nil, Config:MapWidgetParent())
    sampler:SetScript("OnUpdate", SaveState)

    -- Some client builds don't have this side panel at all, hence the nil
    -- checks all the way down.
    local sidePanelToggle = WorldMapFrame.SidePanelToggle
    if sidePanelToggle then
        HookSidePanelToggleButton(sidePanelToggle.OpenButton)
        HookSidePanelToggleButton(sidePanelToggle.CloseButton)
    end
end
