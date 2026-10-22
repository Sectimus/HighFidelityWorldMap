"""Zone database builder for HFWM-Forever.

Downloads the build-pinned DB2 exports and the WDT files they point at,
then produces one entry per renderable UiMap describing:

  * the art-layer geometry the client expects (``cols``/``rows`` of
    tiles, ``layer_w``/``layer_h`` in pixels, ``tile_w``/``tile_h``), and
    the layer-0 ``FileDataID`` of every tile in row-major order, and
  * one or more *regions* — a world-space rectangle on a terrain map,
    the minimap tiles covering it, and the normalised sub-rect of the
    art layer it occupies.

The join chain (all tables verified present on 1.60.1.69913):

    UiMap                 ID, Name_lang, Type
    UiMapXMapArt          UiMapID -> UiMapArtID  (lowest PhaseID wins)
    UiMapArt              ID -> UiMapArtStyleID
    UiMapArtStyleLayer    UiMapArtStyleID -> Layer/Tile width+height
    UiMapArtTile          UiMapArtID -> (RowIndex, ColIndex, FileDataID)
    UiMapAssignment       UiMapID -> MapID, Region_0..5, UiMin/UiMax
    Map                   ID -> Directory, WdtFileDataID

Two deliberate departures from the retail pipeline:

  * **No community listfile.**  Retail resolved a zone's on-disk art
    folder by matching listfile paths; here the tile ``FileDataID``s come
    straight out of ``UiMapArtTile`` and the folder name is derived from
    ``UiMap.Name_lang``, so the pipeline has no third-party dependency.
  * **No WorldMapArea.**  That table 404s on this build.  Zone bounds
    come from ``UiMapAssignment.Region_*``.

``UiMapAssignment`` region fields, confirmed against known zones:

    loc_top    = Region_3   (max world X)
    loc_bottom = Region_0   (min world X)
    loc_left   = Region_4   (max world Y)
    loc_right  = Region_1   (min world Y)
"""

from __future__ import annotations

import hashlib
import json
import re
import time

from ..config.build import GAME_BUILD, GAME_PRODUCT
from ..config.caching import MINIMAP_DB_CACHE_TTL_DAYS
from ..config.endpoints import DB2_TABLES
from ..config.paths import MINIMAP_DB_CACHE, PROVENANCE_FILE, WDT_CACHE_DIR
from ..config.tiles import (
    EXPECTED_ART_LAYER_DIMS,
    HIRES_CONTINENT_MAPS,
    HIRES_CONTINENT_MAX_PX,
    MINIMAP_TILE_PX,
    NATIVE_ZONE_TILE_PX,
    TILE_WORLD_SIZE,
    UI_MAP_TYPE_ZONE,
)
from ..formats.wdt import MAID_FIELD_MINIMAP, parse_wdt_maid
from ..geometry.coordinates import world_to_tile
from ..infra.cache import CachedFile
from ..infra.http import download_casc
from .tables import fetch_pinned_table


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def fetch_zone_db(
    force_refresh: bool = False,
    maid_field: int = MAID_FIELD_MINIMAP,
) -> dict[str, dict]:
    """Return the zone database, using the TTL cache when possible."""
    use_cache = maid_field == MAID_FIELD_MINIMAP
    cache = CachedFile(MINIMAP_DB_CACHE, MINIMAP_DB_CACHE_TTL_DAYS)

    if use_cache and not force_refresh:
        data, age = cache.load_or_none()
        if data is not None:
            print(
                f"  Using cached zone DB ({len(data)} zones, "
                f"{age:.0f} days old).",
                flush=True,
            )
            return data

    tables = _fetch_all_tables(force_refresh)
    db = _build_zone_db(tables, maid_field)
    if use_cache:
        cache.save(db)
    return db


# ---------------------------------------------------------------------------
# DB2 downloads
# ---------------------------------------------------------------------------

