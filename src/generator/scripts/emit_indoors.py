"""Emit IndoorData.lua and IndoorTiles.lua: every other indoor area.

Houses, inns, towers and unnamed caves: every placed WMO that has baked
minimap art and is not one of the hand-registered mines in hfwm/caves/mines.py
(see hfwm/caves/indoors.py for how they are found). Each one is baked exactly
like a mine -- scripts/emit_cave_tiles.py's mine_bake -- and then described
the way CaveData.lua describes a place, with ``kind = "indoor"`` so the addon
only uses it while the "Other indoors" option is on.
Entries in HUBS are the exception: ``kind = "hub"``, with a name and ``areaIDs``, matched by zone name like a named cave.

    python3 scripts/emit_indoors.py

IndoorData.lua   HFWMF_INDOOR_PLACES = { place, ... }   (CaveData.lua's shape)
IndoorTiles.lua  HFWMF_INDOOR_TILES  = { [fdid] = ... } (CaveTiles.lua's shape)

Differences from a mine's CaveData.lua entry: no name or areaIDs (hubs excepted; the addon
matches an indoor by Map.ID and its ``bounds`` alone, and titles the window
with the client's own subzone text), and per-room ``pieces`` only for a
building tall enough that its rooms really sit at different heights.
"""

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from emit_cave_tiles import lua_entry, mine_bake  # noqa: E402
from hfwm.caves.compose import MINIMAP_PX_PER_UNIT, world_to_local_projection  # noqa: E402
from hfwm.caves.indoors import discover_indoors  # noqa: E402
from hfwm.caves.wmo import world_z_range_for_groups  # noqa: E402
from hfwm.config.build import GAME_BUILD  # noqa: E402
from hfwm.config.paths import INDOOR_DATA_FILE, INDOOR_TILES_FILE  # noqa: E402
from hfwm.config.tiles import TILE_WORLD_SIZE  # noqa: E402

# A building gets one art piece per room, fading with the depth slider, only
# when its rooms' heights span more than this (yards). A one-storey house's
# rooms differ by a yard or two; a second storey is 5+ above the first.
MULTI_LEVEL_YARDS = 4.0
# Margin around the rooms' footprint in ``bounds``: the player stands
# inside a wall, not on the room's edge.
BOUNDS_MARGIN = 2.0

# Underground capitals (issue #16): city WMOs that are a cave and indoors at
# once. Emitted as kind="hub" with their zone's AreaTable ID, so the addon
# finds them by zone name like a named cave (always on with the cave map)
# rather than only under "Other indoors". WMO FileDataID -> (name, areaID).
HUBS = {
    7801267: ("Ironforge", 1537),  # world/wmo/autogen-names/ironforge/20884.wmo
    7675285: ("Undercity", 1497),  # world/wmo/autogen-names/undercity/20736.wmo
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
    proj = world_to_local_projection(
        placement, canvas["minx"], canvas["maxy"], MINIMAP_PX_PER_UNIT,
        canvas["w0"], canvas["h0"], canvas["angle"], canvas["w1"], canvas["h1"])
    w, h = canvas["w1"], canvas["h1"]
    bounds = "{" + ",".join(_num(v) for v in world_bounds(canvas)) + "}"
    hub = HUBS.get(spec.wmo_fdid)
    if hub:
        head = [f'name="{hub[0]}"', 'kind="hub"', f"mapID={indoor.map_id}",
                f"areaIDs={{{hub[1]}}}"]
    else:
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


def is_multi_level(canvas):
    mids = [(g.bbox[2] + g.bbox[5]) / 2
            for g in (canvas["groups"][i] for i in canvas["tiled"])]
    return len(mids) > 1 and max(mids) - min(mids) > MULTI_LEVEL_YARDS


def main(limit=None):
    indoors = discover_indoors()[:limit]
    places, tiles, failed = [], [], []
    for n, indoor in enumerate(indoors, 1):
        try:
            canvas, entries = mine_bake(indoor.spec)
        except (ValueError, TypeError, OSError) as exc:
            failed.append((indoor.spec.key, indoor.label, exc))
            continue
        multi = is_multi_level(canvas)
        floor_fdid = indoor.spec.floor_fdid_base
        places.append(place_lua(indoor, canvas, multi))
        tiles += [lua_entry(f, e) for f, e in entries if multi or f == floor_fdid]
        if n % 100 == 0:
            print(f"    {n}/{len(indoors)}", flush=True)

    for fdid in HUBS.keys() - {i.spec.wmo_fdid for i in indoors}:
        print(f"warning: hub {HUBS[fdid][0]} (WMO {fdid}) not discovered on this build")

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
