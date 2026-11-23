"""WMO root-file and ADT placement parsing, and the height maths built on it.

Pure functions over bytes — nothing here touches the network or the disk,
so everything is testable against a captured file.

  * ``MOGI`` (one record per group: local bounding box + name offset) and
    ``MOHD``/``MOGN`` out of a WMO root file;
  * ``MODF`` (where the world places a WMO) out of a split-format
    ``_obj0.adt``.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass


@dataclass
class WmoGroup:
    index: int
    flags: int
    bbox: tuple[float, float, float, float, float, float]  # x1,y1,z1,x2,y2,z2
    name: str
    # A plain FDID for a group whose minimap art is one tile; a
    # {(row, col): fdid} map for one big enough to need several (see
    # fetch_stitched_tile); None for an untiled group (no minimap art at
    # all, e.g. an antiportal/entrance shaft).
    tile_fdid: "int | dict[tuple[int, int], int] | None"


def _iter_chunks(data: bytes):
    pos = 0
    while pos < len(data) - 8:
        magic = data[pos:pos + 4][::-1].decode("ascii", errors="replace")
        size = struct.unpack_from("<I", data, pos + 4)[0]
        yield magic, data[pos + 8:pos + 8 + size]
        pos += 8 + size


def parse_wmo_groups(wmo_root_bytes: bytes,
                      tile_fdids: dict[int, int]) -> list[WmoGroup]:
    """Parse MOHD/MOGN/MOGI out of a WMO root file's raw bytes."""
    chunks = dict(_iter_chunks(wmo_root_bytes))
    mohd = chunks["MOHD"]
    (n_groups,) = struct.unpack_from("<I", mohd, 4)
    mogn = chunks.get("MOGN", b"")

    def name_at(offset: int) -> str:
        if offset < 0:
            return ""
        end = mogn.find(b"\x00", offset)
        return mogn[offset:end].decode("ascii", errors="replace")

    mogi = chunks["MOGI"]
    rec_size = 32
    n = len(mogi) // rec_size
    assert n == n_groups, f"MOGI record count {n} != MOHD nGroups {n_groups}"

    groups = []
    for i in range(n):
        flags, x1, y1, z1, x2, y2, z2, name_off = struct.unpack_from(
            "<I6fi", mogi, i * rec_size)
        groups.append(WmoGroup(
            index=i, flags=flags, bbox=(x1, y1, z1, x2, y2, z2),
            name=name_at(name_off), tile_fdid=tile_fdids.get(i),
        ))
    return groups


def parse_wmo_id(wmo_root_bytes: bytes) -> int:
    """The ``wmoID`` field of MOHD: the key WMOAreaTable rows use."""
    mohd = dict(_iter_chunks(wmo_root_bytes))["MOHD"]
    return struct.unpack_from("<I", mohd, 32)[0]


@dataclass
class WmoPlacement:
    unique_id: int
    position: tuple[float, float, float]
    rotation: tuple[float, float, float]  # degrees: (pitch, yaw, roll)
    name_set: int


