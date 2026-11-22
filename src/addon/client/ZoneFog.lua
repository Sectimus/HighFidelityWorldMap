-------------------------------------------------------------------------------
-- HFWM-Forever ZoneFog
-- World/Continent "Fog of War": which zones of those maps the player has
-- explored in full.
--
-- A zone counts as fully explored when this character has earned its
-- "Explore <zone>" achievement (VISIT_ACHIEVEMENT). That achievement is the
-- source of truth; the exploration overlay count (ZoneOverlays.lua) is no
-- longer used for this.
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

--- Has the player earned this zone's exploration achievement? That alone
--- decides whether the zone is drawn on the World/Continent maps.
local function overlayExplored(zoneID)
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

--- Has the player explored this zone? Forced debug state wins. Otherwise the
--- zone's Explore achievement, or the overlay count when "Use achievement" is off.
local function fullyExplored(zoneID, useAchievement)
    if forced[zoneID] ~= nil then return forced[zoneID] end
    if forcedAll then return true end
    if useAchievement then return ZoneFog:HasEarnedVisitAchievement(zoneID) end
    return overlayExplored(zoneID)
end

--- Exploration achievement per zone (UiMapID -> the "Explore <zone>" achievement
--- ID, from the pinned Achievement table), for every zone on the World and
--- Continent maps.
local VISIT_ACHIEVEMENT = {
    [1411] = 728,    -- Durotar
    [1412] = 736,    -- Mulgore
    [1413] = 750,    -- The Barrens
    [1416] = 760,    -- Alterac Mountains
    [1417] = 761,    -- Arathi Highlands
    [1418] = 765,    -- Badlands
    [1419] = 766,    -- Blasted Lands
    [1420] = 768,    -- Tirisfal Glades
    [1421] = 769,    -- Silverpine Forest
    [1422] = 770,    -- Western Plaguelands
    [1423] = 771,    -- Eastern Plaguelands
    [1424] = 772,    -- Hillsbrad Foothills
    [1425] = 773,    -- The Hinterlands
    [1426] = 627,    -- Dun Morogh
    [1427] = 774,    -- Searing Gorge
    [1428] = 775,    -- Burning Steppes
    [1429] = 776,    -- Elwynn Forest
    [1430] = 777,    -- Deadwind Pass
    [1431] = 778,    -- Duskwood
    [1432] = 779,    -- Loch Modan
    [1433] = 780,    -- Redridge Mountains
    [1434] = 781,    -- Stranglethorn Vale
    [1435] = 782,    -- Swamp of Sorrows
    [1436] = 802,    -- Westfall
    [1437] = 841,    -- Wetlands
    [1438] = 842,    -- Teldrassil
    [1439] = 844,    -- Darkshore
    [1440] = 845,    -- Ashenvale
    [1441] = 846,    -- Thousand Needles
    [1442] = 847,    -- Stonetalon Mountains
    [1443] = 848,    -- Desolace
    [1444] = 849,    -- Feralas
    [1445] = 850,    -- Dustwallow Marsh
    [1446] = 851,    -- Tanaris
    [1447] = 852,    -- Azshara
    [1448] = 853,    -- Felwood
    [1449] = 854,    -- Un'Goro Crater
    [1450] = 855,    -- Moonglade
    [1451] = 856,    -- Silithus
    [1452] = 857,    -- Winterspring
    [2482] = 62356,  -- Mount Hyjal
    [2548] = 62354,  -- Riverglades
    [2652] = 63684,  -- Shen'dralas
}

--- Has this character been to *zoneID*? Two signals, either one is enough:
---  1. The zone's exploration achievement (VISIT_ACHIEVEMENT), earned on this
---     character (wasEarnedByMe). It completes only after exploring the whole
---     zone, so it implies a visit, including visits made before HFWM was
---     installed.
---  2. The visit flag HFWM records itself (RecordVisit), a fallback for when
---     the achievement lookup is unavailable.
--- Flight points are not used: C_TaxiMap reported Moonglade discovered for
--- characters that had never entered it.
function ZoneFog:HasVisited(zoneID)
    if self:HasEarnedVisitAchievement(zoneID) then return true end
    local db = ns.Config.dbObj and ns.Config.dbObj.char
    return db and db.visited and db.visited[zoneID] == true or false
end

--- True when this character has earned the zone's exploration achievement.
function ZoneFog:HasEarnedVisitAchievement(zoneID)
    local id = VISIT_ACHIEVEMENT[zoneID]
    if not id or not GetAchievementInfo then return false end
    local ok, _, _, _, _, _, _, _, _, _, _, _, _, wasEarnedByMe = pcall(GetAchievementInfo, id)
    return ok and wasEarnedByMe == true
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
    local db = ns.Config.db or {}
    local mode
    if ns.Config:ClassifyMapID(mapID) == "world" then
        mode = db.worldFogOfWar
    else
        mode = db.continentFogOfWar
    end
    local useAchievement = mode ~= "areas"
    local zones = {}
    for _, shape in ipairs(shapes) do
        if fullyExplored(shape[1], useAchievement) then zones[#zones + 1] = shape end
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
