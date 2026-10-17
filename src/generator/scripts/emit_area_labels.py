"""Emit AreaLabelData.lua: the names the world map labels, per UiMap.

Four kinds, all from this build's own DB2 exports (see hfwm.config.endpoints):

  continent  UiMap rows of Type 2, placed at the centre of the art.
  capital    AreaPOI rows with Flags 29 (see CAPITAL_FLAGS).
  town       AreaPOI rows with Flags 5 (see TOWN_FLAGS).
  subzone    WorldMapOverlay rects of outdoor areas (AreaTable ParentAreaID != 0).

A town or capital is placed on the zone map its name resolves to through
WorldMapOverlay (AreaTable name -> overlay art -> UiMap), at the POI's world
position mapped through that map's UiMapAssignment Region_* bounds. A subzone
is placed at the centre of its own overlay rect. Names that do not resolve are
listed and skipped, not guessed.

Each labelled area also gets an ``overlay`` key: its WorldMapOverlay row's
OffsetX,OffsetY,TextureWidth,TextureHeight. C_MapExplorationInfo reports an
explored texture with those same four numbers, so AreaLabels can tell whether
that exact area is explored under Fog of War.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from hfwm.config.build import GAME_BUILD  # noqa: E402
from hfwm.config.paths import AREA_LABEL_DATA_FILE  # noqa: E402
from hfwm.config.tiles import (  # noqa: E402
    EXPECTED_ART_LAYER_DIMS,
    UI_MAP_TYPE_CONTINENT,
    UI_MAP_TYPE_ZONE,
)
from hfwm.gamedata.tables import fetch_pinned_table  # noqa: E402
from hfwm.lua.literals import lua_string  # noqa: E402

# Overlay hit rects are in the art layer's own pixel space.
ART_W, ART_H = EXPECTED_ART_LAYER_DIMS[(4, 3)]

# AreaPOI.Flags. Observed on this build: capitals carry 29, towns 5.
CAPITAL_FLAGS = "29"
TOWN_FLAGS = "5"

# Label height in canvas units at scale 1, per kind. The hand-tuned values
# these replace ranged 11.5-19.5 for towns and capitals and 21-26.5 for
# continents; one value per kind is the simplification. Tune in game.
AREA_LABEL_H = {"continent": 24, "capital": 16, "town": 12, "subzone": 10}

# AreaPOI name -> AreaTable name, where they differ.
ALIASES = {
    "Stormwind": "Stormwind City",
    "The Undercity": "Undercity",
}

KIND_ORDER = {"continent": 0, "capital": 1, "town": 2, "subzone": 3}


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
