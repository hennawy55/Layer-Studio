#!/usr/bin/env python3
"""Download and verify the offline Google Fonts bundle for Layer Studio.

Every family is distributed under the SIL Open Font License. This script
downloads the official TTF and the matching OFL notice from google/fonts.
The installed application does not make any network requests.
"""

from __future__ import annotations

import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = ROOT / "assets" / "fonts"
LICENSE_DIR = FONT_DIR / "licenses"
RAW_ROOT = "https://raw.githubusercontent.com/google/fonts/main/ofl"

# Arabic families also include Latin glyphs so mixed Arabic/English captions
# stay within the selected typeface.
ARABIC_FONTS = [
    ("Cairo", "cairo"),
    ("Almarai", "almarai"),
    ("Alexandria", "alexandria"),
    ("Amiri", "amiri"),
    ("Changa", "changa"),
    ("Fustat", "fustat"),
    ("Mada", "mada"),
    ("Harmattan", "harmattan"),
    ("Kufam", "kufam"),
    ("Marhey", "marhey"),
    ("Oi", "oi"),
    ("Rakkas", "rakkas"),
]

LATIN_FONTS = [
    ("Open Sans", "opensans"),
    ("Montserrat", "montserrat"),
    ("Oswald", "oswald"),
    ("Lato", "lato"),
    ("Poppins", "poppins"),
    ("Lora", "lora"),
    ("Nunito", "nunito"),
    ("Raleway", "raleway"),
    ("Merriweather", "merriweather"),
    ("Roboto", "roboto"),
    ("Inter", "inter"),
    ("Archivo", "archivo"),
]


def fetch(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Layer-Studio-Offline-Font-Bundler/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.read()
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError(f"Could not download {url}: {exc}") from exc


def choose_regular_ttf(metadata: str, slug: str) -> str:
    blocks = re.findall(r"\bfonts\s*\{([^}]*)\}", metadata, flags=re.DOTALL)
    candidates: list[tuple[int, str]] = []

    for block in blocks:
        filename_match = re.search(r'filename:\s*"([^"]+\.ttf)"', block)
        if not filename_match:
            continue
        style_match = re.search(r'style:\s*"([^"]+)"', block)
        weight_match = re.search(r"weight:\s*(\d+)", block)
        style = style_match.group(1) if style_match else "normal"
        if style != "normal":
            continue
        weight = int(weight_match.group(1)) if weight_match else 400
        candidates.append((abs(weight - 400), filename_match.group(1)))

    if not candidates:
        raise RuntimeError(f"No normal TTF font file was listed for {slug}.")

    candidates.sort(key=lambda item: item[0])
    return candidates[0][1]


def download_family(family: str, slug: str, required_subset: str) -> None:
    metadata_url = f"{RAW_ROOT}/{slug}/METADATA.pb"
    metadata = fetch(metadata_url).decode("utf-8", errors="replace")

    subsets = set(re.findall(r'subsets:\s*"([^"]+)"', metadata))
    if required_subset not in subsets:
        raise RuntimeError(
            f"{family} ({slug}) does not advertise the required "
            f"{required_subset!r} subset. Found: {sorted(subsets)}"
        )
    if "latin" not in subsets:
        raise RuntimeError(f"{family} ({slug}) does not include Latin glyphs.")

    filename = choose_regular_ttf(metadata, slug)
    encoded_filename = urllib.parse.quote(filename, safe="")
    font_url = f"{RAW_ROOT}/{slug}/{encoded_filename}"
    license_url = f"{RAW_ROOT}/{slug}/OFL.txt"

    font_bytes = fetch(font_url)
    if len(font_bytes) < 10_000:
        raise RuntimeError(f"Downloaded font file is unexpectedly small: {family}")

    (FONT_DIR / f"{slug}.ttf").write_bytes(font_bytes)
    (LICENSE_DIR / f"{slug}-OFL.txt").write_bytes(fetch(license_url))
    print(f"Downloaded {family}: {filename} ({len(font_bytes):,} bytes)")


def main() -> None:
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    LICENSE_DIR.mkdir(parents=True, exist_ok=True)

    for family, slug in ARABIC_FONTS:
        download_family(family, slug, "arabic")
    for family, slug in LATIN_FONTS:
        download_family(family, slug, "latin")

    print(
        f"Prepared {len(ARABIC_FONTS) + len(LATIN_FONTS)} offline font families "
        f"({len(ARABIC_FONTS)} Arabic + {len(LATIN_FONTS)} Latin)."
    )


if __name__ == "__main__":
    main()
