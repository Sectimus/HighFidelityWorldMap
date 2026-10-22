"""wago.tools endpoints and the DB2 tables each pass consumes."""

from __future__ import annotations

from .build import GAME_BUILD

WAGO_DB2_FMT = "https://wago.tools/db2/{table}/csv?build={build}"
WAGO_DB2_LATEST_FMT = "https://wago.tools/db2/{table}/csv"
# CASC files are only ever fetched pinned.  ``/api/casc/{fdid}`` on its own
# serves whichever build was ingested most recently (retail, MoP Classic,
# Classic Era ...), so a file that only exists elsewhere answers 200 there
# and would be baked into a table claiming to describe this build.  With
# ``?build=`` it 404s instead, which is what makes the art-presence probe
# in hfwm/gamedata/microdungeon.py mean anything.
WAGO_CASC_PINNED_FMT = (
    "https://wago.tools/api/casc/{fdid}?build=" + GAME_BUILD
)


def db2_url(table: str) -> str:
    """Return the build-pinned CSV export URL for a DB2 *table*."""
    return WAGO_DB2_FMT.format(table=table, build=GAME_BUILD)


def donor_db2_url(table: str) -> str:
    """Return the *unpinned* (latest retail) CSV export URL for *table*.

    Only the interior pass uses this, and only for map plumbing that this
    build's own tables do not carry.  Never use it for art.
    """
    return WAGO_DB2_LATEST_FMT.format(table=table)


# Tables the zone pipeline consumes.
DB2_TABLES = (
    "Map",
    "UiMap",
    "UiMapAssignment",
    "UiMapXMapArt",
    "UiMapArt",
    "UiMapArtStyleLayer",
    "UiMapArtTile",
)

# Tables the interior pass borrows from retail — see config/interior.py and
# hfwm/gamedata/microdungeon.py for why.
DONOR_DB2_TABLES = (
    "UiMap",
    "UiMapAssignment",
    "UiMapXMapArt",
    "UiMapArt",
    "UiMapArtStyleLayer",
    "UiMapArtTile",
    "UiMapGroupMember",
)

# Build-pinned tables the interior pass needs on top of DB2_TABLES.
INTERIOR_BUILD_DB2_TABLES = ("AreaTable",)
