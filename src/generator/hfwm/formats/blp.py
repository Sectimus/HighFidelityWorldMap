"""BLP2 uncompressed BGRA encoding."""

from __future__ import annotations

import struct

BLP2_HEADER_SIZE = 148
BLP2_PALETTE_SIZE = 1024
BLP2_ENCODING_UNCOMPRESSED_BGRA = 3
NUM_MIP_LEVELS = 1


def _generate_mips(img):
    """Generate a single-level mipmap chain from a PIL Image in BGRA order."""
    from PIL import Image as _Img

    mips = []
    current = img
    for _ in range(NUM_MIP_LEVELS):
        w, h = current.size
        if w < 1 or h < 1:
            break
        mips.append(current.tobytes("raw", "BGRA"))
        if w == 1 and h == 1:
            break
        # Premultiplied, so an erased sea contributes no colour to a mip;
        # the colour bleed that makes the coast safe runs at encode time.
        current = current.resize(
            (max(w // 2, 1), max(h // 2, 1)), _Img.BOX)
    return mips


def encode_blp2_bgra(img) -> bytes:
    """Encode a PIL RGBA Image as an uncompressed BGRA BLP2 file."""
    width, height = img.size
    mips = _generate_mips(img)

    data_start = BLP2_HEADER_SIZE + BLP2_PALETTE_SIZE
    offsets = [0] * 16
    sizes = [0] * 16
    cursor = data_start
    for i, mip_data in enumerate(mips):
        offsets[i] = cursor
        sizes[i] = len(mip_data)
        cursor += len(mip_data)

    buf = bytearray()
    buf += b"BLP2"
    buf += struct.pack("<I", 1)                              # version
    buf += struct.pack("B", BLP2_ENCODING_UNCOMPRESSED_BGRA) # encoding
    buf += struct.pack("B", 8)                               # alpha depth
    buf += struct.pack("B", 8)                               # alpha encoding
    buf += struct.pack("B", 1)                               # has mips
    buf += struct.pack("<II", width, height)
    buf += struct.pack("<16I", *offsets)
    buf += struct.pack("<16I", *sizes)
    buf += b"\x00" * BLP2_PALETTE_SIZE
    for mip_data in mips:
        buf += mip_data
    return bytes(buf)
