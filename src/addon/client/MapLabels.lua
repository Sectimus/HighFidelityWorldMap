-------------------------------------------------------------------------------
-- HFWM-Forever Map Labels
--
-- "Extra Labels" on the world map. For now only Location Names
-- (Config.db.showLocationNames), and only the entries hand-written in
-- LOCATION_NAMES below; issue #17 will replace that with generated data.
--
-- Each label is one texture from Assets/, with the gold text and brown
-- outline already baked in. Labels sit on one mouse-disabled frame on the map
-- canvas, above Config.overlayFrame (whose alpha changes with the SD/Hybrid/HD
-- background). They scale with the canvas, like the art under them.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config    = ns.Config
local MapLabels = ns.MapLabels

local WorldMapFrame = _G.WorldMapFrame

-- [uiMapID] = { { texture, w, h, u, v }, ... }. texture is the Assets/ file
-- name without ".tga"; w and h its size in canvas units; u/v the centre in
-- 0-1 map coordinates from the top-left. Placed by hand.
local LOCATION_NAMES = {
    -- Ironforge on the Dun Morogh map, from its world position (-4981, -881)
    -- and the map's UiMapAssignment bounds.
    [1426] = {
        { texture = "IronforgeLabel", w = 73.25, h = 19.5, u = 0.545, v = 0.336 },
    },
}

local frame
local labelTextures = {}

--- Show label *label* centred on (x, y) from the canvas's top-left.
local function Layout(tex, label, x, y, scale)
    tex:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Assets\\"
        .. label.texture .. ".tga")
    tex:SetSize(label.w * scale, label.h * scale)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", frame, "TOPLEFT", x, y)
    tex:Show()
end

--- Size multiplier for the labels now: the Label Scale slider, times the
--- inverse of the canvas zoom against its loosest step when Auto-scale is on.
--- The art and the labels both scale with the canvas, so zooming out shrinks a
--- label on screen; Auto-scale grows it back by that ratio, and zooming in
--- shrinks it.
local function LabelScale()
    local scale = Config.db.labelScale
    if not Config.db.labelAutoScale then return scale end
    local sc = WorldMapFrame.ScrollContainer
    local levels = sc and sc.zoomLevels
    local base = levels and levels[1] and levels[1].scale
    local cur = sc and sc.currentScale
    if base and cur and cur > 0 then scale = scale * base / cur end
    return scale
end

--- Show or hide the labels for the map now on screen. Safe to call at any
--- time, before the map has ever been opened included.
function MapLabels:Refresh()
    local canvas = WorldMapFrame.ScrollContainer
        and WorldMapFrame.ScrollContainer.Child
    local labels = canvas and Config.db.enabled and Config.db.showLocationNames
        -- HD only, as ToggleButton's HDShowing reads it, unless Show on SD.
        and (Config.db.labelShowOnSD or Config:GetAlpha() > 0.5)
        and LOCATION_NAMES[WorldMapFrame:GetMapID() or 0]
    if not labels then
        if frame then frame:Hide() end
        return
    end

    if not frame then
        frame = CreateFrame("Frame", "HFWMForeverLabels", canvas)
        frame:EnableMouse(false)
        frame:SetScript("OnSizeChanged", function() MapLabels:Refresh() end)
    end
    -- Re-parent if the canvas was replaced, as Renderer does for the overlay.
    if frame:GetParent() ~= canvas then frame:SetParent(canvas) end
    frame:SetAllPoints(canvas)
    frame:SetFrameLevel(canvas:GetFrameLevel() + 501)
    frame:Show()

    local w, h = canvas:GetSize()
    for i, label in ipairs(labels) do
        labelTextures[i] = labelTextures[i] or frame:CreateTexture(nil, "ARTWORK")
        Layout(labelTextures[i], label, label.u * w, -label.v * h, LabelScale())
    end
    for i = #labels + 1, #labelTextures do labelTextures[i]:Hide() end
end

--- Re-lay the labels on every canvas zoom step, for Auto-scale. Called once
--- from Core.lua's PLAYER_LOGIN handler, same timing as the other modules.
function MapLabels:Start()
    local sc = WorldMapFrame.ScrollContainer
    if not sc or not sc.OnCanvasScaleChanged then return end
    hooksecurefunc(sc, "OnCanvasScaleChanged", function() MapLabels:Refresh() end)
end
