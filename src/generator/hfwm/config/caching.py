"""Cache lifetimes, in days."""

from __future__ import annotations

MINIMAP_DB_CACHE_TTL_DAYS = 30
DB2_CACHE_TTL_DAYS = 30

# The donor tables track retail, which patches far more often than Forever
# does, but nothing the interior pass reads out of them (floor
# order, area names, tile FDIDs for vanilla content) has changed in
# years.  A long TTL keeps a ~13 MB UiMapArtTile download off every run;
# --refresh-caves forces it when that assumption needs testing.
DONOR_DB2_CACHE_TTL_DAYS = 30
INTERIOR_PRESENCE_CACHE_TTL_DAYS = 30
