"""Configuration for the HFWM-Forever pipeline.

Nothing in this package does any work: it is data only, split by the
thing that would make a value change, so a build bump touches
:mod:`~hfwm.config.build` and a new art style touches
:mod:`~hfwm.config.tiles`, and neither has to know about the other.

build       Pinned game product/build and the HTTP identity derived from it.
paths       Where the generator reads from and writes to.
endpoints   wago.tools URLs and the DB2 tables each pass consumes.
caching     Cache lifetimes.
tiles       Tile/art-layer geometry and ``UiMapType`` values.
ocean       Sea colours and thresholds.
interior    Interior (cave / dungeon) pass constants.

This is a fork of the retail HFWM pipeline pinned to the "World of Warcraft
Forever" beta client.  Differences from the retail configuration:

* Every DB2 request is pinned to :data:`~hfwm.config.build.GAME_BUILD`.
  ``WorldMapArea`` does not exist on this build (it 404s) and is not used
  at all — zone bounds come from ``UiMapAssignment.Region_*``.
* All caches live under a build-stamped directory, and every CASC file is
  fetched with ``?build=`` (``/api/casc/{fdid}`` alone serves whichever
  product was ingested last), so no other product's data reaches them.
* No continent overlays / zone presets / terrain-phase overrides: those
  are Cataclysm-and-later retail concerns (Vashj'ir, Silithus phasing, the
  150-tile continent art style).  Forever's world is vanilla Azeroth
  rendered with the modern UiMap art framework, and every art style it
  uses is either 1002x668 (4x3) or 512x512 (1x1).
"""
