"""WDT MAID chunk parser — extracts per-tile minimap FileDataIDs."""

from __future__ import annotations

import struct

# MAID field indices.
MAID_FIELD_MINIMAP = 7      # minimapTexture — what we want
MAID_FIELD_MAPTEXTURE = 5   # mapTexture (terrain LOD diffuse), NOT "no liquid"
MAID_FIELD_ROOT_ADT = 0      # root ADT FileDataID: the terrain tile itself


def parse_wdt_maid(
    wdt_bytes: bytes,
    field_index: int = MAID_FIELD_MINIMAP,
) -> dict[tuple[int, int], int]:
    """Parse the MAID chunk from a WDT file.

    Returns ``{(row, col): fdid}`` for populated tiles.

    The MAID chunk stores 8 ``uint32`` fields per tile in a 64×64 grid:
      - field 7 = ``minimapTexture`` (satellite terrain with liquid overlay)
      - field 5 = ``mapTexture`` (terrain without liquid overlay)
    """
    pos = 0
    while pos < len(wdt_bytes) - 8:
        magic = wdt_bytes[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", wdt_bytes, pos + 4)[0]
        if magic == b"MAID":
            maid = wdt_bytes[pos + 8:pos + 8 + size]
            entry_size = size // 4096
            if entry_size < 32:
                return {}
            result: dict[tuple[int, int], int] = {}
            for idx in range(4096):
                fields = struct.unpack_from("<8I", maid, idx * entry_size)
                fdid = fields[field_index]
                if fdid:
                    result[(idx // 64, idx % 64)] = fdid
            return result
        pos += 8 + size
    return {}
