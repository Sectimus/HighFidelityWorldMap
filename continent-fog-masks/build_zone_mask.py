"""Build one zone's Fog of War mask from its hand trace.

Usage: build_zone_mask.py <zoneUiMapID> [eastern|kalimdor]

Writes src/addon/client/ZoneMasks/z<id>.blp and prints two RESULT rows: the continent
box (1415 or 1414) and the World map box (947), in 0-1 units. Copy those rows into
src/addon/client/data/ZoneShapes.lua by hand.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from psd_tools import PSDImage

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "src" / "generator"))

from hfwm.formats.blp import encode_blp2_bgra  # noqa: E402
from hfwm.gamedata.tables import fetch_pinned_table  # noqa: E402

# Continent UiMapID and its terrain MapID in UiMapAssignment. The World map (947) row
# is taken from the same terrain MapID.
CONTINENTS = {
    "eastern": dict(psd="eastern-kingdoms-traces.psd", cont=1415, terrain=0),
    "kalimdor": dict(psd="kalimdor-traces.psd", cont=1414, terrain=1),
}
WORLD_MAP = 947
W, H = 8192, 5461
DILATE = 3  # canvas px
OUT_DIR = REPO / "src" / "addon" / "client" / "ZoneMasks"


def pow2(n):
    return 1 << max(5, (int(np.ceil(n)) - 1).bit_length())


def main():
    zone = int(sys.argv[1])
    cfg = CONTINENTS[sys.argv[2] if len(sys.argv) > 2 else "eastern"]

    psd = PSDImage.open(REPO / "continent-fog-masks" / cfg["psd"])
    if (psd.width, psd.height) != (W, H):
        sys.exit(f"canvas is {psd.width}x{psd.height}, expected {W}x{H}")
    matches = [l for l in psd.descendants() if l.name == f"z{zone}"]
    if len(matches) != 1:
        sys.exit(f"expected one layer named z{zone}, found {len(matches)}")
    layer = matches[0]
    if layer.topil() is None:
        sys.exit(f"layer z{zone} has no pixels")
    alpha_layer = np.asarray(layer.topil().getchannel("A"))
    canvas = np.zeros((H, W), np.uint8)
    y0, x0 = layer.top, layer.left
    canvas[y0:y0 + alpha_layer.shape[0], x0:x0 + alpha_layer.shape[1]] = alpha_layer

    ys, xs = np.nonzero(canvas)
    pad = DILATE + 2
    bx0, bx1 = max(0, xs.min() - pad), min(W, xs.max() + 1 + pad)
    by0, by1 = max(0, ys.min() - pad), min(H, ys.max() + 1 + pad)
    crop = Image.fromarray(canvas[by0:by1, bx0:bx1], "L").filter(
        ImageFilter.MaxFilter(2 * DILATE + 1))
    d = np.asarray(crop)
    dys, dxs = np.nonzero(d)
    cx0, cx1 = bx0 + dxs.min(), bx0 + dxs.max() + 1
    cy0, cy1 = by0 + dys.min(), by0 + dys.max() + 1
    print(f"dilated canvas box px: {cx0},{cy0} {cx1},{cy1}")

    cont_u0, cont_v0 = cx0 / W, cy0 / H
    cont_u1, cont_v1 = cx1 / W, cy1 / H

    mask = Image.fromarray(d[dys.min():dys.max() + 1, dxs.min():dxs.max() + 1], "L")
    w, h = mask.size
    s = 1024 / max(w, h)
    size = (pow2(w * s), pow2(h * s))
    alpha = mask.resize(size, Image.LANCZOS)
    rgba = Image.merge("RGBA", (*(Image.new("L", size, 255),) * 3, alpha))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"z{zone}.blp"
    out.write_bytes(encode_blp2_bgra(rgba))
    print(f"wrote {out} size={size}")

    regions = {}
    for r in fetch_pinned_table("UiMapAssignment"):
        if int(r["UiMapID"]) in (cfg["cont"], WORLD_MAP) and int(r["MapID"]) == cfg["terrain"]:
            regions.setdefault(int(r["UiMapID"]), []).append(dict(
                top=float(r["Region_3"]), bottom=float(r["Region_0"]),
                left=float(r["Region_4"]), right=float(r["Region_1"]),
                umin=float(r["UiMin_0"]), vmin=float(r["UiMin_1"]),
                umax=float(r["UiMax_0"]), vmax=float(r["UiMax_1"])))
    cg = regions[cfg["cont"]][0]
    wg = regions[WORLD_MAP][0]

    def to_yards(g, u, v):
        fu = (u - g["umin"]) / (g["umax"] - g["umin"])
        fv = (v - g["vmin"]) / (g["vmax"] - g["vmin"])
        return g["left"] - fu * (g["left"] - g["right"]), g["top"] - fv * (g["top"] - g["bottom"])

    def from_yards(g, X, Y):
        u = g["umin"] + (g["left"] - X) / (g["left"] - g["right"]) * (g["umax"] - g["umin"])
        v = g["vmin"] + (g["top"] - Y) / (g["top"] - g["bottom"]) * (g["vmax"] - g["vmin"])
        return u, v

    corners = [(cont_u0, cont_v0), (cont_u1, cont_v0), (cont_u0, cont_v1), (cont_u1, cont_v1)]
    world = [from_yards(wg, *to_yards(cg, u, v)) for u, v in corners]
    wu0 = min(p[0] for p in world); wu1 = max(p[0] for p in world)
    wv0 = min(p[1] for p in world); wv1 = max(p[1] for p in world)
    print(f"RESULT {cfg['cont']} {zone},{cont_u0:.6f},{cont_v0:.6f},{cont_u1:.6f},{cont_v1:.6f}")
    print(f"RESULT 947 {zone},{wu0:.6f},{wv0:.6f},{wu1:.6f},{wv1:.6f}")


if __name__ == "__main__":
    main()
