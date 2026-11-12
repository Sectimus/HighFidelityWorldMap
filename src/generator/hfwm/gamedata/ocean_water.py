"""Where the open sea is, read from the terrain (ADT) files.

The minimap BLPs carry no water mask, and the colour the baker paints the
sea with is not stable: it was a flat ``(8, 16, 16)`` on 1.60.1.69913 and is
a field of diagonal near-black bands (``(5,5,5)``, ``(5,6,5)``, ``(5,6,8)``)
on 1.60.1.70888, for the very same ADT bytes. An exact-colour test erased
only the bands it happened to straddle and left the rest as opaque black
stripes.

The ADT says where the water is, whatever the baker paints it. Each of its
256 terrain chunks carries an ``MH2O`` liquid layer (liquid type, surface
height, which of the chunk's 8x8 cells hold water) and the ``MCVT`` seabed
heights. A cell counts as open sea when its liquid is an Ocean type and the
surface sits at least :data:`~hfwm.config.ocean.OCEAN_MIN_DEPTH` yards above
the highest seabed corner of the cell. Shallower than that the seabed shows
through the water in the minimap and the pixel is real coast, not fill.

Per tile this is a 128x128 grid (16 chunks x 8 cells). It is cached as the
*depth* of each ocean cell rather than as a verdict, so changing the
threshold never needs a re-download.
"""

from __future__ import annotations

import struct
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np

from ..config.paths import OCEAN_CELLS_CACHE
from ..formats.wdt import MAID_FIELD_ROOT_ADT, parse_wdt_maid
from ..infra.http import download_casc
from .db2 import _fetch_wdt
from .tables import fetch_pinned_table

CELLS = 128                      # cells per tile edge: 16 chunks x 8 cells
NO_OCEAN = np.int16(-32768)      # depth value of a cell with no ocean water
_DEPTH_MAX = 32767

# MCVT lays its 145 heights out as 9 outer + 8 inner per row pair; these index
# the 9x9 outer lattice and the 8x8 cell centres.
_OUTER = np.arange(9)[:, None] * 17 + np.arange(9)[None, :]
_INNER = np.arange(8)[:, None] * 17 + 9 + np.arange(8)[None, :]

_ocean_liquids: frozenset[int] | None = None


def ocean_liquid_ids() -> frozenset[int]:
    """LiquidType IDs whose name says Ocean (``Ocean``, ``PBRWater - Generic - Ocean`` ...)."""
    global _ocean_liquids
    if _ocean_liquids is None:
        _ocean_liquids = frozenset(
            int(r["ID"]) for r in fetch_pinned_table("LiquidType")
            if "ocean" in r["Name"].lower()
        )
    return _ocean_liquids


