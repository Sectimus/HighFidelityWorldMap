"""Terrain-chunk AreaIDs from the game's ADT files, for emit_area_labels.py.

Every 33-yard terrain chunk of every terrain (ADT) tile carries an AreaID. The 16x16
table of each tile is downloaded once and kept in the cache. Zone outlines do not come
from here: they are the hand traces, built by build_zone_masks.py.
"""
import struct
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from hfwm.config.paths import CACHE_ROOT  # noqa: E402
from hfwm.config.tiles import TILE_WORLD_SIZE  # noqa: E402
from hfwm.formats.wdt import MAID_FIELD_ROOT_ADT, parse_wdt_maid  # noqa: E402
from hfwm.gamedata.db2 import _fetch_wdt  # noqa: E402
from hfwm.gamedata.tables import fetch_pinned_table  # noqa: E402
from hfwm.geometry.coordinates import world_to_tile  # noqa: E402
from hfwm.infra.http import download_casc  # noqa: E402

AREA_CACHE = CACHE_ROOT / "adt_areas"

CHUNK = TILE_WORLD_SIZE / 16
THREADS = 12


def tiles_needed(regions):
    """{map_id: {(row, col)}} of terrain tiles any region covers."""
    need = {}
    for rows in regions.values():
        for g in rows:
            r0, r1 = sorted((world_to_tile(g["top"]), world_to_tile(g["bottom"])))
            c0, c1 = sorted((world_to_tile(g["left"]), world_to_tile(g["right"])))
            need.setdefault(g["map_id"], set()).update(
                (r, c) for r in range(max(0, r0), min(63, r1) + 1)
                for c in range(max(0, c0), min(63, c1) + 1))
    return need


def chunk_areas(job):
    """The 16x16 AreaIDs of one terrain tile, indexed [chunk row][chunk col]."""
    map_id, row, col, fdid = job
    path = AREA_CACHE / f"{map_id}_{row}_{col}_{fdid}.bin"
    if path.exists():
        return job, np.frombuffer(path.read_bytes(), "<u2").reshape(16, 16)
    for attempt in range(4):
        try:
            adt = download_casc(fdid)
            break
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))
    out = np.zeros((16, 16), "<u2")
    pos = 0
    while pos + 8 <= len(adt):
        magic = adt[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", adt, pos + 4)[0]
        if magic == b"MCNK":
            ix, iy = struct.unpack_from("<II", adt, pos + 8 + 4)
            out[iy, ix] = struct.unpack_from("<I", adt, pos + 8 + 0x34)[0]
        pos += 8 + size
    path.write_bytes(out.tobytes())
    return job, out


def terrain_areas(need):
    """{map_id: 1024x1024 array of AreaIDs, one per chunk}, downloading as needed."""
    AREA_CACHE.mkdir(parents=True, exist_ok=True)
    jobs = []
    wdt_fdids = {int(m["ID"]): int(m["WdtFileDataID"]) for m in fetch_pinned_table("Map")}
    for map_id, tiles in need.items():
        # Fetched here (cached by the generator's own downloader) so this runs
        # without a prior generator run, as CI does when the art is cached.
        wdt = _fetch_wdt(map_id, wdt_fdids[map_id])
        if not wdt:
            raise SystemExit(f"could not download the WDT of map {map_id}")
        grid = parse_wdt_maid(wdt, MAID_FIELD_ROOT_ADT)
        jobs += [(map_id, r, c, grid[(r, c)]) for (r, c) in sorted(tiles) if (r, c) in grid]
    print(f"  {len(jobs)} terrain tiles ...", flush=True)

    areas = {m: np.zeros((1024, 1024), "<u2") for m in need}
    with ThreadPoolExecutor(THREADS) as pool:
        for n, ((map_id, r, c, _), a) in enumerate(pool.map(chunk_areas, jobs), 1):
            areas[map_id][r * 16:(r + 1) * 16, c * 16:(c + 1) * 16] = a
            if n % 100 == 0:
                print(f"    {n}/{len(jobs)}", flush=True)
    return areas