def iter_modf_placements(obj0_adt_bytes: bytes):
    """Yield ``(wmo_fdid, WmoPlacement)`` for every direct-FileDataID MODF
    record in a split-format ``_obj0.adt``.

    ``SMMapObjDef`` (wowdev.wiki/ADT/v18#MODF_chunk) is 64 bytes: nameId,
    uniqueId, C3Vector position, C3Vector rotation, CAaBox extents,
    flags, doodadSet, nameSet, scale. This build's obj0 ADTs carry no
    MWMO/MWID chunk at all (confirmed by scanning Fargodeep's own top-level
    chunk list), which only makes sense if ``modf_entry_is_filedata_id``
    (flag 0x8) is set on every record and ``nameId`` is already the
    FileDataID — so that's the only mode this parses; a record without
    that flag would need an MWID lookup this function doesn't have and is
    skipped rather than misread.
    """
    pos = 0
    while pos < len(obj0_adt_bytes) - 8:
        magic = obj0_adt_bytes[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", obj0_adt_bytes, pos + 4)[0]
        if magic == b"MODF":
            body = obj0_adt_bytes[pos + 8:pos + 8 + size]
            for i in range(len(body) // 64):
                (name_id, unique_id, px, py, pz, rx, ry, rz,
                 *_rest_bbox, flags, doodad_set, name_set, _scale) = \
                    struct.unpack_from("<II3f3f6fHHHH", body, i * 64)
                if not (flags & 0x8):
                    continue
                yield name_id, WmoPlacement(
                    unique_id=unique_id, position=(px, py, pz),
                    rotation=(rx, ry, rz), name_set=name_set,
                )
        pos += 8 + size


def parse_modf_placements(obj0_adt_bytes: bytes,
                           wmo_fdid: int) -> list[WmoPlacement]:
    """Every MODF record in *obj0_adt_bytes* that places *wmo_fdid*."""
    return [p for fdid, p in iter_modf_placements(obj0_adt_bytes)
            if fdid == wmo_fdid]


def select_placement(
    placements: list[WmoPlacement],
    wmo_fdid: int,
    adt_obj0_fdid: int,
    expected_unique_id: int | None = None,
) -> WmoPlacement:
    """Pick the MODF placement of *wmo_fdid* out of *placements*.

    *expected_unique_id* narrows it to one record when an ADT places the
    same WMO more than once.  Raises ``ValueError`` if nothing matches.
    """
    if expected_unique_id is not None:
        placements = [p for p in placements if p.unique_id == expected_unique_id]
    if not placements:
        raise ValueError(
            f"No MODF placement of WMO {wmo_fdid} found in ADT {adt_obj0_fdid}"
            + (f" with uniqueId {expected_unique_id}" if expected_unique_id else ""))
    return placements[0]


def world_z_range_for_groups(groups_by_index: dict[int, "WmoGroup"],
                              group_indices: list[int],
                              placement: WmoPlacement) -> tuple[float, float]:
    """Real world-space (worldZ) height range spanned by a floor's groups.

    ``CaveTable.lua``'s ``Contains()`` can't tell Fargodeep's two floors
    apart from X/Y alone over most of the mine — the DB2 rows behind
    ``CaveData.lua``'s ``bounds`` carry no usable Z at all (every interior
    row reads -10000/1000000), and the two floors' real footprints overlap
    almost entirely in a vertical shaft. This WMO's own group geometry
    (already fetched for the art itself) has the real Z data that's
    missing, so it's reused here rather than guessed.

    Converting a group's *local* bbox Z into *world* Z needs the
    placement's own height offset — and that offset is the MODF record's
    raw **y** field, not its z field, per wowdev.wiki/ADT/v18's coordinate
    table: the WDT/ADT (Terrain) axes are `Forward*x + Left*y + Up*z`-style
    Vector3s built from the *placement* row's fields as
    ``Left*x' + Up*y + Forward*z'`` (``x' = 32*TILESIZE - x``,
    ``z' = 32*TILESIZE - z``) — i.e. the raw ``y`` field is Up (height)
    unmodified, while the raw ``x``/``z`` fields are the two *horizontal*
    terrain axes, each needing the ``32*TILESIZE - value`` correction.

    This isn't a guess: it's cross-checked against data this project
    already trusts. Applying that same transform to Fargodeep's own MODF
    position — x'=17066.67-16873.15=193.52, z'=17066.67-26900.29=-9833.62
    (TILESIZE=533.333) — lands *inside* ``CaveData.lua``'s existing
    ``bounds = {-9880, -9700, 34.25, 289.25}`` for this exact place, a
    rectangle that was itself independently confirmed correct from two
    live ``/hfwm debug`` captures (see ``CaveTable.lua``'s ``Contains()``
    comment). Both raw x and raw z land in-range; the raw y field is what's
    left over for height, matching the "Up" row of the same table.

    Yaw (rotation about Up) never changes height, so no rotation math is
    needed here — just the additive offset.

    Returns ``(worldZMin, worldZMax)`` across the given groups.
    """
    local_zs = []
    for i in group_indices:
        g = groups_by_index[i]
        local_zs.append(g.bbox[2])
        local_zs.append(g.bbox[5])
    height_offset = placement.position[1]
    return (min(local_zs) + height_offset, max(local_zs) + height_offset)
