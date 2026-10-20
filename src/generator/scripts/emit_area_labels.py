"""Emit AreaLabelData.lua: the names the world map labels, per UiMap.

Five kinds, all from this build's own DB2 exports (see hfwm.config.endpoints):

  continent  UiMap rows of Type 2, placed at the centre of the art.
  capital    AreaPOI rows with Flags 29 (see CAPITAL_FLAGS).
  town       AreaPOI rows with Flags 5 (see TOWN_FLAGS).
  subzone    WorldMapOverlay rects of outdoor areas (AreaTable ParentAreaID != 0).
  district   the named parts of a capital, on that capital's own map (below).

A town or capital is placed on the zone map its name resolves to through
WorldMapOverlay (AreaTable name -> overlay art -> UiMap), at the POI's world
position mapped through that map's UiMapAssignment Region_* bounds. A subzone
is placed at the centre of its own overlay rect. Names that do not resolve are
listed and skipped, not guessed.

A district is a part of a capital's own map (Stormwind City, not Elwynn
Forest): an AreaTable area under the city, placed at the centre of its
terrain chunks, or a name WMOAreaTable gives groups of the city's WMO
(Mage Quarter, Valley of Wisdom, Magic Quarter), placed at the centre of
those groups. WMOAreaTable names buildings and rooms the same way, so a
WMO name is kept only when its footprint is a real share of the city map
(MIN_DISTRICT_SHARE).

Each labelled area also gets an ``overlay`` key: its WorldMapOverlay row's
OffsetX,OffsetY,TextureWidth,TextureHeight. C_MapExplorationInfo reports an
explored texture with those same four numbers, so AreaLabels can tell whether
that exact area is explored under Fog of War.
"""

import json
import math
import struct
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, urlopen

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from emit_zone_shapes import CHUNK, terrain_areas, tiles_needed  # noqa: E402
from hfwm.caves.indoors import _present_all, _read_listfile  # noqa: E402
from hfwm.caves.indoors import WORLD_MAPS  # noqa: E402
from hfwm.caves.wmo import iter_modf_placements, parse_wmo_groups  # noqa: E402
from hfwm.config.build import GAME_BUILD, USER_AGENT  # noqa: E402
from hfwm.config.endpoints import WAGO_CASC_PINNED_FMT  # noqa: E402
from hfwm.config.paths import (  # noqa: E402
    AREA_LABEL_DATA_FILE, CACHE_ROOT, WMO_CACHE_DIR)
from hfwm.config.tiles import (  # noqa: E402
    EXPECTED_ART_LAYER_DIMS,
    TILE_WORLD_SIZE,
    UI_MAP_TYPE_CONTINENT,
    UI_MAP_TYPE_ZONE,
)
from hfwm.gamedata.tables import fetch_pinned_table  # noqa: E402
from hfwm.infra.http import download_casc_cached  # noqa: E402
from hfwm.lua.literals import lua_string  # noqa: E402

# Overlay hit rects are in the art layer's own pixel space.
ART_W, ART_H = EXPECTED_ART_LAYER_DIMS[(4, 3)]

# AreaPOI.Flags. Observed on this build: capitals carry 29, towns 5.
CAPITAL_FLAGS = "29"
TOWN_FLAGS = "5"

# Label height in canvas units at scale 1, per kind. The hand-tuned values
# these replace ranged 11.5-19.5 for towns and capitals and 21-26.5 for
# continents; one value per kind is the simplification. Tune in game.
AREA_LABEL_H = {"continent": 24, "capital": 16, "town": 12, "subzone": 10,
                "district": 12}

# AreaPOI name -> AreaTable name, where they differ.
ALIASES = {
    "Stormwind": "Stormwind City",
    "The Undercity": "Undercity",
}

KIND_ORDER = {"continent": 0, "capital": 1, "town": 2, "subzone": 3, "district": 4}

# A WMO name is a district, not a building or a room, when its groups' bounding
# box covers this share of the city map. Stormwind's smallest district (Old
# Town) is 5%, its largest building (the Keep) 2%; Ironforge's halls and
# Library, which are not districts, still pass. ponytail: one cut-off for
# every city; raise it if halls show up, lower it if a district goes missing.
MIN_DISTRICT_SHARE = 0.03

