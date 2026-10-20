"""Emit CaveTiles.lua: baked cave floors/pieces as placements of the client's tiles.

Experiment (branch reuse-game-assets).  The baked cave art (WorldMap/<Cave>/*.blp)
is built from Blizzard's per-room WMO minimap tiles: each cropped to its
opaque content, placed at its MOGI bounding box (1.993 px/unit), and the
whole canvas rotated by (placement yaw - 90) with expand=True.  Every one of
those tiles is a real game file, so instead of shipping the composite, record
where each tile lands and let CaveRenderer.lua draw the client's own copies.

The placement is the bake's (bake.py / compose.py / fetch.py) with two
corrections that remove the seams the baked art has between rooms: a room's
opaque crop is placed where it really sits inside its bounding-box corner
region (the bake slid it to the corner), and every room is then stretched
outward by GROW px, and by half the gap toward any neighbour within MAX_GAP,
so touching rooms overlap.  Keys are the synthetic FDIDs CaveData.lua already
uses for the BLPs; nothing there changes.

    python3 scripts/emit_cave_tiles.py              # every discovered mine
    python3 scripts/emit_cave_tiles.py fargodeep    # just those MINES keys

Each entry: { w, h, a, l = { {fdid, srcW, srcH, x0, y0, w, h, cx, cy, dw, dh}, ... } }
  w,h  final (rotated) canvas size       a   rotation applied, degrees (PIL CCW)
  l    leaves in paint order: take region (x0,y0,w,h) of the srcW x srcH
       texture, stretch it to dw x dh, centre it at (cx,cy) in the final
       canvas and rotate it by a.
"""

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from PIL import Image  # noqa: E402

from hfwm.caves.bake import _load_groups, _shared_canvas  # noqa: E402
from hfwm.caves.compose import (  # noqa: E402
    MINIMAP_PX_PER_UNIT,
    split_floors_by_height,
    world_align_rotation_degrees,
)
from hfwm.caves.fetch import (  # noqa: E402
    _cached_path,
    fetch_group_tile,
    fetch_wmo_world_placement,
    stitch_subtiles,
)
from hfwm.caves.mines import MINES  # noqa: E402
from hfwm.config.paths import WMO_TILE_CACHE_DIR  # noqa: E402

OUT = ROOT.parent / "addon" / "client" / "data" / "CaveTiles.lua"
MAX_GAP = 6      # px between neighbouring rooms' tiles that still count as one cave
MIN_SHARED = 4   # px of shared edge needed for two rooms to count as neighbours
GROW = 1.5      # px every single-tile room is grown on each side, at least


def group_leaves(tile_fdid, extent_px=None):
    """Source rectangles making up one WMO group's tile.

    Returns ``(w, h, leaves)`` with ``w x h`` the tile size and each leaf
    ``(fdid, srcW, srcH, x0, y0, w, h, offX, offY)`` -- a region of one
    texture and where its top-left sits inside the tile.

    A plain tile is a power-of-two texture with the room packed into its
    bottom-left corner, ``ceil(bbox extent * scale)`` pixels across.  The
    bake cropped it to its opaque pixels and then placed the crop at the
    corner, which moves the room whenever its walls leave a transparent edge
    (171 of 245 groups) and opens a gap beside it.  Given ``extent_px`` the
    leaf is still the opaque crop, but its offset is where the crop really
    sits inside that corner region, so the room lands where it belongs.
    """
    if not isinstance(tile_fdid, dict):
        img = Image.open(_cached_path(tile_fdid, WMO_TILE_CACHE_DIR)).convert("RGBA")
        bbox = img.split()[-1].getbbox() or (0, 0) + img.size
        ox = oy = 0
        if extent_px is not None:
            # Origin of the corner region, widened to include any opaque
            # pixel just outside it.
            oy = bbox[1] - max(0, min(img.height - math.ceil(round(extent_px[1], 6)), bbox[1]))
        return (bbox[2] - bbox[0], bbox[3] - bbox[1],
                [(tile_fdid, img.width, img.height, bbox[0], bbox[1],
                  bbox[2] - bbox[0], bbox[3] - bbox[1], bbox[0] if extent_px else 0, oy)])

    canvas, rects = stitch_subtiles(tile_fdid)
    bbox = canvas.split()[-1].getbbox() or (0, 0) + canvas.size
    # The same corner-region correction as a plain tile, on the whole grid.
    ox = oy = 0
    if extent_px is not None:
        ox = bbox[0]
        oy = bbox[1] - max(0, min(canvas.height - math.ceil(round(extent_px[1], 6)), bbox[1]))
    leaves = []
    for key, f in sorted(tile_fdid.items()):
        tx, ty, tw, th = rects[key]
        ix0, iy0 = max(bbox[0], tx), max(bbox[1], ty)
        ix1, iy1 = min(bbox[2], tx + tw), min(bbox[3], ty + th)
        if ix1 <= ix0 or iy1 <= iy0:
            continue
        leaves.append((f, tw, th, ix0 - tx, iy0 - ty,
                       ix1 - ix0, iy1 - iy0, ix0 - bbox[0] + ox, iy0 - bbox[1] + oy))
    return bbox[2] - bbox[0], bbox[3] - bbox[1], leaves


