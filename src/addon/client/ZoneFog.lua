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

--- Has this character been to *zoneID*? Two signals, either one is enough:
---  1. Flight points: C_TaxiMap.GetTaxiNodesForMap reports isUndiscovered per
---     node, and a node is only discovered by visiting the area. This is
---     per-character game state, so it also covers visits made before HFWM
---     was installed.
---  2. The visit flag HFWM records itself (RecordVisit), a fallback for when
---     the taxi data is unavailable or the zone has no flight point.
function ZoneFog:HasVisited(zoneID)
    if self:HasDiscoveredTaxiNode(zoneID) then return true end
    local db = ns.Config.dbObj and ns.Config.dbObj.char
    return db and db.visited and db.visited[zoneID] == true or false
end

--- True when *zoneID* has a flight point this character has discovered.
function ZoneFog:HasDiscoveredTaxiNode(zoneID)
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return false end
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, zoneID)
    if not ok or type(nodes) ~= "table" then return false end
    for _, node in ipairs(nodes) do
        if node.isUndiscovered == false then return true end
    end
    return false
end

--- Record that the player is inside *zoneID*. Called on login and zone change.
function ZoneFog:RecordVisit(zoneID)
    if not VISIT_GATED[zoneID] then return end
    local db = ns.Config.dbObj and ns.Config.dbObj.char
    if not db then return end
    db.visited = db.visited or {}
    db.visited[zoneID] = true
end

--- True when an explored rect (C_MapExplorationInfo, layer pixels) lies inside
--- the box of a visit-gated zone on *mapID* that this character has not visited.
--- Such rects are Moonglade's continent-level overlay and must not be drawn.
function ZoneFog:RectGated(mapID, rect, layerW, layerH)
    local shapes = SHAPES[mapID]
    if not shapes then return false end
    local cx = (rect.offsetX + rect.textureWidth / 2) / layerW
    local cy = (rect.offsetY + rect.textureHeight / 2) / layerH
    for _, shape in ipairs(shapes) do
        local zone = shape[1]
        if VISIT_GATED[zone] and cx >= shape[2] and cx <= shape[4]
            and cy >= shape[3] and cy <= shape[5] then
            return not self:HasVisited(zone)
        end
    end
    return false
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