GROUP_ID_CACHE = CACHE_ROOT / "wmo_group_ids.json"


def _f(row, key):
    try:
        return float(row[key])
    except (KeyError, TypeError, ValueError):
        return None


def _i(row, key):
    try:
        return int(row[key])
    except (KeyError, TypeError, ValueError):
        return None


def _region(row):
    return (_f(row, "Region_0"), _f(row, "Region_1"),
            _f(row, "Region_3"), _f(row, "Region_4"))


def _contains(region, x, y):
    x0, y0, x1, y1 = region
    return x0 <= x <= x1 and y0 <= y <= y1


def _uv(region, x, y):
    """db2.py's convention: u runs along world Y, v along world X."""
    x0, y0, x1, y1 = region
    return (y1 - y) / (y1 - y0), (x1 - x) / (x1 - x0)


def _rect_centre(row):
    """Centre of a WorldMapOverlay hit rect in art pixels, or None."""
    l, r = _f(row, "HitRectLeft"), _f(row, "HitRectRight")
    t, b = _f(row, "HitRectTop"), _f(row, "HitRectBottom")
    if None in (l, r, t, b) or (l == r == t == b == 0):
        return None
    # Top and Bottom are not always ordered; the centre does not care.
    return (l + r) / 2, (t + b) / 2


def _overlay_key(row):
    """The explored-texture key of a WorldMapOverlay row, as Lua writes it."""
    return ",".join(str(_i(row, c)) for c in
                    ("OffsetX", "OffsetY", "TextureWidth", "TextureHeight"))


# Where a WMO group's groupID sits in its file: the MVER chunk (12 bytes), the
# MOGP chunk header (8), then the field's offset in the MOGP header (0x38).
GROUP_ID_AT = 12 + 8 + 0x38


def _read_group_id(fdid):
    """MOGP groupID of one WMO group file, or None if the build lacks it. It
    is in the first bytes, so only those are read."""
    request = Request(WAGO_CASC_PINNED_FMT.format(fdid=fdid),
                      headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=30) as resp:
        head = resp.read(GROUP_ID_AT + 4)
    if len(head) < GROUP_ID_AT + 4:
        return None
    assert head[12:16] == b"PGOM", f"{fdid} is not a WMO group file"
    return struct.unpack_from("<I", head, GROUP_ID_AT)[0]


def _group_indices(wmo_path, count, fdid_of_path, cache):
    """{WMOGroupID: group index} of a WMO. WMOAreaTable names a group by the
    groupID in its file, which is not its index in the root file."""
    fdids = {i: fdid_of_path.get(f"{wmo_path}_{i:03d}") for i in range(count)}
    todo = [f for f in fdids.values() if f and str(f) not in cache]
    with ThreadPoolExecutor(16) as pool:
        cache.update(zip(map(str, todo), pool.map(_read_group_id, todo)))
    return {cache[str(f)]: i for i, f in fdids.items()
            if f and cache.get(str(f)) is not None}


def _world_corners(placement, bbox):
    """World (x, y) of a WMO group's four bounding-box corners, placed as
    emit_indoors.world_bounds does."""
    yaw = math.radians(placement.rotation[1])
    base_x = 32 * TILE_WORLD_SIZE - placement.position[2]
    base_y = 32 * TILE_WORLD_SIZE - placement.position[0]
    x1, y1, _, x2, y2, _ = bbox
    return [(base_x + (-lx * math.cos(yaw) + ly * math.sin(yaw)),
             base_y - (lx * math.sin(yaw) + ly * math.cos(yaw)))
            for lx in (x1, x2) for ly in (y1, y2)]


