-------------------------------------------------------------------------------
-- HFWM-Forever Cave
--
-- Decides *whether* there is a cave map to show and *which floor* it should
-- be showing; CaveRenderer owns the window that shows it.
--
-- The case this exists for: the player walks into a cave, a mine, or a
-- vault, anything the client models as its own UiMapID, and the world map
-- carries on showing the zone above, which has nothing to say about where
-- they now are. When the map the player is standing on differs from the map
-- on screen and is an interior type, the cave window opens over the top.
--
-- Two things are deliberately *not* automatic:
--
--   * A cave the user closed stays closed until they leave it. Re-opening it
--     the moment the poll next runs would make the close button useless, and
--     the suppression is keyed on the map group so that walking between
--     floors of a dungeon the user dismissed does not bring it back.
--   * A floor the user picked on the depth slider stays picked while they are
--     still in the same cave. Floor follow-along is the default, but browsing
--     the level below you is the whole reason the slider is there.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Cave   = ns.Cave
local Config = ns.Config
local P      = ns.P

-- Map types that should trigger the cave window.
--
-- Enum.UiMapType is Cosmic=0, World=1, Continent=2, Zone=3, Dungeon=4,
-- Micro=5, Orphan=6. Read from the client where offered, with these numbers
-- as fallback for a build that predates the enum.
--
-- Dungeon and Micro are the two interior kinds:
--
--   Dungeon  a dungeon or raid map, one UiMapID per floor, grouped by
--            C_Map.GetMapGroupID.
--   Micro    small interiors scattered through the outdoor world: caves,
--            mines, huts, cellars, vaults. This is the case the feature
--            exists for, since the world map has no way to navigate to them
--            and just keeps showing the zone above.
--
-- Orphan is excluded: an orphan map has no parent in the map hierarchy, which
-- is about map plumbing, not about being indoors. The few that exist here are
-- transport and scenario scaffolding, and a cave window over them would just
-- be noise.
local UI_MAP_TYPE = (Enum and Enum.UiMapType) or {}
local CAVE_MAP_TYPES = {
    [UI_MAP_TYPE.Dungeon or 4] = true,
    [UI_MAP_TYPE.Micro   or 5] = true,
}

local POLL_INTERVAL = 0.5
local pollFrame
local elapsedSincePoll = 0

-------------------------------------------------------------------------------
-- Sources
--
-- Everything below this point asks the same handful of questions about an
-- interior: where is the player, which floors does this place have, what art
-- draws them, where does the pin go. On any given build only one thing can
-- answer them:
--
--   ClientSource   C_Map. Works wherever the client's UiMap table carries
--                  Dungeon and Micro rows, which is every retail build and no
--                  1.x one.
--
--   BakedSource    CaveData.lua, read through ns.CaveTable. The rows this
--                  build's UiMap does not have, rebuilt offline from retail's
--                  map plumbing, validated against this build's own art and
--                  AreaTable, and shipped with the addon. Its floor IDs are
--                  synthetic (4000001 up) and never handed to a C_Map
--                  function; see CaveTable.lua.
--
-- Both sit behind one interface so nothing further down, including
-- CaveRenderer, has to know which one is talking. C_Map stays preferred where
-- it has anything to say: a client with real interior maps knows more about
-- them than a table baked against a different build, and if this beta ever
-- ships those rows the addon should quietly switch to using them.
-------------------------------------------------------------------------------

local ClientSource, BakedSource

--- Is this UiMapID one of the interior kinds?
---@param mapID number|nil
---@return boolean
local function IsClientInteriorMap(mapID)
    if not mapID then return false end
    local info = C_Map.GetMapInfo(mapID)
    return (info and CAVE_MAP_TYPES[info.mapType]) and true or false
end

