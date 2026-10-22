"""Fetching baked indoor minimap art and the files that place it.

Everything here goes through the *pinned* CASC endpoint: the WMO/ADT files
and the per-group minimap tiles are build-specific, and an unpinned
request would happily serve retail's copy (see
:data:`hfwm.config.endpoints.WAGO_CASC_PINNED_FMT`).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from ..config.paths import WMO_CACHE_DIR, WMO_TILE_CACHE_DIR
from ..infra.http import download_casc_cached
from .wmo import WmoPlacement, parse_modf_placements, select_placement


def _cached_path(fdid: int, cache_dir: Path) -> Path:
    return download_casc_cached(fdid, cache_dir)


def fetch_wmo_root(fdid: int) -> bytes:
    return _cached_path(fdid, WMO_CACHE_DIR).read_bytes()


def fetch_wmo_world_placement(adt_obj0_fdid: int, wmo_fdid: int,
                               expected_unique_id: int | None = None) -> WmoPlacement:
    """Return the MODF placement record (position + rotation) of *wmo_fdid*.

    Only ``rotation.y`` (the yaw about Up, degrees) is used for the flat,
    top-down floor plans this project bakes; pitch/roll (rotation.x /
    rotation.z) are ignored.  wowdev.wiki's ADT/v18 coordinate-system
    table names rotation.y specifically as "the rotation around the Up
    axis" — the only component that can matter for a top-down image.  A
    cave placed with real pitch/roll would need actual 3-D re-projection
    this pipeline doesn't (yet) do; Fargodeep's own record has rotation ==
    (0.0, 301.5, 0.0), i.e. flat, so this isn't exercised here.

    The height component matters too — see
    :func:`hfwm.caves.wmo.world_z_range_for_groups`.
    """
    data = _cached_path(adt_obj0_fdid, WMO_CACHE_DIR).read_bytes()
    placements = parse_modf_placements(data, wmo_fdid)
    return select_placement(placements, wmo_fdid, adt_obj0_fdid, expected_unique_id)


def fetch_tile(fdid: int) -> Image.Image:
    """Fetch one group's minimap tile, cropped to its opaque content.

    Every tile is padded out to a power-of-two texture size (32/64/128px
    square), with the actual room render packed into one corner and the
    rest left fully transparent — a normal texture-atlas constraint, not
    meaningful image content. Left uncropped, that padding was why touching
    rooms rendered with a visible gap between them despite their MOGI
    bboxes having zero coordinate-space gap: each room's real, alpha-cropped
    content aspect ratio matches its bbox aspect ratio closely (verified
    across all 21 Fargodeep tiles, within a few percent each), while the
    padded square does not. Cropping here, once, keeps that fix out of the
    compositing code and applies automatically to any future dungeon.
    """
    img = Image.open(_cached_path(fdid, WMO_TILE_CACHE_DIR)).convert("RGBA")
    opaque_bbox = img.split()[-1].getbbox()
    if opaque_bbox:
        img = img.crop(opaque_bbox)
    return img


# Grid pitch of a multi-subtile group's cells. A tile is at most this big (a
# narrow room's tiles can be 128 wide); see stitch_subtiles for the layout.
WMO_SUBTILE_PX = 256


def stitch_subtiles(subtile_fdids: dict[tuple[int, int], int]):
    """``(canvas, rects)``: a multi-sub-tile group's raw tiles assembled
    uncropped, and each tile's ``(x, y, w, h)`` on that canvas.

    A key ``(a, b)`` comes from the filename ``..._<group:03d>_<a:02d>_<b:02d>
    .blp`` and is a Cartesian cell: *a* counts rightward, *b* counts upward
    from the bottom-left, where a lone tile also packs its room. A tile
    smaller than 256 sits in the bottom-left of its cell. (Checked against
    every multi-tile group of every registered mine and Ironforge: this
    layout makes the opaque content as big as the group's MOGI bbox says,
    the transposed row/col reading does not.)
    """
    cols = max(a for a, _ in subtile_fdids) + 1
    rows = max(b for _, b in subtile_fdids) + 1
    canvas = Image.new("RGBA", (cols * WMO_SUBTILE_PX, rows * WMO_SUBTILE_PX), (0, 0, 0, 0))
    rects = {}
    for (a, b), fdid in subtile_fdids.items():
        sub = Image.open(_cached_path(fdid, WMO_TILE_CACHE_DIR)).convert("RGBA")
        x = a * WMO_SUBTILE_PX
        y = (rows - b) * WMO_SUBTILE_PX - sub.height
        canvas.paste(sub, (x, y))
        rects[(a, b)] = (x, y, *sub.size)
    return canvas, rects


def fetch_stitched_tile(subtile_fdids: dict[tuple[int, int], int]) -> Image.Image:
    """A group's minimap art from more than one raw sub-tile (see
    :func:`stitch_subtiles`), cropped once to the assembled room's opaque
    bbox like :func:`fetch_tile`. Cropping each sub-tile first would throw
    away its position within the room."""
    canvas, _ = stitch_subtiles(subtile_fdids)
    opaque_bbox = canvas.split()[-1].getbbox()
    return canvas.crop(opaque_bbox) if opaque_bbox else canvas


def fetch_group_tile(tile_fdid: "int | dict[tuple[int, int], int]") -> Image.Image:
    """Dispatch to ``fetch_tile`` or ``fetch_stitched_tile`` depending on
    whether *tile_fdid* (a ``MineSpec.tile_fdids`` value, or the
    ``WmoGroup.tile_fdid`` it ends up on) is a plain FDID or a multi-subtile
    ``{(row, col): fdid}`` map. Every call site that used to call
    ``fetch_tile`` directly goes through this instead, so a group can move
    from single- to multi-subtile without touching the compositing code.
    """
    if isinstance(tile_fdid, dict):
        return fetch_stitched_tile(tile_fdid)
    return fetch_tile(tile_fdid)
