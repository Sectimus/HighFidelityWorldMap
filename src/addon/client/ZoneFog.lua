-------------------------------------------------------------------------------
-- HFWM-Forever ZoneFog
-- World/Continent "Fog of War": which zones of those maps the player has
-- explored in full.
--
-- A zone counts as fully explored when the number of distinct overlays
-- C_MapExplorationInfo reports for it reaches the total baked into
-- ZoneOverlays.lua (scripts/emit_zone_overlays.py). One missing patch means
-- the whole zone is not explored. All or nothing, deliberately.
--
-- Where each zone lies on Kalimdor, Eastern Kingdoms and the World map, and
-- the mask that crops the map to its border, are built from the hand traces in
-- continent-fog-masks/ by scripts/build_zone_masks.py: ZoneShapes.lua and
-- ZoneMasks\.
-------------------------------------------------------------------------------
local addonName, ns = ...
local ZoneFog = ns.ZoneFog

local OVERLAYS = HFWMF_ZONE_OVERLAYS or {}
local SHAPES   = HFWMF_ZONE_SHAPES or {}

--- Debug override from /hfwm debug fog show|hide: true/false, nil = real state.
local forced = {}

--- Debug override from /hfwm debug fog show (no zone): every zone explored, this session.
local forcedAll = false

--- Moonglade's single exploration overlay is also filled by continent-level
--- exploration, so on its own it says nothing about the player having been
--- there. Count it as explored only once the player has stood in it (see
--- RecordVisit). Keyed by UiMapID; add other zones here if they need it.
local VISIT_GATED = { [1450] = true }

--- Has the player explored every overlay of this zone?
local function fullyExplored(zoneID)
    if forced[zoneID] ~= nil then return forced[zoneID] end
    if forcedAll then return true end
    local want = OVERLAYS[zoneID]
    if not want then return false end
    if VISIT_GATED[zoneID] and not ZoneFog:HasVisited(zoneID) then return false end
    local seen, n = {}, 0
    for _, t in ipairs(C_MapExplorationInfo.GetExploredMapTextures(zoneID) or {}) do
        local key = t.offsetX .. "," .. t.offsetY .. ","
            .. t.textureWidth .. "," .. t.textureHeight
        if not seen[key] then
            seen[key] = true
            n = n + 1
        end
    end
    return n >= want
end

--- Has this character ever been inside *zoneID*? Persisted per character in
--- HighFidelityWorldMapDB.visited, so it survives sessions and does not
--- depend on when HFWM was installed. Only zones in VISIT_GATED are asked.
function ZoneFog:HasVisited(zoneID)
    local db = ns.Config.dbObj and ns.Config.dbObj.char
    return db and db.visited and db.visited[zoneID] == true or false
end

--- Record that the player is inside *zoneID*. Called on login and zone change.
function ZoneFog:RecordVisit(zoneID)
    if not VISIT_GATED[zoneID] then return end
    local db = ns.Config.dbObj and ns.Config.dbObj.char
    if not db then return end
    db.visited = db.visited or {}
    db.visited[zoneID] = true
end

local warned = {}

--- The fully explored zones of *mapID*. Each entry is { zoneUiMapID, u0, v0,
--- u1, v1 }: the box, as 0-1 coordinates over the map, that the zone's mask
--- (ZoneMasks\z<UiMapID>) covers. Nil when no outlines are baked for
--- this map, so the caller draws it whole rather than blank.
---@param mapID number a World or Continent map
---@return table[]|nil
function ZoneFog:Explored(mapID)
    local shapes = SHAPES[mapID]
    if not shapes then
        if not warned[mapID] then
            warned[mapID] = true
            ns.P(("Fog of War: no zone outlines for map %d, so it is drawn in full."):format(mapID))
        end
        return nil
    end
    local zones = {}
    for _, shape in ipairs(shapes) do
        if fullyExplored(shape[1]) then zones[#zones + 1] = shape end
    end
    return zones
end

--- Debug: treat *zoneID* as fully explored (true) or not (false), this session.
function ZoneFog:SetForced(zoneID, explored)
    forced[zoneID] = explored
end

--- Debug: treat every zone as fully explored (true) or real state (false), this session.
function ZoneFog:SetForcedAll(explored)
    forcedAll = explored
end
