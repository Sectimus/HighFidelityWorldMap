"""Registry of the micro-dungeons whose indoor minimap art is baked.

Data only: the raw FileDataIDs that identify each mine's placement in the
world (which WMO, which ADT, which minimap tiles) and the synthetic
FileDataIDs its baked art is handed.  None of it can be derived from a
table this project already fetches, which is why it is written down here
once, by hand, with the working that produced it.

Adding a mine means filling in one more :class:`MineSpec` and listing it in
:data:`MINES` — no baking code changes (see :mod:`hfwm.caves.bake`).  See
``ECHO_RIDGE`` for a worked example of finding each value.
"""

from __future__ import annotations

from dataclasses import dataclass

# Synthetic FileDataIDs for the bundled composite floor art. Chosen well
# outside any real Blizzard FDID range (current live FDIDs top out well
# under 9 digits) so they can never collide with a genuine one, and grouped
# under one block (900000000+) so a future dungeon's synthetic IDs are easy
# to tell apart from this one's.
FDID_FARGODEEP_UPPER = 900000001
FDID_FARGODEEP_LOWER = 900000002

# Per-piece synthetic FDIDs (Phase 2: continuous per-WMO-group fading rather
# than a 2-floor crossfade). Base chosen with a gap after the two floor IDs
# above so the ranges are visually distinct in FDIDMap.lua; one ID is
# consumed per tiled WMO group, in ascending group-index order, and
# Fargodeep has 21 tiled groups (see FARGODEEP_TILE_FDIDS below) so this
# range only needs to reserve 900000010-900000030 — comfortably short of
# colliding with FDID_FARGODEEP_UPPER/LOWER's block or a next dungeon's.
FDID_FARGODEEP_PIECE_BASE = 900000010


# Fargodeep Mine's actual root WMO. Discovered by checking WMOAreaTable for
# AreaTableID 57 (Fargodeep Mine's own area, already baked into CaveData.lua
# by hfwm/gamedata/microdungeon.py): WMOID=996, NameSetID=3. WMOID 996 does not belong
# to the base md_goldmine.wmo (that one's WMOID is 84, and reverse-engineering
# it first was a red herring reused by four *other* mines) — it belongs to
# the "varianta" model, md_goldmine_varianta.wmo.
FARGODEEP_WMO_FDID = 110773  # world/wmo/dungeon/md_goldmine/md_goldmine_varianta.wmo

# Fargodeep's WMO *instance* — how the world actually places that root file
# into Dun Morogh, needed only for the world-alignment rotation (see
# WORLD_YAW_FOR_CANVAS_ROTATION below). Found the same way the WMO/tile
# FDIDs above were: no DB2 table carries this, so it comes from the actual
# ADT that covers Fargodeep Mine's own world-space bounds (CaveData.lua's
# existing ``bounds = { -9860, -9700, 41.75, 281.75 }``, run through
# hfwm/geometry/coordinates.py's world_to_tile on both axes -> ADT tile (31, 50) on
# Map 0 "Azeroth" -> looked up in the wowdev/wow-listfile release CSV as
# ``world/maps/azeroth/azeroth_31_50_obj0.adt``, FileDataID 777838; the
# root ``..._31_50.adt`` (777837) carries no MWMO/MODF/MDDF at all — they
# live entirely in ``_obj0`` on this build, and MODF's ``nameId`` there is
# already a raw FileDataID (flags & 0x8, no MWID indirection) since neither
# an MWID nor MWMO chunk exists to index into.
FARGODEEP_ADT_OBJ0_FDID = 777838  # world/maps/azeroth/azeroth_31_50_obj0.adt

# The specific MODF record for Fargodeep, for a same-file sanity check
# rather than blind trust in "the one entry whose nameId matches": its
# nameSet (3) matches the WMOAreaTable NameSetID already used elsewhere in
# this project to identify Fargodeep's WMO (see FARGODEEP_WMO_FDID above),
# so both independent lookups (AreaTable's WMOAreaTable row, and this
# ADT's own MODF entry) agree on the same placement.
FARGODEEP_MODF_UNIQUE_ID = 210351
FARGODEEP_MODF_NAME_SET = 3

