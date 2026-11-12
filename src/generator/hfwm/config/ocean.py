"""Ocean handling (see hfwm/gamedata/ocean_water.py and hfwm/imaging/ocean.py)."""

from __future__ import annotations

# A terrain cell counts as open sea when its ocean liquid surface is at least
# this many yards above the highest seabed corner of the cell. Measured on
# build 1.60.1.70888's Eastern Kingdoms, over every Ocean-liquid cell: down to
# ~16 yards the minimap still shows the seabed through the water (mean
# luminance 22+, textured); from 32 it is the flat near-black fill (mean 11);
# from 64, 95% of cells are pure fill and by 128 all of them are. 32 erases
# the fill and leaves the lit coastal shelf alone.
OCEAN_MIN_DEPTH = 32.0

# The colour every sea pixel is collapsed onto by the ``ocean`` pass.  This is
# the coastal water fill, chosen because it is what actually abuts the
# coastline — unify onto the near-black open-ocean fill instead and every
# shore gets darker rather than the sea getting consistent.
DEFAULT_OCEAN_COLOR = (26, 50, 69)

# How much of a source tile must read as ocean before empty cells next to
# it are treated as sea.  Open-water tiles are ~100% ocean and coast tiles
# rarely exceed a third, so anything in the middle of this range works.
OCEAN_TILE_FRACTION = 0.5
