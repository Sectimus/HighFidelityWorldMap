"""Discovering every other indoor area: houses, inns, towers, caves nobody named.

:mod:`hfwm.caves.mines` lists by hand the ~27 places whose minimap art is
baked.  The rest of the world's interiors are built exactly the same way
(a WMO placed by the continent's ``_obj0.adt``, one baked minimap tile per
indoor group), so instead of a registry entry each, this walks the
placements and builds a :class:`~hfwm.caves.mines.MineSpec` for every one:

  1. the community listfile gives, for each continent, its ``_obj0.adt``
     FileDataIDs, every WMO's path, and the minimap tile FileDataIDs under
     ``world/minimaps/wmo/<same path>_<group>_<row>_<col>.blp``;
  2. every MODF record in those ADTs is a placement (de-duplicated by
     uniqueId: a WMO straddling a tile edge is listed in both);
  3. a placement survives if its WMO has at least one minimap tile that
     really exists on the pinned build (the listfile is a union across
     patches, and a missing file answers an empty 200, see
     :func:`_present`) and it is not already one of the hand-registered
     mines.

Nothing here is named: the addon titles the window with the client's own
subzone text, which is what the real minimap shows inside the same building.
"""

from __future__ import annotations

import re
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from urllib.request import Request, urlopen

from ..config.build import USER_AGENT
from ..config.interior import INTERIOR_PROBE_WORKERS
from ..config.paths import LISTFILE_CACHE, WMO_CACHE_DIR, WMO_TILE_CACHE_DIR
from ..infra.http import download_casc_cached
from .mines import MINES, MineSpec
from .wmo import iter_modf_placements

LISTFILE_URL = ("https://github.com/wowdev/wow-listfile/releases/latest/"
                "download/community-listfile.csv")

# World continents, by the directory name their ADTs live under -> Map.ID.
# The instance WDTs (dungeons, raids) are covered by the DB2-driven pass.
WORLD_MAPS = {"azeroth": 0, "kalimdor": 1}

# First synthetic FileDataID handed to a discovered indoor. Clear of the
# hand-registered mines (900000000+, see config/interior.py) and of real ids.
INDOOR_FDID_BASE = 910_000_000

# A placement tilted more than this about either horizontal axis would need a
# real 3-D projection; the bake only knows yaw (see fetch_wmo_world_placement).
MAX_TILT_DEGREES = 1.0

_ADT_RE = re.compile(r"world/maps/(%s)/\1_\d+_\d+_obj0\.adt$" % "|".join(WORLD_MAPS))
_TILE_RE = re.compile(r"world/minimaps/wmo/(.+)_(\d{3})_(\d{2})_(\d{2})\.blp$")


@dataclass
class Indoor:
    spec: MineSpec
    map_id: int
    label: str  # WMO file name, for debugging; the window title is the client's subzone