def _fetch_all_tables(force_refresh: bool) -> dict[str, list[dict]]:
    """Download every table in :data:`DB2_TABLES`."""
    print(f"  Downloading {len(DB2_TABLES)} DB2 tables "
          f"(build {GAME_BUILD}) ...", flush=True)
    tables: dict[str, list[dict]] = {}
    for name in DB2_TABLES:
        rows = fetch_pinned_table(name, force_refresh)
        tables[name] = rows
        print(f"    {name}: {len(rows)} rows", flush=True)
    return tables


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def _int(row: dict, key: str) -> int | None:
    try:
        return int(row[key])
    except (KeyError, TypeError, ValueError):
        return None


def _float(row: dict, key: str) -> float | None:
    try:
        return float(row[key])
    except (KeyError, TypeError, ValueError):
        return None


def _folder_name(name: str) -> str:
    """Blizzard-style folder name: ``Un'Goro Crater`` -> ``UnGoroCrater``."""
    return re.sub(r"[^A-Za-z0-9]", "", name)


# ---------------------------------------------------------------------------
# Art geometry
# ---------------------------------------------------------------------------

def _build_art_geometry(
    art_rows: list[dict],
    style_layer_rows: list[dict],
    art_tile_rows: list[dict],
) -> dict[int, dict]:
    """Return ``{UiMapArtID: geometry}`` for every art with complete tiles.

    ``tile_fdids`` is row-major — the same order the client's
    ``C_Map.GetMapArtLayerTextures`` returns, which is what the addon's
    ``BaseArt.lua`` relies on.
    """
    # UiMapArtID -> UiMapArtStyleID
    art_to_style: dict[int, int] = {}
    for r in art_rows:
        aid = _int(r, "ID")
        sid = _int(r, "UiMapArtStyleID")
        if aid is not None and sid is not None:
            art_to_style[aid] = sid

    # UiMapArtStyleID -> layer-0 dimensions
    style_dims: dict[int, dict] = {}
    for r in style_layer_rows:
        if _int(r, "LayerIndex") != 0:
            continue
        sid = _int(r, "UiMapArtStyleID")
        lw, lh = _int(r, "LayerWidth"), _int(r, "LayerHeight")
        tw, th = _int(r, "TileWidth"), _int(r, "TileHeight")
        if None in (sid, lw, lh, tw, th) or tw <= 0 or th <= 0:
            continue
        cols = -(-lw // tw)   # ceil
        rows = -(-lh // th)
        expected = EXPECTED_ART_LAYER_DIMS.get((cols, rows))
        if expected and (lw, lh) != expected:
            print(
                f"    WARNING: art style {sid} is {cols}x{rows} tiles but "
                f"{lw}x{lh}px — expected {expected[0]}x{expected[1]}px.",
                flush=True,
            )
        style_dims[sid] = {
            "cols": cols, "rows": rows,
            "layer_w": lw, "layer_h": lh,
            "tile_w": tw, "tile_h": th,
        }

    # UiMapArtID -> {(row, col): FileDataID}
    cells: dict[int, dict[tuple[int, int], int]] = {}
    for r in art_tile_rows:
        if _int(r, "LayerIndex") != 0:
            continue
        aid = _int(r, "UiMapArtID")
        ri, ci = _int(r, "RowIndex"), _int(r, "ColIndex")
        fdid = _int(r, "FileDataID")
        if None in (aid, ri, ci, fdid) or fdid <= 0:
            continue
        cells.setdefault(aid, {})[(ri, ci)] = fdid

    geometry: dict[int, dict] = {}
    incomplete = 0
    for aid, grid in cells.items():
        sid = art_to_style.get(aid)
        dims = style_dims.get(sid) if sid is not None else None
        if not dims:
            continue
        ordered: list[int] = []
        missing = False
        for ri in range(dims["rows"]):
            for ci in range(dims["cols"]):
                fdid = grid.get((ri, ci))
                if fdid is None:
                    missing = True
                    break
                ordered.append(fdid)
            if missing:
                break
        if missing:
            incomplete += 1
            continue
        geometry[aid] = dict(dims, tile_fdids=ordered, style_id=sid)

    if incomplete:
        print(f"    {incomplete} arts skipped (incomplete tile grid)",
              flush=True)
    print(f"    {len(geometry)} arts with complete layer-0 geometry",
          flush=True)
    return geometry


# ---------------------------------------------------------------------------
# Native-resolution zone geometry (see constants.NATIVE_ZONE_TILE_PX)
# ---------------------------------------------------------------------------

def _native_zone_layer_dims(regions: list[dict]) -> tuple[float, float]:
    """Native-resolution art-layer size implied by a map's own regions.

    Enough pixels to render every region at exactly the minimap's own
    source density (``MINIMAP_TILE_PX`` per ``TILE_WORLD_SIZE`` yards) — no
    upscale, no downscale. Mirrors the axis mapping ``zone.py`` already
    uses when placing a region into the layer: horizontal (layer_w) is fed
    by world Y (``loc_left``/``loc_right``), vertical (layer_h) by world X
    (``loc_top``/``loc_bottom``).

    A region occupies only its own ``ui_min/max`` sub-rect of the full
    layer, so the layer size implied by *that* region alone is its own
    pixel span divided by the fraction of the layer it covers. Multi-region
    maps take the max across regions, so every region ends up at least at
    native density (a region whose own implied layer is smaller than
    another's just ends up slightly denser than native, never softer).

    Used both for Type=Zone maps (uncapped) and for the three named
    continent/world maps in ``HIRES_CONTINENT_MAPS`` (capped) — see
    :func:`_hires_geometry`.
    """
    native_pp = MINIMAP_TILE_PX / TILE_WORLD_SIZE  # px per world yard
    layer_w = 0.0
    layer_h = 0.0
    for reg in regions:
        span_y = reg["loc_left"] - reg["loc_right"]
        span_x = reg["loc_top"] - reg["loc_bottom"]
        ui_w = reg["ui_max_x"] - reg["ui_min_x"]
        ui_h = reg["ui_max_y"] - reg["ui_min_y"]
        if span_y > 0 and ui_w > 1e-6:
            layer_w = max(layer_w, span_y * native_pp / ui_w)
        if span_x > 0 and ui_h > 1e-6:
            layer_h = max(layer_h, span_x * native_pp / ui_h)
    return layer_w, layer_h


def _hires_geometry(
    ui_map_type: int, folder: str, layer_w: int, layer_h: int,
    regions: list[dict],
) -> dict | None:
    """Return higher-resolution ``{cols, rows, layer_w, layer_h, tile_w,
    tile_h}`` for a map that qualifies, or ``None`` to leave Blizzard's
    fixed layer alone.

    Two cases qualify, and only one is actually lossless:

    * Every Type=Zone map gets its layer sized to the minimap's own native
      density, uncapped — see ``_native_zone_layer_dims``. Zones are small
      enough that even the biggest (TheBarrens) tops out at under 1,000
      tiles.
    * The three maps named in ``HIRES_CONTINENT_MAPS`` (Kalimdor, Eastern
      Kingdoms, the top-level Azeroth map) get the same native-density
      calculation, but then scaled down to fit within
      ``HIRES_CONTINENT_MAX_PX`` on its longer axis if native would exceed
      it — which for a continent it always does by a wide margin (Kalimdor
      alone is 138x92 = 12,696 tiles at true native, an addon-crippling
      texture count for what a player opens constantly). Capped rather
      than lossless is the deliberate trade-off here.

    Either way, ``None`` when the result is already at or below Blizzard's
    own fixed layer (e.g. the 512x512 city maps) — going bigger there would
    upscale rather than preserve detail, so the fixed layer is left alone.
    """
    if ui_map_type == UI_MAP_TYPE_ZONE:
        max_px = None
    elif folder in HIRES_CONTINENT_MAPS:
        max_px = HIRES_CONTINENT_MAX_PX
    else:
        return None

    native_w, native_h = _native_zone_layer_dims(regions)
    if max_px is not None and (native_w > max_px or native_h > max_px):
        scale = min(
            max_px / native_w if native_w > 0 else 1.0,
            max_px / native_h if native_h > 0 else 1.0,
        )
        native_w, native_h = native_w * scale, native_h * scale

    if native_w <= layer_w and native_h <= layer_h:
        return None
    cols = max(1, -(-round(native_w) // NATIVE_ZONE_TILE_PX))
    rows = max(1, -(-round(native_h) // NATIVE_ZONE_TILE_PX))
    return {
        "cols": cols, "rows": rows,
        "layer_w": round(native_w), "layer_h": round(native_h),
        "tile_w": NATIVE_ZONE_TILE_PX, "tile_h": NATIVE_ZONE_TILE_PX,
        # Zone maps ship on unconditionally; the capped continent maps sit
        # behind the addon's "Increase world map clarity" toggle (off by
        # default) because of the render cost their much bigger tile grid
        # adds -- fdid_map.py reads this to mark their Lua table entries so
        # Config/Renderer know which ones to gate.
        "continent": folder in HIRES_CONTINENT_MAPS,
    }


# ---------------------------------------------------------------------------
# WDT downloads
# ---------------------------------------------------------------------------

def _fetch_wdt(map_id: int, wdt_fdid: int) -> bytes:
    """Download a WDT with filesystem caching; ``b""`` on failure."""
    WDT_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = WDT_CACHE_DIR / f"{map_id}_{wdt_fdid}.wdt"
    try:
        if cache_path.exists() and cache_path.stat().st_size > 0:
            return cache_path.read_bytes()
        data = download_casc(wdt_fdid)
        cache_path.write_bytes(data)
        return data
    except Exception as exc:
        print(f"    WARNING: WDT {wdt_fdid} (map {map_id}): {exc}", flush=True)
        return b""


def _download_wdt_grids(
    needed: dict[int, int],
    maid_field: int,
) -> tuple[dict[int, dict[tuple[int, int], int]], dict[str, dict]]:
    """Parse MAID grids for every ``{map_id: wdt_fdid}`` in *needed*.

    Also returns provenance for each WDT (its md5 and tile footprint).
    """
    print(f"  Downloading {len(needed)} WDT files ...", flush=True)
    grids: dict[int, dict[tuple[int, int], int]] = {}
    provenance: dict[str, dict] = {}

    for map_id, wdt_fdid in sorted(needed.items()):
        data = _fetch_wdt(map_id, wdt_fdid)
        if not data:
            continue
        grid = parse_wdt_maid(data, field_index=maid_field)
        if not grid:
            print(f"    map {map_id}: WDT has no MAID field {maid_field} data",
                  flush=True)
            continue
        grids[map_id] = grid

        rows = [r for r, _ in grid]
        cols = [c for _, c in grid]
        provenance[str(wdt_fdid)] = {
            "map_id": map_id,
            "wdt_fdid": wdt_fdid,
            "md5": hashlib.md5(data).hexdigest(),
            "bytes": len(data),
            "tiles": len(grid),
            "row_range": [min(rows), max(rows)],
            "col_range": [min(cols), max(cols)],
        }
        print(
            f"    map {map_id}: {len(grid)} tiles "
            f"(rows {min(rows)}-{max(rows)}, cols {min(cols)}-{max(cols)})",
            flush=True,
        )

    return grids, provenance


# ---------------------------------------------------------------------------
# Zone assembly
# ---------------------------------------------------------------------------

def _build_zone_db(
    tables: dict[str, list[dict]],
    maid_field: int,
) -> dict[str, dict]:
    """Join the DB2 tables and WDT grids into the final zone database."""
    # --- Map: terrain directory + WDT ---
    map_info: dict[int, dict] = {}
    for r in tables["Map"]:
        mid = _int(r, "ID")
        wdt = _int(r, "WdtFileDataID")
        directory = r.get("Directory") or ""
        if mid is not None and wdt and wdt > 0 and directory:
            map_info[mid] = {"directory": directory, "wdt_fdid": wdt}

    # --- UiMap: names + types ---
    ui_names: dict[int, str] = {}
    ui_types: dict[int, int] = {}
    for r in tables["UiMap"]:
        uid = _int(r, "ID")
        name = r.get("Name_lang") or ""
        if uid is None or not name:
            continue
        ui_names[uid] = name
        ui_types[uid] = _int(r, "Type") or 0

    # --- UiMapXMapArt: lowest PhaseID wins ---
    ui_to_art: dict[int, int] = {}
    ui_art_phase: dict[int, int] = {}
    for r in tables["UiMapXMapArt"]:
        uid = _int(r, "UiMapID")
        aid = _int(r, "UiMapArtID")
        if uid is None or aid is None:
            continue
        phase = _int(r, "PhaseID") or 0
        if uid not in ui_to_art or phase < ui_art_phase[uid]:
            ui_to_art[uid] = aid
            ui_art_phase[uid] = phase

    # --- Art geometry ---
    geometry = _build_art_geometry(
        tables["UiMapArt"],
        tables["UiMapArtStyleLayer"],
        tables["UiMapArtTile"],
    )

    # --- UiMapAssignment: group regions per UiMap ---
    assignments: dict[int, list[dict]] = {}
    for idx, r in enumerate(tables["UiMapAssignment"]):
        uid = _int(r, "UiMapID")
        mid = _int(r, "MapID")
        if uid is None or mid is None or mid not in map_info:
            continue
        if uid not in ui_to_art or ui_to_art[uid] not in geometry:
            continue

        r0 = _float(r, "Region_0")
        r1 = _float(r, "Region_1")
        r3 = _float(r, "Region_3")
        r4 = _float(r, "Region_4")
        if None in (r0, r1, r3, r4):
            continue
        if r0 == 0 and r1 == 0 and r3 == 0 and r4 == 0:
            continue

        info = map_info[mid]
        assignments.setdefault(uid, []).append({
            "map_id": mid,
            "map_dir": info["directory"],
            "wdt_fdid": info["wdt_fdid"],
            "loc_top": r3,
            "loc_bottom": r0,
            "loc_left": r4,
            "loc_right": r1,
            "ui_min_x": _float(r, "UiMin_0") or 0.0,
            "ui_min_y": _float(r, "UiMin_1") or 0.0,
            "ui_max_x": _float(r, "UiMax_0") if _float(r, "UiMax_0") is not None else 1.0,
            "ui_max_y": _float(r, "UiMax_1") if _float(r, "UiMax_1") is not None else 1.0,
            "order": idx,
        })

    # --- WDT grids for every map we need ---
    needed: dict[int, int] = {}
    for regions in assignments.values():
        for reg in regions:
            needed.setdefault(reg["map_id"], reg["wdt_fdid"])
    grids, wdt_provenance = _download_wdt_grids(needed, maid_field)

    # --- Emit zones ---
    zones: dict[str, dict] = {}
    used: set[str] = set()
    skipped_no_tiles = 0

    for uid in sorted(assignments):
        art_id = ui_to_art[uid]
        geo = geometry[art_id]

        regions: list[dict] = []
        for reg in sorted(assignments[uid], key=lambda x: x["order"]):
            grid = grids.get(reg["map_id"])
            if not grid:
                continue

            row_min = world_to_tile(reg["loc_top"])
            row_max = world_to_tile(reg["loc_bottom"])
            col_min = world_to_tile(reg["loc_left"])
            col_max = world_to_tile(reg["loc_right"])
            if row_min > row_max:
                row_min, row_max = row_max, row_min
            if col_min > col_max:
                col_min, col_max = col_max, col_min
            row_min, row_max = max(0, row_min), min(63, row_max)
            col_min, col_max = max(0, col_min), min(63, col_max)

            tiles: dict[str, int] = {}
            for rr in range(row_min, row_max + 1):
                for cc in range(col_min, col_max + 1):
                    fdid = grid.get((rr, cc))
                    if fdid:
                        tiles[f"{rr}_{cc}"] = fdid
            if not tiles:
                continue

            regions.append(dict(
                reg,
                row_min=row_min, row_max=row_max,
                col_min=col_min, col_max=col_max,
                tiles=tiles,
            ))

        if not regions:
            skipped_no_tiles += 1
            continue

        base = _folder_name(ui_names[uid]) or f"UiMap{uid}"
        key = base if base not in used else f"{base}{uid}"
        used.add(key)

        ui_map_type = ui_types.get(uid, 0)
        native = _hires_geometry(
            ui_map_type, key, geo["layer_w"], geo["layer_h"], regions,
        )

        # The three capped continent maps ship two builds, not one: the
        # "Increase world map clarity" toggle needs a genuinely lower-res
        # *satellite* fallback for when it's off, not Blizzard's own
        # hand-painted map -- so the base key here always stays the
        # ordinary, Blizzard-grid-matching satellite build (native=None,
        # included in HFWMF_FDID_MAP same as any other non-native map),
        # and a second "<key>HD" entry carries the capped hi-res geometry
        # instead. Every Type=Zone map (native uncapped, no toggle, no
        # dual build) keeps native set on the one entry as before.
        is_continent = bool(native) and native.get("continent")

        zones[key] = {
            "folder": key,
            "area_name": ui_names[uid],
            "ui_map_id": uid,
            "ui_map_type": ui_map_type,
            "ui_map_art_id": art_id,
            "cols": geo["cols"],
            "rows": geo["rows"],
            "layer_w": geo["layer_w"],
            "layer_h": geo["layer_h"],
            "tile_w": geo["tile_w"],
            "tile_h": geo["tile_h"],
            "tile_fdids": geo["tile_fdids"],
            "native": None if is_continent else native,
            "regions": regions,
        }

        if is_continent:
            hd_key = f"{key}HD"
            zones[hd_key] = dict(zones[key], folder=hd_key, native=native)
            used.add(hd_key)

    if skipped_no_tiles:
        print(f"    {skipped_no_tiles} UiMaps skipped (no minimap coverage)",
              flush=True)

    multi = sum(1 for z in zones.values() if len(z["regions"]) > 1)
    unique_tiles = {
        fdid
        for z in zones.values()
        for reg in z["regions"]
        for fdid in reg["tiles"].values()
    }
    print(
        f"  Zone DB: {len(zones)} zones "
        f"({multi} multi-region), {len(unique_tiles)} unique minimap tiles",
        flush=True,
    )

    _write_provenance(wdt_provenance, zones, maid_field)
    return zones


# ---------------------------------------------------------------------------
# Provenance
# ---------------------------------------------------------------------------

def _write_provenance(
    wdt_provenance: dict[str, dict],
    zones: dict[str, dict],
    maid_field: int,
) -> None:
    """Record what this run actually ingested.

    The DB2 exports and CASC files are both build-pinned. The md5 and tile
    footprint recorded here make a changed WDT diagnosable.
    """
    payload = {
        "product": GAME_PRODUCT,
        "build": GAME_BUILD,
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "maid_field": maid_field,
        "note": (
            "DB2 exports and CASC files are both pinned to 'build'. WDT "
            "files cached by a run before CASC pinning may predate it."
        ),
        "wdts": wdt_provenance,
        "zones": {
            key: {
                "ui_map_id": z["ui_map_id"],
                "ui_map_art_id": z["ui_map_art_id"],
                "area_name": z["area_name"],
                "grid": f"{z['cols']}x{z['rows']}",
                "layer": f"{z['layer_w']}x{z['layer_h']}",
                "tile": f"{z['tile_w']}x{z['tile_h']}",
                "native_grid": (
                    f"{z['native']['cols']}x{z['native']['rows']}"
                    if z.get("native") else None
                ),
                "native_layer": (
                    f"{z['native']['layer_w']}x{z['native']['layer_h']}"
                    if z.get("native") else None
                ),
                "regions": [
                    {
                        "map_id": reg["map_id"],
                        "map_dir": reg["map_dir"],
                        "tiles": len(reg["tiles"]),
                        "rows": [reg["row_min"], reg["row_max"]],
                        "cols": [reg["col_min"], reg["col_max"]],
                        "ui_rect": [
                            reg["ui_min_x"], reg["ui_min_y"],
                            reg["ui_max_x"], reg["ui_max_y"],
                        ],
                    }
                    for reg in z["regions"]
                ],
            }
            for key, z in sorted(zones.items())
        },
    }
    PROVENANCE_FILE.parent.mkdir(parents=True, exist_ok=True)
    PROVENANCE_FILE.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"  Provenance written to {PROVENANCE_FILE.name}", flush=True)