# group index -> minimap tile FDID, resolved via the community listfile
# against world/minimaps/wmo/dungeon/md_goldmine_varianta/md_goldmine_varianta_<NNN>_00_00.blp.
# Group 0 has no listfile entry at all (it is the small unnamed antiportal/
# entrance-shaft group, flags 0x8 rather than the 0x2000 every other group
# here has) and is skipped everywhere below.
FARGODEEP_TILE_FDIDS: dict[int, int] = {
    1: 214612, 2: 214613, 3: 214614, 4: 214615, 5: 214616, 6: 214617,
    7: 214618, 8: 214619, 9: 214620, 10: 214621, 11: 214622, 12: 214623,
    13: 214624, 14: 214625, 15: 214626, 16: 214627, 17: 214628, 18: 214629,
    19: 214630, 20: 214631, 21: 214632,
}


@dataclass
class MineSpec:
    """Everything ``generate_mine_floors``/``generate_mine_pieces`` need to
    bake one micro-dungeon's satellite-view art.

    This is the parameterisation of what used to be five Fargodeep-only
    module globals (``FARGODEEP_WMO_FDID`` and friends, still above —
    ``FARGODEEP`` below just wraps them). Adding a second mine means
    filling in one more of these, not writing new baking code.
    """
    key: str                     # WorldMap/<key>/ output folder, e.g. "FargodeepMine"
    wmo_fdid: int | None         # root WMO file (world/wmo/dungeon/.../x.wmo)
    # WMO group index -> its minimap tile FDID, or -> a {(row, col): fdid}
    # map for a group whose room needs more than one sub-tile stitched
    # together (see fetch_stitched_tile).
    tile_fdids: "dict[int, int | dict[tuple[int, int], int]]"
    adt_obj0_fdid: int | None    # the _obj0.adt that places wmo_fdid in the world
    modf_unique_id: int | None   # MODF uniqueId, in case more than one MODF
                                  # record in that ADT places this same wmo_fdid
    modf_name_set: int | None    # cross-check against WMOAreaTable's NameSetID
    floor_fdid_base: int         # synthetic FDID(s) for the whole-floor composite(s)
    piece_fdid_base: int         # synthetic FDID base for the per-room pieces
    single_floor: bool = False   # True: one floor, no crossfade/sharedCanvas


# Fargodeep Mine — fully populated, in production (see CaveData.lua's
# "Fargodeep Mine" entry). Wraps the constants above rather than
# retyping them, so there is exactly one place each number lives.
FARGODEEP = MineSpec(
    key="FargodeepMine",
    wmo_fdid=FARGODEEP_WMO_FDID,
    tile_fdids=FARGODEEP_TILE_FDIDS,
    adt_obj0_fdid=FARGODEEP_ADT_OBJ0_FDID,
    modf_unique_id=FARGODEEP_MODF_UNIQUE_ID,
    modf_name_set=FARGODEEP_MODF_NAME_SET,
    floor_fdid_base=FDID_FARGODEEP_UPPER,  # consumes this id and the next (lower)
    piece_fdid_base=FDID_FARGODEEP_PIECE_BASE,
    single_floor=False,
)

