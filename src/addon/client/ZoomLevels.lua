-------------------------------------------------------------------------------
-- HFWM-Forever Zoom Levels
--
-- Optional "Additional Zoom Levels" feature (on by default): appends extra,
-- closer zoom steps onto the world map's own zoom ladder, so the higher-
-- resolution art this addon ships (see hfwm/gamedata/db2.py's _hires_geometry: every
-- Type=Zone map uncapped, plus Kalimdor/Eastern Kingdoms/Azeroth capped) can
-- be zoomed into past whatever ceiling Blizzard's own map data allows,
-- instead of that extra detail going to waste once the built-in max zoom is
-- reached.
--
-- WorldMapFrame.ScrollContainer (MapCanvasScrollControllerMixin) keeps its
-- own zoom ladder in self.zoomLevels, a plain array of { scale, layerIndex }
-- rebuilt by :CreateZoomLevels() from C_Map.GetMapArtLayers() every time the
-- shown map or the canvas size changes. Zoom-in/out (buttons, mouse wheel,
-- and the clamp inside :SetZoomTarget) all read the *last* entry through
-- :GetScaleForMaxZoom(), which is nothing more than
-- self.zoomLevels[#self.zoomLevels].scale, so appending further, larger-
-- scale entries to that table right after Blizzard finishes building it
-- raises the ceiling for every normal zoom path at once, with no need to
-- touch OnMouseWheel or SetZoomTarget directly. This is a plain post-hook
-- (hooksecurefunc), so a client that ships something incompatible here just
-- leaves the ladder as Blizzard built it; the option quietly does nothing
-- rather than erroring.
--
-- Each extra level keeps the *last* real level's layerIndex: there is no
-- further Blizzard art layer to switch to (Classic-era zones have exactly
-- one), so every extra step is purely a bigger on-screen scale of the same
-- bundled tiles Renderer.lua already draws. Renderer only ever reads
-- canvas:GetSize() (see its Refresh), so it needs no changes to benefit
-- from this.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config     = ns.Config
local ZoomLevels = ns.ZoomLevels

local WorldMapFrame = _G.WorldMapFrame

-- How many extra steps to append.
local EXTRA_STEPS = 8

-- How much closer each extra step gets versus the one before it. Continues
-- Blizzard's own last-step ratio when there is one to read, so the extra
-- steps feel like a natural continuation of the existing ladder rather than
-- an arbitrary jump; this is only the fallback for a map whose own ladder is
-- a single level (no zoom range at all, e.g. a 1x1 city map) and so has no
-- ratio of its own to continue.
local FALLBACK_STEP_RATIO = 1.5

local function Enabled()
    return Config.db and Config.db.additionalZoomLevels
end

--- Blizzard's last zoom level and the step ratio to continue it with, or
--- nil when extra levels don't apply to the map being shown.
---@param sc table the ScrollContainer
---@return table|nil lastLevel, number|nil ratio
local function LadderTail(sc)
    if not Enabled() then return end

    -- Continent and world maps only have art worth zooming into when High
    -- Resolution (which needs the Art addon) is in effect.
    local mapType = Config:ClassifyMapID(WorldMapFrame:GetMapID())
    if (mapType == "world" or mapType == "continent")
       and not Config:MapClarityEnabled(mapType) then
        return
    end
    local levels = sc.zoomLevels
    if not levels or #levels == 0 then return end

    local lastIdx   = #levels
    local lastLevel = levels[lastIdx]
    local ratio = FALLBACK_STEP_RATIO
    if lastIdx >= 2 and levels[lastIdx - 1].scale > 0 then
        local r = lastLevel.scale / levels[lastIdx - 1].scale
        if r > 1 then ratio = r end
    end
    return lastLevel, ratio
end

--- Post-hook target for ScrollContainer:CreateZoomLevels(). Appends
--- EXTRA_STEPS further levels onto whatever ladder Blizzard just rebuilt,
--- each further zoomed in than the last, all pointing at the same layer
--- index Blizzard's own final level used.
---@param sc table the ScrollContainer instance (its own `self`)
local function ExtendZoomLevels(sc)
    ZoomLevels.extra = nil
    -- Off under the gamepad UI: any entry added to Blizzard's zoomLevels is
    -- tainted, the map's own focus/binding flows then read it (via
    -- GetScaleForMaxZoom) and run tainted, and the stick-zoom binding stops
    -- firing. Overriding the view past Blizzard's last step with widget calls
    -- instead avoids that taint but leaves Blizzard's cursor-to-map maths on
    -- the old scale, so clicks land in the wrong place. The gamepad therefore
    -- stops at Blizzard's own last step.
    if Config:IsGamepadUI() then return end
    local lastLevel, ratio = LadderTail(sc)
    if not lastLevel then return end
    -- Blizzard's zoom maths read these entries; see Taint.lua.
    ns.Taint:Engage()

    local levels = sc.zoomLevels
    local scale = lastLevel.scale
    for _ = 1, EXTRA_STEPS do
        scale = scale * ratio
        levels[#levels + 1] = {
            scale = scale,
            layerIndex = lastLevel.layerIndex,
        }
    end
    -- Scales of Blizzard's last step and of the first and last additional
    -- steps, for AreaLabels' zoom fades. Nil whenever no additional steps are
    -- on the ladder.
    ZoomLevels.extra = {
        boundary = lastLevel.scale,
        from = levels[#levels - EXTRA_STEPS + 1].scale,
        to = levels[#levels].scale,
    }
end

--- Force the ladder to rebuild right now, so toggling the option in Options
--- (or via /hfwm zoom, or switching world map resolution) takes effect
--- immediately rather than waiting for the next map change or canvas
--- resize. CreateZoomLevels only recomputes self.baseScale/self.zoomLevels;
--- it does not itself move the current view, so if the ladder just got
--- shorter the view is left zoomed past the new maximum: snap it back.
function ZoomLevels:Refresh()
    local sc = WorldMapFrame.ScrollContainer
    if not (sc and sc.CreateZoomLevels) or Config:IsGamepadUI() then return end
    ns.Taint:Engage()
    pcall(sc.CreateZoomLevels, sc)

    local levels = sc.zoomLevels
    local maxScale = levels and levels[#levels] and levels[#levels].scale
    local scale, x, y = sc.currentScale, sc.currentScrollX, sc.currentScrollY
    if maxScale and scale and x and y and scale > maxScale
       and sc.InstantPanAndZoom then
        pcall(sc.InstantPanAndZoom, sc, maxScale, x, y, true)
    end
end

--- Wire up the hook. Called once from Core.lua's PLAYER_LOGIN handler, same
--- timing every other module here waits for.
function ZoomLevels:Start()
    local sc = WorldMapFrame.ScrollContainer
    if not sc or not sc.CreateZoomLevels then
        return  -- no zoom-ladder API on this client at all; nothing to extend
    end
    hooksecurefunc(sc, "CreateZoomLevels", ExtendZoomLevels)
end
