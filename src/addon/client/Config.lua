-------------------------------------------------------------------------------
-- HFWM-Forever Config
-- Defaults, AceDB-3.0 profile database, and overlay state tracking.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config = ns.Config

-- Defaults (persisted per-profile in HighFidelityWorldMapDB)
Config.DEFAULTS = {
    enabled       = true,
    -- HD/SD blend (ToggleButton's slider), remembered per map type.
    alphas        = { zone = 1.0, continent = 1.0, world = 1.0, city = 1.0 },
    mapBackground = "hybrid",  -- see Config.BACKGROUNDS below

    -- Per-map-type overrides of mapBackground above (now labelled "Global
    -- Background" in Options, since these three exist). "global" (the
    -- default for all three) means "inherit whatever mapBackground says";
    -- anything else must be one of Config.BACKGROUNDS' own keys. See the
    -- "Map background" section below for how these resolve at draw time.
    zoneMapBackground       = "global",
    continentMapBackground  = "global",
    worldMapBackground      = "global",
    cityMapBackground       = "blackout",

    -- Cave map: a window that opens over the world map when the player is
    -- somewhere the map above it has nothing to show (caves, mines, micro
    -- dungeons). On by default; turn it off from Options or /hfwm cave off.
    caveEnabled = true,
    caveAlpha   = 1,

    -- How the cave window decides to show itself, as opposed to whether
    -- the feature exists at all (caveEnabled above).
    --
    -- caveAutoOpen: show the window the instant a tracked cave is entered.
    -- Off means it waits at the reopen icon instead, until clicked.
    --
    -- caveRememberState: reproduce whichever of open/closed the window was
    -- left as last time, instead of the fixed rule above. Wins over
    -- caveAutoOpen when both apply.
    --
    -- caveLastVisible: true if the window's last state change was being
    -- shown; false if the player closed it. Only read when
    -- caveRememberState is on, but tracked unconditionally.
    -- caveKeepOpen: the window stays up after the world map is closed
    -- instead of closing with it.
    caveAutoOpen      = true,
    caveRememberState = false,
    caveLastVisible   = true,
    caveKeepOpen      = false,

    -- caveOtherIndoors: also open the window for buildings, houses and
    -- every other WMO interior (places the generator marks kind = "indoor"),
    -- not just caves, mines and dungeons. Off by default: there are far more
    -- of them and most are one-room houses.
    caveOtherIndoors  = false,

    -- Instance map: the same window inside dungeon ("party") and raid
    -- instances, independent of caveEnabled. Off by default (beta).
    instanceDungeonEnabled = false,
    instanceRaidEnabled    = false,

    -- cavePlacement: where the cave window sits by default.
    --   "outside":  beside the world map's right edge (the original behaviour)
    --   "inside":   in the map pane's top-left corner
    --   "remember": wherever the player last dragged it (caveWindowPoint
    --               below), falling back to "outside" until they have.
    cavePlacement     = "inside",

    -- caveWindowScale: multiplier (0.5..2) on the cave window's default size,
    -- so the window can be made bigger or smaller than the map-fraction
    -- sizing in CaveRenderer's LayoutWindow without changing where it sits.
    caveWindowScale   = 0.75,

    -- Cave map depth window: the real-world elevation range a per-piece
    -- place's rooms (currently just Fargodeep Mine) stay visible within,
    -- as two fractions (0..1) of that place's own [zMin, zMax] span.
    -- Dragged directly on the cave map's own depth slider rather than
    -- through Options; see CaveRenderer's height-window widget.
    caveHeightWindowTop    = 1.0,
    caveHeightWindowBottom = 0.0,

    -- Keep the world map at whatever zoom and pan it was left at, instead
    -- of resetting to the current zone every time it reopens -- the same
    -- job the separate PersistentWorldMap addon does. See MapMemory.lua.
    rememberMapZoomPan = true,

    -- Pans the world map to follow the player's arrow so it stays centered
    -- on screen. Off by default. See KeepCentered.lua.
    keepCentered = false,

    -- Appends 8 extra, closer zoom steps onto the world map so the
    -- native-resolution zone art this addon ships can be zoomed into past
    -- Blizzard's own ceiling. On by default. See ZoomLevels.lua.
    additionalZoomLevels = true,

    -- Draws the three continent/world maps (Kalimdor, Eastern Kingdoms,
    -- Azeroth) from the Art addon's hi-res tile grid instead of the low
    -- resolution set, one saved value per map type (Azeroth is the World
    -- map; Kalimdor and Eastern Kingdoms are Continent maps). On by
    -- default, but Config:MapClarityEnabled forces low resolution while the
    -- Art addon is missing or disabled, so no install is left without art.
    -- See HFWMF_NATIVE_ZONES' `continent` flag and GetNativeZone below.
    worldMapClarity = true,
    continentMapClarity = true,

    -- Fog of War on the Zone map: ground stays grayscale until explored,
    -- then switches to this addon's tiles cropped to Blizzard's own reveal
    -- shape. Only takes effect while the Zone Map background is Hybrid
    -- (the default). See Renderer's Activate() and DrawExploredPiece.
    fogOfWarEnabled = true,

    -- The "Fog of War" checkboxes beside the World Map and Continent Map
    -- dropdowns (Options), each offered under the same condition as
    -- fogOfWarEnabled above and saved separately. On: that map draws this
    -- addon's tiles only over zones explored in full. See ZoneFog.lua.
    worldFogOfWar = true,
    continentFogOfWar = true,

    -- The "sd"/"hd" button ToggleButton.lua docks in the world map's
    -- top-right corner, for flipping the HD/SD blend (`alpha` above)
    -- between all-SD and all-HD, without touching `enabled` above. On by
    -- default; turn off here for a cleaner map with one less button.
    toggleButtonEnabled = true,
    -- "Moveable toggle": lets the button be dragged within the map pane. Its
    -- position (db.toggleButtonPoint, below) is kept either way.
    toggleButtonMovable = true,

    -- The client's own Player and Cursor coordinate readouts on the world
    -- map (Coords.lua), each toggled from Options. On by default, as the
    -- client draws them; off hides that readout.
    showPlayerCoords = true,
    showMouseCoords  = true,

    -- Area Labels (AreaLabels.lua): names drawn on the map over its art, in six
    -- groups: continent names, capital cities, towns and hubs, points of
    -- interest, subzones, and city districts (only on a capital's own map).
    showAreaContinentNames = false,
    showAreaCapitalCities = true,
    showAreaTownsHubs = true,
    showAreaSubzoneNames = true,
    showAreaCityDistricts = true,
    -- Global label scale: multiplier (1..4) on every label. Options shows it
    -- halved, so the default 2 reads as 100%. Multiplies each type's own
    -- scale below. See AreaLabels.lua's AreaLabelScale.
    areaLabelScale = 2,
    -- Per-type label scales, each on top of areaLabelScale. Stored as the actual
    -- multiplier; the Options sliders show each as a percent of its default.
    continentAreaLabelScale = 1,
    capitalAreaLabelScale = 1.15,
    townAreaLabelScale = 1.3,
    subzoneAreaLabelScale = 0.18,
    districtAreaLabelScale = 1.3,
    -- Options' Area Labels sections: collapsed (only Enabled and the button
    -- show) or expanded, remembered per profile.
    continentAreaLabelCollapsed = true,
    capitalAreaLabelCollapsed = true,
    townAreaLabelCollapsed = true,
    subzoneAreaLabelCollapsed = true,
    districtAreaLabelCollapsed = true,
    poiAreaLabelCollapsed = true,
    -- Auto-scale per label type: labels grow as you zoom out and shrink as you
    -- zoom in, from their label scale at the loosest zoom step. See
    -- AreaLabels.lua's AreaLabelScale.
    continentAutoScale = false,
    capitalAutoScale = false,
    townAutoScale = false,
    districtAutoScale = false,
    -- Per-type label colour: Mode is "solid" (Color) or "gradient" (Color to
    -- Color2, along GradientDir: "HORIZONTAL" left to right, "VERTICAL" top
    -- to bottom). {r, g, b} 0..1. The default Color is the gold the labels
    -- are drawn in. See AreaLabels.lua's Paint.
    continentAreaLabelColorMode = "gradient",
    continentAreaLabelColor = { 252 / 255, 230 / 255, 120 / 255 },
    continentAreaLabelColor2 = { 1, 200 / 255, 90 / 255 },
    continentAreaLabelGradientDir = "VERTICAL",
    capitalAreaLabelColorMode = "gradient",
    capitalAreaLabelColor = { 252 / 255, 230 / 255, 120 / 255 },
    capitalAreaLabelColor2 = { 1, 200 / 255, 90 / 255 },
    capitalAreaLabelGradientDir = "VERTICAL",
    townAreaLabelColorMode = "solid",
    townAreaLabelColor = { 1, 247 / 255, 227 / 255 },
    townAreaLabelColor2 = { 1, 200 / 255, 90 / 255 },
    townAreaLabelGradientDir = "VERTICAL",
    subzoneAreaLabelColorMode = "solid",
    subzoneAreaLabelColor = { 1, 247 / 255, 227 / 255 },
    subzoneAreaLabelColor2 = { 1, 200 / 255, 90 / 255 },
    subzoneAreaLabelGradientDir = "VERTICAL",
    districtAreaLabelColorMode = "solid",
    districtAreaLabelColor = { 1, 247 / 255, 227 / 255 },
    districtAreaLabelColor2 = { 1, 200 / 255, 90 / 255 },
    districtAreaLabelGradientDir = "VERTICAL",
    -- Border per type: copies of the text in the Outline colour, BORDER_RATIO of
    -- the font size out (see AreaLabels.lua's Paint).
    continentAreaLabelOutline = { 52 / 255, 20 / 255, 5 / 255 },
    capitalAreaLabelOutline = { 52 / 255, 20 / 255, 5 / 255 },
    townAreaLabelOutline = { 52 / 255, 20 / 255, 5 / 255 },
    subzoneAreaLabelOutline = { 52 / 255, 20 / 255, 5 / 255 },
    districtAreaLabelOutline = { 52 / 255, 20 / 255, 5 / 255 },
    -- Fade when zoomed, per type. Two zoom ladder steps (0 furthest out, 11
    -- the most zoomed in) bound the fade: FadeVisibleAt is where the label is
    -- fully shown, FadeInvisibleAt where it is fully hidden. Speed sets how
    -- the curve bends between them; 1 is linear. Capital and town fade out
    -- as you zoom in, so their visible step is below the invisible one;
    -- subzone fades in, the other way round. Off, the label shows at every
    -- zoom. See AreaLabels.lua's ZoomFade.
    capitalAreaLabelZoomFade = true,
    capitalAreaLabelFadeVisibleAt = 0,
    capitalAreaLabelFadeInvisibleAt = 3,
    capitalAreaLabelFadeInSpeed = 1,
    capitalAreaLabelFadeOutSpeed = 1,
    townAreaLabelZoomFade = true,
    townAreaLabelFadeVisibleAt = 0,
    townAreaLabelFadeInvisibleAt = 3,
    townAreaLabelFadeInSpeed = 1,
    townAreaLabelFadeOutSpeed = 1,
    subzoneAreaLabelZoomFade = true,
    subzoneAreaLabelFadeVisibleAt = 11,
    subzoneAreaLabelFadeInvisibleAt = 3,
    subzoneAreaLabelFadeInSpeed = 1,
    subzoneAreaLabelFadeOutSpeed = 1,
    -- Districts fade out like capitals and towns, on by default.
    districtAreaLabelZoomFade = true,
    districtAreaLabelFadeVisibleAt = 0,
    districtAreaLabelFadeInvisibleAt = 3,
    districtAreaLabelFadeInSpeed = 1,
    districtAreaLabelFadeOutSpeed = 1,
    -- "Show on SD" (Options): labels stay fully visible across the whole HD/SD
    -- blend, not just its HD half. See AreaLabels' AreaLabelAlpha.
    areaLabelShowOnSD = false,
    -- Label fonts (AreaLabels.lua's Paint): a font file path from
    -- Config.AREA_LABEL_FONTS. areaLabelFont is the Global Font; each type's
    -- <color>Font is a path of its own, or "global" to follow the Global Font.
    areaLabelFont = "Fonts\\FRIZQT__.TTF",
    continentAreaLabelFont = "global",
    capitalAreaLabelFont = "global",
    townAreaLabelFont = "global",
    subzoneAreaLabelFont = "global",
    districtAreaLabelFont = "global",
    -- Uppercase (Options): draws the label's text in capital letters. Off by
    -- default.
    continentAreaLabelUppercase = false,
    capitalAreaLabelUppercase = false,
    townAreaLabelUppercase = false,
    subzoneAreaLabelUppercase = false,
    districtAreaLabelUppercase = false,
    poiAreaLabelUppercase = false,
    -- Letter spacing (Options): space between letters, as a fraction of the text
    -- size. 0 is the font's own spacing.
    continentAreaLabelSpacing = 0,
    capitalAreaLabelSpacing = 0,
    townAreaLabelSpacing = 0,
    subzoneAreaLabelSpacing = 0,
    districtAreaLabelSpacing = -0.07,
    poiAreaLabelSpacing = 0,
    -- Opacity (Options): base opacity of the type's labels, 0-1. Zoom fade
    -- and the HD blend scale it further.
    continentAreaLabelOpacity = 1,
    capitalAreaLabelOpacity = 1,
    townAreaLabelOpacity = 1,
    subzoneAreaLabelOpacity = 1,
    districtAreaLabelOpacity = 1,
    poiAreaLabelOpacity = 1,
    -- Include Custom (CustomLabels.lua): per type, also show the hand-kept
    -- labels of that type, replacing same-named labels from the game's own data.
    continentAreaLabelIncludeCustom = true,
    capitalAreaLabelIncludeCustom = true,
    townAreaLabelIncludeCustom = true,
    subzoneAreaLabelIncludeCustom = true,
    districtAreaLabelIncludeCustom = true,
    -- Points of Interest: CustomLabels.lua entries of kind "poi", always shown
    -- while this type is on (no Include Custom toggle of its own). Defaults
    -- match towns and hubs.
    showAreaPOIs = true,
    -- 60% of the Towns and hubs scale (1.3), which Options' Label scale reads against.
    poiAreaLabelScale = 0.78,
    poiAreaLabelColorMode = "solid",
    poiAreaLabelColor = { 1, 247 / 255, 227 / 255 },
    poiAreaLabelColor2 = { 1, 200 / 255, 90 / 255 },
    poiAreaLabelGradientDir = "VERTICAL",
    poiAreaLabelOutline = { 52 / 255, 20 / 255, 5 / 255 },
    poiAreaLabelZoomFade = true,
    poiAreaLabelFadeVisibleAt = 0,
    poiAreaLabelFadeInvisibleAt = 3,
    poiAreaLabelFadeInSpeed = 1,
    poiAreaLabelFadeOutSpeed = 1,
    poiAreaLabelFont = "global",
}

--- Fonts the Area Labels can use, in dropdown order. Blizzard ships these
--- with every client (the game swaps in a locale font where it must).
Config.AREA_LABEL_FONTS = {
    { path = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
    { path = "Fonts\\ARIALN.TTF",   label = "Arial Narrow" },
    { path = "Fonts\\MORPHEUS.TTF", label = "Morpheus" },
    { path = "Fonts\\SKURRI.TTF",   label = "Skurri" },
}
-- The db also carries `caveWindowPoint` -- { left, top }, the window's
-- TOPLEFT in UIParent units -- written by CaveRenderer when the window is
-- dragged under cavePlacement = "remember". Deliberately not in DEFAULTS:
-- absent means "wherever the window opens by default".
-- /hfwm cave reset clears it.
-- Likewise `toggleButtonPoint` -- { x, y } offset of the HD/SD button from
-- the map pane's TOPRIGHT, written when it's dragged. Absent = default spot,
-- which is what a profile reset gives back.

--- Cave map backdrop opacity (the dark fill behind the art, not the window
--- chrome), 0 (fully see-through) to 1.
---@return number
function Config:CaveAlpha()
    local a = self.db and self.db.caveAlpha or self.DEFAULTS.caveAlpha
    if type(a) ~= "number" then a = self.DEFAULTS.caveAlpha end
    return math.max(0, math.min(1, a))
end

-------------------------------------------------------------------------------
-- Cave height window
--
-- The rectangle CaveRenderer's height-window widget drags directly on the
-- cave map's depth slider: a top and bottom fraction (each 0..1 against
-- the shown place's aggregate [zMin, zMax]) bounding which elevation range
-- stays visible. Dragging an edge resizes the window; dragging the body
-- moves it as a unit.
-------------------------------------------------------------------------------

--- Smallest gap kept between top and bottom, so the window can never
--- collapse to nothing and become ungrabbable.
Config.HEIGHT_WINDOW_MIN_SPAN = 0.04

--- Current window bounds, clamped to 0..1 and ordered (top >= bottom).
---@return number top, number bottom
function Config:CaveHeightWindow()
    local top    = self.db and self.db.caveHeightWindowTop
    local bottom = self.db and self.db.caveHeightWindowBottom
    if type(top) ~= "number" then top = self.DEFAULTS.caveHeightWindowTop end
    if type(bottom) ~= "number" then
        bottom = self.DEFAULTS.caveHeightWindowBottom
    end
    top    = math.max(0, math.min(1, top))
    bottom = math.max(0, math.min(1, bottom))
    if top < bottom then top, bottom = bottom, top end
    return top, bottom
end

--- Cave window size multiplier, 0.5 (half the default size) to 2 (double).
---@return number
function Config:CaveWindowScale()
    local s = self.db and self.db.caveWindowScale
    if type(s) ~= "number" then s = self.DEFAULTS.caveWindowScale end
    return math.max(0.5, math.min(2, s))
end

--- Persist new window bounds. Order-independent (swapped if `top < bottom`)
--- and enforces HEIGHT_WINDOW_MIN_SPAN by pushing out whichever edge the
--- caller did *not* just move. Callers still need to push the change out to
--- anything already on screen -- see CaveRenderer's height-window widget.
---@param top number
---@param bottom number
function Config:SetCaveHeightWindow(top, bottom)
    top    = math.max(0, math.min(1, top or 1))
    bottom = math.max(0, math.min(1, bottom or 0))
    if top < bottom then top, bottom = bottom, top end
    if top - bottom < self.HEIGHT_WINDOW_MIN_SPAN then
        if bottom + self.HEIGHT_WINDOW_MIN_SPAN <= 1 then
            top = bottom + self.HEIGHT_WINDOW_MIN_SPAN
        else
            bottom = top - self.HEIGHT_WINDOW_MIN_SPAN
        end
    end
    if not self.db then return end
    self.db.caveHeightWindowTop    = top
    self.db.caveHeightWindowBottom = bottom
end

-------------------------------------------------------------------------------
-- Map background
--
-- The bundled BLPs leave the sea and every cell the terrain grid doesn't
-- cover transparent rather than baking in a colour or Blizzard's art, so
-- the backdrop is a runtime choice instead of a 175 MB regenerate.
--
-- What goes behind the tiles:
--   rgb          -> fill the canvas with this colour.
--   blizzardArt  -> leave the client's own detail-layer art showing through.
--   seeThrough   -> hide the map frame's own backing too, so the holes go
--                   all the way through the UI. See MapFrameBg.lua.
--   (none of the above) -> nothing behind the tiles.
--
-- Which tiles to draw:
--   tiles == nil  -> the bundled transparent art, FDID_MAP.
--   tiles         -> an alternate lookup table. Only "original" exists: a
--                     raw, un-alpha'd dump written under WorldMap/Original/
--                     when the pipeline runs with --original. Hidden by
--                     Config:BackgroundAvailable when that art isn't built.
--                     Labelled "Raw" everywhere a person sees it (Options,
--                     chat commands); `tiles = "original"` itself is left
--                     alone since it names the pipeline's own on-disk
--                     folder and generated lookup tables
--                     (HFWMF_FDID_MAP_ORIGINAL / HFWMF_NATIVE_ZONES_ORIGINAL,
--                     see FDIDMap.lua), not something this file controls.
--
-- Ordered: Options.lua builds its dropdown straight from this list.
--
-- One global choice ("mapBackground", labelled "Global Background" in
-- Options once the per-map-type overrides below exist) plus three optional
-- overrides -- zoneMapBackground/continentMapBackground/worldMapBackground
-- -- that each either name one of these same keys or "global", meaning
-- "follow mapBackground". See GetEffectiveMapTypeBackground/
-- GetBackgroundForMap below for how a map's actual background is resolved,
-- and Options.lua's "Map Background" section for the UI.
-------------------------------------------------------------------------------
Config.BACKGROUNDS = {
    {
        key   = "ocean",
        label = "Ocean Blue",
        -- The game's own coastal water colour (DEFAULT_OCEAN_COLOR).
        desc  = "One flat sea colour, measured from the game's own water.",
        rgb   = { 26 / 255, 50 / 255, 69 / 255 },
    },
    {
        key         = "hybrid",
        label       = "Hybrid",
        desc        = "Blizzard's hand-painted ocean, coast and border "
                   .. "underneath.",
        blizzardArt = true,
    },
    {
        key   = "raw",
        label = "Raw",
        desc  = "The raw stitch, blocky seams and all.",
        tiles = "original",
    },
    {
        key        = "transparent",
        label      = "Transparent",
        desc       = "No backdrop at all: the sea is a hole through the "
                  .. "map frame.",
        seeThrough = true,
    },
    {
        key   = "blackout",
        label = "Blackout",
        desc  = "Complete and total darkness... A black background.",
        rgb   = { 0, 0, 0 },
    },
}

--- Is this background's art actually installed?
--- Only ever false for an entry with its own tile set: a build without
--- --original never wrote WorldMap/Original/.
---@param bg table entry from Config.BACKGROUNDS
---@return boolean
function Config:BackgroundAvailable(bg)
    if bg.tiles == "original" then
        return next(self.FDID_MAP_ORIGINAL) ~= nil
    end
    return true
end

--- The FileDataID -> relative path table a background draws its tiles
--- from. Always returns a table.
---@param bg table entry from Config.BACKGROUNDS
---@return table
function Config:GetTileMap(bg)
    if bg and bg.tiles == "original" then
        return self.FDID_MAP_ORIGINAL
    end
    return self.FDID_MAP
end

--- The backgrounds this install can actually draw, in Config.BACKGROUNDS
--- order. Options.lua and Commands.lua both build from this.
---@return table[]
function Config:AvailableBackgrounds()
    local out = {}
    for _, bg in ipairs(self.BACKGROUNDS) do
        if self:BackgroundAvailable(bg) then
            out[#out + 1] = bg
        end
    end
    return out
end

--- Active background, falling back to the default on garbage or a saved
--- choice whose art isn't installed.
---@return table entry from Config.BACKGROUNDS
function Config:GetBackground()
    local want = self.db and self.db.mapBackground
    local available = self:AvailableBackgrounds()
    for _, bg in ipairs(available) do
        if bg.key == want then return bg end
    end
    for _, bg in ipairs(available) do
        if bg.key == self.DEFAULTS.mapBackground then return bg end
    end
    return available[1] or self.BACKGROUNDS[1]
end

--- Set the active background and redraw. Returns the entry, or nil if the
--- key isn't one this install offers.
---@param key string
function Config:SetBackground(key)
    for _, bg in ipairs(self:AvailableBackgrounds()) do
        if bg.key == key then
            if self.db then self.db.mapBackground = key end
            ns.Renderer:ForceRefresh()
            return bg
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Per-map-type background overrides
--
-- Zone Map, Continent Map and World Map (Config.MAP_TYPES) can each draw a
-- different background from the Global Background above -- e.g. Hybrid on
-- zones for its Fog of War support, Ocean Blue on the continent/world maps
-- where nothing needs to show through. Each is stored as either "global"
-- (the default: follow mapBackground) or one of Config.BACKGROUNDS' keys.
-------------------------------------------------------------------------------

--- {key, label} for the three map kinds that can each override the Global
--- Background. Options.lua builds its three indented dropdowns straight
--- from this list.
Config.MAP_TYPES = {
    { key = "zone",      label = "Zone Map" },
    { key = "continent", label = "Continent Map" },
    { key = "world",     label = "World Map" },
    { key = "city",      label = "City Map" },
}

--- The AceDB field one map type's override lives in.
---@param mapType string one of Config.MAP_TYPES' keys
---@return string
local function MapTypeField(mapType)
    return mapType .. "MapBackground"
end

--- Saved override for one map type: "global" (inherit the Global
--- Background), or one of Config.BACKGROUNDS' keys. Falls back to "global"
--- on garbage, nil, or a background this install can no longer draw, same
--- spirit as GetBackground's own fallback.
---@param mapType string
---@return string
function Config:GetMapTypeBackgroundKey(mapType)
    local want = self.db and self.db[MapTypeField(mapType)]
    if want == nil or want == "global" then return "global" end
    for _, bg in ipairs(self:AvailableBackgrounds()) do
        if bg.key == want then return want end
    end
    return "global"
end

--- Set one map type's override ("global" to inherit, or one of
--- Config.BACKGROUNDS' keys) and redraw.
---@param mapType string
---@param key string
---@return string|nil the key actually applied, or nil if unrecognised
function Config:SetMapTypeBackground(mapType, key)
    if key == "global" then
        if self.db then self.db[MapTypeField(mapType)] = "global" end
        ns.Renderer:ForceRefresh()
        return "global"
    end
    for _, bg in ipairs(self:AvailableBackgrounds()) do
        if bg.key == key then
            if self.db then self.db[MapTypeField(mapType)] = key end
            ns.Renderer:ForceRefresh()
            return key
        end
    end
    return nil
end

--- The background actually in force for one map type: its own override, or
--- the Global Background while that override is "global" (the default) or
--- names a background this install can no longer draw.
---@param mapType string
---@return table entry from Config.BACKGROUNDS
function Config:GetEffectiveMapTypeBackground(mapType)
    local key = self:GetMapTypeBackgroundKey(mapType)
    if key ~= "global" then
        for _, bg in ipairs(self:AvailableBackgrounds()) do
            if bg.key == key then return bg end
        end
    end
    return self:GetBackground()
end

-- Enum.UiMapType is Cosmic=0, World=1, Continent=2, Zone=3, Dungeon=4,
-- Micro=5, Orphan=6 (same convention Cave.lua reads it under). Only these
-- three get their own override; every other kind (caves, dungeons,
-- transport/scenario orphans) draws the Global Background, same as before
-- this setting existed.
local UI_MAP_TYPE = (Enum and Enum.UiMapType) or {}
local MAP_TYPE_BY_UI_TYPE = {
    [UI_MAP_TYPE.World     or 1] = "world",
    [UI_MAP_TYPE.Continent or 2] = "continent",
    [UI_MAP_TYPE.Zone      or 3] = "zone",
}

-- The six capitals (Classic Era UiMapIDs). The client types them Zone, but
-- they get their own background, HD/SD blend and Options row.
local CITY_MAP_IDS = {
    [1453] = true, [1454] = true, [1455] = true,  -- Stormwind, Orgrimmar, Ironforge
    [1456] = true, [1457] = true, [1458] = true,  -- Thunder Bluff, Darnassus, Undercity
}

--- Which of Config.MAP_TYPES *mapID* is, or nil if it's some other kind
--- that doesn't get its own override. Cities are "city", not "zone".
---@param mapID number|nil
---@return string|nil
function Config:ClassifyMapID(mapID)
    if CITY_MAP_IDS[mapID] then return "city" end
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and MAP_TYPE_BY_UI_TYPE[info.mapType] or nil
end

--- The background Renderer should actually draw *mapID* with: that map's
--- own type override if it has one and it's set, otherwise the Global
--- Background. This is the one entry point Renderer.lua calls; everything
--- above exists to support it and the Options UI.
---@param mapID number|nil
---@return table entry from Config.BACKGROUNDS
function Config:GetBackgroundForMap(mapID)
    local mapType = self:ClassifyMapID(mapID)
    if not mapType then return self:GetBackground() end
    return self:GetEffectiveMapTypeBackground(mapType)
end

-- FileDataID lookup tables (populated from FDIDMap.lua)
Config.FDID_MAP          = HFWMF_FDID_MAP          or {}
Config.FDID_MAP_SUB      = HFWMF_FDID_MAP_SUB      or {}
-- The raw second dump, written only when the pipeline ran with --original.
-- Its paths carry their own "Original\\" prefix, so FDID_BASE serves both.
Config.FDID_MAP_ORIGINAL = HFWMF_FDID_MAP_ORIGINAL or {}
-- The low-resolution World and continent art (WorldMap\*.blp, the tiles the
-- two tables above point at) ships inside this addon, so every map type works
-- without anything else installed.
Config.FDID_BASE = "Interface\\AddOns\\" .. addonName .. "\\WorldMap\\"
-- The zone outlines the World/Continent Fog of War crops the map with (see
-- ZoneFog.lua); committed, unlike WorldMap\ above, which is generated.
Config.MASK_BASE = "Interface\\AddOns\\" .. addonName .. "\\ZoneMasks\\"
-- The high-resolution art (NATIVE_ZONES below) ships in the separate,
-- optional Art addon (src/addon/art) so a client update is not a 1 GB
-- download. Tiles are drawn from here only while it is installed.
Config.ART_ADDON = "HighFidelityWorldMap_Art_Forever"
Config.HD_BASE   = "Interface\\AddOns\\" .. Config.ART_ADDON .. "\\WorldMap\\"

--- Is the Art addon installed and enabled? Without it the World and
--- continent maps are drawn at low resolution only (the High Resolution
--- option in Options is disabled); zone and cave maps do not use it.
--- No load-order dependency: the Art addon requires this one, and this is
--- only asked at draw and options time, after both have loaded.
---@return boolean
function Config:IsArtInstalled()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return isLoaded and isLoaded(self.ART_ADDON) and true or false
end

-- Higher-resolution continent/world maps (see hfwm/gamedata/db2.py's
-- _hires_geometry and hfwm/lua/fdid_map.py): Kalimdor/Eastern Kingdoms/the
-- top-level Azeroth map, capped -- see HIRES_CONTINENT_MAPS.
-- Keyed by UiMapID: Renderer.lua uses this geometry and path prefix
-- directly instead of C_Map.GetMapArtLayers/GetMapArtLayerTextures.
Config.NATIVE_ZONES          = HFWMF_NATIVE_ZONES          or {}
Config.NATIVE_ZONES_ORIGINAL = HFWMF_NATIVE_ZONES_ORIGINAL or {}

-- Zone maps are not shipped as art: they are placements of the client's own
-- minimap tiles (MinimapTiles.lua), keyed by UiMapID.
Config.MINIMAP_ZONES = HFWMF_MINIMAP_ZONES or {}
-- Underground capitals (Ironforge, Undercity), whose minimap tiles are the
-- mountain above: same shape plus `submap`, a baked cave canvas (see
-- GetCaveComposite) and the box of it the city's map shows (SubMaps.lua).
Config.SUB_MAPS = HFWMF_SUB_MAPS or {}

---@param mapID number
---@return table|nil
function Config:GetClientZone(mapID)
    return self.MINIMAP_ZONES[mapID] or self.SUB_MAPS[mapID]
end

-- Baked cave floors/pieces as placements of the client's own WMO minimap
-- tiles (CaveTiles.lua), keyed by the synthetic FDIDs CaveData.lua uses.
Config.CAVE_TILES = HFWMF_CAVE_TILES or {}
-- The same for every other indoor area (IndoorTiles.lua).
Config.INDOOR_TILES = HFWMF_INDOOR_TILES or {}

---@param fdid number
---@return table|nil
function Config:GetCaveComposite(fdid)
    return self.CAVE_TILES[fdid] or self.INDOOR_TILES[fdid]
end

--- Draw a baked canvas from the client's own WMO group minimap tiles
--- (scripts/emit_cave_tiles.py) instead of one shipped BLP. Each leaf is a
--- region of a game texture, centred at (cx, cy) in the rotated canvas. The
--- quad is the bounding box of that region once rotated by comp.a, and the
--- eight-value SetTexCoord maps each quad corner back to the point of the
--- source it shows; with CLAMPTOBLACKADDITIVE everything sampled outside the
--- texture is transparent, so the corners vanish.
---@param comp table  { w, h, a, l = { {fdid, srcW, srcH, x0, y0, w, h, cx, cy, dw, dh, sub}, ... } }
---@param parent table  frame the quads are anchored to
---@param scaleX number  parent px per canvas px
---@param scaleY number
---@param offX number  where the canvas's top-left sits in parent
---@param offY number
---@param acquire function  (sub) returns a fresh texture, already on `parent`; sub is the leaf's 0..15 layer, or nil, for the caller to put on ARTWORK sublevel sub - 8 (the game leaves same-sublevel paint order undefined)
---@param clip table|nil  { x0, y0, x1, y1 } canvas box; art outside it is cut
---@return table textures  everything drawn, in paint order
function Config:DrawComposite(comp, parent, scaleX, scaleY, offX, offY, acquire, clip)
    local rad = math.rad(comp.a)
    local c, s = math.cos(rad), math.sin(rad)
    local ac, as = math.abs(c), math.abs(s)
    local drawn = {}
    for _, leaf in ipairs(comp.l) do
        local fdid, sw, sh, x0, y0, w, h, cx, cy, dw, dh, sub = unpack(leaf)
        -- The quad is the bounding box of the dw x dh rect once rotated; the
        -- region w x h is stretched over it (kx, ky), so a room can grow to
        -- meet its neighbour.
        local kx, ky = w / dw, h / dh
        local hx, hy = (dw * ac + dh * as) / 2, (dw * as + dh * ac) / 2
        local mx, my = x0 + w / 2, y0 + h / 2
        -- Quad edges, cut to the clip box. The source UVs are linear in the
        -- offset from the leaf centre, so cutting an edge just moves its
        -- corners' offsets.
        local l, r, t, b = cx - hx, cx + hx, cy - hy, cy + hy
        if clip then
            l, r = math.max(l, clip[1]), math.min(r, clip[3])
            t, b = math.max(t, clip[2]), math.min(b, clip[4])
        end
        if r > l and b > t then
            -- Quad corner at offset (dx, dy) from the leaf centre -> source UV.
            local function uv(dx, dy)
                return (mx + (dx * c - dy * s) * kx) / sw,
                       (my + (dx * s + dy * c) * ky) / sh
            end
            local ulx, uly = uv(l - cx, t - cy)
            local llx, lly = uv(l - cx, b - cy)
            local urx, ury = uv(r - cx, t - cy)
            local lrx, lry = uv(r - cx, b - cy)

            local tex = acquire(sub)
            tex:SetSize((r - l) * scaleX, (b - t) * scaleY)
            tex:SetPoint("TOPLEFT", parent, "TOPLEFT",
                offX + l * scaleX, -(offY + t * scaleY))
            tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
            tex:SetTexture(fdid, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            drawn[#drawn + 1] = tex
        end
    end
    return drawn
end

--- Higher-resolution geometry for *mapID* under the given background, or
--- nil if this map has no such art, the specific dump the background
--- wants wasn't built, or (for the three capped continent maps) "Increase
--- world map clarity" is off. Renderer.lua falls back to the ordinary
--- FDID path whenever this returns nil.
---@param mapID number
---@param bg table entry from Config.BACKGROUNDS
---@return table|nil
function Config:GetNativeZone(mapID, bg)
    local t = (bg and bg.tiles == "original")
        and self.NATIVE_ZONES_ORIGINAL or self.NATIVE_ZONES
    local entry = t[mapID]
    if entry and entry.continent
       and not self:MapClarityEnabled(self:ClassifyMapID(mapID)) then
        return nil
    end
    return entry
end

--- Whether the capped continent maps of *mapType* ("world" = Azeroth,
--- "continent" = Kalimdor/Eastern Kingdoms) draw from the Art addon's
--- hi-res tile grid. Always false while that addon is missing, whatever was
--- saved. Zone maps always draw at native resolution regardless.
---@param mapType string|nil
---@return boolean
function Config:MapClarityEnabled(mapType)
    local on = self.db and ((mapType == "world" and self.db.worldMapClarity)
        or (mapType == "continent" and self.db.continentMapClarity))
    return (on and self:IsArtInstalled()) or false
end

--- Whether this addon's tiles draw only over ground the player has
--- actually explored, with Blizzard's original grayscale art left visible
--- elsewhere.
---
--- Only ever true while the Zone Map background is actually Hybrid --
--- directly, or by inheriting a Hybrid Global Background -- since the
--- grayscale-until-explored look this reproduces IS Blizzard's own detail
--- layer, which only Hybrid leaves showing through underneath. Options.lua
--- greys the toggle out under the same condition; the saved value itself is
--- left alone so it picks back up automatically once Zone Map is Hybrid
--- again, rather than being silently cleared.
---@return boolean
function Config:FogOfWarEnabled()
    return (self.db and self.db.fogOfWarEnabled and self:ZoneBackgroundIsHybrid()) or false
end

--- Is the effective background of *mapType* ("zone"/"continent"/"world")
--- Hybrid? Fog of War shows Blizzard's own art through the unexplored
--- ground, which only Hybrid leaves visible, so each map type's Fog of War
--- checkbox in Options hangs off that map type's own background.
---@param mapType string
---@return boolean
function Config:MapTypeBackgroundIsHybrid(mapType)
    local bg = self:GetEffectiveMapTypeBackground(mapType)
    return bg ~= nil and bg.key == "hybrid"
end

function Config:ZoneBackgroundIsHybrid()
    return self:MapTypeBackgroundIsHybrid("zone")
end

--- Is the World or Continent Fog of War checkbox (Options, beside each map's
--- dropdown) in force on *mapID*? Each map type has its own saved value and
--- is only armed while that map type's own background is Hybrid. When true,
--- Renderer draws this addon's tiles only over zones the player has fully
--- explored (ZoneFog.lua).
---@param mapID number|nil
---@return boolean
function Config:WorldFogOfWarEnabled(mapID)
    if not self.db then return false end
    local mapType = self:ClassifyMapID(mapID)
    if mapType == "world" then
        return self.db.worldFogOfWar == true and self:MapTypeBackgroundIsHybrid("world")
    elseif mapType == "continent" then
        return self.db.continentFogOfWar == true and self:MapTypeBackgroundIsHybrid("continent")
    end
    return false
end

--- Is the client's native gamepad UI (Options > Gamepad > Enable Gamepad UI)
--- the active input style? Same test Blizzard's own InputUtil makes. False
--- on any client without the API.
---@return boolean
function Config:IsGamepadUI()
    return C_InputInterfaceStyle ~= nil
        and C_InputInterfaceStyle.GetCurrentStyle()
            == Enum.InputDeviceInterfaceType.Gamepad
end

local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG",
    "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

--- The frame strata one above *strata* (TOOLTIP stays TOOLTIP, unknown names
--- come back unchanged).
---@param strata string
---@return string
function Config:StrataAbove(strata)
    for i, s in ipairs(STRATA_ORDER) do
        if s == strata then return STRATA_ORDER[math.min(i + 1, #STRATA_ORDER)] end
    end
    return strata
end

--- Parent for HFWM's own widgets that sit on the world map. Under the gamepad
--- UI, Blizzard's SmartNavigation and FrameControlsManager walk WorldMapFrame's
--- children and run Blizzard binding code over whatever they find, so
--- addon frames there taint that code. Those widgets hang off a host frame on
--- UIParent instead (see InitMapHost). Otherwise the map itself, as before.
---@return Frame
function Config:MapWidgetParent()
    return self.mapHost or WorldMapFrame
end

--- Make the host follow the map: shown with it, same scale, one strata above
--- it (so a click that Raise()s the map never buries a widget; same trick the
--- cave window uses).
function Config:SyncMapHost()
    local host = self.mapHost
    if not host then return end
    local scale = WorldMapFrame:GetScale()
    if host:GetScale() ~= scale then host:SetScale(scale) end
    local strata = self:StrataAbove(WorldMapFrame:GetFrameStrata())
    if host:GetFrameStrata() ~= strata then host:SetFrameStrata(strata) end
    host:SetShown(WorldMapFrame:IsShown())
end

--- Create the host, once, only when the gamepad UI may be in play. Must run
--- before any module creates a widget and before Core's own OnShow/OnHide
--- hooks are registered, so the host is already shown when they run.
--- (Decided at load, like every other IsGamepadUI gate: /reload to switch.)
function Config:InitMapHost()
    if self.mapHost or not self:IsGamepadUI() then return end
    local host = CreateFrame("Frame", "HFWMForeverMapHost", UIParent)
    host:SetAllPoints(WorldMapFrame)
    self.mapHost = host
    self:SyncMapHost()
    WorldMapFrame:HookScript("OnShow", function() Config:SyncMapHost() end)
    WorldMapFrame:HookScript("OnHide", function() Config:SyncMapHost() end)
    WorldMapFrame:HookScript("OnSizeChanged", function() Config:SyncMapHost() end)
end

--- Is the HD/SD slider (ToggleButton's right-click popup) below 100%? Then
--- the overlay is drawn at that alpha over Blizzard's own stock map, left
--- visible underneath, so the result is an exact HD/SD mix. Renderer's
--- Activate and Exploration's pin re-hiding both key off this. The
--- threshold absorbs slider step rounding near the top.
---@return boolean
function Config:IsMixing()
    return self.db ~= nil and self:GetAlpha() < 0.995
end

--- Blend of the map currently shown. Maps that aren't world/continent/zone
--- (caves, dungeons) share the zone value.
---@return number
function Config:GetAlpha()
    local mapType = self:ClassifyMapID(WorldMapFrame:GetMapID()) or "zone"
    return self.db.alphas[mapType]
end

---@param value number
function Config:SetAlpha(value)
    local mapType = self:ClassifyMapID(WorldMapFrame:GetMapID()) or "zone"
    self.db.alphas[mapType] = value
end

-- Vashj'ir UiMapIDs -- retail-only (Cataclysm). WoW Forever has no
-- Vashj'ir, so this is intentionally empty. Kept so Renderer.lua stays
-- structurally identical to the retail addon.
Config.VASHJIR_MAPS = {}

-- Runtime state (shared mutable, referenced by all modules)
Config.db              = nil   -- ref to the active AceDB profile
Config.dbObj           = nil   -- the AceDB-3.0 database object
Config.overlayFrame    = nil   -- Frame parented to the map canvas
Config.backdropTexture = nil   -- flat colour drawn under the tiles (Renderer)
Config.overlayActive   = false
Config.refreshPending  = false
Config.lastCanvas      = nil   -- WorldMapFrame.ScrollContainer.Child identity
Config.lastCanvasW     = 0
Config.lastCanvasH     = 0
Config.lastMapID       = nil
Config.lastLayerIdx    = nil
Config.lastSubmerged   = nil
Config.tracing         = false

-- Cave map runtime state (the window itself is built by CaveRenderer)
Config.caveOverlayFrame      = nil   -- the cave window frame
Config.caveContentFrame      = nil   -- clipping frame the cave tiles live in
Config.caveOverlayActive     = false
Config.caveCurrentFloorMapID = nil   -- floor on screen right now
Config.caveAllFloors         = nil   -- [{mapID, name, relativeHeightIndex}, ...]
Config.caveFloorPinned       = false -- user drove the depth slider; stop following them
-- The floor dropdown's own state (see CaveRenderer's floor-picker
-- section): true (the default) layers every floor together; false scopes
-- both the rendered art and the depth slider to Config.caveCurrentFloorMapID
-- alone. Reset to true whenever the window closes, same as caveFloorPinned.
Config.caveFloorFilterAll    = true
Config.caveSuppressedKey     = nil   -- map group the user closed; don't reopen it
-- Map group Cave:UpdateState has already decided Open Automatically /
-- Remember State for, this visit. Cleared unconditionally on every
-- "player is not in a cave" tick, same moment as caveSuppressedKey.
Config.caveDecidedKey        = nil
-- ESC hid the window (see Core.lua). Unlike caveSuppressedKey it is not a
-- "closed" decision: no reopen icon, no Remember State write. Holds the
-- window down until the world map is next shown or the player leaves.
Config.caveEscHidden         = false
Config.caveDisplayedMapID    = nil   -- world-map UiMapID displayed (change detection)
Config.lastPlayerMapID       = nil   -- GetBestMapForUnit cache (change detection)

-- Cache lookup-table sizes for diagnostics
do
    local function count(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end
    Config._fdidMapSize         = count(Config.FDID_MAP)
    Config._fdidMapOriginalSize = count(Config.FDID_MAP_ORIGINAL)
    Config._nativeZonesSize         = count(Config.NATIVE_ZONES)
    Config._nativeZonesOriginalSize = count(Config.NATIVE_ZONES_ORIGINAL)
end

-- Saved background keys that have been renamed. "default" was the
-- original name for what turned out to be simply a transparent map.
-- "original" was Options.lua's old name for the raw stitch, replaced by
-- "raw" once the per-map-type overrides made "Original" easy to misread as
-- "the default choice". Applied to every background field on every
-- profile load (see MigrateBackgroundKeys below), not just the legacy
-- flat-file upgrade this table used to serve alone, so nobody's saved
-- choice silently reverts to Ocean Blue just because its key changed under
-- it.
local BACKGROUND_RENAMES = {
    default   = "transparent",
    original  = "raw",
}

-- Every AceDB field a background choice (global or per-map-type) can be
-- stored under. Kept as one list so a future addition only has to happen
-- here and in Config.DEFAULTS/Config.MAP_TYPES.
local BACKGROUND_FIELDS = {
    "mapBackground", "zoneMapBackground", "continentMapBackground",
    "worldMapBackground", "cityMapBackground",
}

--- Apply BACKGROUND_RENAMES to every background field on *profile* (a
--- db.profile-shaped table, or the old flat SavedVariables table, which
--- has the same field names at its top level). Idempotent: safe to call on
--- every profile load, not just once at upgrade time.
---@param profile table
local function MigrateBackgroundKeys(profile)
    if type(profile) ~= "table" then return end
    for _, field in ipairs(BACKGROUND_FIELDS) do
        local renamed = BACKGROUND_RENAMES[profile[field]]
        if renamed then profile[field] = renamed end
    end
end

--- Move an old, pre-AceDB flat SavedVariables table (one profile, no
--- concept of `.profiles`) onto the AceDB profile shape, so upgrading
--- doesn't lose anyone's settings. No-op on a database that's already in
--- the new shape, or has none at all yet.
---@param dbObj table AceDB-3.0 database object
local function MigrateFlatSavedVariables(dbObj)
    local raw = HighFidelityWorldMapDB
    if type(raw) ~= "table" or raw.profiles then return end

    MigrateBackgroundKeys(raw)

    for k in pairs(Config.DEFAULTS) do
        if raw[k] ~= nil then
            dbObj.profile[k] = raw[k]
            raw[k] = nil
        end
    end
    if raw.caveWindowPoint then
        dbObj.profile.caveWindowPoint = raw.caveWindowPoint
        raw.caveWindowPoint = nil
    end
end

--- Re-point Config.db at the active profile and push the change out to
--- everything that caches state derived from it. Bound to AceDB's profile
--- callbacks below, so switching, copying or resetting a profile takes
--- effect immediately.
function Config:RefreshProfile()
    self.db = self.dbObj.profile
    MigrateBackgroundKeys(self.db)
    ns.Renderer:ForceRefresh()
    ns.ToggleButton:Refresh()
    ns.ZoomLevels:Refresh()
    ns.Cave:UpdateState()
    ns.Options:Refresh()
    ns.AreaLabels:Refresh()
end

--- Create the AceDB-3.0 database after ADDON_LOADED (see Core.lua's
--- OnInitialize). `true` as the default profile shares one profile across
--- every character by default, matching this addon's behavior before
--- profiles existed; AceDBOptions still lets anyone split off a
--- character-specific profile from Options.
function Config:InitDB()
    local isUpgrade = type(HighFidelityWorldMapDB) == "table"
        and not HighFidelityWorldMapDB.profiles

    self.dbObj = LibStub("AceDB-3.0"):New(
        "HighFidelityWorldMapDB", { profile = self.DEFAULTS }, true)

    if isUpgrade then
        MigrateFlatSavedVariables(self.dbObj)
    end

    self.dbObj.RegisterCallback(self, "OnProfileChanged", "RefreshProfile")
    self.dbObj.RegisterCallback(self, "OnProfileCopied", "RefreshProfile")
    self.dbObj.RegisterCallback(self, "OnProfileReset", "RefreshProfile")

    self.db = self.dbObj.profile
    MigrateBackgroundKeys(self.db)
end
