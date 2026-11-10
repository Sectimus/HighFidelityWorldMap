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
-- the mask that crops the map to its border, are baked into ZoneShapes.lua
-- and ZoneMasks\ (scripts/emit_zone_shapes.py) from the game's own
-- per-chunk area data, so the outline is the zone's real border.
-------------------------------------------------------------------------------
local addonName, ns = ...
local ZoneFog = ns.ZoneFog

local OVERLAYS = HFWMF_ZONE_OVERLAYS or {}
local SHAPES   = HFWMF_ZONE_SHAPES or {}

--- Debug override from /hfwm debug fog show|hide: true/false, nil = real state.
local forced = {}

--- Debug override from /hfwm debug fog show (no zone): every zone explored, this session.
local forcedAll = false

--- Has the player explored every overlay of this zone?
local function fullyExplored(zoneID)
    if forced[zoneID] ~= nil then return forced[zoneID] end
    if forcedAll then return true end
    local want = OVERLAYS[zoneID]
    if not want then return false end
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
