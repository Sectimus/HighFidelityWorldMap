"""Ocean unification — one sea colour instead of three.

The stitched minimap shows the sea in three different ways, and where they
meet the result is a set of hard rectangular seams on 533-yard tile
boundaries:

1. **Open-ocean tiles** — an ADT with no terrain in it bakes a flat, almost
   black ``(8, 16, 16)`` fill across the whole 512px minimap tile.
2. **Coastal tiles** — an ADT that does contain terrain renders its water
   surface through the normal water shader, giving the noticeably lighter
   ``(26, 50, 69)``.  So every coast has a light shelf abruptly bounded by
   dark open ocean one tile out.
3. **Cells with no tile at all** — the WDT's MAID grid only covers ADTs
   that exist, so past the edge of the terrain grid there is nothing, and
   the stitch canvas's own black shows through.  On Eastern Kingdoms that
   is 74% of the art layer.

This module collapses all three onto a single colour.  Two passes:

* :func:`unify_tile` rewrites every ocean-palette pixel in a source tile.
  It runs at the tile's **native resolution, before the downscale** to the
  region's stitch resolution — do it after and the downscale has already
  blended dark ocean into light across every coast tile, leaving a fringe
  no exact-colour match can reach.
* :func:`classify_missing_cells` decides what the empty cells become.
  Filling them unconditionally would be wrong: an interior instance map
  like Alterac Valley bakes its own neutral grey void into its tiles, and
  painting the surrounding empty cells blue just moves the seam.  So empty
  cells are grouped into 4-connected components over the region's WDT grid
  and a component is only filled if it actually touches a mostly-ocean
  tile.  AV's void has no ocean neighbour and stays black; a hole in the
  middle of a landmass stays black; the sea around a continent or an island
  fills.

Both passes are keyed off a small measured palette rather than a
"looks blue" heuristic, because the fills are flat and exact and a loose
test eats dark coastal cliff shadow.  Inland lakes use the water shader at
their own tint and are not in the palette in principle, so they are
supposed to survive untouched — but "in principle" is doing a lot of work
there.  A colour test has no idea *where* a pixel is, so anything that
happens to render close enough to one of the five measured fills (within
:data:`OCEAN_FILL_TOLERANCE`) gets erased or recoloured right alongside
real ocean, deep inside a zone's boundary — a lake or river, but also
Blackrock Mountain's near-black interior shading, or any other dark patch
of *dry land* that coincidentally lands in the same narrow colour range as
open ocean.

A first attempt at fixing this restricted the colour test to a border band
near each region's own edge, on the theory that real coastline runs along
the outside of a zone's world rect. That is true often enough, but not at
Blackrock Mountain: it sits in the corner of Burning Steppes' rect, which
*is* an edge, just not a coastal one — Searing Gorge is across it, not the
sea. Distance from the rectangle's edge and distance from the actual
coastline are different things, and only coincide when every edge happens
to be a coast.

The second attempt, :func:`reachable_sea_tiles`, was connectivity instead
of geometry: a whole *tile* only counted as sea if some path of
ocean-coloured tiles connected it back to one read with high confidence as
open water. That fixed Blackrock Mountain — nothing walks a colour-match
chain from it out to the sea — but it was still coarse in the wrong
direction at Stormwind: the canals are real water, so their tile is
legitimately reachable, and the whole-tile gate then erased *every*
ocean-coloured pixel in that tile, including the dark stone of Stormwind
Keep sitting a few pixels away in the same or the next tile over.

:func:`reachable_sea_pixels` is the fix, and it is connectivity at the
resolution the problem actually lives at — pixels, not tiles. Every
tile's own ocean-fill mask is measured at native resolution as before (so
the downscale still can't blend a fringe no exact-colour match could
otherwise reach), but those masks are then assembled into one canvas for
the whole region and split into 4-connected components. A component is
trusted only if it contains at least one pixel from a cell read with high
confidence as open water; a component is a *shape*, so it stops exactly
where the colour does — at the canal's edge, not at the tile's. Real
coastline is one connected body reaching every shore it touches, so it is
always such a component; an isolated match, whatever it is and however
large, is a component of its own that no seed pixel ever falls in.
"""