ClientSource = {
    name = "client",

    --- The UiMapID the player is physically standing on (specific floor).
    ---
    --- Two APIs answer this and they do not always agree, which matters since
    --- the whole feature hangs off the answer:
    ---
    ---   C_Map.GetBestMapForUnit resolves the player's *world position* to a
    ---   map. A micro dungeon has its own coordinate space, and the position
    ---   only lands in it once the player is properly inside; on the threshold
    ---   this still says "the zone".
    ---
    ---   C_Minimap.GetUiMapID reports the map the *minimap* has swapped its
    ---   art to. That swap is the client stating it now considers the player
    ---   to be in the interior, driven by the map's own bounds rather than a
    ---   position lookup, so on the way in it is usually first.
    ---
    --- Neither is reliably ahead of the other, so an interior answer from
    --- either one is taken as the answer, with the position lookup winning
    --- ties. Trusting position alone would leave the window a beat behind the
    --- minimap the player is already looking at.
    ---
    --- Deliberately *not* consulted: IsOutdoors(). It is true in many
    --- interiors with no map of their own (every inn, every tower) and false
    --- in some caves, so as a gate here it would fire spuriously and miss.
    --- The baked source below does use it, but for a different job: not
    --- detecting a cave but telling standing in a mine from standing on the
    --- hill above it, once the name has already said which mine; see
    --- CaveTable.lua's FindPlayerFloor, which gates on it unconditionally.
    ---
    --- Second return, `confident`: always true. Both APIs here are direct
    --- client answers about the player's real position, never a guess or a
    --- deferral to whatever floor is already on screen, so this source has
    --- nothing to be unconfident about.
    CurrentFloor = function()
        local best = C_Map.GetBestMapForUnit("player")
        if IsClientInteriorMap(best) then return best, true end

        if C_Minimap and C_Minimap.GetUiMapID then
            local mini = C_Minimap.GetUiMapID()
            if IsClientInteriorMap(mini) then return mini, true end
        end

        return best, true
    end,

    IsInterior = IsClientInteriorMap,

    --- A stable identifier for "the cave the player is in", so that
    --- suppression survives walking between floors of it. The map group where
    --- there is one, the map itself where there is not.
    GroupKey = function(mapID)
        local groupID = C_Map.GetMapGroupID(mapID)
        return groupID and ("g" .. groupID) or ("m" .. mapID)
    end,

    SameGroup = function(a, b)
        if not a or not b then return false end
        if a == b then return true end
        local groupA = C_Map.GetMapGroupID(a)
        if not groupA then return false end
        return groupA == C_Map.GetMapGroupID(b)
    end,

    --- Sorted floor list, topmost first. Single-entry for a map with no group.
    FloorList = function(caveMapID)
        local function single()
            local info = C_Map.GetMapInfo(caveMapID)
            return {
                { mapID = caveMapID,
                  name = info and info.name or ("Map " .. caveMapID),
                  relativeHeightIndex = 0 },
            }
        end

        local groupID = C_Map.GetMapGroupID(caveMapID)
        if not groupID then return single() end

        local members = C_Map.GetMapGroupMembersInfo(groupID)
        if not members or #members == 0 then return single() end

        local sorted = {}
        for _, m in ipairs(members) do
            sorted[#sorted + 1] = {
                mapID = m.mapID,
                name = m.name or ("Level " .. (m.relativeHeightIndex or 0)),
                relativeHeightIndex = m.relativeHeightIndex or 0,
            }
        end
        -- Descending height: index 1 is the topmost floor, which is the order
        -- the depth slider's notches are laid out in.
        table.sort(sorted, function(a, b)
            if a.relativeHeightIndex == b.relativeHeightIndex then
                return a.mapID < b.mapID
            end
            return a.relativeHeightIndex > b.relativeHeightIndex
        end)
        return sorted
    end,

    --- The map's own name. C_Map has no notion of "the place a floor belongs
    --- to", which is why Cave:GetAreaTitle has to reconstruct one out of the
    --- floor names; the baked source knows it outright.
    PlaceName = function(mapID)
        local info = mapID and C_Map.GetMapInfo(mapID)
        return info and info.name or nil
    end,

    --- Which art layer to draw, as index and descriptor.
    ---
    --- C_Map.GetMapArtLayers can return more than one layer, and the extra
    --- ones are *zoom detail* levels: the same map extent re-cut at a higher
    --- tile resolution. The cave window does not zoom, so it wants layer 1,
    --- the full-extent base layer.
    ArtLayer = function(floorMapID)
        local layers = floorMapID and C_Map.GetMapArtLayers(floorMapID)
        if not layers or #layers == 0 then return nil, nil end
        return 1, layers[1]
    end,

    ArtTextures = function(floorMapID, layerIdx)
        return C_Map.GetMapArtLayerTextures(floorMapID, layerIdx or 1)
    end,

    PlayerPosition = function(floorMapID, unit)
        local pos = C_Map.GetPlayerMapPosition(floorMapID, unit or "player")
        if not pos then return nil end
        return pos:GetXY()
    end,

    CorpsePosition = function(floorMapID)
        local pos = C_DeathInfo.GetCorpseMapPosition(floorMapID)
        if not pos then return nil end
        return pos:GetXY()
    end,

    --- C_Map has no notion of floors sharing a baked canvas: every real
    --- dungeon floor is its own distinct art layer, so the client source
    --- never offers continuous crossfade.
    ContinuousDepth = function()
        return false
    end,

    --- cave-satellite-v2 Phase 2: C_Map has no notion of individually-fading
    --- sub-floor art pieces either, since every real dungeon floor is one
    --- whole art layer, so the client source never offers any.
    Pieces = function()
        return nil
    end,

    PieceCanvasSize = function()
        return nil, nil
    end,

    --- Not needed from this source: nothing baked exists for the client to
    --- fade by real elevation, so there is nothing for this value to drive.
    PlayerWorldZ = function()
        return nil
    end,
}

