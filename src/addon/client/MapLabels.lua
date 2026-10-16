-------------------------------------------------------------------------------
-- HFWM-Forever Map Labels
--
-- "Extra Labels" on the world map. For now only Location Names
-- (Config.db.showLocationNames), and only the entries hand-written in
-- LOCATION_NAMES below; issue #17 will replace that with generated data.
--
-- Labels are small frames on one mouse-disabled frame on the map canvas,
-- above Config.overlayFrame (whose alpha changes with the SD/Hybrid/HD
-- background). They scale with the canvas, like the art under them.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config    = ns.Config
local MapLabels = ns.MapLabels

local WorldMapFrame = _G.WorldMapFrame

-- [uiMapID] = { { name, u, v }, ... }, u/v in 0-1 map coordinates from the
-- top-left. Placed by hand.
local LOCATION_NAMES = {
    -- Ironforge on the Dun Morogh map, from its world position (-4981, -881)
    -- and the map's UiMapAssignment bounds.
    [1426] = {
        { "Ironforge", 0.545, 0.336 },
    },
}

-- Friz Quadrata TT, the game's own UI font.
local FONT = "Fonts\\FRIZQT__.TTF"
local SIZE = 16
local TOP     = { 1.00, 0.92, 0.55 }  -- light gold
local BOTTOM  = { 0.85, 0.62, 0.12 }  -- slightly darker gold
local OUTLINE = { 0.30, 0.17, 0.06 }  -- brown
-- A FontString takes one colour, so the gradient is BANDS horizontal slices
-- of the same text, each in its own clip frame and in a colour between TOP
-- and BOTTOM. The game's own text outline is always black, so the brown one
-- is the text again, in brown, behind it, nudged 1 unit in each direction.
local BANDS = 6
local OUTLINE_OFFSETS = {
    { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, -1 },
    { 0, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 },
}

local frame
local labelFrames = {}

local function Text(parent, layer, color)
    local fs = parent:CreateFontString(nil, layer)
    fs:SetFont(FONT, SIZE, "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    return fs
end

--- One label: a holder frame with the brown copies behind and the gold
--- bands in front. Sized and positioned by Layout.
local function NewLabel()
    local holder = CreateFrame("Frame", nil, frame)
    holder:EnableMouse(false)
    local l = { holder = holder, outline = {}, bands = {} }
    for i = 1, #OUTLINE_OFFSETS do
        l.outline[i] = Text(holder, "BACKGROUND", OUTLINE)
    end
    for i = 1, BANDS do
        local t = (i - 1) / (BANDS - 1)
        local color = {}
        for c = 1, 3 do color[c] = TOP[c] + (BOTTOM[c] - TOP[c]) * t end
        local clip = CreateFrame("Frame", nil, holder)
        clip:SetClipsChildren(true)
        l.bands[i] = { clip = clip, fs = Text(clip, "OVERLAY", color) }
    end
    return l
end

--- Centre label *l* reading *name* on (x, y) from the canvas's top-left.
local function Layout(l, name, x, y)
    for i, fs in ipairs(l.outline) do
        fs:SetText(name)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", l.holder, "TOPLEFT",
            OUTLINE_OFFSETS[i][1], OUTLINE_OFFSETS[i][2])
    end
    local w, h = l.outline[1]:GetStringWidth(), l.outline[1]:GetStringHeight()
    l.holder:SetSize(w, h)
    l.holder:ClearAllPoints()
    l.holder:SetPoint("CENTER", frame, "TOPLEFT", x, y)
    for i, band in ipairs(l.bands) do
        band.clip:SetSize(w + 4, h / BANDS)
        band.clip:ClearAllPoints()
        band.clip:SetPoint("TOPLEFT", l.holder, "TOPLEFT",
            -2, -(i - 1) * h / BANDS)
        band.fs:SetText(name)
        band.fs:ClearAllPoints()
        band.fs:SetPoint("TOPLEFT", l.holder, "TOPLEFT")
    end
    l.holder:Show()
end

local function Hide()
    if not frame then return end
    frame:Hide()
    for _, l in ipairs(labelFrames) do l.holder:Hide() end
end

--- Show or hide the labels for the map now on screen. Safe to call at any
--- time, before the map has ever been opened included.
function MapLabels:Refresh()
    local canvas = WorldMapFrame.ScrollContainer
        and WorldMapFrame.ScrollContainer.Child
    local labels = canvas and Config.db.enabled and Config.db.showLocationNames
        and LOCATION_NAMES[WorldMapFrame:GetMapID() or 0]
    if not labels then return Hide() end

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
        labelFrames[i] = labelFrames[i] or NewLabel()
        Layout(labelFrames[i], label[1], label[2] * w, -label[3] * h)
    end
    for i = #labels + 1, #labelFrames do labelFrames[i].holder:Hide() end
end
