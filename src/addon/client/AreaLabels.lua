-------------------------------------------------------------------------------
-- HFWM-Forever Area Labels
--
-- "Area Labels" on the world map: continent names, capital cities, towns and hubs,
-- points of interest, subzones, and city districts, each group toggled from Options
-- (Config.db.showAreaContinentNames, showAreaCapitalCities, showAreaTownsHubs,
-- showAreaPOIs, showAreaSubzoneNames, showAreaCityDistricts). The names come from
-- AreaLabelData.lua, generated from the game's own DB2 tables by
-- src/generator/scripts/emit_area_labels.py.
--
-- Each label is text drawn at runtime in Friz Quadrata TT, the game's own UI
-- font: a gold fill with the font's own thick black outline. Labels sit on one mouse-disabled
-- frame on the map canvas, above Config.overlayFrame (whose alpha changes with
-- the SD/Hybrid/HD background). They scale with the canvas, like the art under
-- them.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config    = ns.Config
local AreaLabels = ns.AreaLabels

local WorldMapFrame = _G.WorldMapFrame

-- [uiMapID] = { { name, kind, h, u, v }, ... }, from AreaLabelData.lua. name is
-- the text shown; kind is "continent", "capital", "town", "subzone" or
-- "district" (a part of a capital, listed only under that capital's own map), and
-- picks its Options toggle through KIND below; h its height in canvas units at
-- label scale 1; u/v the centre in 0-1 map coordinates from the top-left.
local AREA_LABELS = HFWMF_AREA_LABELS or {}

--- Hand-kept labels from CustomLabels.lua, same shape as AREA_LABELS entries
--- (h optional). Each shows under its kind's Include Custom toggle; kind
--- "poi" shows with the Points of Interest type itself.
local CUSTOM_LABELS = HFWMF_CUSTOM_LABELS or {}

--- Label height in canvas units at scale 1 for a custom POI with no h of its
--- own. Same values as AREA_LABEL_H in emit_area_labels.py.
local DEFAULT_H = { continent = 24, capital = 16, town = 12, subzone = 10, poi = 10, district = 12 }

--- Per label kind: the Options toggle that shows it, and its own scale and
--- Auto-scale fields.
local KIND = {
    continent = { show = "showAreaContinentNames", scale = "continentAreaLabelScale",
                  auto = "continentAutoScale", color = "continentAreaLabel" },
    capital   = { show = "showAreaCapitalCities", scale = "capitalAreaLabelScale",
                  auto = "capitalAutoScale", color = "capitalAreaLabel" },
    town      = { show = "showAreaTownsHubs", scale = "townAreaLabelScale",
                  auto = "townAutoScale", color = "townAreaLabel" },
    subzone   = { show = "showAreaSubzoneNames", scale = "subzoneAreaLabelScale",
                  color = "subzoneAreaLabel" },
    poi       = { show = "showAreaPOIs", scale = "poiAreaLabelScale",
                  color = "poiAreaLabel" },
    district  = { show = "showAreaCityDistricts", scale = "districtAreaLabelScale",
                  auto = "districtAutoScale", color = "districtAreaLabel" },
}

--- The font a label kind draws in: its own, or the Global Font.
local function FontFor(key)
    local font = Config.db[key .. "Font"]
    return font == "global" and Config.db.areaLabelFont or font
end
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
-- The border: copies of the text drawn at offsets behind the fill, in the
-- Outline colour.
local OUTLINE_OFFSETS = {
    { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, -1 },
    { 0, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 },
}
-- Outline padding around a label's clip frames, as a fraction of its font
-- size. ponytail: a fixed fraction; raise it if it still clips.
local OUTLINE_PAD = 0.2
-- Border width as a share of the label's font size, so it thins with the text.
-- ponytail: starting point, tune in game.
local BORDER_RATIO = 0.05

local frame
local labelFrames = {}  -- [i] = { holder, outline = {run}, bands = {{clip, run}} }

--- UTF-8 characters of *s*, one string each, for letter spacing.
local function Chars(s)
    local out = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

--- A text copy: its FontStrings, created on *parent* (the holder, or a band's
--- clip) as they were before letter spacing. One per segment: a whole line, or
--- a letter when letter spacing or a horizontal gradient needs it placed or
--- coloured alone.
local function NewRun(parent, layer)
    return { parent = parent, layer = layer, fs = {} }
end

--- Lay *text* out in *run*, each FontString TOPLEFT-anchored to *anchor* at
--- (ax, ay): lines on rows, segments spaced by *gap* canvas units, each line
--- centred on the widest. *color* colours the run; *grad* ({a, b}) colours each
--- letter across the text instead. Returns the run's width and height.
local function SetRun(run, anchor, ax, ay, text, font, size, gap, color, grad)
    local perChar = gap ~= 0 or grad ~= nil
    local lines, total = {}, 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local segs = perChar and Chars(line) or { line }
        lines[#lines + 1] = segs
        total = total + #segs
    end

    local placed, widths, maxW, lineH = {}, {}, 0, 0
    local used, k = 0, 0
    for row, segs in ipairs(lines) do
        local x = 0
        for _, seg in ipairs(segs) do
            used = used + 1
            k = k + 1
            local fs = run.fs[used]
            if not fs then
                fs = run.parent:CreateFontString(nil, run.layer)
                fs:SetJustifyH("LEFT")
                run.fs[used] = fs
            end
            fs:SetFont(font, size, "")
            fs:SetText(seg)
            if grad then
                local t = total > 1 and (k - 1) / (total - 1) or 0
                fs:SetTextColor(grad[1][1] + (grad[2][1] - grad[1][1]) * t,
                    grad[1][2] + (grad[2][2] - grad[1][2]) * t,
                    grad[1][3] + (grad[2][3] - grad[1][3]) * t, 1)
            else
                fs:SetTextColor(color[1], color[2], color[3], 1)
            end
            fs:Show()
            lineH = math.max(lineH, fs:GetStringHeight())
            placed[#placed + 1] = { fs = fs, x = x, row = row }
            x = x + fs:GetStringWidth() + gap
        end
        widths[row] = #segs > 0 and x - gap or 0
        maxW = math.max(maxW, widths[row])
    end
    for i = used + 1, #run.fs do run.fs[i]:Hide() end
    for _, p in ipairs(placed) do
        p.fs:ClearAllPoints()
        p.fs:SetPoint("TOPLEFT", anchor, "TOPLEFT",
            ax + p.x + (maxW - widths[p.row]) / 2, ay - (p.row - 1) * lineH)
    end
    return maxW, #lines * lineH
end

--- One label: a holder frame with its outline copies behind and its text
--- bands in front. Positioned and painted by Paint.
local function NewLabel()
    local holder = CreateFrame("Frame", nil, frame)
    holder:EnableMouse(false)
    local l = { holder = holder, outline = {}, bands = {} }
    for i = 1, #OUTLINE_OFFSETS do
        l.outline[i] = NewRun(holder, "BACKGROUND")
    end
    return l
end

--- Position and colour one label centred on (x, y) from the canvas's
--- top-left, at *scale*. The border is copies of the text in the Outline colour,
--- BORDER_RATIO of the font size out. The fill is the Color of its kind, solid
--- or gradient. A horizontal gradient colours each letter across the label; a
--- vertical one is BANDS clipped copies, each in its band's colour from the top
--- (Color) to the bottom (Color2). *opaque* is true when the label is drawn at
--- full opacity. Bands blend twice where they meet once a label is translucent,
--- which shows as a line at every seam, so a translucent vertical gradient is
--- one copy in the gradient's middle colour instead.
local function Paint(l, label, x, y, scale, opaque)
    local key = KIND[label.kind].color
    local size = (label.h or DEFAULT_H[label.kind]) * FONT_PER_H * scale
    local a = Config.db[key .. "Color"]
    local b = a
    local dir = "HORIZONTAL"
    local gradient = Config.db[key .. "ColorMode"] == "gradient"
    if gradient then
        b = Config.db[key .. "Color2"]
        dir = Config.db[key .. "GradientDir"]
    end
    local vertical = gradient and dir == "VERTICAL"
    local banded = vertical and opaque
    local o = Config.db[key .. "Outline"]
    local grad = gradient and not vertical and { a, b } or nil
    local gap = Config.db[key .. "Spacing"] * size
    local font = FontFor(key)
    local shown = label.text or label.name
    if Config.db[key .. "Uppercase"] then shown = shown:upper() end

    local slices = 1
    if banded then
        local span = math.max(math.abs(b[1] - a[1]), math.abs(b[2] - a[2]),
            math.abs(b[3] - a[3])) * 255
        slices = math.min(MAX_BANDS, math.max(1, math.ceil(span / BAND_LEVELS)))
    end
    while #l.bands < slices do
        local clip = CreateFrame("Frame", nil, l.holder)
        l.bands[#l.bands + 1] = { clip = clip, run = NewRun(clip, "OVERLAY") }
    end

    local w, h = SetRun(l.bands[1].run, l.holder, 0, 0, shown, font, size, gap, a, grad)
    l.holder:SetSize(w, h)
    l.holder:ClearAllPoints()
    l.holder:SetPoint("CENTER", frame, "TOPLEFT", x, y)

    local pad = math.max(2, math.ceil(size * OUTLINE_PAD))
    local bw = size * BORDER_RATIO
    for i, run in ipairs(l.outline) do
        SetRun(run, l.holder, OUTLINE_OFFSETS[i][1] * bw, OUTLINE_OFFSETS[i][2] * bw,
            shown, font, size, gap, o, nil)
    end
    local overlap = 1 / frame:GetEffectiveScale()
    for i, band in ipairs(l.bands) do
        if i > slices then
            band.clip:Hide()
        else
            local c = a
            if banded then
                local t = slices > 1 and (i - 1) / (slices - 1) or 0
                c = {}
                for k = 1, 3 do c[k] = a[k] + (b[k] - a[k]) * t end
            elseif vertical then
                c = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }
            end
            -- Each band runs one screen pixel into the next, so a fractional
            -- clip edge cannot open a gap; the next band draws over the overlap.
            -- Only banded labels clip. The first and last extend by pad so the
            -- outline is not cut at the label's ends; the last also covers the
            -- descent below the holder.
            local top = (i - 1) * h / slices
            local bottom = i == slices and h + size or i * h / slices + overlap
            local up = i == 1 and pad or 0
            local down = i == slices and pad or 0
            band.clip:SetClipsChildren(banded)
            band.clip:SetSize(w + 2 * pad, bottom - top + up + down)
            band.clip:ClearAllPoints()
            band.clip:SetPoint("TOPLEFT", l.holder, "TOPLEFT", -pad, up - top)
            band.clip:Show()
            SetRun(band.run, l.holder, 0, 0, shown, font, size, gap, c, grad)
        end
    end
    l.holder:Show()
end

--- Fade one label to *alpha*. The outline is dark copies behind the fill, so a
--- translucent fill over it reads as dimmed. The outline fades out by half-way
--- instead, leaving the fill translucent over the map alone.
local function Fade(l, alpha)
    local halo = math.max(0, math.min(1, (alpha - 0.5) * 2))
    for _, run in ipairs(l.outline) do
        for _, fs in ipairs(run.fs) do fs:SetAlpha(halo) end
    end
    for _, band in ipairs(l.bands) do band.clip:SetAlpha(alpha) end
end

--- Size multiplier for a label of *kind*: the Global label scale, times that
--- kind's own label scale, times the inverse of the canvas zoom against its
--- loosest step when the kind's Auto-scale is on. The art and the labels
--- both scale with the canvas, so zooming out shrinks a label on screen;
--- Auto-scale grows it back by that ratio, and zooming in shrinks it.
local function AreaLabelScale(kind)
    local scale = Config.db.areaLabelScale * Config.db[KIND[kind].scale]
    local auto = KIND[kind].auto
    if not (auto and Config.db[auto]) then return scale end
    local sc = WorldMapFrame.ScrollContainer
    local levels = sc and sc.zoomLevels
    local base = levels and levels[1] and levels[1].scale
    local cur = sc and sc.currentScale
    if base and cur and cur > 0 then scale = scale * base / cur end
    return scale
end

--- Opacity of the labels. With Show on SD they are always fully visible.
--- Otherwise they fade in with the HD side of the blend, from 50% up to 100%.
local function AreaLabelAlpha()
    if Config.db.areaLabelShowOnSD then return 1 end
    return math.max(0, math.min(1, (Config:GetAlpha() - 0.5) * 2))
end

--- The canvas's current zoom ladder step, fractional between two entries. 0
--- is the loosest, the last index the tightest. Nil when the ladder isn't there.
local function LadderStep()
    local sc = WorldMapFrame.ScrollContainer
    local levels = sc and sc.zoomLevels
    local cur = sc and sc.currentScale
    if not (levels and cur and #levels > 0) then return nil end
    for k = 1, #levels - 1 do
        local a, b = levels[k].scale, levels[k + 1].scale
        if cur < b then return (k - 1) + math.max(0, (cur - a) / (b - a)) end
    end
    return #levels - 1
end

--- Opacity of a label of *kind* from zoom. 1 when the kind has no Fade when
--- zoomed, or it is off. Fully visible at the kind's Fully visible step and
--- fully hidden at its Fully invisible step, whichever order they come in
--- (the order sets the direction). Fade speed bends the curve between them:
--- 1 is linear; higher starts the change sooner and eases in at the far end;
--- lower holds the label until just before that end.
local function ZoomFade(kind)
    local key = KIND[kind].color
    if not Config.db[key .. "ZoomFade"] then return 1 end
    local step = LadderStep()
    step = step or 0 -- ladder not built yet: the zone view's default is level 0
    local vis = Config.db[key .. "FadeVisibleAt"]
    local inv = Config.db[key .. "FadeInvisibleAt"]
    if vis == inv then return step >= vis and 1 or 0 end
    if inv > vis and step < vis then
        -- Below the visible step, a fade-out label fades in from nothing at step 0
        -- up to full at the visible step. Fade-in speed bends it; 0 is a hard switch.
        local fin = Config.db[key .. "FadeInSpeed"]
        if fin == 0 then return 0 end
        return (step / vis) ^ (1 / fin)
    end
    local t = math.max(0, math.min(1, (step - vis) / (inv - vis)))
    if inv > vis then
        -- Fade-out: between the two ends. Fade-out speed bends it; 0 is a hard switch.
        local fout = Config.db[key .. "FadeOutSpeed"]
        if fout == 0 then return step >= inv and 0 or 1 end
        return (1 - t) ^ fout
    end
    -- Fade-in (subzone): between the two ends, using fade-in speed; 0 is a hard switch.
    local fin = Config.db[key .. "FadeInSpeed"]
    if fin == 0 then return step >= vis and 1 or 0 end
    return 1 - t ^ fin
end

--- Show or hide the labels for the map now on screen. Safe to call at any
--- time, before the map has ever been opened included.
function AreaLabels:Refresh()
    local canvas = WorldMapFrame.ScrollContainer
        and WorldMapFrame.ScrollContainer.Child
    local labels = {}
    local all = canvas and Config.db.enabled
        and AREA_LABELS[WorldMapFrame:GetMapID() or 0]
    -- Under Fog of War only explored areas are labelled; continent names always
    -- show. A label's overlay is its area's explored-texture key (see emitter).
    -- A subzone with no overlay key cannot be checked, so it stays hidden.
    local mapID = WorldMapFrame:GetMapID() or 0
    local fog = Config:FogOfWarEnabled() or Config:WorldFogOfWarEnabled(mapID)
    local explored, rects
    if fog then
        explored, rects = {}, {}
        for _, t in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
            explored[t.offsetX .. "," .. t.offsetY .. ","
                .. t.textureWidth .. "," .. t.textureHeight] = true
            rects[#rects + 1] = t
        end
    end
    -- Custom labels carry no overlay key: explored when their point lies in an
    -- explored texture (offsets are in the 1002x668 map space). Maps with no
    -- exploration overlays (cities) are never fogged.
    local function CustomExplored(p)
        if not (rects and (HFWMF_ZONE_OVERLAYS or {})[mapID]) then return true end
        local x, y = p.u * 1002, p.v * 668
        for _, t in ipairs(rects) do
            if x >= t.offsetX and x <= t.offsetX + t.textureWidth
                and y >= t.offsetY and y <= t.offsetY + t.textureHeight then
                return true
            end
        end
        return false
    end
    local custom, shadowed = {}, {}
    for _, p in ipairs(all and CUSTOM_LABELS[mapID] or {}) do
        local k = KIND[p.kind]
        if p.hide then
            shadowed[p.kind .. "|" .. p.name] = true
        elseif Config.db[k.show] and (p.kind == "poi" or Config.db[k.color .. "IncludeCustom"])
            and (p.kind == "continent" or CustomExplored(p)) then
            custom[#custom + 1] = p
            shadowed[p.kind .. "|" .. p.name] = true
        end
    end
    -- A shown custom label, or a hide entry, takes over a same-kind area label
    -- of the same name on this map. Other kinds coexist.
    for _, label in ipairs(all or {}) do
        if Config.db[KIND[label.kind].show]
            and (not explored or (label.overlay and explored[label.overlay])
                or (label.overlay == nil and label.kind ~= "subzone"))
            and not shadowed[label.kind .. "|" .. label.name] then
            labels[#labels + 1] = label
        end
    end
    for _, p in ipairs(custom) do labels[#labels + 1] = p end
    if #labels == 0 then
        if frame then frame:Hide() end
        return
    end

    if not frame then
        frame = CreateFrame("Frame", "HFWMForeverAreaLabels", canvas)
        frame:EnableMouse(false)
        frame:SetScript("OnSizeChanged", function() AreaLabels:Refresh() end)
    end
    -- Re-parent if the canvas was replaced, as Renderer does for the overlay.
    if frame:GetParent() ~= canvas then frame:SetParent(canvas) end
    frame:SetAllPoints(canvas)
    frame:SetFrameLevel(canvas:GetFrameLevel() + 501)
    frame:Show()
    local frameAlpha = AreaLabelAlpha()
    frame:SetAlpha(frameAlpha)

    local w, h = canvas:GetSize()
    for i, label in ipairs(labels) do
        local l = labelFrames[i]
        if not l then
            l = NewLabel()
            labelFrames[i] = l
        end
        local alpha = ZoomFade(label.kind) * Config.db[KIND[label.kind].color .. "Opacity"]
        Paint(l, label, label.u * w, -label.v * h, AreaLabelScale(label.kind),
            alpha * frameAlpha >= 1)
        Fade(l, alpha)
    end
    for i = #labels + 1, #labelFrames do
        labelFrames[i].holder:Hide()
    end
end

--- Re-lay the labels on every canvas zoom step, for Auto-scale. Called once
--- from Core.lua's PLAYER_LOGIN handler, same timing as the other modules.
function AreaLabels:Start()
    local sc = WorldMapFrame.ScrollContainer
    if not sc or not sc.OnCanvasScaleChanged then return end
    hooksecurefunc(sc, "OnCanvasScaleChanged", function() AreaLabels:Refresh() end)
end