def _wmo_footprints(cities, named):
    """{city uiMapID: {name: [(x, y), ...]}}: the world corners of every group
    that WMOAreaTable names, in each WMO placed inside a city's region.
    *cities*: uiMapID -> (Map.ID, region); *named*: WMOID -> [(NameSetID,
    WMOGroupID, name)]. A WMOID is the number its file is named by."""
    adts, wmo_paths, _ = _read_listfile()
    wmoid_of = {}
    for fdid, path in wmo_paths.items():
        stem = path.rpartition("/")[2]
        if stem.isdigit() and int(stem) in named:
            wmoid_of[fdid] = int(stem)
    fdid_of_path = {p: f for f, p in wmo_paths.items()}
    cache = (json.loads(GROUP_ID_CACHE.read_text())
             if GROUP_ID_CACHE.exists() else {})

    out = {uid: {} for uid in cities}
    seen = set()  # a WMO on a tile edge is listed by both tiles
    for adt in sorted(_present_all(adts, WMO_CACHE_DIR)):
        data = (WMO_CACHE_DIR / f"{adt}.blp").read_bytes()
        for fdid, placement in iter_modf_placements(data):
            if fdid not in wmoid_of or placement.unique_id in seen:
                continue
            x = 32 * TILE_WORLD_SIZE - placement.position[2]
            y = 32 * TILE_WORLD_SIZE - placement.position[0]
            city = next((uid for uid, (map_id, region) in cities.items()
                         if map_id == WORLD_MAPS[adts[adt]]
                         and _contains(region, x, y)), None)
            if city is None:
                continue
            seen.add(placement.unique_id)
            root = download_casc_cached(fdid, WMO_CACHE_DIR, pinned=True)
            groups = parse_wmo_groups(root.read_bytes(), {})
            index_of = _group_indices(wmo_paths[fdid], len(groups),
                                      fdid_of_path, cache)
            for name_set, group_id, name in named[wmoid_of[fdid]]:
                i = index_of.get(group_id)
                if name_set == placement.name_set and i is not None:
                    out[city].setdefault(name, []).extend(
                        _world_corners(placement, groups[i].bbox))
    GROUP_ID_CACHE.write_text(json.dumps(cache))
    return out


def _terrain_centres(grid, region, wanted):
    """{AreaID: (x, y)}: the centre of each wanted area's terrain chunks inside
    *region*. *grid* is terrain_areas' one-AreaID-per-chunk array."""
    x0, y0, x1, y1 = region
    r0, r1 = (math.floor(32 * 16 - x / CHUNK) for x in (x1, x0))
    c0, c1 = (math.floor(32 * 16 - y / CHUNK) for y in (y1, y0))
    sub = grid[r0:r1 + 1, c0:c1 + 1]
    out = {}
    for aid in wanted:
        rows, cols = np.nonzero(sub == aid)
        if len(rows):
            out[aid] = ((32 * 16 - (rows.mean() + r0 + 0.5)) * CHUNK,
                        (32 * 16 - (cols.mean() + c0 + 0.5)) * CHUNK)
    return out