BakedSource = {
    name = "baked",

    --- The baked floor, falling back to whatever C_Map does know.
    ---
    --- The fallback is not cosmetic: the poller compares this value between
    --- ticks to decide whether anything has changed, so returning nil for the
    --- whole outdoor world would leave it blind to the player crossing zones.
    ---
    --- Passes the floor already on screen through as FindPlayerFloor's
    --- tie-break hint, for places whose floors' footprints overlap too much
    --- for position alone to tell apart (Fargodeep Mine's shaft); see
    --- FloorForPosition's comment. Without it every ambiguous poll would
    --- re-guess independently and could flip-flop, or worse lock onto
    --- whichever floor wins the guess and never leave it.
    ---
    --- Second return, `confident`: passed straight through from
    --- FindPlayerFloor, false exactly when that tie-break hint (or the
    --- smallest-rectangle fallback) answered rather than real position data.
    --- The C_Map fallback below is its own last resort, not a location fix
    --- on any baked floor, so it is unconditionally false too.
    CurrentFloor = function()
        local floorID, confident =
            ns.CaveTable:FindPlayerFloor(Config.caveCurrentFloorMapID)
        if floorID then return floorID, confident end
        return C_Map.GetBestMapForUnit("player"), false
    end,

    IsInterior = function(floorID)
        return ns.CaveTable:GetFloor(floorID) ~= nil
    end,

    GroupKey = function(floorID)
        return ns.CaveTable:GetGroupKey(floorID) or ("b?" .. tostring(floorID))
    end,

    SameGroup = function(a, b)
        if not a or not b then return false end
        if a == b then return true end
        return ns.CaveTable:SamePlace(a, b)
    end,

    FloorList = function(floorID)
        return ns.CaveTable:BuildFloorList(floorID)
    end,

    PlaceName = function(floorID)
        return ns.CaveTable:GetPlaceName(floorID)
    end,

    ArtLayer = function(floorID)
        return ns.CaveTable:GetArtLayer(floorID)
    end,

    ArtTextures = function(floorID)
        return ns.CaveTable:GetArtTextures(floorID)
    end,

    PlayerPosition = function(floorID, unit)
        return ns.CaveTable:GetPlayerPosition(floorID, unit)
    end,

    CorpsePosition = function(floorID)
        return ns.CaveTable:GetCorpsePosition(floorID)
    end,

    ContinuousDepth = function(floorID)
        return ns.CaveTable:HasSharedCanvas(floorID)
    end,

    Pieces = function(floorID)
        return ns.CaveTable:GetPieces(floorID)
    end,

    PieceCanvasSize = function(floorID)
        return ns.CaveTable:GetPieceCanvasSize(floorID)
    end,

    PlayerWorldZ = function()
        return ns.CaveTable:GetPlayerWorldZ()
    end,
}

-- Which source answered last, so /hfwm debug can say, and whether the choice
-- between them has been made yet.
local activeSource   = ClientSource
local sourceResolved = false

--- The source to ask. Memoised, but only once there is a choice to make:
--- with no baked table loaded there is nothing to weigh up and the answer is
--- C_Map without a probe. When there *is* a baked table, the probe that
--- decides between them walks the whole map tree, which is far too much work
--- for a half-second poll to repeat, hence the memo and
--- Cave:InvalidateSource() for the one case that can change it.
---@return table
function Cave:GetSource()
    if not ns.CaveTable:IsLoaded() then
        activeSource = ClientSource
        return ClientSource
    end
    if activeSource and sourceResolved then return activeSource end
    -- Zero is the answer that matters: the client has no interior map for the
    -- player ever to be standing on, so C_Map cannot answer and the baked
    -- table is the only thing that can. Nil means the client gave no way to
    -- ask, which is not the same as none; keep C_Map in that case.
    local count = self:CountInteriorMaps()
    activeSource   = (count == 0) and BakedSource or ClientSource
    sourceResolved = true
    return activeSource
end

--- Forget the memoised source choice. For anything that changes the client's
--- map table under us: in practice a loading screen into a different flavour
--- of the world, and the test harness.
function Cave:InvalidateSource()
    sourceResolved = false
end

--- Which source is in use, for /hfwm debug.
---@return string
function Cave:SourceName()
    return self:GetSource().name
end

-------------------------------------------------------------------------------
-- Detection
-------------------------------------------------------------------------------

--- Is this map/floor ID one of the interior kinds?
---@param mapID number|nil
---@return boolean
local function IsInteriorMap(mapID)
    if not mapID then return false end
    return Cave:GetSource().IsInterior(mapID) and true or false
end

--- The map/floor ID the player is physically standing on.
---
--- Second return, `confident`: true when this is a real position fix
--- rather than a guess or a deferral to whatever floor is already being
--- shown; see BakedSource.CurrentFloor / FloorForPosition's own comments
--- for when it isn't. Every existing caller predates this and only reads
--- the first return, which keeps their behaviour (follow the player,
--- defer to the slider when ambiguous) exactly as it was; a caller has to
--- opt in to the second value to change how it treats an ambiguous answer.
---@return number|nil floorID
---@return boolean confident
function Cave:GetCurrentFloorMapID()
    return self:GetSource().CurrentFloor()
end

--- Are these two IDs the same place: the same map, or two floors of one
--- group?
---@return boolean
local function SameMapGroup(a, b)
    return Cave:GetSource().SameGroup(a, b)
end

--- Is the window allowed where the player is standing? Dungeon and raid
--- instances follow their own Instance map toggles; everywhere else follows
--- the cave map's. The two never stand in for each other.
---@return boolean
function Cave:IsEnabledHere()
    local db = Config.db
    if not (db and db.enabled) then return false end
    local instanceType = GetInstanceInfo and select(2, GetInstanceInfo())
    if instanceType == "party" then return db.instanceDungeonEnabled and true or false end
    if instanceType == "raid" then return db.instanceRaidEnabled and true or false end
    return db.caveEnabled and true or false
end

--- True if the player is in a cave/micro/dungeon map *and* the world map is
--- showing somewhere else entirely.
---
--- The comparison is by map *group*, not by map ID. A dungeon's floors are
--- separate UiMapIDs but the world map showing any one of them draws the
--- client's own floor selector, so the player can already get to the rest;
--- opening a second set of floor controls on top would be a duplicate of a
--- control that is right there. On the baked source the world map can never
--- show a baked floor, since the client has no way to navigate to one, so
--- this test simply never fires, which is correct rather than merely
--- harmless.
---@return boolean inCave, number|nil playerMapID
function Cave:IsPlayerInCave()
    local playerMapID = self:GetCurrentFloorMapID()
    if not playerMapID then return false end

    if not IsInteriorMap(playerMapID) then return false end

    if SameMapGroup(WorldMapFrame:GetMapID(), playerMapID) then
        return false
    end

    return true, playerMapID
end

--- A stable identifier for "the cave the player is in", so that suppression
--- survives walking between floors of it.
---@param mapID number
---@return string
local function GroupKey(mapID)
    return Cave:GetSource().GroupKey(mapID)
end

-------------------------------------------------------------------------------
-- Art and position, for CaveRenderer
--
-- The renderer used to call C_Map directly for all three. It goes through here
-- instead so the window, its proportions, its tiles and its player pin all
-- come from whichever source located the cave in the first place: a window
-- sized from C_Map's idea of a layer while its tiles came from the baked
-- table would be stretched, and a pin placed in the wrong coordinate space is
-- worse than no pin.
-------------------------------------------------------------------------------

--- Which art layer to draw, as index and descriptor.
---@param floorMapID number|nil
---@return number|nil layerIdx, table|nil layer
function Cave:GetArtLayer(floorMapID)
    if not floorMapID then return nil, nil end
    return self:GetSource().ArtLayer(floorMapID)
end

--- Row-major FileDataIDs for a floor's art layer.
---@return table|nil
function Cave:GetArtTextures(floorMapID, layerIdx)
    if not floorMapID then return nil end
    return self:GetSource().ArtTextures(floorMapID, layerIdx)
end

--- The player's (or, given *unit*, another unit's) normalised position within
--- a floor's art, 0..1 from its top-left, or nil where there is no fix in
--- that floor's space.
---@return number|nil x, number|nil y
function Cave:GetPlayerMapXY(floorMapID, unit)
    if not floorMapID then return nil end
    return self:GetSource().PlayerPosition(floorMapID, unit)
