"""Build the World/Continent Fog of War zone masks from the hand traces.

Source: continent-fog-masks/eastern-kingdoms-traces.psd and kalimdor-traces.psd.
Each holds one filled layer per zone, named z<UiMapID> (see
continent-fog-masks/continent-fog-masks.md). These files are the only source for
the masks and for data/ZoneShapes.lua.

Writes:
  src/addon/client/ZoneMasks/z<UiMapID>.blp  one mask per zone (gitignored, built here)
  src/addon/client/data/ZoneShapes.lua       where each mask goes on each map (committed)

The World map (947) box is derived from each continent box through the continent's
UiMapAssignment rows, not traced. CI runs this on every asset build and fails when the
committed ZoneShapes.lua differs from its output.

    python src/generator/scripts/build_zone_masks.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from psd_tools import PSDImage

ROOT = Path(__file__).resolve().parents[1]  # src/generator
REPO = ROOT.parents[1]
sys.path.insert(0, str(ROOT))

from hfwm.formats.blp import encode_blp2_bgra  # noqa: E402
from hfwm.gamedata.tables import fetch_pinned_table  # noqa: E402

TRACES = REPO / "continent-fog-masks"
ADDON = REPO / "src" / "addon" / "client"
MASK_DIR = ADDON / "ZoneMasks"
OUT = ADDON / "data" / "ZoneShapes.lua"

# One trace file per continent: its UiMapID and the terrain MapID of its rows in
# UiMapAssignment. The World map (947) row for the same terrain MapID is derived.
CONTINENTS = (
    dict(psd="eastern-kingdoms-traces.psd", cont=1415, terrain=0),
    dict(psd="kalimdor-traces.psd", cont=1414, terrain=1),
)
WORLD_MAP = 947
MAP_ORDER = (1414, 1415, WORLD_MAP)
W, H = 8192, 5461  # canvas, px; the same as the stitched art
DILATE = 3  # canvas px, closes seams between neighbouring zones
MASK_LONG_SIDE = 1024  # px before rounding up to a power of two


def pow2(n):
    return 1 << max(5, (int(np.ceil(n)) - 1).bit_length())


def trace_layers(psd):
    """{zone UiMapID: layer} for the trace file. Any layer not named z<id> is an error."""
    layers = {}
    for layer in psd.descendants():
        name = layer.name
        if not (name[:1] == "z" and name[1:].isdigit()):
            sys.exit(f"{psd.name or 'trace file'}: layer {name!r} is not named z<UiMapID>")
        zone = int(name[1:])
        if zone in layers:
            sys.exit(f"duplicate layer z{zone}")
        layers[zone] = layer
    return layers


def zone_canvas(layer):
    """The layer's alpha on the full canvas, at its offset."""
    pixels = layer.topil()
    if pixels is None:
        sys.exit(f"layer z{layer.name[1:]} has no pixels")
    alpha = np.asarray(pixels.getchannel("A"))
    y0, x0 = layer.top, layer.left
    if y0 < 0 or x0 < 0 or y0 + alpha.shape[0] > H or x0 + alpha.shape[1] > W:
        sys.exit(f"layer {layer.name} extends outside the {W}x{H} canvas")
    canvas = np.zeros((H, W), np.uint8)
    canvas[y0:y0 + alpha.shape[0], x0:x0 + alpha.shape[1]] = alpha
    return canvas


def zone_mask(canvas):
    """(dilated mask image, its box in canvas px (x0, y0, x1, y1))."""
    ys, xs = np.nonzero(canvas)
    pad = DILATE + 2
    bx0, bx1 = max(0, xs.min() - pad), min(W, xs.max() + 1 + pad)
    by0, by1 = max(0, ys.min() - pad), min(H, ys.max() + 1 + pad)
    crop = Image.fromarray(canvas[by0:by1, bx0:bx1], "L").filter(
        ImageFilter.MaxFilter(2 * DILATE + 1))
    d = np.asarray(crop)
    dys, dxs = np.nonzero(d)
    box = (bx0 + dxs.min(), by0 + dys.min(), bx0 + dxs.max() + 1, by0 + dys.max() + 1)
    mask = Image.fromarray(d[dys.min():dys.max() + 1, dxs.min():dxs.max() + 1], "L")
    return mask, box


