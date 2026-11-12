"""Terrain-less tiles: open sea, read from the root ADTs rather than its colour.

A terrain tile whose ADT has no terrain in it is open water, and its minimap
tile is a flat dark fill. The fill's colour changes between builds, so the
palette in :mod:`hfwm.config.ocean` cannot identify it by colour alone. The
root ADT can: every MCNK chunk of a tile with terrain carries a height table
(MCVT), pointed to by ``ofsHeight`` at byte 0x14 of the MCNK header.
"""

from __future__ import annotations

import struct
from concurrent.futures import ThreadPoolExecutor

from ..config.paths import ADT_TERRAIN_CACHE
from ..formats.wdt import MAID_FIELD_ROOT_ADT, parse_wdt_maid
from ..gamedata.db2 import _fetch_wdt
from ..gamedata.tables import fetch_pinned_table
from ..infra.http import download_casc

MCNK_OFS_HEIGHT = 0x14
THREADS = 12


def has_terrain(adt: bytes) -> bool:
    """True if any MCNK chunk of a root ADT has a height table."""
    pos = 0
    while pos + 8 <= len(adt):
        magic = adt[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", adt, pos + 4)[0]
        if magic == b"MCNK" and struct.unpack_from("<I", adt, pos + 8 + MCNK_OFS_HEIGHT)[0]:
            return True
        pos += 8 + size
    return False


def _cached_has_terrain(fdid: int) -> bool:
    path = ADT_TERRAIN_CACHE / f"{fdid}.txt"
    if path.exists():
        return path.read_text() == "1"
    value = has_terrain(download_casc(fdid))
    ADT_TERRAIN_CACHE.mkdir(parents=True, exist_ok=True)
    path.write_text("1" if value else "0")
    return value


def terrainless_cells(map_id: int, cells) -> set[tuple[int, int]]:
    """The cells of *map_id* among *cells* whose root ADT has no terrain.

    Raises if the WDT cannot be downloaded or a root ADT cannot be fetched: a
    silent miss would leave open sea unfilled with no sign of why.
    """
    wdt_fdids = {int(m["ID"]): int(m["WdtFileDataID"]) for m in fetch_pinned_table("Map")}
    wdt = _fetch_wdt(map_id, wdt_fdids[map_id])
    if not wdt:
        raise RuntimeError(f"could not download the WDT of map {map_id}")
    roots = parse_wdt_maid(wdt, MAID_FIELD_ROOT_ADT)
    known = [(cell, roots[cell]) for cell in cells if cell in roots]
    with ThreadPoolExecutor(THREADS) as pool:
        has = list(pool.map(_cached_has_terrain, [fdid for _, fdid in known]))
    return {cell for (cell, _), t in zip(known, has) if not t}