# Echo Ridge Mine — progress so far (from a live WMOAreaTable.csv export,
# build 1.60.1.69913): AreaTableID 34 rows give WMOID=84, NameSetID=3.
# WMOID 84 is the *base* md_goldmine.wmo (not the "_varianta" model
# Fargodeep uses, WMOID 996 -- see FARGODEEP_WMO_FDID's comment) -- the
# same base model already noted there as being reused by several other
# mines. NameSetID 3 matches Fargodeep's own placement, consistent with
# both being the same WMO family. Still needed: the base model's own
# FileDataID (not 110773 -- that's the varianta model), its per-group
# minimap tile FDIDs, and the ADT placing it (candidate ADT tile (32, 48)
# on Map 0 "Azeroth", from running CaveData.lua's bounds {-8686, -8500,
# -306, -27} through world_to_tile on both axes -- (32, 47) as a fallback
# since the Y span straddles that tile's boundary).
#
# AreaTable 34, uiMapID 426 (CaveData.lua already has a
# generic single-floor entry for it, baked by hfwm/gamedata/microdungeon.py from
# this build's own real MicroDungeon world-map art). It has only one
# floor, so single_floor=True: there is no crossfade/sharedCanvas question
# for it, only the per-room `pieces` treatment Fargodeep's Phase 2 added.
#
# The five fields below are None/empty because — unlike everything else in
# this module — they cannot be pulled from any table this project already
# fetches. They have to be looked up once, by hand, exactly the way
# Fargodeep's were (see FARGODEEP_WMO_FDID's comment above for the worked
# example); each step below is that same recipe applied to this mine:
#
#   1. wmo_fdid       - wago.tools -> DB2 -> WMOAreaTable, filtered to
#                        AreaTableID 34. Note the WMOID/NameSetID columns,
#                        then resolve that WMOID to an actual root .wmo
#                        FileDataID via wago.tools' file browser or the
#                        wow-listfile (github.com/wowdev/wow-listfile) —
#                        Fargodeep's WMOID (996) turned out to be
#                        md_goldmine_varianta.wmo, FDID 110773; expect a
#                        similarly-named dungeon wmo here, not necessarily
#                        the same file or even the same base model.
#   2. adt_obj0_fdid  - CaveData.lua's existing bounds for this place
#                        ({-8686, -8500, -306, -27}) run through
#                        hfwm/geometry/coordinates.py's world_to_tile on both axes
#                        to get the covering ADT's column/row, then the
#                        matching world/maps/<continent>/<continent>_
#                        <col>_<row>_obj0.adt resolved to a FileDataID
#                        the same way FARGODEEP_ADT_OBJ0_FDID was.
#   3. modf_unique_id
#   4. modf_name_set  - fetch that _obj0.adt and run parse_modf_placements()
#                        (hfwm/caves/wmo.py) against wmo_fdid from step 1 to find
#                        the matching record; its uniqueId and nameSet are
#                        these two fields. nameSet should match
#                        WMOAreaTable's NameSetID from step 1 — if it
#                        doesn't, it's the wrong placement.
#   5. tile_fdids     - once wmo_fdid's own path is known, call
#                        fetch_wmo_root + parse_wmo_groups() (hfwm/caves) to
#                        enumerate its MOGI groups, then resolve each
#                        tiled group's minimap tile FDID the same way
#                        FARGODEEP_TILE_FDIDS was: world/minimaps/wmo/
#                        dungeon/<wmoName>/<wmoName>_<group:03d>_00_00.blp
#                        against the listfile.
#
# None of this is guessable from inside this repo, and none of it should
# be trusted un-checked once filled in: Fargodeep's rotation math
# (world_align_rotation_degrees) is cross-validated against Fargodeep's
# own live /hfwm debug captures specifically, not against this mine's —
# so treat a first attempt here as provisional until the same in-game
# check confirms the cave's orientation and player-pin position look
# right. Once the five fields above are filled in, run
# ``python -m hfwm.caves echoridge`` and paste its output into
# CaveData.lua / FDIDMap.lua the same way Fargodeep's was.
#
# Update (from a live community-listfile.csv, same build): wmo_fdid and
# tile_fdids resolved cleanly — "world/wmo/dungeon/md_goldmine/md_goldmine
# .wmo" (the bare name, WMOID 84, matching WMOAreaTable) is FDID 110750,
# and its own minimap tiles are the *only* "md_goldmine_NNN_00_00.blp"
# entries with no variant suffix: groups 000-008, FDIDs 214595-214603,
# nine in a row with no gap. That strongly implies 9 tiled groups
# numbered from 0 (unlike Fargodeep's varianta, which skips an untiled
# group 0 and numbers tiles from 1) — but this is only a hypothesis from
# the listfile; the real group count/order still needs confirming
# against the WMO file's own MOHD/MOGI chunks once fetched, same as
# everything parse_wmo_groups() checks for Fargodeep.
#
# Fully resolved (from the actual WMO + both candidate ADTs, fetched from
# cache and parsed with hfwm/caves/wmo.py's own parse_wmo_groups/parse_modf_
# placements): the WMO really does have 10 groups, exactly 9 of them
# (0-8, flags 0x2000) tiled -- matching FDIDs 214595-214603 one-for-one,
# confirming the tile_fdids guessed from the listfile above needed no
# changes. Group 9 (flags 0x8, "interior02") is the untiled antiportal/
# entrance group, the same role Fargodeep's untiled group plays.
#
# Both candidate ADTs (778023 and 778028) carry the *same* MODF record
# for this WMO -- uniqueId 71448, pos (17198.39, 91.62, 25712.89), yaw
# 325.0, nameSet 3 (matching WMOAreaTable exactly) -- because the
# placement really does straddle the tile (32,47)/(32,48) seam, as
# guessed from the bounds earlier. Either FDID works identically;
# 778028 is kept as primary. Running this position through the same
# raw-x/z -> world correction Fargodeep's derivation validates
# (placementWorldX = 32*TILESIZE - pz, placementWorldY = 32*TILESIZE -
# px) lands at (-8646.22, -131.72) -- inside CaveData.lua's existing
# bounds {-8686, -8500, -306, -27} on both axes, the same cross-check
# Fargodeep's own placement was validated with.
ECHO_RIDGE = MineSpec(
    key="EchoRidgeMine",
    wmo_fdid=110750,
    tile_fdids={i: 214595 + i for i in range(9)},
    adt_obj0_fdid=778028,
    modf_unique_id=71448,
    modf_name_set=3,
    floor_fdid_base=900000100,   # first free block after Fargodeep's piece range
    piece_fdid_base=900000200,   # (900000010-900000030) and floor range (...01-02)
    single_floor=True,
)


