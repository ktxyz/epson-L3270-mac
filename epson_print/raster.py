"""PWG raster page headers + libcups-compatible PackBits compressor."""

from __future__ import annotations

HEADER_SIZE = 1796
COLOR_SPACE_SRGB = 19
COLOR_SPACE_SGRAY = 18

MEDIA = {
    "a4": ("iso_a4_210x297mm", 595, 841),
    "letter": ("na_letter_8.5x11in", 612, 792),
    "legal": ("na_legal_8.5x14in", 612, 1008),
    "a5": ("iso_a5_148x210mm", 420, 595),
    "a6": ("iso_a6_105x148mm", 298, 420),
    "b5": ("iso_b5_176x250mm", 499, 709),
    "4x6": ("na_index-4x6_4x6in", 288, 432),
    "5x7": ("na_5x7_5x7in", 360, 504),
    "8x10": ("na_8x10_8x10in", 576, 720),
}


def geometry(media: str) -> tuple[str, int, int, int, int]:
    key = media.lower()
    if key not in MEDIA:
        raise ValueError(f"unknown media {media!r}")
    name, w_pts, h_pts = MEDIA[key]
    width_px = round(w_pts / 72 * 360)
    height_px = round(h_pts / 72 * 360)
    return name, w_pts, h_pts, width_px, height_px


def _put32(buf: bytearray, offset: int, value: int) -> None:
    buf[offset : offset + 4] = value.to_bytes(4, "big")


def page_header(
    width: int,
    height: int,
    color_space: int,
    media_name: str = "iso_a4_210x297mm",
    media_width: int = 595,
    media_height: int = 841,
) -> bytes:
    if color_space not in (COLOR_SPACE_SRGB, COLOR_SPACE_SGRAY):
        raise ValueError("invalid color space")
    bpp = 24 if color_space == COLOR_SPACE_SRGB else 8
    bpc = 8
    num_colors = 3 if color_space == COLOR_SPACE_SRGB else 1
    bpl = width * (bpp // 8)

    buf = bytearray(HEADER_SIZE)
    buf[0:9] = b"PwgRaster"
    _put32(buf, 276, 360)
    _put32(buf, 280, 360)
    _put32(buf, 284, 0)
    _put32(buf, 288, 0)
    _put32(buf, 292, media_width)
    _put32(buf, 296, media_height)
    _put32(buf, 324, 1)
    _put32(buf, 352, media_width)
    _put32(buf, 356, media_height)
    _put32(buf, 372, width)
    _put32(buf, 376, height)
    _put32(buf, 384, bpc)
    _put32(buf, 388, bpp)
    _put32(buf, 392, bpl)
    _put32(buf, 396, 0)
    _put32(buf, 400, color_space)
    _put32(buf, 420, num_colors)
    base = 452
    _put32(buf, base + 0, 1)
    _put32(buf, base + 4, 1)
    _put32(buf, base + 8, 1)
    _put32(buf, base + 28, 0x00FFFFFF)
    name_bytes = media_name.encode("ascii")[:64]
    buf[1732 : 1732 + len(name_bytes)] = name_bytes
    return bytes(buf)


def packbits_row(row: bytes, bpp: int) -> bytes:
    out = bytearray()
    n = len(row)
    pos = 0
    while pos < n:
        pixel_end = min(pos + bpp, n)
        if pixel_end == n:
            out.append(0)
            out.extend(row[pos:pixel_end])
            break
        if row[pos:pixel_end] == row[pixel_end : pixel_end + bpp]:
            count = 1
            p = pos + bpp
            while p + bpp <= n and row[pos:pixel_end] == row[p : p + bpp] and count < 128:
                count += 1
                p += bpp
            out.append(count - 1)
            out.extend(row[pos:pixel_end])
            pos = p
        else:
            count = 1
            p = pos + bpp
            while count < 128 and p < n - bpp and row[p : p + bpp] != row[p + bpp : p + 2 * bpp]:
                count += 1
                p += bpp
            if p >= n - bpp and count < 128:
                count += 1
                p += bpp
            out.append((257 - count) & 0xFF)
            out.extend(row[pos : pos + count * bpp])
            pos = p
    return bytes(out)


def compress_rows(raw: bytes, width: int, height: int, bpp: int) -> bytes:
    stride = width * bpp
    out = bytearray()
    y = 0
    while y < height:
        row = raw[y * stride : (y + 1) * stride]
        encoded = packbits_row(row, bpp)
        repeat = 1
        z = y + 1
        while z < height:
            next_row = raw[z * stride : (z + 1) * stride]
            if packbits_row(next_row, bpp) != encoded:
                break
            repeat += 1
            z += 1
        out.append(repeat - 1)
        out.extend(encoded)
        y = z
    return bytes(out)


def write_pwg_raster(
    pages: list[bytes],
    *,
    color_space: int,
    media_name: str,
    media_width: int,
    media_height: int,
    width: int,
    height: int,
) -> bytes:
    bpp = 3 if color_space == COLOR_SPACE_SRGB else 1
    out = bytearray()
    out.extend(b"RaS2")
    for raw in pages:
        header = page_header(
            width, height, color_space, media_name, media_width, media_height
        )
        out.extend(header)
        out.extend(compress_rows(raw, width, height, bpp))
    return bytes(out)
