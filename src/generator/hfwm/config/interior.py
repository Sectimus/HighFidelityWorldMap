"""Interior (cave / dungeon) map table — see hfwm/gamedata/microdungeon.py.

This build ships Blizzard's interior map art (Interface\\WorldMap\\
MicroDungeon\\... and the instance art beside it) but its ``UiMap`` table
lists outdoor zones only: 60 rows, 1 World + 4 Continent + 55 Zone, and
not a single Dungeon or Micro.  So ``C_Map.GetBestMapForUnit`` can never
name a cave, ``C_Map.GetMapArtLayers`` can never describe one, and the
art sits in the client unreachable from Lua.

The rows that would point at it do exist — on retail, where ``UiMap``
carries 257 Micro and 897 Dungeon entries.  The interior pass borrows the
*plumbing* from retail (which floors a place has, which tiles draw
them, which area the player has to be standing in) while taking the
*art* from the pinned build, then bakes the result into CaveData.lua so
the addon can drive its own cave window with no C_Map interior support
at all.

Every borrowed row is validated against the pinned build before it is
emitted: the tile FileDataIDs must resolve on this build, the
assignment's MapID must exist in this build's ``Map``, and the names
must exist in this build's ``AreaTable``.  Anything retail has that
this build does not is dropped rather than guessed at.
"""

from __future__ import annotations

# First non-Blizzard FileDataID hfwm/caves hands out for baked cave/mine
# art (see hfwm/caves/mines.py's registry and the hfwm-add-cave skill's
# "allocate synthetic FDIDs" step). Real Blizzard FDIDs on this build top
# out in the low millions, so this block is chosen well clear of any real
# range.
#
# generate_cave_data() and generate_fdid_map() both read this to find and
# preserve hand-added cave-satellite-v2 data across a regeneration: the
# DB2-driven passes that write CaveData.lua and FDIDMap.lua know nothing
# about caves/mines above the generic fallback, so without this guard a
# plain `python3 generateHFWM.py` silently reverts every hand-upgraded
# mine back to its generic floors-only entry and drops its FDIDMap.lua
# rows entirely -- exactly what happened to Fargodeep Mine and Echo Ridge
# Mine once already (both mines' cave windows rendered solid green in
# game until this was found and reverse-engineered from git history).
SYNTHETIC_FDID_BASE = 900000000

# How many art-presence probes to run at once.  One small HTTP GET per
# candidate interior against the pinned CASC endpoint; 16 keeps the whole
# sweep under a minute without hammering wago.tools.
INTERIOR_PROBE_WORKERS = 16

# AreaTable rows of the caves, mines and dens that discover_indoors finds as
# plain WMO placements (hfwm/caves/indoors.py) rather than as hand-registered
# MINES. An indoor whose WMO is assigned one of these areas by WMOAreaTable is
# emitted with ``cave = true`` and opens the cave window without the "Other
# indoors" option. Taken from the Forever cave list (warcraftmaps.com cave
# section) by area name; the unnamed "Cave near ..." entries have no area of
# their own and are not covered. Keyed by area ID, with the list's name.
CAVE_AREA_IDS = {
    803: "Amberstill Ranch",
    736: "Ban'ethil Hollow",
    231: "Beren's Peril",
    455: "Blackwood Den",
    498: "Bloodfen Burrow",
    1887: "Bogen's Ledge",
    600: "Bolgan's Hole",
    381: "Boulder Lode Mine",
    316: "Boulderfist Hall",
    3157: "Boulderslide Cavern",
    358: "Brambleblade Ravine",
    801: "Chill Breeze Valley",
    282: "Crushridge Hold",
    310: "Crystalvein Mine",
    499: "Darkmist Cavern",
    2256: "Darkwhisper Gorge",
    1056: "Darrow Hill",
    213: "Deep Elem Mine",
    436: "Demon Fall Ridge",
    1439: "Dreadmaul Post",
    249: "Dreadmaul Rock",
    2138: "Dreadmist Den",
    318: "Drywhisker Gorge",
    2248: "Dun Mandarr",
    983: "Dunemaul Compound",
    347: "Dustbelch Grotto",
    2158: "Emberstrife's Den",
    1105: "Feral Scar Vale",
    537: "Fire Plume Ridge",
    1442: "Firewatch Ridge",
    251: "Flame Crest",
    542: "Fungal Rock",
    1000: "Galardell Valley",
    1457: "Garrison Armory",
    2937: "Grosh'gok Compound",
    1683: "Growless Cave",
    190: "Hearthglen",
    2247: "Ice Thistle Hills",
    211: "Iceflow Lake",
    1768: "Irontree Cavern",
    354: "Jintha'Alor",
    259: "Lake Al'Ameth",
    2539: "Malaka'jin",
    116: "Misty Valley",
    143: "Mo'grosh Stronghold",
    3139: "Moon Horror Den",
    105: "Mosh'Ogg Ogre Mound",
    2250: "Owl Wing Thicket",
    1115: "Rage Scar Hold",
    1017: "Raptor Ridge",
    998: "Render's Rock",
    997: "Render's Valley",
    98: "Rethban Caverns",
    487: "Roguefeather Den",
    2161: "Roland's Doom",
    3140: "Scalebeard's Cave",
    1440: "Serpent's Coil",
    1770: "Shadow Hold",
    3117: "Shalzaru's Lair",
    802: "Shimmer Ridge",
    1771: "Shrine of the Deceiver",
    149: "Silver Stream Mine",
    351: "Skulk Rock",
    2419: "Slither Rock",
    431: "Splintertree Post",
    1557: "Splithoof Hold",
    1817: "Stagalbog Cave",
    2253: "Starfall Village",
    923: "Stonesplinter Valley",
    246: "The Cauldron",
    364: "The Den",
    509: "The Den of Flame",
    432: "The Dor'Danil Barrow Den",
    136: "The Grizzled Den",
    982: "The Noxious Lair",
    479: "The Rustmaul Dig Site",
    226: "The Skittering Dark",
    1443: "The Slag Pit",
    106: "The Stockpile",
    468: "The Talon Den",
    2561: "The Vice",
    488: "The Weathered Nook",
    198: "The Weeping Cave",
    1021: "Thelgen Rock",
    1769: "Timbermaw Hold",
    93: "Vul'Gol Ogre Mound",
    118: "Whelgar's Excavation Site",
    2160: "Windshear Mine",
    317: "Witherbark Village",
    2520: "Woodpaw Den",
}