def write_mask(zone, mask):
    w, h = mask.size
    s = MASK_LONG_SIDE / max(w, h)
    size = (pow2(w * s), pow2(h * s))
    alpha = mask.resize(size, Image.LANCZOS)
    rgba = Image.merge("RGBA", (*(Image.new("L", size, 255),) * 3, alpha))
    (MASK_DIR / f"z{zone}.blp").write_bytes(encode_blp2_bgra(rgba))


def regions_by_map(ui_maps):
    """{(UiMapID, terrain MapID): region} from UiMapAssignment, one row each."""
    rows = {}
    for r in fetch_pinned_table("UiMapAssignment"):
        ui = int(r["UiMapID"])
        if ui in ui_maps:
            rows.setdefault((ui, int(r["MapID"])), []).append(dict(
                top=float(r["Region_3"]), bottom=float(r["Region_0"]),
                left=float(r["Region_4"]), right=float(r["Region_1"]),
                umin=float(r["UiMin_0"]), vmin=float(r["UiMin_1"]),
                umax=float(r["UiMax_0"]), vmax=float(r["UiMax_1"])))
    for key, found in rows.items():
        if len(found) != 1:
            sys.exit(f"UiMapAssignment has {len(found)} rows for UiMapID/MapID {key}")
    return {key: found[0] for key, found in rows.items()}


def to_yards(g, u, v):
    fu = (u - g["umin"]) / (g["umax"] - g["umin"])
    fv = (v - g["vmin"]) / (g["vmax"] - g["vmin"])
    return g["left"] - fu * (g["left"] - g["right"]), g["top"] - fv * (g["top"] - g["bottom"])


def from_yards(g, X, Y):
    u = g["umin"] + (g["left"] - X) / (g["left"] - g["right"]) * (g["umax"] - g["umin"])
    v = g["vmin"] + (g["top"] - Y) / (g["top"] - g["bottom"]) * (g["vmax"] - g["vmin"])
    return u, v


def world_box(cont_region, world_region, box):
    """A continent box (0-1) as its bounds on the World map (0-1)."""
    u0, v0, u1, v1 = box
    corners = [from_yards(world_region, *to_yards(cont_region, u, v))
               for u, v in ((u0, v0), (u1, v0), (u0, v1), (u1, v1))]
    us, vs = [p[0] for p in corners], [p[1] for p in corners]
    return min(us), min(vs), max(us), max(vs)


def write_shapes(rows):
    lines = [
        "-- Generated by scripts/build_zone_masks.py from continent-fog-masks/*-traces.psd.",
        "-- DO NOT EDIT: change the trace and rerun the script.",
        "-- Per map: { zone UiMapID, u0, v0, u1, v1 } -- where ZoneMasks\\",
        "-- z<UiMapID>.blp goes, in 0-1 map coordinates. See ZoneFog.lua.",
        "HFWMF_ZONE_SHAPES = {",
    ]
    for ui in MAP_ORDER:
        lines.append(f"    [{ui}] = {{")
        for zone, u0, v0, u1, v1 in sorted(rows[ui]):
            lines.append(f"        {{{zone},{u0:.6f},{v0:.6f},{u1:.6f},{v1:.6f}}},")
        lines.append("    },")
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n")


def main():
    MASK_DIR.mkdir(parents=True, exist_ok=True)
    regions = regions_by_map({c["cont"] for c in CONTINENTS} | {WORLD_MAP})
    rows = {ui: [] for ui in MAP_ORDER}
    for cfg in CONTINENTS:
        psd = PSDImage.open(TRACES / cfg["psd"])
        if (psd.width, psd.height) != (W, H):
            sys.exit(f"{cfg['psd']} is {psd.width}x{psd.height}, expected {W}x{H}")
        cont_region = regions[(cfg["cont"], cfg["terrain"])]
        world_region = regions[(WORLD_MAP, cfg["terrain"])]
        for zone, layer in sorted(trace_layers(psd).items()):
            mask, (x0, y0, x1, y1) = zone_mask(zone_canvas(layer))
            write_mask(zone, mask)
            box = (x0 / W, y0 / H, x1 / W, y1 / H)
            rows[cfg["cont"]].append((zone, *box))
            rows[WORLD_MAP].append((zone, *world_box(cont_region, world_region, box)))
        print(f"{cfg['psd']}: {len(rows[cfg['cont']])} zones so far")
    write_shapes(rows)
    print(f"wrote {len(rows[WORLD_MAP])} zone masks to {MASK_DIR} and {OUT}")


if __name__ == "__main__":
    main()