from __future__ import annotations

from collections import deque

from ..config.ocean import (
    OCEAN_DARK_MAX,
    OCEAN_FILL_COLORS,
    OCEAN_FILL_TOLERANCE,
    OCEAN_TILE_FRACTION,
)


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

def ocean_mask(rgb, terrainless: bool = False):
    """Return a bool mask of ocean-fill pixels in an ``HxWx3`` array.

    Matches any colour in :data:`OCEAN_FILL_COLORS` within
    :data:`OCEAN_FILL_TOLERANCE` per channel (Chebyshev distance).

    Pure black is matched only in a terrain-less tile (*terrainless*, see
    :mod:`hfwm.gamedata.terrain`). There the sea is a flat dark fill whatever
    colour the build paints it, so every pixel at or below
    :data:`OCEAN_DARK_MAX` counts. Elsewhere pure black is not sea: it is
    sparse inland speckle, and matching it put blue dots into interior maps
    like Alterac Valley. Whole cells the WDT never had a tile for are handled
    by :func:`classify_missing_cells`.
    """
    import numpy as np

    rgb = rgb.astype(np.int16, copy=False)
    mask = np.zeros(rgb.shape[:2], dtype=bool)
    for color in OCEAN_FILL_COLORS:
        delta = np.abs(rgb - np.array(color, dtype=np.int16)).max(axis=2)
        mask |= delta <= OCEAN_FILL_TOLERANCE
    if terrainless:
        mask |= (rgb <= OCEAN_DARK_MAX).all(axis=2)
    return mask


def apply_unify(arr, mask, ocean_rgb: tuple[int, int, int]) -> None:
    """Recolour *arr*'s RGB in-place wherever *mask* is set.

    Shared core of :func:`unify_tile` (per-tile, mask computed on the spot)
    and the region-wide path in :mod:`hfwm.pipeline.zone` (mask is the pixel-level
    :func:`reachable_sea_pixels` result). *arr* is an ``HxWx4`` uint8
    array; *mask* is ``HxW`` bool.
    """
    if mask.any():
        arr[:, :, :3][mask] = ocean_rgb


def apply_erase(arr, mask, keep_rgb: bool = True) -> None:
    """Clear *arr*'s alpha in-place wherever *mask* is set.

    Shared core of :func:`erase_tile` and the region-wide path in
    :mod:`hfwm.pipeline.zone`. Only the alpha is cleared, by default: see
    :func:`erase_tile` for why the RGB underneath is worth keeping.
    Pass ``keep_rgb=False`` for the old zeroing behaviour.
    """
    if mask.any():
        if keep_rgb:
            arr[:, :, 3][mask] = 0
        else:
            arr[mask] = (0, 0, 0, 0)


def unify_tile(img, ocean_rgb: tuple[int, int, int]) -> tuple[object, float]:
    """Recolour every ocean-fill pixel of *img* to *ocean_rgb*.

    Returns ``(image, ocean_fraction)``.  *img* is an RGBA PIL image at its
    native resolution; the returned image is a new one.  ``ocean_fraction``
    is what share of the tile was sea, which
    :func:`classify_missing_cells` uses to tell open water from an
    interior map's void.

    Unconditional — matches every colour hit with no idea whether it is
    real sea. :mod:`hfwm.pipeline.zone` does not call this directly any more for
    that reason; it assembles every tile's mask into one canvas and runs
    :func:`reachable_sea_pixels` across the whole region before touching
    anything. This still exists as the single-tile building block (and
    what :func:`reachable_sea_pixels`'s caller measures each tile's own
    fraction with).
    """
    import numpy as np
    from PIL import Image

    arr = np.array(img)
    mask = ocean_mask(arr[:, :, :3])
    frac = float(mask.mean())
    apply_unify(arr, mask, ocean_rgb)
    if frac:
        img = Image.fromarray(arr)
    return img, frac