# --- Batch 3: 13 more micro-dungeons resolved from ADT MODF placement data
# directly (see the 2026-09-28 session) rather than name-guessing --
# WMOAreaTable + community-listfile.csv + each covering ADT's own MODF
# chunk gave every raw ID with no ambiguity. All single_floor=True (no
# retail-floor-count-driven 2-means split attempted); every group used
# below is single-subtile (_00_00 only) -- mines needing multi-subtile
# group art are held back for a later pass.
BANETHILBARROWDEN = MineSpec(
    key='BanethilBarrowDen',
    wmo_fdid=110359,
    tile_fdids={0: 214278, 1: 214279, 2: 214280, 3: 214281, 4: 214282, 5: 214283, 6: 214284, 7: 214285, 8: 214286, 9: 214287, 10: 214288, 11: 214289, 12: 214290, 13: 214291, 14: 214292, 15: 214293, 16: 214294, 17: 214295, 18: 214296, 19: 214297, 20: 214298, 21: 214299, 22: 214300, 23: 214301, 24: 214302, 25: 214303, 27: 214304, 28: 214305, 29: 214306, 30: 214307, 31: 214308, 32: 214309},
    adt_obj0_fdid=783826,
    modf_unique_id=173805,
    modf_name_set=3,
    floor_fdid_base=900000300,
    piece_fdid_base=900000400,
    single_floor=True,
)

COLDRIDGEPASS = MineSpec(
    key='ColdridgePass',
    wmo_fdid=110345,
    tile_fdids={0: 214267, 1: 214268, 2: 214269, 3: 214270, 4: 214271, 5: 214272, 6: 214273, 7: 214274, 8: 214275, 10: 214276, 12: 214277},
    adt_obj0_fdid=777803,
    modf_unique_id=48527,
    modf_name_set=1,
    floor_fdid_base=900000500,
    piece_fdid_base=900000600,
    single_floor=True,
)

DUSTWINDCAVE = MineSpec(
    key='DustwindCave',
    wmo_fdid=111304,
    tile_fdids={0: 215223, 1: 215224, 3: 215225, 4: 215226, 5: 215227, 6: 215228, 7: 215229},
    adt_obj0_fdid=786646,
    modf_unique_id=172378,
    modf_name_set=2,
    floor_fdid_base=900000700,
    piece_fdid_base=900000800,
    single_floor=True,
)

