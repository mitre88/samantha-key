"""Render the iPhone Duo App Store screenshots from duo.html with Playwright WebKit.

usage: python3 render_duo.py <output-dir>
Writes 01.png ... 05.png at the exact App Store Connect sizes (inner 2853x2007, cover 1398x2034),
flattened to RGB because App Store Connect rejects alpha channels.
"""
import sys
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
SIZES = {"inner": (2853, 2007), "outer": (1398, 2034)}
SLIDES = ["inner", "inner", "inner", "inner", "outer"]


def main(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.webkit.launch()
        for index, canvas in enumerate(SLIDES):
            width, height = SIZES[canvas]
            page = browser.new_page(viewport={"width": width, "height": height}, device_scale_factor=1)
            page.goto(f"{(HERE / 'duo.html').as_uri()}?slide={index}")
            # Wait until every capture is decoded and painted; a plain load check raced the paint.
            page.evaluate("Promise.all(Array.from(document.images).map(i => i.decode()))")
            page.evaluate("new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))")
            page.wait_for_timeout(300)
            target = out_dir / f"{index + 1:02d}.png"
            page.screenshot(path=str(target), clip={"x": 0, "y": 0, "width": width, "height": height})
            page.close()
            image = Image.open(target).convert("RGB")
            assert image.size == (width, height), (target, image.size)
            image.save(target, optimize=True)
            print(target, image.size)
        browser.close()


if __name__ == "__main__":
    main(Path(sys.argv[1]))