def mine_entries(spec):
    """Yield ``(synthetic_fdid, entry_dict)`` for every floor and piece."""
    yield from mine_bake(spec)[1]


# Floors this many yards apart are different levels of a building, not one.
LEVEL_GAP = 3


def layer_leaves(leaves, zs, angle):
    """*leaves* (painted low to high, *zs* their floor heights) with a 12th
    value: the ARTWORK sublevel (0..15, minus 8 in game) to draw each on. The
    game leaves the paint order of textures on the same sublevel undefined, so
    each leaf sits one sublevel above the highest leaf it overlaps that has a
    floor more than LEVEL_GAP yards lower. Leaves at one level (street-level
    pieces differ by tenths of a yard) or not overlapping share a sublevel."""
    ac, as_ = abs(math.cos(math.radians(angle))), abs(math.sin(math.radians(angle)))
    boxes = []
    for leaf in leaves:
        cx, cy, dw, dh = leaf[7:11]
        hx, hy = (dw * ac + dh * as_) / 2, (dw * as_ + dh * ac) / 2
        boxes.append((cx - hx, cx + hx, cy - hy, cy + hy))
    subs = []
    for i, (l, r, t, b) in enumerate(boxes):
        sub = 0
        for j in range(i):
            l2, r2, t2, b2 = boxes[j]
            if (zs[i] - zs[j] > LEVEL_GAP and min(r, r2) - max(l, l2) > 2
                    and min(b, b2) - max(t, t2) > 2):
                sub = max(sub, subs[j] + 1)
        subs.append(sub)
    if subs and max(subs) > 15:
        print(f"  warning: {max(subs) + 1} overlapping layers, only 16 sublevels")
    return [leaf + [min(s, 15)] for leaf, s in zip(leaves, subs)]