end

--- The player's corpse within a floor's art, same space as GetPlayerMapXY;
--- nil when there is no corpse on that floor.
---@return number|nil x, number|nil y
function Cave:GetCorpseMapXY(floorMapID)
    if not floorMapID then return nil end
    return self:GetSource().CorpsePosition(floorMapID)
end

--- Should CaveRenderer crossfade this floor's place continuously as the
--- depth slider moves, rather than hard-swapping floor art? True only for
--- places whose floors are baked from one shared, aligned canvas (currently
--- just Fargodeep Mine). Always false from the client source, which has no
--- such concept.
function Cave:HasContinuousDepth(floorMapID)
    if not floorMapID then return false end
    local source = self:GetSource()
    return source.ContinuousDepth and source.ContinuousDepth(floorMapID) or false
end

--- cave-satellite-v2 Phase 2: this floor's place's per-piece art list (see
--- CaveTable:GetPieces), or nil from the client source and from any baked
--- place that has no per-piece bake yet. CaveRenderer checks this instead
--- of (or ahead of) HasContinuousDepth once a place has one: pieces are the
--- finer-grained replacement for the whole-floor crossfade, not an addition
--- to it.
---@param floorMapID number|nil
---@return table|nil pieces
function Cave:GetPieces(floorMapID)
    if not floorMapID then return nil end
    local source = self:GetSource()
    return source.Pieces and source.Pieces(floorMapID) or nil
