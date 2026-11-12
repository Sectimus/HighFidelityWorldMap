"""Ocean unification (see hfwm/imaging/ocean.py).

The sea arrives in the stitch as several different flat fills, so where
they meet you get hard rectangular seams on tile boundaries.  Measured
over the 1858 cached minimap tiles for this build, these are the fills
and roughly how much of the sampled pixel population each holds:

  (8, 16, 16)    4.1%   open ocean — an ADT with no terrain in it
  (26, 50, 69)   0.3%   coastal water rendered through the water shader
  (2, 55, 70)    0.1%   deeper water over an ADT
  (8, 20, 21)    0.1%   open ocean, second variant
  (29, 53, 72)   0.03%  coastal water, second variant

Inland lakes are deliberately absent: they carry their own tint and are
left alone.
"""

from __future__ import annotations

OCEAN_FILL_COLORS = (
    (8, 16, 16),
    (26, 50, 69),
    (2, 55, 70),
    (8, 20, 21),
    (29, 53, 72),
)

# Per-channel slack when matching the fills above.  The fills are flat and
# exact, so this only needs to absorb the ±6 dither the terrain renderer
# leaves behind; going much wider starts eating dark coastal cliff shadow.
OCEAN_FILL_TOLERANCE = 10

# Terrain-less tiles are open sea whatever colour the build paints them. In
# build 1.60.1.70888 that is near-black (5, 6, 5), (5, 5, 5) and (0, 0, 0), so
# inside those tiles any pixel at or below this per-channel level is sea.
# Tiles with terrain never use this; see hfwm.gamedata.terrain.
OCEAN_DARK_MAX = 20

# The colour everything above is collapsed onto.  This is the coastal
# water fill, chosen because it is what actually abuts the coastline —
# unify onto the near-black open-ocean fill instead and every shore gets
# darker rather than the sea getting consistent.
DEFAULT_OCEAN_COLOR = (26, 50, 69)

# How much of a source tile must read as ocean before empty cells next to
# it are treated as sea.  Open-water tiles are ~100% ocean and coast tiles
# rarely exceed a third, so anything in the middle of this range works.
OCEAN_TILE_FRACTION = 0.5