def mine_bake(spec):
    """``(canvas, entries)``: *entries* as :func:`mine_entries` yields them,
    *canvas* the numbers the placement was composed with (``groups`` by
    index, ``tiled`` indices, ``minx``/``maxy``/``w0``/``h0`` the pre-rotation
    canvas, ``w1``/``h1`` the rotated one, ``placement``, ``angle``)."""
    groups = _load_groups(spec)
    by_index = {g.index: g for g in groups}
    tiled = sorted(i for i in by_index if by_index[i].tile_fdid is not None)
    tiles = {i: fetch_group_tile(by_index[i].tile_fdid) for i in tiled}
    scale = MINIMAP_PX_PER_UNIT
    minx, maxy, w0, h0 = _shared_canvas(by_index, tiled, tiles, scale)

    placement = fetch_wmo_world_placement(
        spec.adt_obj0_fdid, spec.wmo_fdid, spec.modf_unique_id)
    angle = world_align_rotation_degrees(placement.rotation[1])
    w1, h1 = Image.new("RGBA", (w0, h0)).rotate(angle, expand=True).size
    cos, sin = math.cos(math.radians(angle)), math.sin(math.radians(angle))

    def extent_px(g):
        return ((g.bbox[3] - g.bbox[0]) * scale, (g.bbox[4] - g.bbox[1]) * scale)

    def corner(g):
        return round((g.bbox[0] - minx) * scale), round((maxy - g.bbox[4]) * scale)

    # Where two rooms' tiles sit within MAX_GAP px of each other with a real
    # stretch of shared edge, each is grown toward the other by half the gap
    # (rounded up) so they meet; the room's own edge pixels are stretched,
    # nothing is invented.  ext[idx] = (left, top, right, bottom) growth.
    rect = {}
    for i in tiled:
        w, h, lv = group_leaves(by_index[i].tile_fdid, extent_px(by_index[i]))
        gx, gy = corner(by_index[i])
        rect[i] = (gx + min(l[7] for l in lv), gy + min(l[8] for l in lv), w, h)
    ext = {i: [0, 0, 0, 0] for i in tiled}
    for a in tiled:
        for b in tiled:
            if a >= b:
                continue
            ax, ay, aw, ah = rect[a]
            bx, by_, bw, bh = rect[b]
            if min(ay + ah, by_ + bh) - max(ay, by_) >= MIN_SHARED:
                gap = max(bx - (ax + aw), ax - (bx + bw))
                if 0 < gap <= MAX_GAP:
                    lo, hi = (a, b) if ax < bx else (b, a)
                    ext[lo][2] = max(ext[lo][2], -(-gap // 2))
                    ext[hi][0] = max(ext[hi][0], -(-gap // 2))
            if min(ax + aw, bx + bw) - max(ax, bx) >= MIN_SHARED:
                gap = max(by_ - (ay + ah), ay - (by_ + bh))
                if 0 < gap <= MAX_GAP:
                    lo, hi = (a, b) if ay < by_ else (b, a)
                    ext[lo][3] = max(ext[lo][3], -(-gap // 2))
                    ext[hi][1] = max(ext[hi][1], -(-gap // 2))

    def placed(idx):
        g = by_index[idx]
        gx, gy = corner(g)
        _, _, leaves = group_leaves(g.tile_fdid, extent_px(g))
        grow = [max(e, GROW) for e in ext[idx]] if len(leaves) == 1 else [0, 0, 0, 0]
        out = []
        for f, sw, sh, x0, y0, w, h, ox, oy in leaves:
            dw, dh = w + grow[0] + grow[2], h + grow[1] + grow[3]
            dx = gx + ox - grow[0] + dw / 2 - w0 / 2
            dy = gy + oy - grow[1] + dh / 2 - h0 / 2
            out.append([f, sw, sh, x0, y0, w, h,
                        round(w1 / 2 + dx * cos + dy * sin, 2),
                        round(h1 / 2 - dx * sin + dy * cos, 2), dw, dh])
        return out

    entries = []
    if spec.single_floor:
        floors = {"floor": sorted(tiled)}
    else:
        lower, upper = split_floors_by_height(groups)
        floors = {"upper": upper, "lower": lower}
    for i, name in enumerate(floors):
        # Later leaves paint over earlier ones, so lowest floor first: a lower
        # room's art must sit under the higher one above it. The floor (a
        # group's bottom), not its mid-height: a tall cavern whose floor is
        # far down must not cover the small rooms standing in it.
        ordered = sorted(floors[name], key=lambda idx: (by_index[idx].bbox[2], -by_index[idx].bbox[5], idx))
        placed_z = [(by_index[idx].bbox[2], leaf) for idx in ordered for leaf in placed(idx)]
        leaves = layer_leaves([leaf for _, leaf in placed_z], [z for z, _ in placed_z], angle)
        entries.append((spec.floor_fdid_base + i,
                        {"w": w1, "h": h1, "a": angle, "l": leaves}))
    for order, idx in enumerate(tiled):
        entries.append((spec.piece_fdid_base + order, {
            "w": w1, "h": h1, "a": angle, "l": placed(idx)}))
    canvas = dict(groups=by_index, tiled=tiled, minx=minx, maxy=maxy,
                  w0=w0, h0=h0, w1=w1, h1=h1, placement=placement, angle=angle)
    return canvas, entries


def lua_entry(fdid, e):
    # :g would print an FDID of 7+ digits as 8.11306e+06, a different file.
    leaves = ",".join("{" + f"{int(leaf[0])}," + ",".join(f"{v:g}" for v in leaf[1:]) + "}" for leaf in e["l"])
    return f"    [{fdid}]={{w={e['w']},h={e['h']},a={e['a']:g},l={{{leaves}}}}},"


def main(only):
    lines = ["-- Auto-generated by scripts/emit_cave_tiles.py - DO NOT EDIT",
             "-- Baked cave floors/pieces as placements of the client's own WMO minimap tiles.",
             "HFWMF_CAVE_TILES = {"]
    done = 0
    for key, spec in MINES.items():
        if only and key not in only:
            continue
        try:
            entries = list(mine_entries(spec))
        except (ValueError, TypeError) as exc:
            print(f"skip {key}: {exc}")
            continue
        lines.append(f"    -- {spec.key}")
        lines += [lua_entry(f, e) for f, e in entries]
        done += 1
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n")
    print(f"{done} mines -> {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main(set(sys.argv[1:]))
