"""Extract the Night City 2045 map from an operator-owned sourcebook PDF.

The output belongs under ``data/`` and is intentionally gitignored. Cyberpunk
RED's printed page number matches the PDF page index for the supplied edition,
so printed page 296 is accessed as ``document[296]``.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import pymupdf


def extract_map(pdf_path: Path, output_path: Path, page_index: int = 296) -> Path:
    if not pdf_path.is_file():
        raise FileNotFoundError(pdf_path)
    document = pymupdf.open(pdf_path)
    if page_index < 0 or page_index >= len(document):
        raise ValueError(f"page index {page_index} is outside this {len(document)}-page PDF")
    images = document[page_index].get_images(full=True)
    if not images:
        raise ValueError(f"no embedded images found on PDF page index {page_index}")
    map_image = max(images, key=lambda entry: int(entry[2]) * int(entry[3]))
    pixmap = pymupdf.Pixmap(document, int(map_image[0]))
    if pixmap.width < 500 or pixmap.height < 500:
        raise ValueError("largest page image is too small to be the Night City map")
    if pixmap.colorspace is None or pixmap.colorspace.n != 3:
        pixmap = pymupdf.Pixmap(pymupdf.csRGB, pixmap)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    pixmap.save(output_path)
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", type=Path, required=True, help="path to Cyberpunk Red.pdf")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/maps/night_city_2045.png"),
        help="gitignored output path",
    )
    parser.add_argument(
        "--page-index",
        type=int,
        default=296,
        help="PDF page index containing the map (also printed page 296 in this edition)",
    )
    arguments = parser.parse_args()
    output = extract_map(arguments.pdf, arguments.output, arguments.page_index)
    print(output.resolve())


if __name__ == "__main__":
    main()