end

--- The shared canvas size backing GetPieces's list, or nil alongside it.
---@param floorMapID number|nil
---@return number|nil canvasW, number|nil canvasH
function Cave:GetPieceCanvasSize(floorMapID)
    if not floorMapID then return nil end
    local source = self:GetSource()
    if not source.PieceCanvasSize then return nil end
    return source.PieceCanvasSize(floorMapID)
end

--- The player's real worldZ (height), for fading the pin against whichever
--- piece the slider says is at the player's own elevation. nil from the
--- client source, which has nothing baked to fade against.
---@return number|nil worldZ
function Cave:GetPlayerWorldZ()
    local source = self:GetSource()
    return source.PlayerWorldZ and source.PlayerWorldZ() or nil
end

-------------------------------------------------------------------------------
-- Capability probe
--
-- The whole feature rests on the client's map table containing interior maps,
-- and on a 1.x-era build it may contain none at all: vanilla shipped 60
-- outdoor zone maps and nothing else, no dungeon maps and no micro-dungeon
-- maps, which is precisely why the world map was blank inside a dungeon and
-- why walking into a mine changed nothing. A cave the client has no UiMapID
-- for is a cave this addon cannot draw: there is no art to ask for.
--
-- So rather than switch on a feature that can never fire and leave the user
-- watching for a window, the probe below answers the question outright and
-- the enable path says so.
-------------------------------------------------------------------------------

--- The root of the map tree, walked up from wherever the player is.
---@return number|nil
local function MapTreeRoot()
    local mapID = C_Map.GetBestMapForUnit("player")
        or (WorldMapFrame and WorldMapFrame:GetMapID())
    local seen = {}
    while mapID and not seen[mapID] do
        seen[mapID] = true
        local info = C_Map.GetMapInfo(mapID)
        local parent = info and info.parentMapID
        if not parent or parent == 0 or parent == mapID then return mapID end
        mapID = parent
    end
    return mapID
end

