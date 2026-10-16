-------------------------------------------------------------------------------
-- HFWM-Forever Map Labels
--
-- "Labels" on the world map: continent names, capital cities, and towns and
-- hubs, each group toggled from Options (Config.db.showContinentNames,
-- showCapitalCities, showTownsHubs). Only the entries hand-written in LABELS
-- below; issue #17 will replace that with generated data.
--
-- Each label is text drawn at runtime in Friz Quadrata TT, the game's own UI
-- font: a brown outline behind a gold fill. Labels sit on one mouse-disabled
-- frame on the map canvas, above Config.overlayFrame (whose alpha changes with
-- the SD/Hybrid/HD background). They scale with the canvas, like the art under
-- them.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config    = ns.Config
local MapLabels = ns.MapLabels

local WorldMapFrame = _G.WorldMapFrame

-- [uiMapID] = { { name, kind, h, u, v }, ... }. name is the text shown; kind is
-- "continent", "capital" or "town", and picks its Options toggle through KIND
-- below; h its height in canvas units at label scale 1; u/v the centre in 0-1
-- map coordinates from the top-left. Placed by hand: each point is the
-- centroid of the area's ADT chunks, on the outdoor zone map that contains it.
local LABELS = {
    -- Continent names, on the continent maps.
    [1414] = {
        { name = "Kalimdor", kind = "continent",
          h = 21, u = 0.493, v = 0.536 },
    },
    [1415] = {
        { name = "Eastern Kingdoms", kind = "continent",
          h = 26.5, u = 0.490, v = 0.510 },
    },
    [1411] = {
        { name = "Razor Hill", kind = "town",
          h = 12, u = 0.532, v = 0.421 },
    },
    [1412] = {
        { name = "Thunder Bluff", kind = "capital",
          h = 15.5, u = 0.398, v = 0.353 },
    },
    [1413] = {
        { name = "The Crossroads", kind = "town",
          h = 12, u = 0.519, v = 0.300 },
        { name = "Ratchet", kind = "town",
          h = 12, u = 0.620, v = 0.380 },
    },
    [1417] = {
        { name = "Refuge Pointe", kind = "town",
          h = 14.5, u = 0.460, v = 0.473 },
    },
    [1420] = {
        { name = "Undercity", kind = "capital",
          h = 19, u = 0.619, v = 0.726 },
        { name = "Brill", kind = "town",
          h = 12, u = 0.593, v = 0.502 },
    },
    -- Ironforge on the Dun Morogh map, from its world position (-4981, -881)
    -- and the map's UiMapAssignment bounds.
    [1426] = {
        { name = "Ironforge", kind = "capital",
          h = 19.5, u = 0.545, v = 0.336 },
        { name = "Kharanos", kind = "town",
          h = 12, u = 0.468, v = 0.518 },
    },
    [1429] = {
        { name = "Stormwind", kind = "capital",
          h = 15.5, u = 0.232, v = 0.308 },
        { name = "Goldshire", kind = "town",
          h = 12, u = 0.429, v = 0.655 },
        { name = "Northshire", kind = "town",
          h = 12, u = 0.525, v = 0.393 },
    },
    [1432] = {
        { name = "Thelsamar", kind = "town",
          h = 12, u = 0.368, v = 0.495 },
    },
    [1433] = {
        { name = "Lakeshire", kind = "town",
          h = 12, u = 0.230, v = 0.446 },
    },
    [1434] = {
        { name = "Booty Bay", kind = "town",
          h = 14, u = 0.269, v = 0.752 },
    },
    [1436] = {
        { name = "Sentinel Hill", kind = "town",
          h = 12, u = 0.550, v = 0.507 },
    },
    [1437] = {
        { name = "Menethil Harbor", kind = "town",
          h = 12, u = 0.098, v = 0.569 },
    },
    [1438] = {
        { name = "Darnassus", kind = "capital",
          h = 15, u = 0.293, v = 0.555 },
    },
    [1439] = {
        { name = "Auberdine", kind = "town",
          h = 12, u = 0.374, v = 0.430 },
    },
    [1440] = {
        { name = "Astranaar", kind = "town",
          h = 11.5, u = 0.368, v = 0.508 },
    },
    [1446] = {
        { name = "Gadgetzan", kind = "town",
          h = 14.5, u = 0.524, v = 0.269 },
    },
    [1452] = {
        { name = "Everlook", kind = "town",
          h = 12, u = 0.613, v = 0.371 },
    },
    -- Orgrimmar's area centroid lies outside Durotar's bounds, so it sits on
    -- its own zone map.
    [1454] = {
        { name = "Orgrimmar", kind = "capital",
          h = 19, u = 0.535, v = 0.466 },
    },
}