GOLDCOASTQUARRY = MineSpec(
    key='GoldCoastQuarry',
    wmo_fdid=111137,
    tile_fdids={0: 214998, 1: 214999, 3: 215000, 4: 215001, 5: 215002, 6: 215003, 7: 215004},
    adt_obj0_fdid=777243,
    modf_unique_id=170486,
    modf_name_set=5,
    floor_fdid_base=900000900,
    piece_fdid_base=900001000,
    single_floor=True,
)

JANGOLODEMINE = MineSpec(
    key='JangolodeMine',
    wmo_fdid=110750,
    tile_fdids={0: 214595, 1: 214596, 2: 214597, 3: 214598, 4: 214599, 5: 214600, 6: 214601, 7: 214602, 8: 214603},
    adt_obj0_fdid=777438,
    modf_unique_id=16632,
    modf_name_set=4,
    floor_fdid_base=900001100,
    piece_fdid_base=900001200,
    single_floor=True,
)

JASPERLODEMINE = MineSpec(
    key='JasperlodeMine',
    wmo_fdid=111538,
    tile_fdids={0: 215383, 1: 215384, 2: 215385, 3: 215386, 4: 215387, 5: 215388, 7: 215389, 8: 215390, 9: 215391, 10: 215392, 11: 215393},
    adt_obj0_fdid=778028,
    modf_unique_id=71446,
    modf_name_set=3,
    floor_fdid_base=900001300,
    piece_fdid_base=900001400,
    single_floor=True,
)

LIGHTSHOPECHAPEL = MineSpec(
    key='LightsHopeChapel',
    wmo_fdid=106695,
    tile_fdids={0: 209852},
    adt_obj0_fdid=779648,
    modf_unique_id=200881,
    modf_name_set=0,
    floor_fdid_base=900001500,
    piece_fdid_base=900001600,
    single_floor=True,
)

NIGHTWEBSHOLLOW = MineSpec(
    key='NightWebsHollow',
    wmo_fdid=111551,
    tile_fdids={0: 215394, 1: 215395, 2: 215396, 3: 215397, 4: 215398, 5: 215399, 7: 215401, 8: 215402, 9: 215403, 10: 215404, 11: 408584},
    adt_obj0_fdid=777128,
    modf_unique_id=70052623,
    modf_name_set=2,
    floor_fdid_base=900001700,
    piece_fdid_base=900001800,
    single_floor=True,
)

THEGAPINGCHASM = MineSpec(
    key='TheGapingChasm',
    wmo_fdid=110955,
    tile_fdids={0: 214793, 1: 214794, 2: 214795, 3: 214796, 4: 214797, 5: 214798, 6: 214799, 7: 214800, 8: 214801, 9: 214802, 10: 214803, 11: 214804},
    adt_obj0_fdid=786736,
    modf_unique_id=298596,
    modf_name_set=1,
    floor_fdid_base=900001900,
    piece_fdid_base=900002000,
    single_floor=True,
)

THEGRIZZLEDDEN = MineSpec(
    key='TheGrizzledDen',
    wmo_fdid=110491,
    tile_fdids={0: 214404},
    adt_obj0_fdid=777998,
    modf_unique_id=51584,
    modf_name_set=1,
    floor_fdid_base=900002100,
    piece_fdid_base=900002200,
    single_floor=True,
)

ULDAMANAPPROACH = MineSpec(
    key='UldamanApproach',
    wmo_fdid=109758,
    tile_fdids={0: 213412, 1: 213413, 2: 213414, 3: 213415, 4: 213416, 5: 213417, 6: 213418, 7: 213419, 8: 213420, 10: 213421, 11: 213422, 12: 213423, 13: 213424, 14: 213425, 15: 213426, 16: 213427, 17: 213428, 18: 213429, 19: 213430, 20: 213431, 21: 213432, 22: 213433},
    adt_obj0_fdid=778998,
    modf_unique_id=180253,
    modf_name_set=1,
    floor_fdid_base=900002300,
    piece_fdid_base=900002400,
    single_floor=True,
)