--- How many Dungeon and Micro maps exist anywhere in this client's map tree.
---
--- Nil means the client gave no way to ask, which is not the same as none.
--- Zero is the interesting answer: no cave window can open anywhere, because
--- there is no interior map for the player ever to be standing on.
---@return number|nil
function Cave:CountInteriorMaps()
    if not C_Map.GetMapChildrenInfo then return nil end
    local root = MapTreeRoot()
    if not root then return nil end

    local total = 0
    for mapType in pairs(CAVE_MAP_TYPES) do
        local kids = C_Map.GetMapChildrenInfo(root, mapType, true)
        total = total + (kids and #kids or 0)
    end
    return total
end

--- Say so when the feature has been switched on for a client that cannot use
--- it. Returns true if it warned.
---@return boolean
function Cave:WarnIfUnsupported()
    if self:CountInteriorMaps() ~= 0 then return false end
    -- The client having no interior maps is the expected case on this build
    -- and is no longer a problem, because the shipped table stands in for
    -- exactly the rows it is missing. Only say something when that is absent
    -- too, which means CaveData.lua failed to load or was generated empty.
    if ns.CaveTable:IsLoaded() then return false end

    P("|cffff7777Cave map: this client's UiMap table has no interior entries, "
        .. "and the addon's own cave table did not load.|r C_Map will never "
        .. "report a cave or dungeon map, so the window has nothing to key "
        .. "off and will not open anywhere, including inside mines.")
    P("|cff999999The art isn't the problem: this build ships Blizzard's "
        .. "micro-dungeon map tiles under Interface\\WorldMap\\MicroDungeon "
        .. "(Fargodeep Mine has two floors' worth). What's missing is the map "
        .. "table pointing the client at them, which is CaveData.lua's job. "
        .. "Check it's present and listed in the .toc, or rebuild it with "
        .. "src/generator/generateHFWM.py --caves-only. Run /hfwm debug inside a cave to "
        .. "see what the client reports.|r")
    return true
end

-------------------------------------------------------------------------------
-- Naming
-------------------------------------------------------------------------------

--- The title the window carries. Falls back down the chain the client offers:
--- the map's own name, then the subzone the player is standing in, then the
--- zone, then the map ID, because an untitled window over the world map is
--- worse than an ugly one.
---@param floorMapID number
---@return string
function Cave:GetAreaTitle(floorMapID)
    local source = self:GetSource()
    local name   = source.PlaceName(floorMapID)

    -- Floors of a group are often named for the floor ("Level 2") rather than
    -- for the place. Prefer the group's shared name where the members agree
    -- on one, so the title says where you are and the footer says how deep.
    --
    -- Only worth doing on the client source, where "the place" has to be
    -- reconstructed from the floor names because C_Map has no such concept.
    -- The baked table records it, and recorded beats inferred: guessing from
    -- Gnomeregan's floor names ("Launch Bay", "The Clean Zone") would never
    -- arrive at "Gnomeregan", and there is no shared run to find.
    local floors = Config.caveAllFloors
    if source == ClientSource and floors and #floors > 1 then
        local shared = self:SharedFloorName(floors)
        if shared then name = shared end
    end

    if name and name ~= "" then return name end

    local sub = GetSubZoneText()
    if sub and sub ~= "" then return sub end

    local zone = GetZoneText()
    if zone and zone ~= "" then return zone end

    local minimapZone = GetMinimapZoneText()
    if minimapZone and minimapZone ~= "" then return minimapZone end

    return "Map " .. tostring(floorMapID)
end

-- Words that number a floor rather than name a place. The common run across
-- a group's names almost always ends in one of these, because the numbering
-- is exactly what the names differ *after*.
local FLOOR_NOISE = {
    level = true, lvl = true, floor = true, tier = true,
    sublevel = true, story = true, storey = true, stage = true,
}

--- Is this word floor numbering rather than part of the place's name?
---@param word string
---@return boolean
local function IsFloorNoise(word)
    local bare = word:lower():gsub("%p", "")
    if bare == "" then return true end            -- lone punctuation, "-", ":"
    if FLOOR_NOISE[bare] then return true end
    if bare:match("^%d+$") then return true end   -- "2"
    if #bare <= 4 and bare:match("^[ivx]+$") then return true end -- "II"
    return false
end

--- The name the floors of a group share, or nil when they share nothing
--- usable. "The Deadmines" out of "The Deadmines Level 1/2/3"; nil out of
--- "Level 1" and "Level 2", where every shared word is numbering.
---
--- Two passes, and the second is the one that matters. The longest common
--- leading word run across the names is only the start: for "The Deadmines
--- Level 1/2/3" that run is "The Deadmines Level", and the place is not
--- called that. So the trailing numbering words come off afterwards, leaving
--- the title to say where you are and the footer to say how deep.
---@param floors table[]
---@return string|nil
function Cave:SharedFloorName(floors)
    local first = floors[1] and floors[1].name
    if not first or first == "" then return nil end

    local words = {}
    for word in first:gmatch("%S+") do words[#words + 1] = word end

    for count = #words, 1, -1 do
        local candidate = table.concat(words, " ", 1, count)
        local all = true
        for _, f in ipairs(floors) do
            if not (f.name and f.name:find(candidate, 1, true) == 1) then
                all = false
                break
            end
        end
        if all then
            -- The longest run, and therefore the only one worth trimming: a
            -- shorter one is a prefix of this and can add nothing.
            local trimmed = count
            while trimmed > 0 and IsFloorNoise(words[trimmed]) do
                trimmed = trimmed - 1
            end
            if trimmed == 0 then return nil end

            local name = table.concat(words, " ", 1, trimmed)
            -- Strip a dangling separator the numbering hung off ("Uldaman -").
            -- ASCII only on purpose: a Lua character class is a set of bytes,
            -- so putting an en dash in one would let it eat the tail byte of
            -- an unrelated multibyte character.
            name = name:gsub("[%s%-:,;]+$", "")
            -- One word of agreement is usually an article ("The"), which is
            -- not a name; insist on either two words or a single long one.
            if trimmed > 1 or #name > 4 then return name end
            return nil
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Floors
-------------------------------------------------------------------------------

--- Sorted floor list for a cave map, topmost first. Single-entry list for a
--- map that is not part of a group. This is what the depth slider lays its
--- notches out from, so the order is load-bearing.
---@param caveMapID number
---@return table[] floors  [{ mapID, name, relativeHeightIndex }, ...]
function Cave:BuildFloorList(caveMapID)
    return self:GetSource().FloorList(caveMapID)
end

--- Is `mapID` one of the floors already built?
local function FloorListCovers(floors, mapID)
    if not floors then return false end
    for _, f in ipairs(floors) do
        if f.mapID == mapID then return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- Suppression (the close button)
-------------------------------------------------------------------------------

--- Don't re-open the cave the player is currently in. Called by the window's
--- close button.
function Cave:SuppressCurrent()
    local _, playerMapID = self:IsPlayerInCave()
    -- Fall back to the floor on screen: the player may have walked out in the
    -- moment between the window opening and the click landing.
    local mapID = playerMapID or Config.caveCurrentFloorMapID
    Config.caveSuppressedKey = mapID and GroupKey(mapID) or nil
    -- Only an explicit close counts as "last visible = false" for the
    -- Remember State option below: walking out of a cave that was still
    -- showing is not the player choosing to hide it.
    if Config.db then Config.db.caveLastVisible = false end
end

--- Forget the suppression, so the next poll opens the window again.
function Cave:Unsuppress()
    Config.caveSuppressedKey = nil
end

--- Open the cave window for wherever the player is, ignoring a previous
--- close. Returns false if there is no cave to show.
---@return boolean
function Cave:ForceShow()
    self:Unsuppress()
    -- Also drop an ESC hide (Core.lua): the player has asked for the window
    -- back, so UpdateState must not keep holding it down.
    Config.caveEscHidden = false
    Config.caveFloorPinned = false
    local inCave, playerMapID = self:IsPlayerInCave()
    if not inCave then return false end
    Config.caveAllFloors = self:BuildFloorList(playerMapID)
    ns.CaveRenderer:ShowCave(playerMapID)
    -- Belt-and-suspenders: UpdateState's next poll would clear this anyway,
    -- but the reopen icon (if this was called by clicking it) should vanish
    -- the instant the window comes back, not up to POLL_INTERVAL later.
    ns.CaveRenderer:SetReopenAvailable(false)
    -- The player asked for it open, so that is what Remember State should
    -- reproduce next time, whether this was the reopen icon, /hfwm cave
    -- show, or anything else that lands here.
    if Config.db then Config.db.caveLastVisible = true end
    return true
end

-------------------------------------------------------------------------------
-- State reconciliation
-------------------------------------------------------------------------------

--- Bring the cave window in line with where the player is and what the world
--- map is showing. Safe to call as often as you like; it is a no-op when
--- nothing has changed.
function Cave:UpdateState()
    if not self:IsEnabledHere() then
        if Config.caveOverlayActive then ns.CaveRenderer:HideCave() end
        ns.CaveRenderer:SetReopenAvailable(false)
        return
    end

    local inCave, playerMapID = self:IsPlayerInCave()
    if not inCave then
        -- Out of the cave: drop the suppression, the per-visit open/closed
        -- decision, and the pinned floor, so walking back in, to this cave or
        -- a different one, is unconditionally a clean slate.
        -- caveDecidedKey in particular has to go here even though
        -- caveAllFloors (below) sometimes doesn't: see its own comment in
        -- Config.lua for why leaning on caveAllFloors alone as "have I
        -- already handled this visit" was the bug where Open Automatically
        -- off, or Remember State closed, silently stopped mattering after
        -- the first leave-and-return.
        Config.caveSuppressedKey = nil
        Config.caveEntrance      = nil
        -- Only a player map that is known and not an interior is "outside";
        -- nil (loading screen) or "world map is on this cave" is not, and
        -- must not forget the saved entrance.
        local here = self:GetCurrentFloorMapID()
        if here and not IsInteriorMap(here) then
            Config.caveSawOutside = true
            Config.dbObj.char.caveEntrance = nil
        end
        Config.caveDecidedKey    = nil
        Config.caveEscHidden     = false
        if Config.caveOverlayActive then ns.CaveRenderer:HideCave() end
        ns.CaveRenderer:SetReopenAvailable(false)
        return
    end

    local groupKey = GroupKey(playerMapID)

    -- A group we haven't already decided for is a new visit: the one moment
    -- to decide whether it opens on its own, before falling into the
    -- suppression check below. Remember State, when on, wins over Open
    -- Automatically since it's the more specific of the two ("do what I did
    -- last time" beats "always/never"). A "no" from either one is applied
    -- the same way the close button is, by pre-suppressing this visit's
    -- group key, so every branch below (the reopen icon, ForceShow undoing
    -- it) already handles it correctly without needing to know *why* it's
    -- suppressed.
    if Config.caveDecidedKey ~= groupKey then
        Config.caveDecidedKey = groupKey
        -- Entrance: kept per character (the profile is shared) so it survives
        -- /reload and logging out. Only a crossing actually seen this session
        -- is recorded; a login that lands inside a cave has no entrance to
        -- show, unless one was saved for this same cave.
        local char = Config.dbObj.char
        if char.caveEntrance and char.caveEntrance.key ~= groupKey then
            char.caveEntrance = nil
        end
        if not char.caveEntrance and Config.caveSawOutside then
            local ex, ey = self:GetPlayerMapXY(playerMapID)
            if ex and ey and (ex ~= 0 or ey ~= 0) then
                char.caveEntrance = { key = groupKey, mapID = playerMapID, x = ex, y = ey }
            end
        end
        Config.caveEntrance = char.caveEntrance
        local state = Config.db.caveDefaultState
        local openByDefault
        if state == "remember" then
            openByDefault = Config.db.caveLastVisible ~= false
        elseif state == "minimized" then
            openByDefault = false
        else
            openByDefault = Config.db.caveAutoOpen ~= false
        end
        Config.caveSuppressedKey = (not openByDefault) and groupKey or nil
    end

    -- Rebuild the floor list when the player has moved into a cave whose
    -- floors we do not already have. Independent of the decision above:
    -- this can be stale on its own (e.g. a saved window position restored
    -- before the player ever walked anywhere) without that meaning the
    -- open/closed decision needs re-running too.
    if not FloorListCovers(Config.caveAllFloors, playerMapID) then
        Config.caveAllFloors   = self:BuildFloorList(playerMapID)
        Config.caveFloorPinned = false
    end

    if Config.caveSuppressedKey == groupKey then
        if Config.caveOverlayActive then ns.CaveRenderer:HideCave() end
        -- Closed, but there is a cave right here to reopen: this is the one
        -- state the reopen icon exists for.
        ns.CaveRenderer:SetReopenAvailable(true)
        return
    end

    ns.CaveRenderer:SetReopenAvailable(false)

    -- Hidden by ESC: stay down (no reopen icon either) until the world map
    -- is next shown, which clears the flag.
    if Config.caveEscHidden then return end

    -- Follow the player between floors, unless they have taken the depth
    -- slider off automatic.
    if Config.caveFloorPinned and Config.caveOverlayActive then
        return
    end

    if Config.caveCurrentFloorMapID ~= playerMapID
       or not Config.caveOverlayActive then
        ns.CaveRenderer:ShowCave(playerMapID)
        -- This is the "opened on its own" path (auto-open, or Remember
        -- State finding the last visit open) as well as the ordinary
        -- follow-the-player floor switch. Both are "visible now", which is
        -- exactly what Remember State needs recorded.
        Config.db.caveLastVisible = true
    end
end

-------------------------------------------------------------------------------
-- Poller
--
-- Separate from Watchdog, which exists to fight the client redrawing its own
-- map art. This one only watches for the player and the map disagreeing, and
-- does nothing at all while the feature is off.
-------------------------------------------------------------------------------
local function OnPollUpdate(_, elapsed)
    elapsedSincePoll = elapsedSincePoll + elapsed
    if elapsedSincePoll < POLL_INTERVAL then return end
    elapsedSincePoll = 0

    if not Cave:IsEnabledHere() then
        return
    end

    -- GetMapID() is the visibility gate rather than IsShown(), which is
    -- unreliable on this client. Keep Open opts out: the window outlives
    -- the map, so a closed map is no reason to hide or stop updating it.
    if not Config.db.caveKeepOpen and not WorldMapFrame:GetMapID() then
        if Config.caveOverlayActive then ns.CaveRenderer:HideCave() end
        ns.CaveRenderer:SetReopenAvailable(false)
        return
    end

    local playerMapID    = Cave:GetCurrentFloorMapID()
    local displayedMapID = WorldMapFrame:GetMapID()
    if playerMapID ~= Config.lastPlayerMapID
       or displayedMapID ~= Config.caveDisplayedMapID then
        Config.lastPlayerMapID    = playerMapID
        Config.caveDisplayedMapID = displayedMapID
        Cave:UpdateState()
    end
end

function Cave:Start()
    -- Indexing the shipped table needs C_Map.GetAreaInfo, so it cannot happen
    -- at file load: the AreaTable is not queryable until the player is in the
    -- world. Core.lua calls this from PLAYER_LOGIN, which is late enough.
    ns.CaveTable:Load()
    self:InvalidateSource()

    if pollFrame then return end
    pollFrame = CreateFrame("Frame", "HFWMForeverCavePoller")
    pollFrame:SetScript("OnUpdate", OnPollUpdate)
end
