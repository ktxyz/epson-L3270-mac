#!/usr/bin/env python3
"""Driverless printing to an Epson L3270 over IPP + PWG raster."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import mdns
from . import ipp
from .raster import COLOR_SPACE_SGRAY, COLOR_SPACE_SRGB, geometry, write_pwg_raster
from .render import render_file


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="epson-print", description="Print to Epson L3270")
    parser.add_argument("file", help="PDF or image to print")
    parser.add_argument("--media", default="a4")
    parser.add_argument("--mono", action="store_true")
    parser.add_argument("--copies", type=int, default=1)
    parser.add_argument("--quality", choices=["draft", "normal", "high"], default="normal")
    parser.add_argument("--printer", default="L3270")
    parser.add_argument("--host", help="Printer host, skip discovery")
    parser.add_argument("--dry-run", metavar="FILE", help="Write PWG stream instead of printing")
    args = parser.parse_args(argv)

    path = Path(args.file)
    if not path.exists():
        print(f"error: {path} not found", file=sys.stderr)
        return 1

    media_name, mw, mh, width, height = geometry(args.media)
    color_space = COLOR_SPACE_SGRAY if args.mono else COLOR_SPACE_SRGB
    print(f"rendering {path} ({args.media}, {'mono' if args.mono else 'color'})...")
    pages = render_file(path, args.media, args.mono)
    document = write_pwg_raster(
        pages,
        color_space=color_space,
        media_name=media_name,
        media_width=mw,
        media_height=mh,
        width=width,
        height=height,
    )

    if args.dry_run:
        Path(args.dry_run).write_bytes(document)
        print(f"wrote {len(document)} bytes to {args.dry_run}")
        return 0

    if args.host:
        host = args.host.split(":")[0]
        port = int(args.host.split(":")[1]) if ":" in args.host else 631
        client = ipp.IPPClient(host, port)
    else:
        printers = mdns.find_printers(args.printer)
        if not printers:
            print(f"error: no printer matching {args.printer!r}", file=sys.stderr)
            return 1
        found = printers[0]
        print(f"found {found.name} at {found.host}:{found.port}")
        client = ipp.IPPClient(found.host, found.port, found.resource)

    quality = 4 if args.quality == "high" else 3
    attrs = client.print_job(
        document,
        copies=args.copies,
        media=media_name,
        color_mode="monochrome" if args.mono else "color",
        quality=quality,
    )
    job_id = (attrs.get("job-id") or ["?"])[0]
    print(f"job {job_id} accepted ({len(pages)} page(s), {args.copies} copy(ies))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
