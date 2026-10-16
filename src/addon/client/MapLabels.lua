-------------------------------------------------------------------------------
-- HFWM-Forever Map Labels
--
-- "Labels" on the world map: continent names, capital cities, towns and hubs,
-- and subzones, each group toggled from Options (Config.db.showContinentNames,
-- showCapitalCities, showTownsHubs, showSubzoneNames). The names come from
-- MapLabelData.lua, generated from the game's own DB2 tables by
-- src/generator/scripts/emit_map_labels.py.
--
-- Each label is text drawn at runtime in Friz Quadrata TT, the game's own UI
-- font: a gold fill with the font's own thick black outline. Labels sit on one mouse-disabled
-- frame on the map canvas, above Config.overlayFrame (whose alpha changes with
-- the SD/Hybrid/HD background). They scale with the canvas, like the art under
-- them.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config    = ns.Config
local MapLabels = ns.MapLabels

local WorldMapFrame = _G.WorldMapFrame

-- [uiMapID] = { { name, kind, h, u, v }, ... }, from MapLabelData.lua. name is
-- the text shown; kind is "continent", "capital", "town" or "subzone", and
-- picks its Options toggle through KIND below; h its height in canvas units at
-- label scale 1; u/v the centre in 0-1 map coordinates from the top-left.
local LABELS = HFWMF_MAP_LABELS or {}

--- Per label kind: the Options toggle that shows it, and its own scale and
--- Auto-scale fields.
local KIND = {
    continent = { show = "showContinentNames", scale = "continentLabelScale",
                  auto = "continentAutoScale", color = "continentLabel" },
    capital   = { show = "showCapitalCities", scale = "capitalLabelScale",
                  auto = "capitalAutoScale", color = "capitalLabel" },
    town      = { show = "showTownsHubs", scale = "townLabelScale",
                  auto = "townAutoScale", color = "townLabel" },
    subzone   = { show = "showSubzoneNames", scale = "subzoneLabelScale",
                  auto = "subzoneAutoScale", color = "subzoneLabel" },
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
-- The copy outline: the text drawn at one-unit offsets behind the fill, in the
-- Outline colour. Used when a kind's True Border is off.
local OUTLINE_OFFSETS = {
    { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, -1 },
    { 0, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 },
}
-- Outline padding around a label's clip frames, as a fraction of its font
-- size, for True Border. ponytail: a fixed fraction; raise it if it still clips.
local OUTLINE_PAD = 0.2

local frame
local labelFrames = {}  -- [i] = { holder, outline = {FontString}, bands = {{clip, fs}} }

local function Text(parent, layer)
    local fs = parent:CreateFontString(nil, layer)
    fs:SetJustifyH("LEFT")
    return fs
end

--- One label: a holder frame with its outline copies behind and its text
--- bands in front. Positioned and painted by Paint.
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
--- top-left, at *scale*. The border is the font's thick outline (True Border)
--- or the copies in the Outline colour, per kind. The fill is the Color of its
--- kind, solid or gradient. A horizontal gradient is set in the text itself; a
--- vertical one is BANDS clipped copies, each in its band's colour from the top
--- (Color) to the bottom (Color2).
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
    local trueBorder = Config.db[key .. "TrueBorder"]
    local flags = trueBorder and "THICKOUTLINE" or ""
    local o = Config.db[key .. "Outline"]

    local slices = 1
    if vertical then
        local span = math.max(math.abs(b[1] - a[1]), math.abs(b[2] - a[2]),
            math.abs(b[3] - a[3])) * 255
        slices = math.min(MAX_BANDS, math.max(1, math.ceil(span / BAND_LEVELS)))
    end
    while #l.bands < slices do
        local clip = CreateFrame("Frame", nil, l.holder)
        l.bands[#l.bands + 1] = { clip = clip, fs = Text(clip, "OVERLAY") }
    end

    local first = l.bands[1].fs
    first:SetFont(FONT, size, flags)
    first:SetText(label.name)
    local w, h = first:GetStringWidth(), first:GetStringHeight()
    l.holder:SetSize(w, h)
    l.holder:ClearAllPoints()
    l.holder:SetPoint("CENTER", frame, "TOPLEFT", x, y)

    local pad = trueBorder and math.max(2, math.ceil(size * OUTLINE_PAD)) or 2

    for i, fs in ipairs(l.outline) do
        fs:SetShown(not trueBorder)
        if not trueBorder then
            fs:SetFont(FONT, size, "")
            fs:SetText(label.name)
            fs:SetTextColor(o[1], o[2], o[3], 1)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", l.holder, "TOPLEFT",
                OUTLINE_OFFSETS[i][1], OUTLINE_OFFSETS[i][2])
        end
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
            -- Only vertical bands clip. The first and last extend by pad so the
            -- outline is not cut at the label's ends; the last also covers the
            -- descent below the holder.
            local overlap = 1 / frame:GetEffectiveScale()
            local top = (i - 1) * h / slices
            local bottom = i == slices and h + size or i * h / slices + overlap
            local up = i == 1 and pad or 0
            local down = i == slices and pad or 0
            band.clip:SetClipsChildren(vertical)
            band.clip:SetSize(w + 2 * pad, bottom - top + up + down)
            band.clip:ClearAllPoints()
            band.clip:SetPoint("TOPLEFT", l.holder, "TOPLEFT", -pad, up - top)
            band.clip:Show()
            band.fs:SetFont(FONT, size, flags)
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

--- Opacity of subzone labels: 0 at the first additional zoom level, rising
--- linearly to 1 at the tightest one. 0 when there are no additional levels.
local function SubzoneAlpha()
    local extra = ns.ZoomLevels.extra
    local sc = WorldMapFrame.ScrollContainer
    local cur = sc and sc.currentScale
    if not extra or not cur then return 0 end
    local span = extra.to - extra.from
    if span <= 0 then return cur >= extra.to and 1 or 0 end
    return math.max(0, math.min(1, (cur - extra.from) / span))
end

--- Show or hide the labels for the map now on screen. Safe to call at any
--- time, before the map has ever been opened included.
function MapLabels:Refresh()
    local canvas = WorldMapFrame.ScrollContainer
        and WorldMapFrame.ScrollContainer.Child
    local labels = {}
    local all = canvas and Config.db.enabled
        and LABELS[WorldMapFrame:GetMapID() or 0]
    -- Under Fog of War only explored areas are labelled; continent names always
    -- show. A label's overlay is its area's explored-texture key (see emitter).
    local mapID = WorldMapFrame:GetMapID() or 0
    local fog = Config:FogOfWarEnabled() or Config:WorldFogOfWarEnabled(mapID)
    local explored
    if fog then
        explored = {}
        for _, t in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
            explored[t.offsetX .. "," .. t.offsetY .. ","
                .. t.textureWidth .. "," .. t.textureHeight] = true
        end
    end
    for _, label in ipairs(all or {}) do
        if Config.db[KIND[label.kind].show]
            and (not explored or label.overlay == nil or explored[label.overlay]) then
            labels[#labels + 1] = label
        end
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

    local subzoneAlpha = SubzoneAlpha()
    local w, h = canvas:GetSize()
    for i, label in ipairs(labels) do
        local l = labelFrames[i]
        if not l then
            l = NewLabel()
            labelFrames[i] = l
        end
        Paint(l, label, label.u * w, -label.v * h, LabelScale(label.kind))
        l.holder:SetAlpha(label.kind == "subzone" and subzoneAlpha or 1)
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
