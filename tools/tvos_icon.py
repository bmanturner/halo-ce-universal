#!/usr/bin/env python3
"""Makes the tvOS app's icon and top shelf images from the ringworld artwork,
port/apple/RingArtwork.png (the artwork the iOS icon uses):

    python3 tools/tvos_icon.py

Writes the brand assets port/tvos/Assets.xcassets/App Icon & Top Shelf Image.brandassets:
- App Icon.imagestack (400x240 @1x, 800x480 @2x) and App Icon - App Store.imagestack
  (1280x768), each of two layers: Back, the artwork covering the frame, darkened
  and blurred (opaque), and Front, the artwork centred at 80% of the frame
  height on transparency (the layer that moves with the parallax effect);
- Top Shelf Image.imageset (1920x720 @1x, 3840x1440 @2x) and Top Shelf Image
  Wide.imageset (2320x720 @1x, 4640x1440 @2x): the artwork covering the frame
  and cropped to it (opaque).

Run it again when the artwork changes; it rewrites every file it owns. Needs
Pillow.
"""

import json
import shutil
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ARTWORK = ROOT / "port/apple/RingArtwork.png"
CATALOG = ROOT / "port/tvos/Assets.xcassets"
BRAND = CATALOG / "App Icon & Top Shelf Image.brandassets"

INFO = {"version": 1, "author": "xcode"}


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def cover(art: Image.Image, size: tuple) -> Image.Image:
    """the artwork scaled to fill the frame, the overflow cropped evenly"""
    scale = max(size[0] / art.width, size[1] / art.height)
    scaled = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
    x = (scaled.width - size[0]) // 2
    y = (scaled.height - size[1]) // 2
    return scaled.crop((x, y, x + size[0], y + size[1]))


def back(art: Image.Image, size: tuple) -> Image.Image:
    image = cover(art, size).filter(ImageFilter.GaussianBlur(size[1] / 40))
    return ImageEnhance.Brightness(image).enhance(0.55)


def front(art: Image.Image, size: tuple) -> Image.Image:
    height = round(size[1] * 0.8)
    scaled = art.resize((height, height), Image.LANCZOS)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(scaled, ((size[0] - height) // 2, (size[1] - height) // 2), scaled)
    return layer


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")


def imagestack(name: str, base: tuple, scales: tuple, art: Image.Image) -> None:
    stack = BRAND / f"{name}.imagestack"
    # the stack lists its layers from the front to the back
    layers = [("Front", front, "RGBA"), ("Back", back, "RGB")]
    write_json(stack / "Contents.json", {
        "layers": [{"filename": f"{layer}.imagestacklayer"} for layer, _, _ in layers],
        "info": INFO,
    })
    for layer, make, mode in layers:
        folder = stack / f"{layer}.imagestacklayer"
        write_json(folder / "Contents.json", {"info": INFO})
        images = []
        for scale in scales:
            size = (base[0] * scale, base[1] * scale)
            filename = f"{layer}{'' if scale == 1 else f'@{scale}x'}.png"
            save(make(art, size).convert(mode), folder / "Content.imageset" / filename)
            images.append({"filename": filename, "idiom": "tv", "scale": f"{scale}x"})
        write_json(folder / "Content.imageset/Contents.json", {"images": images, "info": INFO})


def topshelf(name: str, base: tuple, art: Image.Image) -> str:
    folder = BRAND / f"{name}.imageset"
    images = []
    for scale in (1, 2):
        filename = f"{name.replace(' ', '')}{'' if scale == 1 else f'@{scale}x'}.png"
        save(cover(art, (base[0] * scale, base[1] * scale)).convert("RGB"), folder / filename)
        images.append({"filename": filename, "idiom": "tv", "scale": f"{scale}x"})
    write_json(folder / "Contents.json", {"images": images, "info": INFO})
    return folder.name


def main() -> None:
    art = Image.open(ARTWORK).convert("RGBA")
    if BRAND.exists():
        shutil.rmtree(BRAND)
    write_json(CATALOG / "Contents.json", {"info": INFO})
    imagestack("App Icon", (400, 240), (1, 2), art)
    imagestack("App Icon - App Store", (1280, 768), (1,), art)
    topshelf("Top Shelf Image", (1920, 720), art)
    topshelf("Top Shelf Image Wide", (2320, 720), art)
    write_json(BRAND / "Contents.json", {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv",
             "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv",
             "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": INFO,
    })


if __name__ == "__main__":
    main()