TIRAGARDEKEEP = MineSpec(
    key='TiragardeKeep',
    wmo_fdid=111454,
    tile_fdids={0: 215331, 1: 215332, 2: 215333, 3: 215334, 4: 215335, 5: 215336, 6: 215337, 7: 215338, 8: 215339, 9: 215340, 10: 215341, 11: 215342, 13: 215343, 14: 215344, 15: 215345},
    adt_obj0_fdid=786876,
    modf_unique_id=183741,
    modf_name_set=0,
    floor_fdid_base=900002500,
    piece_fdid_base=900002600,
    single_floor=True,
)

THEMASTERSCELLAR = MineSpec(
    key='TheMastersCellar',
    wmo_fdid=114572,
    tile_fdids={1: 217703, 2: 217704, 3: 217705, 4: 217706, 5: 217707, 6: 217708},
    adt_obj0_fdid=778658,
    modf_unique_id=566705,
    modf_name_set=0,
    floor_fdid_base=900002700,
    piece_fdid_base=900002800,
    single_floor=True,
)


# --- Batch 4: 9 more micro-dungeons, this time exercising
# fetch_stitched_tile() -- several groups here need more than one raw
# 256x256 sub-tile (see WMO_SUBTILE_PX). The Noxious Lair uses only its
# 'mini-hive_d' structure; a second, separate 'mini-hive_e' WMO instance
# also sits inside this place's bounds but sharing one place-level
# `projection` between two independently-placed WMO instances isn't
# something CaveData.lua's schema supports yet, so it's left out rather
# than forced in -- see the 2026-09-28 session notes.
FELROCK = MineSpec(
    key='FelRock',
    wmo_fdid=111098,
    tile_fdids={0: {(0, 0): 214942, (0, 1): 214943, (1, 0): 214944, (1, 1): 214945}, 1: {(0, 0): 214946, (0, 1): 214947, (1, 0): 214948, (1, 1): 214949}, 2: {(0, 0): 214950, (0, 1): 214951, (1, 0): 214952, (1, 1): 214953}, 3: {(0, 0): 214954, (0, 1): 214955, (1, 0): 214956, (1, 1): 214957}, 4: {(0, 0): 214958, (0, 1): 214959, (1, 0): 214960, (1, 1): 214961}, 5: {(0, 0): 214962, (0, 1): 214963, (1, 0): 214964, (1, 1): 214965}, 6: {(0, 0): 214966, (0, 1): 214967, (1, 0): 214968, (1, 1): 214969}, 7: {(0, 0): 214970, (0, 1): 214971, (1, 0): 214972, (1, 1): 214973}, 8: 214974, 9: 214975, 10: {(0, 0): 214976, (0, 1): 214977, (1, 0): 214978, (1, 1): 214979}, 11: {(0, 0): 214980, (0, 1): 214981, (1, 0): 214982, (1, 1): 214983}},
    adt_obj0_fdid=784056,
    modf_unique_id=138950,
    modf_name_set=1,
    floor_fdid_base=900002900,
    piece_fdid_base=900003000,
    single_floor=True,
)

FROSTMANEHOLD = MineSpec(
    key='FrostmaneHold',
    wmo_fdid=111044,
    tile_fdids={0: 214872, 1: 214873, 2: {(0, 0): 214874, (0, 1): 214875}, 3: 214876, 4: 214877, 6: 214878},
    adt_obj0_fdid=777598,
    modf_unique_id=349103,
    modf_name_set=1,
    floor_fdid_base=900003100,
    piece_fdid_base=900003200,
    single_floor=True,
)

GOLBOLARQUARRY = MineSpec(
    key='GolBolarQuarry',
    wmo_fdid=111061,
    tile_fdids={0: 214889, 1: 214890, 3: {(0, 0): 214891, (0, 1): 214892, (1, 0): 214893, (1, 1): 214894}},
    adt_obj0_fdid=778398,
    modf_unique_id=350748,
    modf_name_set=1,
    floor_fdid_base=900003300,
    piece_fdid_base=900003400,
    single_floor=True,
)

PALEMANEROCK = MineSpec(
    key='PalemaneRock',
    wmo_fdid=111221,
    tile_fdids={0: 215084, 1: 215085, 3: {(0, 0): 215086, (0, 1): 215087, (1, 0): 215088, (1, 1): 215089}},
    adt_obj0_fdid=784426,
    modf_unique_id=398076,
    modf_name_set=1,
    floor_fdid_base=900003500,
    piece_fdid_base=900003600,
    single_floor=True,
)

