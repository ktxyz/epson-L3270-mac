"""Render PDFs and images to 360 dpi raw pages."""

from __future__ import annotations

from pathlib import Path

import pypdfium2 as pdfium
from PIL import Image

from .raster import geometry


def _fit_box(src_w: int, src_h: int, dst_w: int, dst_h: int) -> tuple[int, int, int, int]:
    scale = min(dst_w / src_w, dst_h / src_h)
    w = max(1, int(src_w * scale))
    h = max(1, int(src_h * scale))
    x = (dst_w - w) // 2
    y = (dst_h - h) // 2
    return x, y, w, h


def render_pdf(path: Path, media: str, mono: bool) -> list[bytes]:
    _, _, _, width, height = geometry(media)
    doc = pdfium.PdfDocument(str(path))
    pages: list[bytes] = []
    for i in range(len(doc)):
        page = doc[i]
        pw, ph = page.get_size()
        scale = min(width / pw, height / ph)
        render_w = max(1, int(pw * scale))
        render_h = max(1, int(ph * scale))
        bitmap = page.render(scale=scale)
        pil = bitmap.to_pil()
        canvas = Image.new("RGB", (width, height), "white")
        x, y, w, h = _fit_box(pil.width, pil.height, width, height)
        canvas.paste(pil.resize((w, h), Image.Resampling.LANCZOS), (x, y))
        if mono:
            pages.append(canvas.convert("L").tobytes())
        else:
            pages.append(canvas.tobytes())
    return pages


def render_image(path: Path, media: str, mono: bool) -> list[bytes]:
    _, _, _, width, height = geometry(media)
    img = Image.open(path).convert("RGB")
    canvas = Image.new("RGB", (width, height), "white")
    x, y, w, h = _fit_box(img.width, img.height, width, height)
    canvas.paste(img.resize((w, h), Image.Resampling.LANCZOS), (x, y))
    if mono:
        return [canvas.convert("L").tobytes()]
    return [canvas.tobytes()]


def render_file(path: Path, media: str, mono: bool) -> list[bytes]:
    suffix = path.suffix.lower()
    if suffix == ".pdf":
        return render_pdf(path, media, mono)
    return render_image(path, media, mono)
