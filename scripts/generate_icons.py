#!/usr/bin/env python3
"""Generate every Ulash launcher icon from one geometric definition.

The mark is two exchange arrows on the brand turquoise. Geometry is defined on
a 1024-unit grid and written as an SVG master. The same
geometry is rasterized by headless Chromium (Playwright for Node, which must
be installed) at 1024 px and downscaled with Pillow.

Usage: python3 scripts/generate_icons.py   (run from the repository root)
"""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'apps' / 'file_transfer'

TOP = (0x00, 0xA3, 0x96)      # gradient start (top-left)
BOTTOM = (0x00, 0x6B, 0x66)   # gradient end (bottom-right)
WHITE = (255, 255, 255)
MINT = (0xB8, 0xF5, 0xEC)
STROKE = 84

# Arrow polylines on the 1024 grid: (shaft start, shaft end, head points).
UPPER = [((300, 410), (708, 410)), ((612, 314), (708, 410), (612, 506))]
LOWER = [((724, 614), (316, 614)), ((412, 518), (316, 614), (412, 710))]


def _hex(color) -> str:
    return '#%02X%02X%02X' % color


def svg(*, background: bool = True, mark_scale: float = 1.0,
        upper=WHITE, lower=MINT, arrows: bool = True) -> str:
    """mark_scale shrinks the arrows around the centre (adaptive safe zone)."""
    def path(line):
        return 'M' + ' L'.join(f'{x} {y}' for x, y in line)

    def arrow(lines, color):
        return ''.join(
            f'<path d="{path(line)}" fill="none" stroke="{_hex(color)}" '
            f'stroke-width="{STROKE}" stroke-linecap="round" '
            'stroke-linejoin="round"/>' for line in lines)

    offset = 512 * (1 - mark_scale)
    back = (
        '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{_hex(TOP)}"/>'
        f'<stop offset="1" stop-color="{_hex(BOTTOM)}"/></linearGradient></defs>'
        '<rect width="1024" height="1024" fill="url(#g)"/>' if background else '')
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
        f'width="1024" height="1024">{back}'
        f'<g transform="translate({offset} {offset}) scale({mark_scale})">'
        f'{arrow(LOWER, lower) + arrow(UPPER, upper) if arrows else ""}</g></svg>\n')


_NODE = r"""
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const jobs = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
  for (const job of jobs) {
    await page.setContent('<html><body style="margin:0;background:transparent">' + job.svg + '</body></html>');
    await page.locator('svg').screenshot({ path: job.out, omitBackground: true });
  }
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
"""

_cache: dict[str, Image.Image] = {}


def _rasterize(variants: dict[str, str]) -> None:
    """Render 1024px masters of every SVG variant in one Chromium session."""
    with tempfile.TemporaryDirectory() as temp:
        jobs = [{'svg': text, 'out': str(Path(temp) / f'{key}.png')}
                for key, text in variants.items()]
        spec = Path(temp) / 'jobs.json'
        spec.write_text(json.dumps(jobs))
        script = Path(temp) / 'render.js'
        script.write_text(_NODE)
        subprocess.run(['node', str(script), str(spec)], check=True, cwd=temp)
        for key, job in zip(variants, jobs):
            _cache[key] = Image.open(job['out']).convert('RGBA').copy()


VARIANTS = {
    'full': dict(),
    'bg': dict(arrows=False),
    'fg': dict(background=False, mark_scale=0.78),
    'mono': dict(background=False, mark_scale=0.78, upper=WHITE, lower=WHITE),
    'launch': dict(background=False, upper=(0, 0x7F, 0x79), lower=(0x5F, 0xC9, 0xBC)),
}


def render(size: int, variant: str = 'full') -> Image.Image:
    image = _cache[variant].resize((size, size), Image.LANCZOS)
    return image.convert('RGB') if variant in ('full', 'bg') else image


def ios() -> None:
    folder = APP / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    contents = json.loads((folder / 'Contents.json').read_text())
    for image in contents['images']:
        points = float(image['size'].split('x')[0])
        pixels = round(points * int(image['scale'][0]))
        render(pixels).save(folder / image['filename'], optimize=True)
    # Launch mark: arrows only, centred on a plain background colour.
    launch = APP / 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
    for scale, name in ((1, 'LaunchImage.png'), (2, 'LaunchImage@2x.png'), (3, 'LaunchImage@3x.png')):
        render(120 * scale, 'launch').save(launch / name, optimize=True)


def android() -> None:
    res = APP / 'android/app/src/main/res'
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, factor in densities.items():
        folder = res / f'mipmap-{name}'
        folder.mkdir(exist_ok=True)
        render(round(48 * factor)).save(folder / 'ic_launcher.png', optimize=True)
        size = round(108 * factor)
        # 66/108 safe zone: the scaled mark spans ~39% of the layer width.
        render(size, 'fg').save(folder / 'ic_launcher_foreground.png', optimize=True)
        render(size, 'mono').save(folder / 'ic_launcher_monochrome.png', optimize=True)
        render(size, 'bg').save(folder / 'ic_launcher_background.png', optimize=True)
    anydpi = res / 'mipmap-anydpi-v26'
    anydpi.mkdir(exist_ok=True)
    (anydpi / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n')
    for density, factor in densities.items():
        render(round(96 * factor), 'launch').save(
            res / f'mipmap-{density}' / 'launch_mark.png', optimize=True)


def windows() -> None:
    master = render(256)
    master.save(APP / 'windows/runner/resources/app_icon.ico',
                sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


def main() -> None:
    branding = APP / 'assets' / 'branding'
    branding.mkdir(parents=True, exist_ok=True)
    (branding / 'ulash_icon.svg').write_text(svg())
    _rasterize({key: svg(**options) for key, options in VARIANTS.items()})
    render(1024).save(branding / 'ulash_icon_1024.png', optimize=True)
    ios()
    android()
    windows()
    print('Icons generated.')


if __name__ == '__main__':
    main()
