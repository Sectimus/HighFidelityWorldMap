"""hfwm — High Fidelity World Map pipeline toolkit.

A fork of the retail HFWM pipeline pinned to the "World of Warcraft
Forever" client.  The community listfile, AI inpainting, continent
overlays and zone presets are all gone; tile identity comes straight
from the build-pinned ``UiMapArtTile`` export instead.

Layout
------
Dependencies point one way, down this list: a package may import from any
package above it, never below.

config      Pinned build, paths, endpoints, geometry — data only.
infra       HTTP, the TTL JSON cache, formatting.
formats     BLP2 encoding, WDT parsing.
geometry    World/tile/pixel coordinate maths and output tile naming.
imaging     Resampling, sea masking, the art-pass registry.
gamedata    Build-pinned game data: the zone DB (DB2 join chain + WDT
            grids) and the interior map table.
pipeline    Zone production: stitch / crop / fit / encode, tile downloads,
            and the worker-pool runner.
caves       Baking indoor WMO minimap art for micro-dungeons.
lua         Writing the addon's generated Lua: FDIDMap.lua, CaveData.lua.
cli         Argument parsing and the phase sequence.
"""

__version__ = "1.0.0"