SHADOWTHREADCAVE = MineSpec(
    key='ShadowthreadCave',
    wmo_fdid=111099,
    tile_fdids={1: 214934, 2: 214935, 3: 214936, 4: 214937, 5: {(0, 0): 214938, (0, 1): 214939, (1, 0): 214940, (1, 1): 214941}},
    adt_obj0_fdid=784301,
    modf_unique_id=361332,
    modf_name_set=1,
    floor_fdid_base=900003700,
    piece_fdid_base=900003800,
    single_floor=True,
)

THESLITHERINGSCAR = MineSpec(
    key='TheSlitheringScar',
    wmo_fdid=110886,
    tile_fdids={0: 214723, 1: 214724, 2: 214725, 3: 214726, 4: {(0, 0): 214727, (0, 1): 214728, (1, 0): 214729, (1, 1): 214730}, 5: 214731, 6: 214732},
    adt_obj0_fdid=785181,
    modf_unique_id=310138,
    modf_name_set=1,
    floor_fdid_base=900003900,
    piece_fdid_base=900004000,
    single_floor=True,
)

THEVENTURECOMINE = MineSpec(
    key='TheVentureCoMine',
    wmo_fdid=110808,
    tile_fdids={1: {(0, 0): 214642, (0, 1): 214643}, 2: 214644, 3: 214645, 5: 214646, 7: {(0, 0): 214647, (0, 1): 214648}, 8: {(0, 0): 214649, (0, 1): 214650, (1, 0): 214651, (1, 1): 214652}, 9: {(0, 0): 214653, (0, 1): 214654, (1, 0): 214655, (1, 1): 214656}},
    adt_obj0_fdid=785121,
    modf_unique_id=170819,
    modf_name_set=1,
    floor_fdid_base=900004100,
    piece_fdid_base=900004200,
    single_floor=True,
)

TWILIGHTSRUN = MineSpec(
    key='TwilightsRun',
    wmo_fdid=111181,
    tile_fdids={0: 215049, 2: {(0, 0): 215050, (1, 0): 215051}},
    adt_obj0_fdid=784696,
    modf_unique_id=604994,
    modf_name_set=2,
    floor_fdid_base=900004300,
    piece_fdid_base=900004400,
    single_floor=True,
)

THENOXIOUSLAIR = MineSpec(
    key='TheNoxiousLair',
    wmo_fdid=110917,
    tile_fdids={1: 214757, 2: 214758, 3: 214759, 4: 214760, 5: 214761, 6: 214762},
    adt_obj0_fdid=785846,
    modf_unique_id=24646413,
    modf_name_set=2,
    floor_fdid_base=900004500,
    piece_fdid_base=900004600,
    single_floor=True,
)


# --- Batch 5: Burning Blade Coven, Skull Rock (both share md_warmcave.wmo,
# FDID 111290 -- two separate MODF placements of the same WMO), and
# Dalaran (md_crypt_d.wmo, FDID 110630). All three were held back after
# batch 4 pending the multi-subtile stitcher, on the theory that groups
# 0-7/10-11 (warmcave) and 6/8/9/13/14 (crypt_d) needed a stitched 2x2
# mosaic like Fel Rock's. A community-listfile.csv scrape *does* list
# "_00_01"/"_01_00"/"_01_01" sub-tile FDIDs for most of those groups --
# but every one of those FDIDs comes back a genuine, build-pinned-and-
# confirmed empty 200 on this build (verified directly: retried through
# wago.tools' ?build=1.60.1.69913-pinned endpoint with strict HTTP-status
# checking, not just the unpinned one that silently serves whichever
# build happens to be freshest). That listfile is a union across this
# WMO's entire patch history; the higher-numbered sub-tile FDIDs were
# added in some later retail patch that baked a higher-resolution mosaic
# for these rooms, and simply don't exist yet in the 1.60.1.69913
# build's own CASC archive. So every one of these groups is single-tile
# here, the same as groups 8/9 (warmcave) and 9/14 (crypt_d) already
# were assumed to be -- no stitching needed after all, and nothing left
# to fetch: every FDID below was already sitting in the local cache from
# the original round-3 fetch (only its *extra*, nonexistent siblings were
# ever missing).
#
# Dalaran's WMO group 7 ("wonkyhall03") is the outlier: it carries a
# different MOGP flag (0x80000008, vs every other group's plain 0x2000)
# and has *no* tile FDID anywhere in the listfile, not even a "_00_00" --
# consistent with it being a non-rendered antiportal/culling group on
# every build, not just this one. It's correctly left out of tile_fdids
# below, the same way md_warmcave's untiled group 12 ("mountaincave05",
# flags 0x200008) is left out of that mine's.
BURNINGBLADECOVEN = MineSpec(
    key='BurningBladeCoven',
    wmo_fdid=111290,
    tile_fdids={0: 215181, 1: 215185, 2: 215189, 3: 215193, 4: 215197, 5: 215201,
                6: 215205, 7: 215209, 8: 215213, 9: 215214, 10: 215215, 11: 215219},
    adt_obj0_fdid=786431,
    modf_unique_id=176000,
    modf_name_set=3,
    floor_fdid_base=900004700,
    piece_fdid_base=900004800,
    single_floor=True,
)