def ocean_depth(adt: bytes, ocean_ids: frozenset[int]) -> np.ndarray:
    """Per-cell depth (yards, int16) of ocean water in a root ADT; ``NO_OCEAN`` elsewhere.

    Depth is surface height minus the highest of the cell's five seabed
    heights, so a positive value means the whole cell is under water.
    """
    heights: dict[tuple[int, int], np.ndarray] = {}
    mh2o = None
    pos = 0
    while pos + 8 <= len(adt):
        magic = adt[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", adt, pos + 4)[0]
        if magic == b"MH2O":
            mh2o = pos + 8
        elif magic == b"MCNK":
            start = pos + 8
            ix, iy = struct.unpack_from("<II", adt, start + 4)
            base_z = struct.unpack_from("<f", adt, start + 0x70)[0]
            sub, end = start + 128, start + size
            while sub + 8 <= end:
                sub_magic = adt[sub:sub + 4][::-1]
                sub_size = struct.unpack_from("<I", adt, sub + 4)[0]
                if sub_magic == b"MCVT":
                    heights[(iy, ix)] = (
                        np.frombuffer(adt, "<f4", 145, sub + 8) + base_z
                    )
                    break
                sub += 8 + sub_size
        pos += 8 + size

    depth = np.full((CELLS, CELLS), np.inf, np.float32)
    if mh2o is None:
        return np.full((CELLS, CELLS), NO_OCEAN, np.int16)

    for cy in range(16):
        for cx in range(16):
            h = heights.get((cy, cx))
            if h is None:
                continue
            offset, layers, _attrs = struct.unpack_from(
                "<III", adt, mh2o + (cy * 16 + cx) * 12)
            if not layers:
                continue
            outer, inner = h[_OUTER], h[_INNER]
            seabed = np.maximum.reduce([
                outer[:-1, :-1], outer[:-1, 1:],
                outer[1:, :-1], outer[1:, 1:], inner,
            ])
            for i in range(layers):
                (liquid, _fmt, surface, _max, x0, y0, w, hgt, exists,
                 _verts) = struct.unpack_from(
                    "<HHffBBBBII", adt, mh2o + offset + i * 24)
                if liquid not in ocean_ids:
                    continue
                cells = np.ones((hgt, w), bool)
                if exists:
                    bits = np.unpackbits(
                        np.frombuffer(adt, np.uint8, (w * hgt + 7) // 8,
                                      mh2o + exists),
                        bitorder="little")[:w * hgt]
                    cells = bits.reshape(hgt, w).astype(bool)
                d = surface - seabed[y0:y0 + hgt, x0:x0 + w]
                view = depth[cy * 8 + y0:cy * 8 + y0 + hgt,
                             cx * 8 + x0:cx * 8 + x0 + w]
                view[cells] = np.minimum(view[cells], d[cells])

    out = np.full((CELLS, CELLS), NO_OCEAN, np.int16)
    wet = np.isfinite(depth)
    out[wet] = np.clip(np.rint(depth[wet]), -_DEPTH_MAX, _DEPTH_MAX)
    return out


def _cache_path(map_id: int, row: int, col: int) -> Path:
    return OCEAN_CELLS_CACHE / f"{map_id}_{row}_{col}.npy"


def fetch_ocean_cells(regions, workers: int = 8) -> None:
    """Make sure every ADT under *regions* has its ocean depth grid cached.

    *regions* are zone-DB region dicts (``map_id``, ``wdt_fdid``, ``tiles``).
    Done up front, in one process, so the zone workers only ever read.
    """
    OCEAN_CELLS_CACHE.mkdir(parents=True, exist_ok=True)
    grids: dict[int, dict[tuple[int, int], int]] = {}
    jobs: dict[tuple[int, int, int], int] = {}
    for reg in regions:
        map_id = reg["map_id"]
        if map_id not in grids:
            wdt = _fetch_wdt(map_id, reg["wdt_fdid"])
            if not wdt:
                raise OSError(f"no WDT for map {map_id}; cannot tell where its sea is")
            grids[map_id] = parse_wdt_maid(wdt, MAID_FIELD_ROOT_ADT)
        for key in reg["tiles"]:
            row, col = (int(x) for x in key.split("_"))
            if not _cache_path(map_id, row, col).exists():
                # fdid 0: the WDT has no terrain for this tile, so no sea in it
                jobs[(map_id, row, col)] = grids[map_id].get((row, col), 0)

    if not jobs:
        print("  All ocean cells already cached.", flush=True)
        return
    print(f"  {len(jobs)} terrain tiles to read for ocean cells ...", flush=True)
    ids = ocean_liquid_ids()

    def _one(item):
        (map_id, row, col), fdid = item
        grid = np.full((CELLS, CELLS), NO_OCEAN, np.int16)
        if fdid:
            for attempt in range(4):
                try:
                    adt = download_casc(fdid)
                    break
                except Exception:
                    if attempt == 3:
                        raise
                    time.sleep(2 * (attempt + 1))
            grid = ocean_depth(adt, ids)
        path = _cache_path(map_id, row, col)
        tmp = path.with_suffix(".tmp")
        with tmp.open("wb") as f:
            np.save(f, grid)
        tmp.replace(path)

    with ThreadPoolExecutor(workers) as pool:
        list(pool.map(_one, jobs.items()))


def ocean_cells(map_id: int, row: int, col: int, min_depth: float) -> np.ndarray:
    """128x128 bool: the open-sea cells of one tile.

    Raises if :func:`fetch_ocean_cells` has not covered the tile: a missing
    grid must not quietly mean "no sea".
    """
    depth = np.load(_cache_path(map_id, row, col))
    return (depth != NO_OCEAN) & (depth >= min_depth)