--- Per label kind: the Options toggle that shows it, and its own scale and
--- Auto-scale fields.
local KIND = {
    continent = { show = "showContinentNames", scale = "continentLabelScale",
                  auto = "continentAutoScale", color = "continentLabel" },
    capital   = { show = "showCapitalCities", scale = "capitalLabelScale",
                  auto = "capitalAutoScale", color = "capitalLabel" },
    town      = { show = "showTownsHubs", scale = "townLabelScale",
                  auto = "townAutoScale", color = "townLabel" },
}

local FONT = "Fonts\\FRIZQT__.TTF"
-- Font height per unit of label h. Matches the text size of the art the
-- labels were drawn at before; approximate, tune in game.
local FONT_PER_H = 0.85
-- Vertical gradients stack flat-colour clipped copies of the text, one per
-- band, sized so neighbouring bands differ by about BAND_LEVELS of 255.
-- Each band costs 2 FontStrings per label.
-- ponytail: steps of ~2 levels, capped at MAX_BANDS=40; a gradient spanning
-- more than 80 levels will show steps. Raise MAX_BANDS to fix.
local BAND_LEVELS = 2
local MAX_BANDS = 40
local OUTLINE_OFFSETS = {
    { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, -1 },
    { 0, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 },
}

local frame
local labelFrames = {}  -- [i] = { holder, outline = {FontString}, bands = {{clip, fs}} }

local function Text(parent, layer)
    local fs = parent:CreateFontString(nil, layer)
    fs:SetJustifyH("LEFT")
    return fs
end

--- One label: a holder frame with the brown copies behind and the gold text
--- in front. Positioned and painted by Paint.
local function NewLabel()
    local holder = CreateFrame("Frame", nil, frame)
    holder:EnableMouse(false)
    local l = { holder = holder, outline = {}, bands = {} }
    for i = 1, #OUTLINE_OFFSETS do
        l.outline[i] = Text(holder, "BACKGROUND")
    end
    return l
end

--- Two hex digits of a 0..1 colour channel.
local function Hex(v)
    return ("%02x"):format(math.floor(v * 255 + 0.5))
end

--- *name* with each letter in its own colour, from a at the first letter to b
--- at the last. Inline colour codes, so the gradient needs no art.
local function Inline(name, a, b)
    local out, n = {}, #name
    for i = 1, n do
        local t = n > 1 and (i - 1) / (n - 1) or 0
        out[i] = "|cff" .. Hex(a[1] + (b[1] - a[1]) * t)
            .. Hex(a[2] + (b[2] - a[2]) * t) .. Hex(a[3] + (b[3] - a[3]) * t)
            .. name:sub(i, i) .. "|r"
    end
    return table.concat(out)
end

