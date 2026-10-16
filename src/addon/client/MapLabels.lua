-------------------------------------------------------------------------------
-- HFWM-Forever Map Labels
--
-- "Labels" on the world map: continent names, capital cities, and towns and
-- hubs, each group toggled from Options (Config.db.showContinentNames,
-- showCapitalCities, showTownsHubs). Only the entries hand-written in LABELS
-- below; issue #17 will replace that with generated data.
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

-- [uiMapID] = { { texture, kind, w, h, u, v }, ... }. texture is the Assets/
-- file name without ".tga"; kind is "continent", "capital" or "town", and
-- picks its Options toggle through SHOW below; w and h its size in canvas
-- units; u/v the centre in 0-1 map coordinates from the top-left. Placed by
-- hand: each point is the centroid of the area's ADT chunks, on the outdoor
-- zone map that contains it.
local LABELS = {
    -- Continent names, on the continent maps.
    [1414] = {
        { texture = "KalimdorLabel", kind = "continent",
          w = 104, h = 21, u = 0.493, v = 0.536 },
    },
    [1415] = {
        { texture = "EasternKingdomsLabel", kind = "continent",
          w = 202.5, h = 26.5, u = 0.490, v = 0.510 },
    },
    [1411] = {
        { texture = "RazorHillLabel", kind = "town",
          w = 56, h = 12, u = 0.532, v = 0.421 },
    },
    [1412] = {
        { texture = "ThunderBluffLabel", kind = "capital",
          w = 107.5, h = 15.5, u = 0.398, v = 0.353 },
    },
    [1413] = {
        { texture = "TheCrossroadsLabel", kind = "town",
          w = 87, h = 12, u = 0.519, v = 0.300 },
        { texture = "RatchetLabel", kind = "town",
          w = 47, h = 12, u = 0.620, v = 0.380 },
    },
    [1417] = {
        { texture = "RefugePointeLabel", kind = "town",
          w = 81, h = 14.5, u = 0.460, v = 0.473 },
    },
    [1420] = {
        { texture = "UndercityLabel", kind = "capital",
          w = 77.5, h = 19, u = 0.619, v = 0.726 },
        { texture = "BrillLabel", kind = "town",
          w = 26, h = 12, u = 0.593, v = 0.502 },
    },
    -- Ironforge on the Dun Morogh map, from its world position (-4981, -881)
    -- and the map's UiMapAssignment bounds.
    [1426] = {
        { texture = "IronforgeLabel", kind = "capital",
          w = 73.25, h = 19.5, u = 0.545, v = 0.336 },
        { texture = "KharanosLabel", kind = "town",
          w = 56, h = 12, u = 0.468, v = 0.518 },
    },
    [1429] = {
        { texture = "StormwindLabel", kind = "capital",
          w = 86, h = 15.5, u = 0.232, v = 0.308 },
        { texture = "GoldshireLabel", kind = "town",
          w = 56.5, h = 12, u = 0.429, v = 0.655 },
        { texture = "NorthshireLabel", kind = "town",
          w = 64, h = 12, u = 0.525, v = 0.393 },
    },
    [1432] = {
        { texture = "ThelsamarLabel", kind = "town",
          w = 62, h = 12, u = 0.368, v = 0.495 },
    },
    [1433] = {
        { texture = "LakeshireLabel", kind = "town",
          w = 57.5, h = 12, u = 0.230, v = 0.446 },
    },
    [1434] = {
        { texture = "BootyBayLabel", kind = "town",
          w = 59.5, h = 14, u = 0.269, v = 0.752 },
    },
    [1436] = {
        { texture = "SentinelHillLabel", kind = "town",
          w = 70, h = 12, u = 0.550, v = 0.507 },
    },
    [1437] = {
        { texture = "MenethilHarborLabel", kind = "town",
          w = 95, h = 12, u = 0.098, v = 0.569 },
    },
    [1438] = {
        { texture = "DarnassusLabel", kind = "capital",
          w = 81.5, h = 15, u = 0.293, v = 0.555 },
    },
    [1439] = {
        { texture = "AuberdineLabel", kind = "town",
          w = 61, h = 12, u = 0.374, v = 0.430 },
    },
    [1440] = {
        { texture = "AstranaarLabel", kind = "town",
          w = 58.5, h = 11.5, u = 0.368, v = 0.508 },
    },
    [1446] = {
        { texture = "GadgetzanLabel", kind = "town",
          w = 63, h = 14.5, u = 0.524, v = 0.269 },
    },
    [1452] = {
        { texture = "EverlookLabel", kind = "town",
          w = 52, h = 12, u = 0.613, v = 0.371 },
    },
    -- Orgrimmar's area centroid lies outside Durotar's bounds, so it sits on
    -- its own zone map.
    [1454] = {
        { texture = "OrgrimmarLabel", kind = "capital",
          w = 88.5, h = 19, u = 0.535, v = 0.466 },
    },
}

--- Per label kind: the Options toggle that shows it, and its own scale and
--- Auto-scale fields.
local KIND = {
    continent = { show = "showContinentNames", scale = "continentLabelScale",
                  auto = "continentAutoScale" },
    capital   = { show = "showCapitalCities", scale = "capitalLabelScale",
                  auto = "capitalAutoScale" },
    town      = { show = "showTownsHubs", scale = "townLabelScale",
                  auto = "townAutoScale" },
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

--- Size multiplier for a label of *kind*: the Global label scale, times that
--- kind's own label scale, times the inverse of the canvas zoom against its
--- loosest step when the kind's Auto-scale is on. The art and the labels
--- both scale with the canvas, so zooming out shrinks a label on screen;
--- Auto-scale grows it back by that ratio, and zooming in shrinks it.
local function LabelScale(kind)
    local scale = Config.db.labelScale * Config.db[KIND[kind].scale]
    if not Config.db[KIND[kind].auto] then return scale end
    local sc = WorldMapFrame.ScrollContainer
    local levels = sc and sc.zoomLevels
    local base = levels and levels[1] and levels[1].scale
    local cur = sc and sc.currentScale
    if base and cur and cur > 0 then scale = scale * base / cur end
    return scale
end

--- Opacity of the labels. With Show on SD they are always fully visible.
--- Otherwise they fade in with the HD side of the blend, from 50% up to 100%.
local function LabelAlpha()
    if Config.db.labelShowOnSD then return 1 end
    return math.max(0, math.min(1, (Config:GetAlpha() - 0.5) * 2))
end

--- Show or hide the labels for the map now on screen. Safe to call at any
--- time, before the map has ever been opened included.
function MapLabels:Refresh()
    local canvas = WorldMapFrame.ScrollContainer
        and WorldMapFrame.ScrollContainer.Child
    local labels = {}
    local all = canvas and Config.db.enabled
        and LABELS[WorldMapFrame:GetMapID() or 0]
    for _, label in ipairs(all or {}) do
        if Config.db[KIND[label.kind].show] then labels[#labels + 1] = label end
    end
    if #labels == 0 then
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
    frame:SetAlpha(LabelAlpha())

    local w, h = canvas:GetSize()
    for i, label in ipairs(labels) do
        labelTextures[i] = labelTextures[i] or frame:CreateTexture(nil, "ARTWORK")
        Layout(labelTextures[i], label, label.u * w, -label.v * h, LabelScale(label.kind))
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