def main():
    uimap = {_i(r, "ID"): r for r in fetch_pinned_table("UiMap")}
    assignments = fetch_pinned_table("UiMapAssignment")
    xmap = fetch_pinned_table("UiMapXMapArt")
    areatable = fetch_pinned_table("AreaTable")
    overlays = fetch_pinned_table("WorldMapOverlay")
    areapoi = fetch_pinned_table("AreaPOI")

    by_map = {}
    for r in assignments:
        by_map.setdefault(_i(r, "UiMapID"), []).append(r)

    # Lowest PhaseID wins, as in db2.py's _lowest_phase_art.
    art_to_map = {}
    for r in sorted(xmap, key=lambda r: _i(r, "PhaseID") or 0):
        art_to_map.setdefault(_i(r, "UiMapArtID"), _i(r, "UiMapID"))

    def is_zone(uid):
        return uimap.get(uid, {}).get("Type") == str(UI_MAP_TYPE_ZONE)

    names_to_area = {}
    for r in areatable:
        names_to_area.setdefault(r["AreaName_lang"], []).append(r)
    areas_by_id = {_i(r, "ID"): r for r in areatable}

    out = {}  # uiMapID -> [label dict]

    # ---- continents -------------------------------------------------------
    for uid, row in uimap.items():
        if row.get("Type") != str(UI_MAP_TYPE_CONTINENT) or not by_map.get(uid):
            continue
        out.setdefault(uid, []).append({
            "name": row["Name_lang"], "kind": "continent", "u": 0.5, "v": 0.5,
        })

    # ---- which zone map each area is drawn on, and its overlay row --------
    # Every overlay row links its areas to an art, clickable or not, so a
    # capital whose rect is zero-size still resolves to its zone.
    art_for_area = {}   # areaID -> [uiMapID]
    overlay_key = {}    # (uiMapID, areaID) -> (rect size, overlay key)
    subzone_rect = {}   # (uiMapID, areaID) -> (rect size, u, v)
    for r in overlays:
        uid = art_to_map.get(_i(r, "UiMapArtID"))
        if uid is None or not is_zone(uid):
            continue
        key = _overlay_key(r)
        centre = _rect_centre(r)
        size = 0.0
        if centre is not None:
            size = abs(_f(r, "HitRectRight") - _f(r, "HitRectLeft")) * \
                abs(_f(r, "HitRectBottom") - _f(r, "HitRectTop"))
        for k in range(4):
            aid = _i(r, f"AreaID_{k}")
            if not aid:
                continue
            art_for_area.setdefault(aid, []).append(uid)
            if (uid, aid) not in overlay_key or size > overlay_key[(uid, aid)][0]:
                overlay_key[(uid, aid)] = (size, key)
            if centre is None or k != 0:
                continue
            u, v = centre[0] / ART_W, centre[1] / ART_H
            if (uid, aid) not in subzone_rect or size > subzone_rect[(uid, aid)][0]:
                subzone_rect[(uid, aid)] = (size, u, v)

    # ---- towns and capitals ----------------------------------------------
    unresolved = []
    placed = set()  # (uiMapID, name)
    for poi in areapoi:
        if poi["Flags"] == CAPITAL_FLAGS:
            kind = "capital"
        elif poi["Flags"] == TOWN_FLAGS:
            kind = "town"
        else:
            continue
        name = poi["Name_lang"]
        X, Y = _f(poi, "Pos_0"), _f(poi, "Pos_1")
        cont = _i(poi, "ContinentID")
        if X is None or Y is None:
            unresolved.append(name)
            continue

        cands = []  # (uiMapID, areaID)
        for a in names_to_area.get(ALIASES.get(name, name), []):
            aid = _i(a, "ID")
            for uid in art_for_area.get(aid, []):
                if (uid, aid) not in cands:
                    cands.append((uid, aid))

        done = False
        for uid, aid in cands:
            asg = next((a for a in by_map.get(uid, [])
                        if _i(a, "MapID") == cont
                        and _contains(_region(a), X, Y)), None)
            if asg is None:
                continue
            if (uid, name) not in placed:
                placed.add((uid, name))
                u, v = _uv(_region(asg), X, Y)
                entry = {"name": name, "kind": kind, "u": u, "v": v}
                if (uid, aid) in overlay_key:
                    entry["overlay"] = overlay_key[(uid, aid)][1]
                out.setdefault(uid, []).append(entry)
            done = True
            break
        if not done:
            unresolved.append(name)

    # ---- subzones -----------------------------------------------------------
    areas_by_id = {_i(r, "ID"): r for r in areatable}
    for (uid, aid), (_, u, v) in sorted(subzone_rect.items()):
        at = areas_by_id.get(aid)
        if not at or _i(at, "ParentAreaID") in (0, None):
            continue
        name = at["AreaName_lang"]
        if not name or (uid, name) in placed:
            continue
        placed.add((uid, name))
        out.setdefault(uid, []).append({
            "name": name, "kind": "subzone", "u": u, "v": v,
            "overlay": overlay_key[(uid, aid)][1],
        })

    # ---- city districts -----------------------------------------------------
    # The capitals' own maps: the zone map each capital's AreaTable row owns.
    owner = {_i(r, "AreaID"): r for r in assignments
             if _i(r, "AreaID") and is_zone(_i(r, "UiMapID"))}
    cities = {}  # city uiMapID -> (assignment row, the city's AreaID)
    for poi in areapoi:
        if poi["Flags"] != CAPITAL_FLAGS:
            continue
        for a in names_to_area.get(ALIASES.get(poi["Name_lang"], poi["Name_lang"]), []):
            asg = owner.get(_i(a, "ID"))
            if asg:
                cities[_i(asg, "UiMapID")] = (asg, _i(a, "ID"))
    regions = {uid: _region(asg) for uid, (asg, _) in cities.items()}

    def under(aid, root):
        for _ in range(8):
            if aid == root:
                return True
            aid = _i(areas_by_id.get(aid, {}), "ParentAreaID")
            if not aid:
                return False
        return False

    wmo_names = {}  # WMOID -> [(NameSetID, WMOGroupID, name)]; group -1 is the root
    for r in fetch_pinned_table("WMOAreaTable"):
        if r["AreaName_lang"] and _i(r, "WMOGroupID") >= 0:
            wmo_names.setdefault(_i(r, "WMOID"), []).append(
                (_i(r, "NameSetID"), _i(r, "WMOGroupID"), r["AreaName_lang"]))
    footprints = _wmo_footprints(
        {uid: (_i(asg, "MapID"), regions[uid]) for uid, (asg, _) in cities.items()},
        wmo_names)
    grids = terrain_areas(tiles_needed({
        uid: [dict(map_id=_i(asg, "MapID"), top=regions[uid][2],
                   bottom=regions[uid][0], left=regions[uid][3],
                   right=regions[uid][1])]
        for uid, (asg, _) in cities.items()}))

    for uid, (asg, city_aid) in sorted(cities.items()):
        region = regions[uid]
        x0, y0, x1, y1 = region
        found = {}  # casefolded name -> (name, x, y)
        # Terrain: AreaTable areas under the city.
        under_city = [a for a in areatable
                      if _i(a, "ID") != city_aid and under(_i(a, "ID"), city_aid)]
        centres = _terrain_centres(grids[_i(asg, "MapID")], region,
                                   {_i(a, "ID") for a in under_city})
        for a in under_city:
            if a["AreaName_lang"] and _i(a, "ID") in centres:
                found.setdefault(a["AreaName_lang"].casefold(),
                                 (a["AreaName_lang"], *centres[_i(a, "ID")]))
        # WMO groups. A name that is another zone's area (Undercity's "Ruins
        # of Lordaeron"), the city's own, or lower-case debug text is not one.
        city_name = areas_by_id[city_aid]["AreaName_lang"]
        for name, pts in footprints[uid].items():
            xs, ys = zip(*pts)
            share = (max(xs) - min(xs)) * (max(ys) - min(ys)) / ((x1 - x0) * (y1 - y0))
            areas = names_to_area.get(name, [])
            if (not name[:1].isupper() or name.casefold() == city_name.casefold()
                    or share < MIN_DISTRICT_SHARE
                    or (areas and not any(under(_i(r, "ID"), city_aid) for r in areas))):
                continue
            found.setdefault(name.casefold(),
                             (name, sum(xs) / len(xs), sum(ys) / len(ys)))
        for name, x, y in found.values():
            if _contains(region, x, y):
                u, v = _uv(region, x, y)
                out.setdefault(uid, []).append(
                    {"name": name, "kind": "district", "u": u, "v": v})
        print(f"  {uimap[uid]['Name_lang']}: "
              + ", ".join(sorted(n for n, _, _ in found.values())))

    _write(out)
    counts = {}
    for labels in out.values():
        for d in labels:
            counts[d["kind"]] = counts.get(d["kind"], 0) + 1
    print(f"wrote {AREA_LABEL_DATA_FILE.name}: {counts}")
    if unresolved:
        print(f"  unresolved POI names ({len(set(unresolved))}): "
              + ", ".join(sorted(set(unresolved))))


def _write(out):
    with open(AREA_LABEL_DATA_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Auto-generated by scripts/emit_area_labels.py - DO NOT EDIT\n")
        f.write(f"-- World-map labels on build {GAME_BUILD}, keyed by UiMapID.\n")
        f.write("-- u/v: centre, 0..1 from the map's top-left. h: canvas units\n")
        f.write("-- at label scale 1. overlay: the area's explored-texture key,\n")
        f.write("-- for Fog of War. Read by AreaLabels.lua.\n")
        f.write("HFWMF_AREA_LABELS = {\n")
        for uid in sorted(out):
            f.write(f"    [{uid}] = {{\n")
            for d in sorted(out[uid], key=lambda d: (KIND_ORDER[d["kind"]], d["name"])):
                line = (
                    f"        {{ name = {lua_string(d['name'])}, "
                    f"kind = \"{d['kind']}\", h = {AREA_LABEL_H[d['kind']]}, "
                    f"u = {d['u']:.3f}, v = {d['v']:.3f}"
                )
                if d.get("overlay"):
                    line += f", overlay = {lua_string(d['overlay'])}"
                f.write(line + " },\n")
            f.write("    },\n")
        f.write("}\n")


if __name__ == "__main__":
    main()
