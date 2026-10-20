-------------------------------------------------------------------------------
-- HFWM-Forever CaveTable
--
-- Presents the generated CaveData.lua through the same questions C_Map would
-- answer about an interior, so Cave.lua can drive the window off either one.
--
-- Why this file has to exist at all: this build ships Blizzard's own interior
-- map art (Fargodeep Mine has two floors of it sitting in the client right
-- now), but its UiMap table lists outdoor zones only: 60 rows, no Dungeon and
-- no Micro. So C_Map.GetBestMapForUnit can never name a cave, GetMapArtLayers
-- can never describe one, and the art is unreachable from Lua even though the
-- engine happily draws it on the minimap. What is missing is the *plumbing*,
-- not the pictures, and that is what hfwm/gamedata/microdungeon.py rebuilds offline and
-- bakes into HFWMF_CAVE_DATA.
--
-- The three questions this has to answer that C_Map answers for free:
--
--   Where is the player?   C_Map resolves a world position to a map ID. With
--       no interior maps there is nothing to resolve to, so the lookup runs
--       the other way: the baked AreaTable IDs are turned into names through
--       C_Map.GetAreaInfo at load, and the names are matched against what the
--       client says the player's area is called. Both sides therefore come
--       from the client's own locale data and the match holds in any
--       language, despite the table being built from enUS exports.
--   Which floor?           Dungeon floors share one AreaID (all four
--       Gnomeregan floors are area 721), so the name says only *where*. The
--       floor comes from the world-space rectangles instead, where they
--       discriminate; see FloorForPosition.
--   What art?              Straight out of the table: FileDataIDs the client
--       already has, in the row-major order GetMapArtLayerTextures uses.
--
-- Floor identity is a synthetic ID minted here rather than the retail UiMapID
-- the table carries. The retail numbering is kept on each floor for tracing,
-- but it is retail's: this client renumbered the world (Elwynn Forest is
-- 1429 here and 37 there), so handing it to anything that might pass it to
-- C_Map would be inviting a lookup against the wrong map.
-------------------------------------------------------------------------------
local addonName, ns = ...
local CaveTable = ns.CaveTable
local Config    = ns.Config

