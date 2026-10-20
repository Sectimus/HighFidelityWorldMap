"""Emit IndoorData.lua and IndoorTiles.lua: every other indoor area.

Houses, inns, towers and unnamed caves: every placed WMO that has baked
minimap art and is not one of the hand-registered mines in hfwm/caves/mines.py
(see hfwm/caves/indoors.py for how they are found). Each one is baked exactly
like a mine -- scripts/emit_cave_tiles.py's mine_bake -- and then described
the way CaveData.lua describes a place, with ``kind = "indoor"`` so the addon
only uses it while the "Other indoors" option is on.
Entries in SUBMAPS are the exception: they are not places at all. See submap_lua.

    python3 scripts/emit_indoors.py

IndoorData.lua   HFWMF_INDOOR_PLACES = { place, ... }   (CaveData.lua's shape)
IndoorTiles.lua  HFWMF_INDOOR_TILES  = { [fdid] = ... } (CaveTiles.lua's shape)

Differences from a mine's CaveData.lua entry: no name or areaIDs (the addon
matches an indoor by Map.ID and its ``bounds`` alone, and titles the window
with the client's own subzone text), and per-room ``pieces`` only for a
building tall enough that its rooms really sit at different heights.
"""

import dataclasses
import json
import math
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from emit_cave_tiles import lua_entry, mine_bake  # noqa: E402
from hfwm.caves.bake import _load_groups  # noqa: E402
from hfwm.caves.compose import MINIMAP_PX_PER_UNIT, world_to_local_projection  # noqa: E402
from hfwm.caves.indoors import discover_indoors  # noqa: E402
from hfwm.caves.wmo import world_z_range_for_groups  # noqa: E402
from hfwm.config.build import GAME_BUILD  # noqa: E402
from hfwm.config.paths import (  # noqa: E402
    SUB_MAPS_FILE, INDOOR_DATA_FILE, INDOOR_TILES_FILE, MINIMAP_DB_CACHE)
from hfwm.config.tiles import TILE_WORLD_SIZE  # noqa: E402

# A building gets one art piece per room, fading with the depth slider, only
# when its rooms' heights span more than this (yards). A one-storey house's
# rooms differ by a yard or two; a second storey is 5+ above the first.
MULTI_LEVEL_YARDS = 4.0
# Margin around the rooms' footprint in ``bounds``: the player stands
# inside a wall, not on the room's edge.
BOUNDS_MARGIN = 2.0

# Underground capitals (issue #16): city WMOs whose zone has a world map of
# its own, whose minimap tiles show the mountain above rather than the city.
# Not cave-window places: their baked canvas is drawn on that map instead
# (SubMaps.lua), so the HD/SD toggle works. WMO FileDataID -> (name, UiMapID).
SUBMAPS = {
    # Third field: yards above street a group may start before it is an
    # overhead piece the real minimap shows as a void (None: keep everything).
    # Ironforge's roof pieces start ~40 above the street, every other group
    # within ~8, so anything in 10..38 is the same cut.
    7801267: ("Ironforge", 1455, 20),  # world/wmo/autogen-names/ironforge/20884.wmo
    # Two real levels (tunnels near the surface, the city below): no single
    # street to cull against.
    7675285: ("Undercity", 1458, None),  # world/wmo/autogen-names/undercity/20736.wmo
}


def _num(v, digits=2):
    """Lua literal for *v*, trimmed of trailing zeros."""
    if not isinstance(v, float):
        return str(v)
    return f"{v:.{digits}f}".rstrip("0").rstrip(".")


def _fields(**kw):
    return ",".join(f"{k}={v}" for k, v in kw.items())


def world_bounds(canvas):
    """``{ minX, maxX, minY, maxY }`` of the rooms' footprint, as CaveData.lua
    stores bounds (see world_to_local_projection for the transform)."""
    placement = canvas["placement"]
    yaw = math.radians(placement.rotation[1])
    base_x = 32 * TILE_WORLD_SIZE - placement.position[2]
    base_y = 32 * TILE_WORLD_SIZE - placement.position[0]
    xs, ys = [], []
    for i in canvas["tiled"]:
        x1, y1, _, x2, y2, _ = canvas["groups"][i].bbox
        for lx in (x1, x2):
            for ly in (y1, y2):
                north = -lx * math.cos(yaw) + ly * math.sin(yaw)
                east = lx * math.sin(yaw) + ly * math.cos(yaw)
                xs.append(base_x + north)
                ys.append(base_y - east)
    m = BOUNDS_MARGIN
    return [min(xs) - m, max(xs) + m, min(ys) - m, max(ys) + m]


