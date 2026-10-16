-------------------------------------------------------------------------------
-- HFWM-Forever Reset View
--
-- Shift+right-click on the world map resets the view of the map shown:
-- fully zoomed out and centered, undoing any panning/zooming. It never
-- changes which map is shown: WorldMapFrame:SetMapID from addon code
-- taints WorldMapFrame.mapID for good, and every pin a data provider
-- creates after that is tainted too (see Taint.lua). Blizzard's own
-- right-click on the ScrollContainer navigates up one level (zone ->
-- continent) before this hooked script can cancel it, so the reset is
-- deferred a frame to land after it. The cave window has its own
-- shift+right-click that only resets its zoom/pan (CaveRenderer). A plain
-- right-click is left alone (whatever Blizzard's own OnMouseUp on the
-- ScrollContainer already does with it); this only adds a second script onto
-- the same event, gated on the shift modifier, via HookScript rather than
-- SetScript so nothing already wired up there is replaced.
-------------------------------------------------------------------------------
local addonName, ns = ...
local ResetView = ns.ResetView

local WorldMapFrame  = _G.WorldMapFrame
local IsShiftKeyDown = _G.IsShiftKeyDown

--- Reset the world map's zoom/pan to the fitted view of the map currently shown.
local function ResetMapView()
    local sc = WorldMapFrame.ScrollContainer
    if not sc or ns.Config:IsGamepadUI() then return end  -- see MapMemory's Enabled

    -- zoomLevels[1] is always the loosest (fit-to-frame) step on the
    -- ladder -- see ZoomLevels.lua's own read of the *last* entry for the
    -- opposite, tightest end of the same table.
    local levels = sc.zoomLevels
    local baseScale = levels and levels[1] and levels[1].scale
    if not baseScale then return end

    if sc.InstantPanAndZoom then
        ns.Taint:Engage()  -- InstantPanAndZoom taints the scroll fields; see Taint.lua
        pcall(sc.InstantPanAndZoom, sc, baseScale, 0.5, 0.5, true)
    end
end

local function OnMouseUp(_, button)
    if button ~= "RightButton" or not IsShiftKeyDown() then return end
    -- Deferred a frame: Blizzard's own right-click (navigate up one level,
    -- zone -> continent) has to have run first, or it would land on top of
    -- the reset.
    C_Timer.After(0, ResetMapView)
end

function ResetView:HookFrame(frame, handler, recursive)
    if not frame or frame._hfwmResetHook then return end

    local callback = handler or OnMouseUp
    frame:HookScript("OnMouseUp", callback)
    frame._hfwmResetHook = true

    if recursive and frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            self:HookFrame(child, handler, true)
        end
    end
end

--- Wire up the hook. Called once from Core.lua's PLAYER_LOGIN handler, same
--- timing every other module here waits for.
function ResetView:Start()
    local sc = WorldMapFrame.ScrollContainer
    if not sc then return end
    self:HookFrame(sc, OnMouseUp, false)
end
