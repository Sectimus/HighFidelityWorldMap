"""The game build this generator is pinned to."""

from __future__ import annotations

# Read from the installed Forever client's .flavor.info + .build.info.
# Bump this (and delete the cache dir) when Forever patches.
GAME_PRODUCT = "wowf"
GAME_BUILD = "1.60.1.70888"

USER_AGENT = f"HighFidelityWorldMap/1.0 (build {GAME_BUILD})"
