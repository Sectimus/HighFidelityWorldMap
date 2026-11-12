"""Ocean handling — turning the sea into one colour, or into nothing.

The stitched minimap shows the sea in several ways, and where they meet the
result is a set of hard rectangular seams on 533-yard tile boundaries; past
the edge of the terrain grid there is no tile at all.  This module is the
pixel and grid half of dealing with that.  *Which* pixels are sea is not
decided here and is not decided by colour: :mod:`hfwm.gamedata.ocean_water`
reads it from the terrain files, and :mod:`hfwm.pipeline.zone` hands the
resulting per-tile masks to the functions below.

(It used to be a colour match against a measured palette of sea fills. That
broke when the minimap baker changed its sea colour between game builds for
identical terrain, leaving black stripes where the new fill fell outside the
palette. The terrain does not change with the baker.)

* :func:`apply_unify` recolours the masked pixels to one sea colour.
* :func:`apply_erase` makes them transparent, so the addon's backdrop shows.
* :func:`classify_missing_cells` decides what the empty cells become.
  Filling them unconditionally would be wrong: an interior instance map
  like Alterac Valley bakes its own neutral grey void into its tiles, and
  painting the surrounding empty cells blue just moves the seam.  So empty
  cells are grouped into 4-connected components over the region's WDT grid
  and a component is only filled if it actually touches a mostly-ocean
  tile.  AV's void has no ocean neighbour and stays black; a hole in the
  middle of a landmass stays black; the sea around a continent or an island
  fills.

Both pixel operations run at each tile's **native resolution, before the
downscale** to the region's stitch resolution — do it after and the downscale
has already blended dark ocean into light across every coast tile, leaving a
fringe no mask can reach.
"""

from __future__ import annotations

from collections import deque

from ..config.ocean import OCEAN_TILE_FRACTION


# ---------------------------------------------------------------------------
# Colour parsing
# ---------------------------------------------------------------------------

def parse_rgb(value: str) -> tuple[int, int, int]:
    """Parse ``#RRGGBB`` / ``RRGGBB`` / ``R,G,B`` into an RGB triple."""
    text = value.strip()
    if "," in text:
        parts = [p.strip() for p in text.split(",")]
        if len(parts) != 3:
            raise ValueError(f"expected 3 comma-separated channels, got {value!r}")
        rgb = tuple(int(p) for p in parts)
    else:
        hexpart = text[1:] if text.startswith("#") else text
        if len(hexpart) != 6:
            raise ValueError(f"expected 6 hex digits, got {value!r}")
        rgb = tuple(int(hexpart[i:i + 2], 16) for i in (0, 2, 4))

    if any(c < 0 or c > 255 for c in rgb):
        raise ValueError(f"channels must be 0-255, got {value!r}")
    return rgb  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# Pixel pass
# ---------------------------------------------------------------------------

def apply_unify(arr, mask, ocean_rgb: tuple[int, int, int]) -> None:
    """Recolour *arr*'s RGB in-place wherever *mask* is set.

    *arr* is an ``HxWx4`` uint8 array; *mask* is ``HxW`` bool.
    """
    if mask.any():
        arr[:, :, :3][mask] = ocean_rgb


def apply_erase(arr, mask, keep_rgb: bool = True) -> None:
    """Clear *arr*'s alpha in-place wherever *mask* is set.

    Only the alpha is cleared, by default.  The sea's original colour is left
    in the RGB channels underneath, where alpha blending will never show it
    directly, because it is the better neighbour for the LANCZOS downscale to
    the region's stitch resolution, which interpolates colour and alpha
    independently.  A coast pixel ends up part-transparent either way; the
    question is only what colour it carries.  Zeroing the RGB makes that
    colour part-black, and blending part-black at partial alpha is the
    classic dark halo.  Leaving the real sea colour there means the fringe
    blends land into sea, which is what it is.

    Pass ``keep_rgb=False`` for the old zeroing behaviour.
    """
    if mask.any():
        if keep_rgb:
            arr[:, :, 3][mask] = 0
        else:
            arr[mask] = (0, 0, 0, 0)


# ---------------------------------------------------------------------------
# Empty-cell pass
# ---------------------------------------------------------------------------

def classify_missing_cells(
    ocean_fracs: dict[tuple[int, int], float],
    row_min: int,
    row_max: int,
    col_min: int,
    col_max: int,
    tile_fraction: float = OCEAN_TILE_FRACTION,
) -> list[tuple[int, int]]:
    """Return the empty ``(row, col)`` cells that should be filled with sea.

    *ocean_fracs* maps every cell that produced a tile to that tile's ocean
    fraction; any cell in the region's grid that is absent from it is empty.
    Empty cells are grouped into 4-connected components, and a component is
    returned only if at least one of its neighbours is a tile whose ocean
    fraction reaches *tile_fraction* — i.e. the gap opens onto real water,
    not onto the grey void of an interior map or the middle of a landmass.
    """
    grid_rows = range(row_min, row_max + 1)
    grid_cols = range(col_min, col_max + 1)

    empty = {
        (r, c)
        for r in grid_rows
        for c in grid_cols
        if (r, c) not in ocean_fracs
    }
    if not empty:
        return []

    oceanic = {
        cell for cell, frac in ocean_fracs.items() if frac >= tile_fraction
    }
    if not oceanic:
        # Nothing in this region reads as open water, so there is no sea to
        # extend into the gaps.  Leave them black.
        return []

    fill: list[tuple[int, int]] = []
    unvisited = set(empty)
    while unvisited:
        seed = unvisited.pop()
        component = [seed]
        touches_ocean = False
        queue = deque([seed])
        while queue:
            r, c = queue.popleft()
            for nr, nc in ((r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)):
                if (nr, nc) in oceanic:
                    touches_ocean = True
                    continue
                if (nr, nc) in unvisited:
                    unvisited.discard((nr, nc))
                    component.append((nr, nc))
                    queue.append((nr, nc))
        if touches_ocean:
            fill.extend(component)

    return fill