def erase_tile(img, keep_rgb: bool = True) -> tuple[object, float]:
    """Make every ocean-fill pixel of *img* fully transparent.

    The other thing you can do with the sea once you can find it: instead
    of picking a colour for it, punch it out and let whatever is
    underneath show through.  That is how the ``base-art`` pass gets
    Blizzard's own hand-painted ocean back.

    Only the alpha is cleared.  The sea's original colour is left sitting
    in the RGB channels underneath, where alpha blending will never show
    it directly, because it is the better neighbour for the LANCZOS
    downscale to the region's stitch resolution, which interpolates
    colour and alpha independently.  A coast pixel ends up
    part-transparent either way; the question is only what colour it
    carries.  Zeroing the RGB makes that colour part-black, and blending
    part-black at partial alpha is the classic dark halo.  Leaving the
    real sea colour there means the fringe blends land into sea, which is
    what it is.

    This used to carry a second justification — that the addon could show
    the raw stitch by drawing the same tile with
    ``SetBlendMode("DISABLE")``, which would ignore the alpha channel and
    put the erased pixels back on screen.  The files are indeed bit-exact
    to a raw stitch, but this client honours alpha whatever the blend
    mode, so that never worked in game.  The raw look is a genuinely
    separate dump now (``--original``), and this function's only remaining
    claim is the downscale one above.

    Pass ``keep_rgb=False`` for the old zeroing behaviour.

    Unconditional, same as :func:`unify_tile`, and superseded the same way
    by :func:`reachable_sea_pixels` for the region-wide erase pass.
    """
    import numpy as np
    from PIL import Image

    arr = np.array(img)
    mask = ocean_mask(arr[:, :, :3])
    frac = float(mask.mean())
    apply_erase(arr, mask, keep_rgb)
    if frac:
        img = Image.fromarray(arr)
    return img, frac


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


# ---------------------------------------------------------------------------
# Pixel-connectivity gate for the colour test
# ---------------------------------------------------------------------------

def reachable_sea_pixels(mask, seed_mask):
    """Return the pixels of *mask* whose 4-connected component touches *seed_mask*.

    Both are ``HxW`` bool arrays over the same region-wide canvas: *mask*
    is every pixel that matched the ocean palette (however it got there),
    *seed_mask* marks the pixels that sit inside a cell read with high
    confidence as open water (:data:`OCEAN_TILE_FRACTION` or more of it —
    see :mod:`hfwm.pipeline.zone`, which paints whole ``tile_px``-sized blocks of
    it in before calling this).

    :func:`scipy.ndimage.label` splits *mask* into its 4-connected
    components (the default structuring element in 2D). A component is
    kept in full, exactly as matched, if any one of its pixels is also in
    *seed_mask*; otherwise every pixel in it is dropped, however large the
    component is. Real coastline is always one connected body reaching
    every shore it touches, so a genuine stretch of sea and the confident
    tile it borders end up in the same component and the whole thing
    survives intact. A false positive — Blackrock Mountain's shading, a
    lake, or (the case this was rewritten for) Stormwind Keep's stone
    sitting next to a real canal — is a component of its own with no seed
    pixel in it, so it is dropped whole, without eating into the
    legitimate water it happens to touch or sit near: the component
    boundary *is* the colour boundary, pixel for pixel, not the tile it
    happened to fall in.
    """
    import numpy as np
    from scipy import ndimage

    labels, num = ndimage.label(mask)
    if num == 0:
        return mask  # all False; nothing matched at all.

    seed_labels = np.unique(labels[seed_mask & mask])
    seed_labels = seed_labels[seed_labels != 0]
    if seed_labels.size == 0:
        return np.zeros_like(mask)

    keep = np.zeros(num + 1, dtype=bool)
    keep[seed_labels] = True
    return keep[labels]
