"""Overlay one zone's mask edge on its continent art, to check the trace.

Usage: overlay_zone.py <zoneUiMapID> <u0> <v0> <u1> <v1> [eastern|kalimdor]

Writes /tmp/z<id>_overlay.png with the mask outline in red, placed at the box.
"""
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parents[1]
ART = {"eastern": "eastern-kingdoms-8192x5461.png", "kalimdor": "kalimdor-8192x5461.png"}
W, H = 8192, 5461
PAD = 200


def read_blp_alpha(path):
    raw = path.read_bytes()
    w, h = struct.unpack_from("<II", raw, 12)
    off = struct.unpack_from("<I", raw, 20)[0]
    bgra = np.frombuffer(raw, np.uint8, count=w * h * 4, offset=off).reshape(h, w, 4)
    return Image.fromarray(bgra[:, :, 3], "L")


def main():
    zone = sys.argv[1]
    u0, v0, u1, v1 = map(float, sys.argv[2:6])
    continent = sys.argv[6] if len(sys.argv) > 6 else "eastern"
    mask = read_blp_alpha(REPO / "src" / "addon" / "client" / "ZoneMasks" / f"z{zone}.blp")
    art = Image.open(REPO / "continent-fog-masks" / ART[continent]).convert("RGBA")
    x0, y0 = int(u0 * W) - PAD, int(v0 * H) - PAD
    x1, y1 = int(u1 * W) + PAD, int(v1 * H) + PAD
    crop = art.crop((x0, y0, x1, y1))
    bw, bh = int(u1 * W) - int(u0 * W), int(v1 * H) - int(v0 * H)
    mask = mask.resize((bw, bh), Image.BILINEAR)
    edge = mask.filter(ImageFilter.FIND_EDGES).point(lambda p: 255 if p >= 40 else 0)
    layer = Image.new("RGBA", crop.size, (0, 0, 0, 0))
    layer.paste((255, 0, 0, 255), (int(u0 * W) - x0, int(v0 * H) - y0), edge)
    out = Path(f"/tmp/z{zone}_overlay.png")
    Image.alpha_composite(crop, layer).convert("RGB").save(out)
    print("overlay", crop.size, out)


if __name__ == "__main__":
    main()