def _download_listfile(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    print(f"  downloading {LISTFILE_URL} ...", flush=True)
    tmp = path.with_suffix(".part")
    request = Request(LISTFILE_URL, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=300) as resp, open(tmp, "wb") as out:
        while chunk := resp.read(1 << 20):
            out.write(chunk)
    tmp.replace(path)


def _read_listfile(path: Path = LISTFILE_CACHE):
    """``(adts, wmo_paths, tiles)`` out of the community listfile.

    adts       {fdid: map dir}                    continent ``_obj0.adt`` files
    wmo_paths  {fdid: "dir/name"}                 ``world/wmo/dir/name.wmo``
    tiles      {"dir/name": {(group, row, col): fdid}}
    """
    if not path.exists():
        _download_listfile(path)
    adts: dict[int, str] = {}
    wmo_paths: dict[int, str] = {}
    tiles: dict[str, dict[tuple[int, int, int], int]] = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if "world/" not in line:
                continue
            fdid, _, name = line.rstrip("\n").partition(";")
            if name.startswith("world/maps/"):
                m = _ADT_RE.match(name)
                if m:
                    adts[int(fdid)] = m.group(1)
            elif name.startswith("world/wmo/") and name.endswith(".wmo"):
                wmo_paths[int(fdid)] = name[len("world/wmo/"):-len(".wmo")]
            elif name.startswith("world/minimaps/wmo/"):
                m = _TILE_RE.match(name)
                if m:
                    tiles.setdefault(m.group(1), {})[
                        (int(m.group(2)), int(m.group(3)), int(m.group(4)))
                    ] = int(fdid)
    return adts, wmo_paths, tiles


def _present(fdid: int, cache_dir: Path) -> bool:
    """Does *fdid* exist on the pinned build?

    A file the build doesn't have comes back as an empty 200, not a 404, so
    emptiness is the signal. The empty file is removed so the cache never
    holds a file that isn't there.
    """
    path = download_casc_cached(fdid, cache_dir)
    if path.stat().st_size:
        return True
    path.unlink()
    return False


def _present_all(fdids, cache_dir: Path) -> set[int]:
    fdids = list(fdids)
    with ThreadPoolExecutor(INTERIOR_PROBE_WORKERS) as pool:
        return {f for f, ok in zip(fdids, pool.map(
            lambda f: _present(f, cache_dir), fdids)) if ok}


def _group_tiles(raw: dict[tuple[int, int, int], int],
                 present: set[int]) -> dict:
    """``MineSpec.tile_fdids`` from a WMO's listfile tiles: group -> fdid, or
    group -> {(row, col): fdid} when more than the ``_00_00`` tile exists."""
    by_group: dict[int, dict[tuple[int, int], int]] = {}
    for (group, row, col), fdid in raw.items():
        if fdid in present:
            by_group.setdefault(group, {})[(row, col)] = fdid
    return {g: (t[(0, 0)] if list(t) == [(0, 0)] else t)
            for g, t in sorted(by_group.items())}


def discover_indoors(verbose: bool = True) -> list[Indoor]:
    """Every placed WMO interior with baked minimap art that isn't a
    hand-registered mine, ordered by MODF uniqueId (so synthetic FileDataIDs
    stay put when nothing changes)."""
    adts, wmo_paths, tiles = _read_listfile()
    adt_fdids = _present_all(adts, WMO_CACHE_DIR)
    if verbose:
        print(f"  {len(adt_fdids)} of {len(adts)} continent object files on "
              f"this build.", flush=True)

    known = {s.modf_unique_id for s in MINES.values()}
    placements = {}  # uniqueId -> (adt fdid, wmo fdid, placement)
    for adt in sorted(adt_fdids):
        data = (WMO_CACHE_DIR / f"{adt}.blp").read_bytes()
        for wmo_fdid, placement in iter_modf_placements(data):
            if placement.unique_id in known:
                continue
            path = wmo_paths.get(wmo_fdid)
            if path in tiles:
                placements.setdefault(
                    placement.unique_id, (adt, wmo_fdid, placement))
    if verbose:
        print(f"  {len(placements)} placements of WMOs that have minimap "
              f"tiles listed.", flush=True)

    wanted = {t for fdid in {w for _, w, _ in placements.values()}
              for t in tiles[wmo_paths[fdid]].values()}
    present = _present_all(wanted, WMO_TILE_CACHE_DIR)
    roots = _present_all({w for _, w, _ in placements.values()}, WMO_CACHE_DIR)

    out: list[Indoor] = []
    tilted = 0
    next_fdid = INDOOR_FDID_BASE
    for uid in sorted(placements):
        adt, wmo_fdid, placement = placements[uid]
        tile_fdids = _group_tiles(tiles[wmo_paths[wmo_fdid]], present)
        if wmo_fdid not in roots or not tile_fdids:
            continue
        if any(min(a % 360, 360 - a % 360) > MAX_TILT_DEGREES
               for a in (placement.rotation[0], placement.rotation[2])):
            tilted += 1
            continue
        # Floor composite, then one piece per tiled group (emit_cave_tiles).
        floor_fdid = next_fdid
        next_fdid += 1 + len(tile_fdids)
        out.append(Indoor(
            spec=MineSpec(
                key=f"Indoor{uid}", wmo_fdid=wmo_fdid, tile_fdids=tile_fdids,
                adt_obj0_fdid=adt, modf_unique_id=uid,
                modf_name_set=placement.name_set,
                floor_fdid_base=floor_fdid, piece_fdid_base=floor_fdid + 1,
                single_floor=True),
            map_id=WORLD_MAPS[adts[adt]],
            label=wmo_paths[wmo_fdid].rsplit("/", 1)[-1],
        ))
    if verbose:
        print(f"  {len(out)} indoors with art on this build"
              + (f" ({tilted} skipped: tilted)" if tilted else "") + ".",
              flush=True)
    return out