def place_lua(indoor, canvas, with_pieces):
    spec, groups, placement = indoor.spec, canvas["groups"], canvas["placement"]
    z = {i: world_z_range_for_groups(groups, [i], placement) for i in canvas["tiled"]}
    z_min, z_max = min(a for a, _ in z.values()), max(b for _, b in z.values())
    proj = canvas_projection(canvas)
    w, h = canvas["w1"], canvas["h1"]
    bounds = "{" + ",".join(_num(v) for v in world_bounds(canvas)) + "}"
    head = [f'name="{indoor.label}"', 'kind="indoor"', f"mapID={indoor.map_id}"]
    parts = head + [
        f"bounds={bounds}",
        "projection={" + _fields(**{
            k: _num(v, 6)
            for k, v in proj.items()}) + "}",
    ]
    if with_pieces:
        pieces = ",".join(
            "{" + _fields(fdid=spec.piece_fdid_base + order, group=i,
                          zMin=_num(z[i][0]), zMax=_num(z[i][1])) + "}"
            for order, i in enumerate(canvas["tiled"]))
        parts += [f"pieces={{{pieces}}}", f"pieceCanvasW={w}", f"pieceCanvasH={h}"]
    parts.append("floors={{" + _fields(
        name='""', uiMapID=0, layerW=w, layerH=h, tileW=w, tileH=h,
        cols=1, rows=1, tiles=f"{{{spec.floor_fdid_base}}}",
        zMin=_num(z_min), zMax=_num(z_max)) + "}}")
    return "    {" + ",".join(parts) + "},"


def canvas_projection(canvas):
    return world_to_local_projection(
        canvas["placement"], canvas["minx"], canvas["maxy"], MINIMAP_PX_PER_UNIT,
        canvas["w0"], canvas["h0"], canvas["angle"], canvas["w1"], canvas["h1"])


def canvas_xy(p, north, west):
    """Canvas pixel of a world point: CaveTable.lua's ProjectPlayerPosition,
    unclamped and in pixels. ``placementWorldX`` is a north coordinate."""
    yaw, rot = math.radians(p["yaw"]), math.radians(p["rotateAngle"])
    n, e = north - p["placementWorldX"], p["placementWorldY"] - west
    lx = -n * math.cos(yaw) + e * math.sin(yaw)
    ly = n * math.sin(yaw) + e * math.cos(yaw)
    dx = (lx - p["minLocalX"]) * p["scale"] - p["preRotW"] / 2
    dy = (p["maxLocalY"] - ly) * p["scale"] - p["preRotH"] / 2
    return (p["rotatedW"] / 2 + dx * math.cos(rot) + dy * math.sin(rot),
            p["rotatedH"] / 2 - dx * math.sin(rot) + dy * math.cos(rot))


def submap_lua(canvas, name, ui_map_id, floor_fdid):
    """SubMaps.lua entry: the part of the submap's canvas the city's UiMap shows.

    The canvas is already rotated to true north, so the map's rectangle is an
    axis-aligned box on it: ``submap`` = (x0, y0, x1, y1) in canvas pixels."""
    zone = next(z for z in json.loads(MINIMAP_DB_CACHE.read_text()).values()
                if z["ui_map_id"] == ui_map_id)
    r = zone["regions"][0]
    proj = canvas_projection(canvas)
    x0, y0 = canvas_xy(proj, r["loc_top"], r["loc_left"])
    x1, y1 = canvas_xy(proj, r["loc_bottom"], r["loc_right"])
    # Axis-aligned or the renderer's box is wrong.
    ux, uy = canvas_xy(proj, r["loc_top"], r["loc_right"])
    assert abs(ux - x1) < 0.5 and abs(uy - y0) < 0.5, f"{name}: canvas not north-aligned"
    return (f"    [{ui_map_id}]={{layerW={zone['layer_w']},layerH={zone['layer_h']},"
            f"regions={{}},submap={{fdid={floor_fdid},x0={_num(x0)},y0={_num(y0)},"
            f"x1={_num(x1)},y1={_num(y1)}}}}},  -- {name}")