-- Synthetic floor IDs start here. Well clear of any UiMapID a client could
-- mint (retail's highest is in the low thousands) and positive, so a baked
-- floor ID prints, sorts and compares like the map ID it stands in for
-- everywhere the existing code already handles one.
local FLOOR_ID_BASE = 4000000

-- Enum.UiMapType values, so GetMapInfo can answer mapType like C_Map does.
local UI_MAP_TYPE = (Enum and Enum.UiMapType) or {}
local MAP_TYPE_BY_KIND = {
    micro   = UI_MAP_TYPE.Micro   or 5,
    indoor  = UI_MAP_TYPE.Micro   or 5,
    dungeon = UI_MAP_TYPE.Dungeon or 4,
}


-------------------------------------------------------------------------------
-- Indices, built once at login
-------------------------------------------------------------------------------
local loaded = false
local places = {}        -- [i] = place, with .floors[j].id filled in
local floorByID = {}     -- [floorID] = { place = place, floor = floor }
local placesByName = {}  -- [lowercased localised area name] = { place, ... }
local placeByInstance = {} -- [Map.ID] = place, dungeons only
-- Buildings, houses and every other WMO interior (IndoorData.lua). Matched by
-- Map.ID and footprint alone, never by name: most sit in the same subzone as
-- the street outside, so the name says nothing about which building it is.
local indoorPlaces = {}

--- Fold a place into the name index under every name it could be recognised
--- by: the place's own areas and each floor's.
local function IndexNames(place)
    local seen = {}
    local function add(areaID)
        if not areaID or seen[areaID] then return end
        seen[areaID] = true
        -- The localised name for this build's own AreaTable row. nil means
        -- the client does not know the area, which the generator is supposed
        -- to have made impossible (every baked ID was matched against this
        -- build's AreaTable), so it is simply skipped rather than guessed at.
        local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
        if not name or name == "" then return end
        local key = name:lower()
        local list = placesByName[key]
        if not list then
            list = {}
            placesByName[key] = list
        end
        for _, p in ipairs(list) do
            if p == place then return end
        end
        list[#list + 1] = place
    end

    for _, areaID in ipairs(place.areaIDs or {}) do add(areaID) end
    for _, floor in ipairs(place.floors) do
        for _, areaID in ipairs(floor.areaIDs or {}) do add(areaID) end
    end
end

--- Read HFWMF_CAVE_DATA into the indices above. Safe to call more than once;
--- the second call rebuilds, which is what makes it useful from /hfwm debug
--- after a table swap.
function CaveTable:Load()
    loaded = false
    places, floorByID, placesByName, placeByInstance = {}, {}, {}, {}
    indoorPlaces = {}

    local data = HFWMF_CAVE_DATA
    if type(data) ~= "table" or type(data.places) ~= "table" then
        return false
    end

    -- Indoors ship in their own table (IndoorData.lua, same shape, kind =
    -- "indoor") so regenerating them never touches the hand-curated places.
    local sources = data.places
    if type(HFWMF_INDOOR_PLACES) == "table" then
        sources = {}
        for _, src in ipairs(data.places) do sources[#sources + 1] = src end
        for _, src in ipairs(HFWMF_INDOOR_PLACES) do sources[#sources + 1] = src end
    end

    local nextID = FLOOR_ID_BASE
    for i, src in ipairs(sources) do
        if type(src.floors) == "table" and #src.floors > 0 then
            local place = {
                index   = i,
                name    = src.name,
                kind    = src.kind,
                mapID   = src.mapID,
                areaIDs = src.areaIDs or {},
                bounds  = src.bounds,
                -- World<->pixel projection for rotated, WMO-local-coordinate
                -- art (see CaveData.lua's Fargodeep entry and
                -- ProjectPlayerPosition below). Absent on every place whose
                -- art is the plain unrotated bounds-stretch, which
                -- GetPlayerPosition treats as "use the old formula".
                projection = src.projection,
                -- True only when every floor below is baked from the exact
                -- same composite canvas (currently just Fargodeep Mine; see
                -- CaveData.lua). Lets CaveRenderer crossfade this place's
                -- floors continuously as the depth slider moves instead of
                -- hard-swapping between them. Absent/false is the safe
                -- default for every place using the generic per-floor
                -- "paperback" background, which must never crossfade.
                sharedCanvas = src.sharedCanvas,
                -- cave-satellite-v2 Phase 2: individually-fading art pieces
                -- (one per WMO group), each on the same pieceCanvasW/H
                -- canvas as every floor below. Absent on every place that
                -- has no per-piece bake yet (everything but Fargodeep Mine
                -- today), which the renderer treats as "fall back to
                -- whole-floor crossfade or hard-swap" exactly as before.
                pieces = src.pieces,
                pieceCanvasW = src.pieceCanvasW,
                pieceCanvasH = src.pieceCanvasH,
                floors  = {},
                -- Suppression is keyed on this, so it has to be stable across
                -- a session and distinct from any C_Map group key. The place's
                -- position in the shipped table is both.
                groupKey = "b" .. i,
            }
            for j, floor in ipairs(src.floors) do
                nextID = nextID + 1
                place.floors[j] = {
                    id       = nextID,
                    place    = place,
                    depth    = j,          -- 1 = shallowest, as generated
                    name     = floor.name,
                    uiMapID  = floor.uiMapID,   -- retail's, for tracing only
                    areaIDs  = floor.areaIDs or {},
                    bounds   = floor.bounds,
                    layerW   = floor.layerW,
                    layerH   = floor.layerH,
                    tileW    = floor.tileW,
                    tileH    = floor.tileH,
                    cols     = floor.cols,
                    rows     = floor.rows,
                    tiles    = floor.tiles,
                    -- Real worldZ range from the floor's own WMO geometry,
                    -- when the generator provided one (see CaveData.lua's
                    -- Fargodeep entries). Absent on every floor that has no
                    -- such data, which FloorForPosition treats as "no
                    -- opinion" rather than a false match.
                    zMin     = floor.zMin,
                    zMax     = floor.zMax,
                }
                floorByID[nextID] = place.floors[j]
            end
            places[#places + 1] = place
            if place.kind == "indoor" then
                indoorPlaces[#indoorPlaces + 1] = place
            else
                IndexNames(place)
            end
            -- Instance map IDs are unique per dungeon and are exactly what
            -- GetInstanceInfo hands back, so inside a dungeon the lookup can
            -- skip the names entirely. Micro dungeons share the continent's
            -- Map.ID between all of them, so they are deliberately left out.
            if place.kind == "dungeon" and place.mapID then
                placeByInstance[place.mapID] = place
            end
        end
    end

    loaded = #places > 0
    return loaded
end

function CaveTable:IsLoaded() return loaded end
function CaveTable:CountPlaces() return #places end
function CaveTable:GetBuild()
    return HFWMF_CAVE_DATA and HFWMF_CAVE_DATA.build or nil
end

--- The floor record behind a synthetic floor ID, or nil for anything else,
--- which is how every caller tells a baked ID from a real UiMapID.
---@param floorID number|nil
function CaveTable:GetFloor(floorID)
    return floorID and floorByID[floorID] or nil
end

-------------------------------------------------------------------------------
-- Locating the player
-------------------------------------------------------------------------------

--- The Map.ID (instance / continent) the player is on, and whether it is an
--- instance. GetInstanceInfo's 8th return is the instance map ID, and it is 0
--- or the continent's ID out in the world, which is precisely what the table's
--- `mapID` holds for a micro dungeon.
---@return number|nil mapID, boolean inInstance
local function CurrentMapID()
    if not GetInstanceInfo then return nil, false end
    local ok, _, instanceType, _, _, _, _, _, instanceMapID =
        pcall(GetInstanceInfo)
    if not ok then return nil, false end
    return instanceMapID, (instanceType ~= nil and instanceType ~= "none")
end

--- Player world position as the baked rectangles measure it.
---
--- UnitPosition returns y, x, z, instanceID: Y first, which is easy to get
--- backwards and produces a pin that is plausibly wrong rather than obviously
--- wrong, so it is unpacked in one place only.
---
--- z is read and then thrown away unconditionally. It is not just unreliable
--- on this client (confirmed live at obviously different real elevations, in
--- and out of Fargodeep Mine, top floor and bottom); it is documented
--- (warcraft.wiki.gg/wiki/API_UnitPosition) as a permanent placeholder that is
--- *always* 0, addon-side, on every version of the game, with no workaround:
--- HereBeDragons, the library other addons reach for to avoid exactly this
--- kind of hand-rolled position math, doesn't expose a Z either, since there
--- is nothing behind UnitPosition for it to expose. A real elevation was
--- never coming through this call. Keeping it would mean a literal 0
--- silently wins ContainsZ's tie-break in FloorForPosition against whichever
--- floor's baked zMin/zMax happens to straddle 0 (Lower Mines here), locking
--- floor detection and the elevation marker onto that one floor forever
--- regardless of where the player actually is. Discarding it instead lets
--- the rectangle test, and ultimately the manual depth slider, take over,
--- same as any other place with no baked Z data at all.
---@param unit string|nil  defaults to "player"; other units are dropped when
---  they are in a different instance, whose coordinates mean something else.
---@return number|nil worldX, number|nil worldY
local function PlayerWorldXY(unit)
    if not UnitPosition then return nil end
    local ok, y, x, _, instanceID = pcall(UnitPosition, unit or "player")
    if not ok or not x or not y then return nil end
    if unit and unit ~= "player" then
        local _, _, _, myInstance = UnitPosition("player")
        if instanceID ~= myInstance then return nil end
    end
    return x, y
end

--- Does this world-space rectangle contain (worldX, worldY)?
---
--- bounds reads as { minY, maxY, minX, maxX }, not the { minX, maxX, minY,
--- maxY } CaveData.lua's header claims. Confirmed from two live /hfwm debug
--- captures at Fargodeep Mine, one on the hillside above it and one inside
--- the shaft: the player's real worldY (from UnitPosition, itself correct;
--- see PlayerWorldXY) landed inside bounds[1..2] and real worldX inside
--- bounds[3..4], the opposite of documented. That is why FindPlayerFloor
--- used to return nil for every micro dungeon regardless of the outdoors
--- gate or name match: this check was failing for every place, always.
--- The generator (hfwm/gamedata/db2.py's Region_0..5 -> world-axis mapping, around
--- line 34) has the transposition at its root and is worth fixing there so
--- a future regenerate doesn't reintroduce this; until then, this reads the
--- table as it actually is.
local function Contains(bounds, worldX, worldY)
    if not bounds then return false end
    return worldY >= bounds[1] and worldY <= bounds[2]
        and worldX >= bounds[3] and worldX <= bounds[4]
end

local function RectArea(bounds)
    return (bounds[2] - bounds[1]) * (bounds[4] - bounds[3])
end

--- Does *floor*'s real worldZ range (see CaveData.lua's Fargodeep entries)
--- contain worldZ? Returns nil, not false, when either side has no opinion
--- (no worldZ reading, or this floor was generated without a zMin/zMax);
--- callers must tell "doesn't contain" apart from "can't say" so a place
--- with no Z data at all falls through to the rectangle test untouched.
---@param floor table
---@param worldZ number|nil
---@return boolean|nil
local function ContainsZ(floor, worldZ)
    if not worldZ or not floor.zMin or not floor.zMax then return nil end
    return worldZ >= floor.zMin and worldZ <= floor.zMax
end

--- Which floor of *place* the player is most likely standing on.
---
--- The X/Y rectangles are the primary discriminator, but the source rows
--- behind them carry no usable Z bounds (they are -10000 and 1000000 on
--- every interior row), so two floors stacked in the same shaft can have
--- overlapping, sometimes identical, footprints. Where the rectangles do
--- differ this gets the floor right without any Z data at all; Gnomeregan's
--- four levels are a good case, since the Hall of Gears and the Launch Bay
--- barely overlap.
---
--- Where the footprints don't differ, a floor generated with a real worldZ
--- range (from its own WMO geometry, not the DB2 rows; see
--- hfwm/caves/wmo.py's world_z_range_for_groups) gets first say: if
--- exactly one floor's range contains the player's altitude, that floor
--- wins outright, rectangle area be damned. Fargodeep Mine's upper and
--- lower floors are exactly this case: their X/Y footprints overlap almost
--- entirely, but their real heights (roughly 14-49 vs. 0-24) mostly don't.
---
--- Failing that (no floor here has Z data, both ranges contain the player,
--- or neither does), it falls back to the smallest containing rectangle,
--- and if that doesn't discriminate either it returns the shallowest, with
--- the depth slider as how the player says otherwise. That is not a
--- consolation prize; it is the reason the slider is the feature's main
--- control rather than a nicety.
--- `preferredFloorID` is the floor currently on screen, for the case
--- neither Z nor the rectangles can settle: see the ambiguous-match branch
--- below. Optional; every existing caller that omits it keeps today's
--- behaviour exactly.
---
--- The second return, `confident`, is true only when *position* (Z or the
--- rectangle test) actually discriminated between this place's floors,
--- false whenever the answer instead came from deferring to
--- `preferredFloorID` or from the smallest-rectangle tie-break, since
--- neither of those is really locating the player, just picking something
--- non-disruptive to show. Callers that only care about "which floor's art
--- to draw" (the depth slider following the player) can ignore it exactly
--- as before; a caller that means to assert "the player really is on floor
--- X" (e.g. hiding the map pin on every *other* floor) must not act on a
--- `false` one, or it ends up hiding/showing based on a coin flip dressed
--- up as an answer.
---@param place table
---@param preferredFloorID number|nil
---@return table floor
---@return boolean confident
local function FloorForPosition(place, preferredFloorID)
    local first = place.floors[1]
    if #place.floors == 1 then return first, true end

    local worldX, worldY, worldZ = PlayerWorldXY()
    if not worldX then return first, false end

    local zHit
    for _, floor in ipairs(place.floors) do
        if ContainsZ(floor, worldZ) then
            if zHit then
                -- More than one floor's range contains the player: not a
                -- discriminator here (they overlap at this altitude), fall
                -- through to the rectangle test instead of guessing.
                zHit = nil
                break
            end
            zHit = floor
        end
    end
    if zHit then return zHit, true end

    local matches, best, bestArea = {}, nil, nil
    for _, floor in ipairs(place.floors) do
        if Contains(floor.bounds, worldX, worldY) then
            matches[#matches + 1] = floor
            local area = RectArea(floor.bounds)
            -- Smallest containing rectangle wins: a floor whose footprint is
            -- the whole cave says less about where the player is than one cut
            -- tightly around a single chamber.
            if not bestArea or area < bestArea then
                best, bestArea = floor, area
            end
        end
    end

    if #matches == 1 then
        -- Exactly one floor's rectangle claims this position: the
        -- rectangles *did* discriminate, same as the Z tie-break above.
        return matches[1], true
    end

    -- Zero or multiple matches: position alone couldn't settle it.
    --
    -- More than one floor's rectangle claims this position: Fargodeep's
    -- upper and lower floors overlap almost entirely in the shaft, which is
    -- exactly the case the Z tie-break above exists for, and it just came up
    -- empty. Forcing the smallest-rectangle guess here would flip-flop to a
    -- specific floor and then freeze there, wrong half the time the player
    -- is actually on the other one. Staying on whatever floor is already
    -- showing, if it's one of the genuine candidates, isn't a guess; it's
    -- deferring to the slider, same as this function's fallback always has.
    if #matches > 1 and preferredFloorID then
        for _, floor in ipairs(matches) do
            if floor.id == preferredFloorID then return floor, false end
        end
    end

    return best or first, false
end

--- Every name the client currently offers for where the player is, most
--- specific first. The subzone is the one that names a mine; the zone is what
--- names a dungeon, because inside one the "zone" *is* the dungeon.
local function PlayerAreaNames()
    local out = {}
    for _, fn in ipairs({ GetSubZoneText, GetZoneText, GetMinimapZoneText }) do
        if fn then
            local ok, name = pcall(fn)
            if ok and name and name ~= "" then out[#out + 1] = name end
        end
    end
    return out
end

--- The smallest "indoor" place whose footprint holds (worldX, worldY), or
--- nil. Only while the Other indoors option is on.
---@return table|nil place
local function IndoorAt(mapID, worldX, worldY)
    if not (worldX and Config.db and Config.db.caveOtherIndoors) then return nil end
    local best, bestArea
    for _, place in ipairs(indoorPlaces) do
        if (mapID == nil or place.mapID == mapID)
           and Contains(place.bounds, worldX, worldY) then
            local area = RectArea(place.bounds)
            if not bestArea or area < bestArea then
                best, bestArea = place, area
            end
        end
    end
    return best
end

--- The baked floor the player is standing on, or nil.
---
--- Two routes in, and the instance one is both simpler and stronger:
---
---   In a dungeon the instance map ID identifies the place outright. It is
---   the same number the table was built from and nothing else can produce
---   it, so no name matching is involved at all.
---
---   Out in the world it has to be the area name, and a name alone is not
---   enough: area 57 is "Fargodeep Mine" whether the player is down the shaft
---   or on the hillside above it, and the rectangle cannot tell those apart
---   either because there are no Z bounds to compare. IsOutdoors() is what
---   separates them: a mine is a WMO and the client knows it is inside one.
---
---   This used to carry a per-place exemption from the outdoors check for
---   Fargodeep Mine, on the theory that it was a terrain-cut mine with no
---   enclosing WMO. Two live /hfwm debug captures disproved that: outdoors
---   read true on the hillside and false in the shaft, exactly as it should.
---   The real fault was Contains() reading every place's bounds transposed
---   (see its comment), which made the rectangle test fail everywhere,
---   independent of this gate, so the gate was never the problem, for
---   Fargodeep or anything else, and stays unconditional.
---@param preferredFloorID number|nil the floor currently on screen, passed
---  straight through to FloorForPosition for its ambiguous-match fallback
---@return number|nil floorID
---@return boolean confident  see FloorForPosition's own doc for what this
---  means; always false alongside a nil floorID.
function CaveTable:FindPlayerFloor(preferredFloorID)
    if not loaded then return nil, false end

    local mapID, inInstance = CurrentMapID()

    if inInstance then
        local place = mapID and placeByInstance[mapID]
        if place then
            local floor, confident = FloorForPosition(place, preferredFloorID)
            return floor.id, confident
        end
        -- An instance with no baked table entry: nothing to draw, and
        -- falling through to the name match would only find an unrelated
        -- micro dungeon that happens to share a room name.
        return nil, false
    end

    if IsOutdoors and IsOutdoors() then return nil, false end

    local worldX, worldY = PlayerWorldXY()

    local best, bestArea
    for _, name in ipairs(PlayerAreaNames()) do
        for _, place in ipairs(placesByName[name:lower()] or {}) do
            -- Micro dungeons only out here. A dungeon's rows are in instance
            -- space, so its rectangle would be compared against world
            -- coordinates and could match anywhere.
            if place.kind == "micro"
               and (mapID == nil or place.mapID == mapID) then
                if not worldX or not place.bounds then
                    -- No position or no rectangle: the name and being indoors
                    -- are all there is, so take it.
                    local floor, confident =
                        FloorForPosition(place, preferredFloorID)
                    return floor.id, confident
                end
                if Contains(place.bounds, worldX, worldY) then
                    local area = RectArea(place.bounds)
                    if not bestArea or area < bestArea then
                        best, bestArea = place, area
                    end
                end
            end
        end
        -- The subzone naming a place is a better answer than the zone naming
        -- one, so stop at the first name that resolved rather than letting a
        -- broader name overwrite it.
        if best then break end
    end

    -- No named cave or mine here: a building or other indoor area?
    best = best or IndoorAt(mapID, worldX, worldY)
    if not best then return nil, false end
    local floor, confident = FloorForPosition(best, preferredFloorID)
    return floor.id, confident
end

--- Line-by-line replay of FindPlayerFloor's decision, for /hfwm debug.
---
--- This exists because "resolved floor fell back to C_Map" turned out not to
--- say *which* of FindPlayerFloor's checks was the one that let go: instance
--- routing, the outdoors gate, the name index, and the bounding rectangle all
--- return the same nil from the outside. Each step here is copied rather than
--- factored out into something FindPlayerFloor also calls, so a bug in the
--- trace can never make FindPlayerFloor itself agree with a wrong answer.
---@return string[] lines
function CaveTable:DebugTrace()
    local lines = {}
    local add = function(s) lines[#lines + 1] = s end

    if not loaded then
        add("  findFloor: cave table not loaded")
        return lines
    end

    local mapID, inInstance = CurrentMapID()
    add(("  findFloor: mapID(instance/continent)=%s  inInstance=%s"):format(
        tostring(mapID), tostring(inInstance)))

    if inInstance then
        local place = mapID and placeByInstance[mapID]
        add(("  findFloor: instance route -> place=%s"):format(
            place and place.name or "none (nil floor)"))
        return lines
    end

    local outdoors = (IsOutdoors and IsOutdoors()) and true or false
    add(("  findFloor: outdoors=%s"):format(tostring(outdoors)))
    if outdoors then
        add("  findFloor: outdoors gate -> nil (matches FindPlayerFloor's "
            .. "unconditional early return)")
        return lines
    end

    local worldX, worldY, worldZ = PlayerWorldXY()
    add(("  findFloor: worldX=%s  worldY=%s  worldZ=%s"):format(
        tostring(worldX), tostring(worldY), tostring(worldZ)))

    local names = PlayerAreaNames()
    add("  findFloor: names tried, in order: "
        .. (names[1] and table.concat(names, " | ") or "(none)"))

    for _, name in ipairs(names) do
        local key  = name:lower()
        local list = placesByName[key]
        add(("  findFloor: name=%q indexed=%s candidates=%d"):format(
            name, tostring(list ~= nil), list and #list or 0))
        for _, place in ipairs(list or {}) do
            local kindOK = place.kind == "micro"
            local mapOK  = (mapID == nil or place.mapID == mapID)
            add(("    place=%s kind=%s mapOK=%s(place.mapID=%s)")
                :format(place.name, place.kind, tostring(mapOK),
                    tostring(place.mapID)))
            if kindOK and mapOK then
                if not worldX or not place.bounds then
                    add("      -> no position/bounds: takes this place")
                else
                    local b = place.bounds
                    add(("      -> place.bounds={%.1f,%.1f,%.1f,%.1f} contains(%.1f,%.1f)=%s")
                        :format(b[1], b[2], b[3], b[4], worldX, worldY,
                            tostring(Contains(b, worldX, worldY))))
                end
            end
        end
    end

    local indoor = IndoorAt(mapID, worldX, worldY)
    add(("  findFloor: other indoors option=%s  footprint match=%s"):format(
        tostring(Config.db and Config.db.caveOtherIndoors or false),
        indoor and indoor.name or "none"))
    return lines
end

-------------------------------------------------------------------------------
-- The C_Map-shaped accessors Cave.lua drives the window through
-------------------------------------------------------------------------------

--- Like C_Map.GetMapInfo: name, type and parent for a floor.
function CaveTable:GetMapInfo(floorID)
    local floor = self:GetFloor(floorID)
    if not floor then return nil end
    return {
        mapID       = floorID,
        name        = floor.name,
        mapType     = MAP_TYPE_BY_KIND[floor.place.kind],
        parentMapID = 0,
    }
end

--- The suppression / identity key for the place a floor belongs to, so that
--- closing the window on one floor of a dungeon keeps it closed on the rest.
function CaveTable:GetGroupKey(floorID)
    local floor = self:GetFloor(floorID)
    return floor and floor.place.groupKey or nil
end

--- Are these two floor IDs floors of the same place?
function CaveTable:SamePlace(a, b)
    local fa, fb = self:GetFloor(a), self:GetFloor(b)
    if not fa or not fb then return false end
    return fa.place == fb.place
end

--- Does this floor's place bake every floor from the same aligned canvas
--- (currently only Fargodeep Mine)? CaveRenderer uses this to decide whether
--- the depth slider crossfades floors continuously or hard-swaps them.
function CaveTable:HasSharedCanvas(floorID)
    local floor = self:GetFloor(floorID)
    return floor and floor.place.sharedCanvas and true or false
end

--- cave-satellite-v2 Phase 2: this floor's place's per-piece art list, or
--- nil when this place has no per-piece bake (see CaveData.lua's `pieces`
--- and hfwm/caves/bake.py's generate_mine_pieces). Each entry is
--- `{ fdid, group, name, zMin, zMax }`, a whole-canvas piece anchored at
--- (0,0) exactly like a floor tile, differing only in how much of that
--- canvas its own art actually covers. CaveRenderer uses this list, not
--- `floors`, to decide what to draw once it's present; `floors` continues
--- to drive player-location detection and the title bar regardless.
---@param floorID number|nil
---@return table|nil pieces
function CaveTable:GetPieces(floorID)
    local floor = self:GetFloor(floorID)
    return floor and floor.place.pieces or nil
end

--- The shared canvas size backing `GetPieces`'s list, or nil alongside it.
---@param floorID number|nil
---@return number|nil canvasW, number|nil canvasH
function CaveTable:GetPieceCanvasSize(floorID)
    local floor = self:GetFloor(floorID)
    if not floor then return nil end
    return floor.place.pieceCanvasW, floor.place.pieceCanvasH
end

--- The player's real worldZ (height), independent of any floor's own
--- zMin/zMax window. cave-satellite-v2 Phase 2 needs this raw value to
--- fade the player pin against whichever *piece* the slider says is at
--- the player's own elevation, rather than against a floor-index
--- distance. Reuses the same UnitPosition read PlayerWorldXY and
--- FloorForPosition already trust; see PlayerWorldXY's own comment for
--- why Z is threaded through in one place only.
---@return number|nil worldZ
function CaveTable:GetPlayerWorldZ()
    local _, _, worldZ = PlayerWorldXY()
    return worldZ
end

--- The place's name, which is the window's titlebar. Distinct from the floor
--- name on purpose: the floors of Gnomeregan are called things like "Launch
--- Bay", so a title taken from the floor would never say "Gnomeregan".
function CaveTable:GetPlaceName(floorID)
    local floor = self:GetFloor(floorID)
    -- Indoors have no name of their own; nil sends the title down to the
    -- client's subzone text (Cave:GetAreaTitle), as the real minimap does.
    if floor and floor.place.kind == "indoor" then return nil end
    return floor and floor.place.name or nil
end

--- Like Cave:BuildFloorList: every floor of the place, topmost first.
---@return table[] floors  [{ mapID, name, relativeHeightIndex, zMin, zMax }, ...]
function CaveTable:BuildFloorList(floorID)
    local floor = self:GetFloor(floorID)
    if not floor then return nil end
    local out = {}
    local all = floor.place.floors
    -- The table is generated shallowest-first and the window wants topmost
    -- first, which is the same order; relativeHeightIndex is emitted
    -- descending to match what C_Map hands back for a real map group.
    for i, f in ipairs(all) do
        out[i] = {
            mapID = f.id,
            name  = f.name or ("Level " .. i),
            relativeHeightIndex = #all - i,
            -- Real worldZ range, when this floor was generated with one
            -- (see CaveData.lua's Fargodeep entries), carried through so
            -- CaveRenderer's floor picker can scope a per-piece place's
            -- pieces and depth-slider range to one floor at a time. nil on
            -- every floor with no such data, same as the field it's copied
            -- from.
            zMin = f.zMin,
            zMax = f.zMax,
        }
    end
    return out
end

--- Like C_Map.GetMapArtLayers, minus the zoom-detail layers: the baked table
--- only carries the full-extent base layer, which is the only one a fixed
--- window can use anyway.
function CaveTable:GetArtLayer(floorID)
    local floor = self:GetFloor(floorID)
    if not floor then return nil, nil end
    return 1, {
        layerWidth  = floor.layerW,
        layerHeight = floor.layerH,
        tileWidth   = floor.tileW,
        tileHeight  = floor.tileH,
    }
end

--- Like C_Map.GetMapArtLayerTextures: row-major FileDataIDs.
function CaveTable:GetArtTextures(floorID)
    local floor = self:GetFloor(floorID)
    return floor and floor.tiles or nil
end

--- Blizzard's own real per-floor world-map art for a floor, hand-added to
--- CaveData.lua for the handful of places that have one (see Fargodeep
--- Mine's own floors there for the full story on why this can't just be
--- generated the normal way) -- real FileDataIDs, not this addon's own
--- baked satellite composite. nil for every floor that has nothing hand-
--- added. Used by Cave.lua's HasOriginalArt/GetArtLayer/GetArtTextures,
--- CaveRenderer's own sd/hd toggle.
---@param floorID number|nil
---@return number|nil layerW, number|nil layerH, number|nil tileW,
---        number|nil tileH, table|nil tiles
function CaveTable:GetRealMapArt(floorID)
    local floor = self:GetFloor(floorID)
    if not floor or not floor.realTiles then return nil end
    return floor.realLayerW, floor.realLayerH,
        floor.realTileW, floor.realTileH, floor.realTiles
end

--- Place the player on rotated, WMO-local-coordinate art (see
--- CaveData.lua's Fargodeep entry) via *projection*, the constants
--- hfwm/caves/compose.py's world_to_local_projection bakes offline.
---
--- Two transforms chain together, both cross-validated against real data
--- when they were derived (see world_to_local_projection's own docstring
--- for the validation: a 0.000000-unit local->world->local round trip
--- over every WMO group corner, and the resulting world-space bounding
--- box landing inside CaveData.lua's already-trusted place bounds):
---
---   1. World (worldX, worldY) -> WMO-local (localX, localY). The inverse
---      of the yaw rotation applied when the WMO was placed into the
---      world: a 2x2 matrix that is its own inverse here, so the same
---      cos/sin terms invert it. Given northOffset/eastOffset relative to
---      the placement's own world position,
---        localX = -northOffset * cos(yaw) + eastOffset * sin(yaw)
---        localY =  northOffset * sin(yaw) + eastOffset * cos(yaw)
---   2. WMO-local -> baked pixel. The composite canvas places local (X,
---      Y) at column <- (localX - minLocalX) * scale, row <- (maxLocalY
---      - localY) * scale (build_floor_image's own anchor formula), then
---      the whole canvas was rotated with Image.rotate(angle,
---      expand=True) to align to true north, undone here with the same
---      rotate-about-center formula already validated against Pillow's
---      actual behaviour.
---
---@return number|nil x, number|nil y  0..1 from the art's top-left
local function ProjectPlayerPosition(projection, worldX, worldY)
    local yawRad = math.rad(projection.yaw)
    local cosYaw, sinYaw = math.cos(yawRad), math.sin(yawRad)

    -- Same DB2 axis transposition as Contains() below, just baked into the
    -- projection block instead of `bounds`: hfwm/caves's
    -- world_to_local_projection names its fields placementWorldX/Y as if
    -- they lined up with UnitPosition's X/Y, but placementWorldX is
    -- actually the WMO placement's real *west* (this file's worldY)
    -- coordinate and placementWorldY its real *north* (worldX) coordinate,
    -- swapped, the same way `bounds` turned out to be. Confirmed the same
    -- way that one was: with the fields taken at face value, every sampled
    -- point across Fargodeep's own DB2 rectangle projected miles outside
    -- the baked canvas (0/441 landed in 0..1); swapping which real
    -- coordinate feeds which offset here puts the great majority (378/441)
    -- inside it, with the rest legitimately falling outside the WMO's
    -- footprint near the rectangle's corners. Worth fixing at the root in
    -- world_to_local_projection so a future regenerate doesn't reintroduce
    -- this; until then, this reads the block as it actually is.
    local northOffset = worldY - projection.placementWorldX
    local eastOffset  = projection.placementWorldY - worldX
    local localX = -northOffset * cosYaw + eastOffset * sinYaw
    local localY =  northOffset * sinYaw + eastOffset * cosYaw

    local x0 = (localX - projection.minLocalX) * projection.scale
    local y0 = (projection.maxLocalY - localY) * projection.scale

    local rotRad = math.rad(projection.rotateAngle)
    local cosRot, sinRot = math.cos(rotRad), math.sin(rotRad)
    local dx = x0 - projection.preRotW / 2
    local dy = y0 - projection.preRotH / 2
    local finalX = projection.rotatedW / 2 + dx * cosRot + dy * sinRot
    local finalY = projection.rotatedH / 2 - dx * sinRot + dy * cosRot

    local x, y = finalX / projection.rotatedW, finalY / projection.rotatedH
    -- Outside the art entirely (player is elsewhere in the mine's DB2 area
    -- rectangle but off this floor's own composited footprint); no pin
    -- beats a wrong one, same standard as the bounds path below.
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

--- Like C_Map.GetPlayerMapPosition, as plain normalised x, y.
---
--- The axis mapping is the one hfwm/gamedata/db2.py documents for UiMapAssignment and
--- every known zone confirms: the top of the map is max world X, the left is
--- max world Y. So map x runs down from max Y and map y runs down from max X,
--- which is why neither numerator looks like the other. bounds itself reads
--- as { minY, maxY, minX, maxX }, see Contains's comment, so it is indexed
--- to match that, not the { minX, maxX, minY, maxY } it is documented as.
---
--- This linear stretch only holds for unrotated art that fills its canvas
--- edge to edge. Fargodeep's real WMO-local-coordinate art is rotated to
--- true north (see CaveData.lua's projection block), so it's routed through
--- ProjectPlayerPosition instead whenever the place carries one.
---@param unit string|nil  defaults to "player"
---@return number|nil x, number|nil y  0..1 from the art's top-left
function CaveTable:GetPlayerPosition(floorID, unit)
    local worldX, worldY = PlayerWorldXY(unit)
    if not worldX then return nil end
    return self:WorldToFloor(floorID, worldX, worldY)
end

--- The player's corpse on *floorID*, nil when there is none or it isn't on
--- this floor's footprint. The baked floors aren't UiMaps, so the corpse is
--- read off the outdoor zone the player is in and lifted back to world space;
--- the vector's x is UnitPosition's first return (world Y), as PlayerWorldXY.
---@return number|nil x, number|nil y  0..1 from the art's top-left
function CaveTable:GetCorpsePosition(floorID)
    local zoneMapID = C_Map.GetBestMapForUnit("player")
    local pos = zoneMapID and C_DeathInfo.GetCorpseMapPosition(zoneMapID)
    if not pos then return nil end
    local _, worldPos = C_Map.GetWorldPosFromMapPos(zoneMapID, pos)
    if not worldPos then return nil end
    local worldY, worldX = worldPos:GetXY()
    return self:WorldToFloor(floorID, worldX, worldY)
end

---@return number|nil x, number|nil y  0..1 from the art's top-left
function CaveTable:WorldToFloor(floorID, worldX, worldY)
    local floor = self:GetFloor(floorID)
    if not floor then return nil end

    if floor.place.projection then
        return ProjectPlayerPosition(floor.place.projection, worldX, worldY)
    end

    -- The floor's own rectangle where it has one, the place's otherwise: a
    -- pin placed against the wrong extent is worse than no pin.
    local bounds = floor.bounds or floor.place.bounds
    if not bounds then return nil end
    if not Contains(bounds, worldX, worldY) then return nil end

    local spanY = bounds[2] - bounds[1]
    local spanX = bounds[4] - bounds[3]
    if spanX <= 0 or spanY <= 0 then return nil end

    return (bounds[2] - worldY) / spanY, (bounds[4] - worldX) / spanX
end

--- One line per place, for /hfwm debug.
function CaveTable:DebugLines(limit)
    local out = {}
    for i = 1, math.min(limit or #places, #places) do
        local place = places[i]
        out[i] = ("%-28s %-7s map=%-5s floors=%d areas=%s"):format(
            place.name, place.kind, tostring(place.mapID), #place.floors,
            table.concat(place.areaIDs, ","))
    end
    return out
end
