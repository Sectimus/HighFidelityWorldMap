"""The pipeline's non-zone phases: zone database, tiles, FDIDMap.lua, caves."""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path
from urllib.error import HTTPError, URLError

from ..config.paths import (
    BASE_ART_TILE_CACHE,
    CAVE_DATA_FILE,
    MINIMAP_TILE_CACHE,
)
from ..config.tiles import UI_MAP_TYPE_CONTINENT, UI_MAP_TYPE_WORLD
from ..gamedata.db2 import fetch_zone_db
from ..gamedata.microdungeon import build_cave_table
from ..gamedata.ocean_water import fetch_ocean_cells
from ..imaging.effects import stamp
from ..lua.cave_data import generate_cave_data
from ..lua.fdid_map import generate_fdid_map
from ..pipeline.downloads import download_tiles, tile_size_histogram


# ---------------------------------------------------------------------------
# Phase 1: zone database
# ---------------------------------------------------------------------------

def load_zone_db(
    force_refresh: bool, maid_field: int, zones: str | None,
) -> dict[str, dict]:
    """Build the zone database, narrowed to *zones* (comma-separated names).

    Exits with status 1, having said why, if it cannot produce at least one
    zone.
    """
    print("--- Phase 1: Zone database ---", flush=True)
    try:
        zone_db = fetch_zone_db(
            force_refresh=force_refresh, maid_field=maid_field,
        )
    except (URLError, HTTPError, OSError) as exc:
        print(f"  ERROR: could not build the zone DB: {exc}", file=sys.stderr)
        sys.exit(1)

    if not zone_db:
        print("  ERROR: zone DB is empty — nothing to do.", file=sys.stderr)
        sys.exit(1)

    if zones:
        wanted = {z.strip().lower() for z in zones.split(",")}
        zone_db = {
            k: v for k, v in zone_db.items()
            if k.lower() in wanted or v["area_name"].lower() in wanted
        }
        if not zone_db:
            print("  ERROR: no zones matched --zones.", file=sys.stderr)
            sys.exit(1)
    return zone_db


def art_zones(zone_db: dict[str, dict]) -> dict[str, dict]:
    """The maps whose stitched art the addon ships.

    Only the World and Continent views are stitched offline. Zone and cave
    maps are drawn from the client's own minimap tiles, placed by
    ``MinimapTiles.lua`` / ``CaveTiles.lua`` (``scripts/emit_*_tiles.py``),
    so they stay in the zone DB, and their source tiles stay downloaded,
    but get no BLPs and no FDIDMap.lua entries.
    """
    art = {
        k: v for k, v in zone_db.items()
        if v["ui_map_type"] in (UI_MAP_TYPE_WORLD, UI_MAP_TYPE_CONTINENT)
    }
    if not art:
        print("  ERROR: no World or Continent map selected (--zones); zone "
              "maps ship no art.", file=sys.stderr)
        sys.exit(1)
    return art


def _grid(z: dict) -> str:
    g = z.get("native")
    return f"{g['cols']}x{g['rows']}" if g else f"{z['cols']}x{z['rows']}"


def _tiles(z: dict) -> int:
    g = z.get("native")
    return g["cols"] * g["rows"] if g else z["cols"] * z["rows"]


def source_fdids(zone_db: dict[str, dict]) -> set[int]:
    """Every unique minimap tile FileDataID the zones are stitched from."""
    return {
        fdid
        for z in zone_db.values()
        for reg in z["regions"]
        for fdid in reg["tiles"].values()
    }


def print_plan(zone_db: dict[str, dict], needed_fdids: set[int]) -> None:
    grids = Counter(_grid(z) for z in zone_db.values())
    out_tiles = sum(_tiles(z) for z in zone_db.values())
    native_zones = sum(1 for z in zone_db.values() if z.get("native"))

    print(f"\nZones:     {len(zone_db)}", flush=True)
    print("Grids:     "
          + ", ".join(f"{k} x{v}" for k, v in grids.most_common()),
          flush=True)
    print(f"Src tiles: {len(needed_fdids)} unique minimap textures",
          flush=True)
    print(f"Out tiles: {out_tiles} BLPs"
          + (f" ({native_zones} zone(s) at native minimap resolution)"
             if native_zones else ""),
          flush=True)


def print_dry_run(zone_db: dict[str, dict], with_caves: bool) -> None:
    print(flush=True)
    for folder in sorted(zone_db):
        z = zone_db[folder]
        native = z.get("native")
        layer = (f"{native['layer_w']}x{native['layer_h']}" if native
                 else f"{z['layer_w']}x{z['layer_h']}")
        src = sum(len(r["tiles"]) for r in z["regions"])
        print(
            f"  {folder:34s} {_grid(z):>7} "
            f"{layer:<11} "
            f"{len(z['regions'])} region(s)  {src:4d} src tiles  "
            f"{'[native] ' if native else ''}[{z['area_name']}]",
        )
    if with_caves:
        print(f"\n  Would also rebuild {CAVE_DATA_FILE.name} "
              f"(--no-caves to skip, --caves-only to run just that).")
    print("\n(dry run — nothing downloaded or written)")