def is_multi_level(canvas):
    mids = [(g.bbox[2] + g.bbox[5]) / 2
            for g in (canvas["groups"][i] for i in canvas["tiled"])]
    return len(mids) > 1 and max(mids) - min(mids) > MULTI_LEVEL_YARDS


def cull_overhead(spec, name, overhead):
    """*spec* without the groups the real minimap leaves as a void: pieces
    that start more than *overhead* yards above street level (roof beams,
    pillar capitals), street being the median floor of the WMO's tiled
    groups. Judged by a group's bottom, not its top: the Great Forge's
    groups reach far above and below the street and are kept. The client has
    no player height to cull against, so it is fixed here."""
    tiled = [g for g in _load_groups(spec) if g.tile_fdid is not None]
    street = statistics.median(g.bbox[2] for g in tiled)
    high = {g.index for g in tiled if g.bbox[2] - street > overhead}
    print(f"  {name}: street z={street:.1f}, culled {len(high)}/{len(tiled)} groups: {sorted(high)}")
    return dataclasses.replace(
        spec, tile_fdids={i: t for i, t in spec.tile_fdids.items() if i not in high})


def main(limit=None):
    indoors = discover_indoors()[:limit]
    places, tiles, submaps, failed = [], [], [], []
    for n, indoor in enumerate(indoors, 1):
        spec = indoor.spec
        submap = SUBMAPS.get(spec.wmo_fdid)
        try:
            if submap and submap[2] is not None:
                spec = cull_overhead(spec, submap[0], submap[2])
            canvas, entries = mine_bake(spec)
        except (ValueError, TypeError, OSError) as exc:
            failed.append((indoor.spec.key, indoor.label, exc))
            continue
        multi = is_multi_level(canvas)
        floor_fdid = indoor.spec.floor_fdid_base
        if submap:
            submaps.append(submap_lua(canvas, submap[0], submap[1], floor_fdid))
        else:
            places.append(place_lua(indoor, canvas, multi))
        tiles += [lua_entry(f, e) for f, e in entries if multi or f == floor_fdid]
        if n % 100 == 0:
            print(f"    {n}/{len(indoors)}", flush=True)

    for fdid in SUBMAPS.keys() - {i.spec.wmo_fdid for i in indoors}:
        print(f"warning: submap {SUBMAPS[fdid][0]} (WMO {fdid}) not discovered on this build")
    SUB_MAPS_FILE.write_text(
        "-- Auto-generated by scripts/emit_indoors.py - DO NOT EDIT\n"
        "-- Underground capitals' baked canvas, placed on their UiMap (Renderer.lua).\n"
        "HFWMF_SUB_MAPS = {\n" + "\n".join(submaps) + "\n}\n")

    head = "-- Auto-generated by scripts/emit_indoors.py - DO NOT EDIT\n"
    INDOOR_DATA_FILE.write_text(
        head + f'-- Every other indoor area on build {GAME_BUILD}, in CaveData.lua\'s shape.\n'
        "HFWMF_INDOOR_PLACES = {\n" + "\n".join(places) + "\n}\n")
    INDOOR_TILES_FILE.write_text(
        head + "-- Baked indoor floors/pieces as placements of the client's own WMO minimap tiles.\n"
        "HFWMF_INDOOR_TILES = {\n" + "\n".join(tiles) + "\n}\n")
    print(f"{len(places)} indoors -> {INDOOR_DATA_FILE.name} "
          f"({INDOOR_DATA_FILE.stat().st_size} bytes), {INDOOR_TILES_FILE.name} "
          f"({INDOOR_TILES_FILE.stat().st_size} bytes)")
    for key, label, exc in failed:
        print(f"skip {key} ({label}): {exc}")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else None)