--- Position and colour one label centred on (x, y) from the canvas's
--- top-left, at *scale*. The outline is the Outline colour. The fill is the
--- Color of its kind, solid or gradient. A horizontal gradient is set in the
--- text itself; a vertical one is BANDS clipped copies, each in its band's
--- colour from the top (Color) to the bottom (Color2).
local function Paint(l, label, x, y, scale)
    local key = KIND[label.kind].color
    local size = label.h * FONT_PER_H * scale
    local a = Config.db[key .. "Color"]
    local b = a
    local dir = "HORIZONTAL"
    local gradient = Config.db[key .. "ColorMode"] == "gradient"
    if gradient then
        b = Config.db[key .. "Color2"]
        dir = Config.db[key .. "GradientDir"]
    end
    local vertical = gradient and dir == "VERTICAL"
    local o = Config.db[key .. "Outline"]

    for i, fs in ipairs(l.outline) do
        fs:SetFont(FONT, size, "")
        fs:SetText(label.name)
        fs:SetTextColor(o[1], o[2], o[3], 1)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", l.holder, "TOPLEFT",
            OUTLINE_OFFSETS[i][1], OUTLINE_OFFSETS[i][2])
    end
    local w, h = l.outline[1]:GetStringWidth(), l.outline[1]:GetStringHeight()
    l.holder:SetSize(w, h)
    l.holder:ClearAllPoints()
    l.holder:SetPoint("CENTER", frame, "TOPLEFT", x, y)

    local slices = 1
    if vertical then
        local span = math.max(math.abs(b[1] - a[1]), math.abs(b[2] - a[2]),
            math.abs(b[3] - a[3])) * 255
        slices = math.min(MAX_BANDS, math.max(1, math.ceil(span / BAND_LEVELS)))
    end
    while #l.bands < slices do
        local clip = CreateFrame("Frame", nil, l.holder)
        clip:SetClipsChildren(true)
        l.bands[#l.bands + 1] = { clip = clip, fs = Text(clip, "OVERLAY") }
    end
    local inline = gradient and not vertical and Inline(label.name, a, b)
    for i, band in ipairs(l.bands) do
        if i > slices then
            band.clip:Hide()
        else
            local c = a
            if vertical then
                local t = slices > 1 and (i - 1) / (slices - 1) or 0
                c = {}
                for k = 1, 3 do c[k] = a[k] + (b[k] - a[k]) * t end
            end
            -- Each band runs one screen pixel into the next, so a fractional
            -- clip edge cannot open a gap; the next band draws over the overlap.
            -- The last band also covers the descent below the holder (the
            -- tail of a G, say), which the holder height does not include.
            local overlap = 1 / frame:GetEffectiveScale()
            local bottom = i == slices and h + size or i * h / slices + overlap
            band.clip:SetSize(w + 4, bottom - (i - 1) * h / slices)
            band.clip:ClearAllPoints()
            band.clip:SetPoint("TOPLEFT", l.holder, "TOPLEFT",
                -2, -(i - 1) * h / slices)
            band.clip:Show()
            band.fs:SetFont(FONT, size, "")
            band.fs:SetText(inline or label.name)
            if inline then
                band.fs:SetTextColor(1, 1, 1, 1)
            else
                band.fs:SetTextColor(c[1], c[2], c[3], 1)
            end
            band.fs:ClearAllPoints()
            band.fs:SetPoint("TOPLEFT", l.holder, "TOPLEFT")
        end
    end
    l.holder:Show()
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
        local l = labelFrames[i]
        if not l then
            l = NewLabel()
            labelFrames[i] = l
        end
        Paint(l, label, label.u * w, -label.v * h, LabelScale(label.kind))
    end
    for i = #labels + 1, #labelFrames do
        labelFrames[i].holder:Hide()
    end
end

--- Re-lay the labels on every canvas zoom step, for Auto-scale. Called once
--- from Core.lua's PLAYER_LOGIN handler, same timing as the other modules.
function MapLabels:Start()
    local sc = WorldMapFrame.ScrollContainer
    if not sc or not sc.OnCanvasScaleChanged then return end
    hooksecurefunc(sc, "OnCanvasScaleChanged", function() MapLabels:Refresh() end)
end