# ---------------------------------------------------------------------------
# Phase 2: tile downloads
# ---------------------------------------------------------------------------

def download_source_tiles(
    zone_db: dict[str, dict],
    needed_fdids: set[int],
    dl_threads: int,
    want_base_art: bool,
) -> tuple[dict[int, Path], dict[int, Path]]:
    """Download the minimap tiles, and Blizzard's art-layer tiles if wanted.

    Returns ``(minimap_tiles, base_art_tiles)``; the second is empty
    unless *want_base_art*.
    """
    print("\n--- Phase 2: Downloading minimap tiles ---", flush=True)
    tile_cache = download_tiles(
        needed_fdids, MINIMAP_TILE_CACHE, "minimap", dl_threads,
    )
    tile_size_histogram(tile_cache)

    # Which pixels are sea is read from the terrain, not guessed from the
    # minimap's colour; see hfwm.gamedata.ocean_water. Only the stitched
    # (World and Continent) maps need it.
    print("\n--- Phase 2a: Reading terrain for the open sea ---", flush=True)
    fetch_ocean_cells(
        reg for z in art_zones(zone_db).values() for reg in z["regions"]
    )

    base_art_cache: dict[int, Path] = {}
    if want_base_art:
        # The base-art backdrop is built from the very FDIDs the addon
        # remaps — the client's own art-layer tiles for each zone.
        art_fdids = {
            fdid for z in zone_db.values() for fdid in z["tile_fdids"]
        }
        print(f"\n--- Phase 2b: Downloading base art ({len(art_fdids)} "
              f"tiles) ---", flush=True)
        base_art_cache = download_tiles(
            art_fdids, BASE_ART_TILE_CACHE, "base art", dl_threads,
        )
        if not base_art_cache:
            print("  ERROR: --base-art is on but no original art tiles "
                  "could be downloaded.", file=sys.stderr)
            sys.exit(1)
    return tile_cache, base_art_cache


# ---------------------------------------------------------------------------
# Phase 4: FDIDMap.lua
# ---------------------------------------------------------------------------

def run_fdid_map_phase(
    output_dir: str,
    lowres_dir: str,
    zone_db: dict[str, dict],
    passes: dict,
    *,
    include_original: bool,
    total_out_tiles: int,
    metadata_only: bool = False,
) -> None:
    print("\n--- Phase 4: Generating FDIDMap.lua ---", flush=True)
    summary = None
    try:
        summary = generate_fdid_map(
            output_dir,
            lowres_dir,
            zone_db,
            stamp(passes),
            original=include_original,
            metadata_only=metadata_only,
        )
    except OSError as exc:
        print(f"  Warning: FDIDMap.lua generation failed: {exc}",
              flush=True)

    if summary and summary["entries"] != total_out_tiles:
        print(
            f"  NOTE: {summary['entries']} map entries vs "
            f"{total_out_tiles} BLPs written — "
            f"{summary['missing']} expected files were absent.",
            flush=True,
        )
    if summary and summary["original_entries"]:
        print(
            f"  In-game Original background available: "
            f"{summary['original_entries']} raw textures across "
            f"{summary['original_zones']} zones.",
            flush=True,
        )


# ---------------------------------------------------------------------------
# Phase 5: CaveData.lua
# ---------------------------------------------------------------------------

def run_cave_pass(force_refresh: bool = False) -> bool:
    """Build the interior map table and write ``CaveData.lua``.

    Returns whether the file was written.  A failure here is reported and
    swallowed rather than fatal: the cave window is one optional feature,
    and there is no reason a wago.tools hiccup should cost a caller the
    zone art they just spent twenty minutes generating.
    """
    try:
        places = build_cave_table(force_refresh=force_refresh)
    except (URLError, HTTPError, OSError) as exc:
        print(f"  Warning: the cave pass could not reach its sources: "
              f"{exc}", flush=True)
        print("  CaveData.lua left as it was; the cave window will use "
              "whatever is already shipped.", flush=True)
        return False

    if not places:
        # Not an error in itself — a build whose UiMap does carry interior
        # rows needs no baked table, because C_Map can answer directly.
        print("  No interiors survived validation against this build; "
              "CaveData.lua not written.", flush=True)
        return False

    summary = generate_cave_data(places)
    slider = summary["multi"]
    print(
        f"  {slider} of them have more than one floor, so the depth "
        f"slider has notches to show.",
        flush=True,
    )
    return True
