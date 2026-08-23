"""Unit tests for PWG raster encoder."""

from __future__ import annotations

import struct

import pytest

from epson_print.raster import (
    COLOR_SPACE_SRGB,
    HEADER_SIZE,
    compress_rows,
    packbits_row,
    page_header,
    write_pwg_raster,
)


def get32(buf: bytes, offset: int) -> int:
    return struct.unpack_from(">I", buf, offset)[0]


def test_header_size():
    assert HEADER_SIZE == 1796


def test_header_layout():
    h = page_header(2976, 4209, COLOR_SPACE_SRGB, "iso_a4_210x297mm")
    assert len(h) == HEADER_SIZE
    assert h[0:9] == b"PwgRaster"
    assert get32(h, 276) == 360
    assert get32(h, 372) == 2976
    assert get32(h, 376) == 4209
    assert get32(h, 388) == 24
    assert get32(h, 392) == 2976 * 3
    assert get32(h, 400) == COLOR_SPACE_SRGB
    name = h[1732:1748].rstrip(b"\x00")
    assert name == b"iso_a4_210x297mm"


def test_packbits_literal_one_pixel():
    row = bytes([255, 0, 0, 0, 255, 0])
    enc = packbits_row(row, 3)
    assert enc[0] == 0  # (257 - 2) & 0xFF for count=1 literal -> 256 -> 0


def test_compress_2x2():
    # red row + green/blue row
    row0 = bytes([255, 0, 0] * 2)
    row1 = bytes([0, 255, 0, 0, 0, 255])
    raw = row0 + row1
    stream = compress_rows(raw, 2, 2, 3)
    assert len(stream) == 1 + 4 + 1 + 7


def test_write_document():
    raw = bytes([255] * (4 * 3))
    doc = write_pwg_raster(
        [raw],
        color_space=COLOR_SPACE_SRGB,
        media_name="iso_a4_210x297mm",
        media_width=595,
        media_height=841,
        width=2,
        height=2,
    )
    assert doc[:4] == b"RaS2"
    assert len(doc) == 4 + HEADER_SIZE + len(compress_rows(raw, 2, 2, 3))