SKULLROCK = MineSpec(
    key='SkullRock',
    wmo_fdid=111290,
    tile_fdids={0: 215181, 1: 215185, 2: 215189, 3: 215193, 4: 215197, 5: 215201,
                6: 215205, 7: 215209, 8: 215213, 9: 215214, 10: 215215, 11: 215219},
    adt_obj0_fdid=786641,
    modf_unique_id=250582,
    modf_name_set=2,
    floor_fdid_base=900004900,
    piece_fdid_base=900005000,
    single_floor=True,
)

DALARAN = MineSpec(
    key='Dalaran',
    wmo_fdid=110630,
    tile_fdids={
        0: 214498, 1: 214499, 2: 214500, 3: 214501, 4: 214502, 5: 214503,
        6: {(0, 0): 214504, (0, 1): 214505, (1, 0): 214506, (1, 1): 214507},
        8: {(0, 0): 214508, (1, 0): 214509},
        9: 214510,
        10: 214511, 11: 214512, 12: 214513,
        13: {(0, 0): 214514, (0, 1): 214515},
        14: 214516,
        15: 214517, 16: 214518, 17: 214519, 18: 214520,
    },
    adt_obj0_fdid=778658,
    modf_unique_id=571057,
    modf_name_set=0,
    floor_fdid_base=900005100,
    piece_fdid_base=900005200,
    single_floor=True,
)


# Registry the command line (``python -m hfwm.caves <key>``) dispatches on.
MINES: dict[str, MineSpec] = {
    "fargodeep": FARGODEEP,
    "echoridge": ECHO_RIDGE,
    "banethil": BANETHILBARROWDEN,
    "coldridgepass": COLDRIDGEPASS,
    "dustwind": DUSTWINDCAVE,
    "goldcoastquarry": GOLDCOASTQUARRY,
    "jangolode": JANGOLODEMINE,
    "jasperlode": JASPERLODEMINE,
    "lightshope": LIGHTSHOPECHAPEL,
    "nightwebshollow": NIGHTWEBSHOLLOW,
    "gapingchasm": THEGAPINGCHASM,
    "grizzledden": THEGRIZZLEDDEN,
    "uldamanapproach": ULDAMANAPPROACH,
    "tiragardekeep": TIRAGARDEKEEP,
    "masterscellar": THEMASTERSCELLAR,
    "felrock": FELROCK,
    "frostmanehold": FROSTMANEHOLD,
    "golbolarquarry": GOLBOLARQUARRY,
    "palemanerock": PALEMANEROCK,
    "shadowthreadcave": SHADOWTHREADCAVE,
    "slitheringscar": THESLITHERINGSCAR,
    "venturecomine": THEVENTURECOMINE,
    "twilightsrun": TWILIGHTSRUN,
    "noxiouslair": THENOXIOUSLAIR,
    "burningbladecoven": BURNINGBLADECOVEN,
    "skullrock": SKULLROCK,
    "dalaran": DALARAN,
}
