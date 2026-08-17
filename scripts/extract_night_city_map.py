#!/usr/bin/env python3
"""Extract the largest raster from a user-owned PDF page without retaining it."""
from __future__ import annotations

import argparse
from pathlib import Path

import fitz
from PIL import Image


def extract(pdf_path: Path, output: Path, page: int | None = None) -> tuple[int, int]:
    document = fitz.open(pdf_path)
    pages = [document[page - 1]] if page else document
    candidates: list[tuple[int, fitz.Page, tuple]] = []
    for pdf_page in pages:
        for info in pdf_page.get_images(full=True):
            candidates.append((int(info[2]) * int(info[3]), pdf_page, info))
    if not candidates:
        raise ValueError("no embedded images found in the selected PDF page(s)")
    _, pdf_page, info = max(candidates, key=lambda candidate: candidate[0])
    raw = document.extract_image(info[0])["image"]
    output.parent.mkdir(parents=True, exist_ok=True)
    from io import BytesIO
    with Image.open(BytesIO(raw)) as image:
        if image.width < 1000 or image.height < 700:
            raise ValueError(f"largest image is suspiciously small ({image.width}x{image.height})")
        if image.mode not in ("RGB", "RGBA"):
            image = image.convert("RGB")
        image.save(output, "PNG", optimize=True)
        return image.width, image.height


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--page", type=int, help="one-based map page; scans all pages when omitted")
    args = parser.parse_args()
    width, height = extract(args.pdf, args.output, args.page)
    print(f"Wrote RGB-compatible PNG {width}x{height} to {args.output}")


if __name__ == "__main__":
    main()
