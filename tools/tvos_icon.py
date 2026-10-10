#!/usr/bin/env python3
"""Makes the tvOS app's icon and top shelf images from the ringworld artwork,
port/apple/RingArtwork.png (the artwork the iOS icon uses):

    python3 tools/tvos_icon.py

Writes the brand assets port/tvos/Assets.xcassets/App Icon & Top Shelf Image.brandassets:
- App Icon.imagestack (400x240 @1x, 800x480 @2x) and App Icon - App Store.imagestack
  (1280x768), each a full-bleed 5:3 crop of the artwork (its full width, 752 pixels
  high from row 120) split into three depth layers, listed front to back:
  Front, the near mountains and foothills (transparent elsewhere); Middle, the far
  ridges and the valley (transparent elsewhere); Back, the sky, stars, ring, river
  and lake (opaque). Every size is rendered from the full-resolution artwork;
- Top Shelf Image.imageset (1920x720 @1x, 3840x1440 @2x) and Top Shelf Image
  Wide.imageset (2320x720 @1x, 4640x1440 @2x): the artwork covering the frame
  and cropped to it (opaque).

tvOS shifts the layers of a focused icon apart, so a layer's hidden parts would show
as doubled edges. To avoid that, the layers are cut from the artwork with hand-traced
polygons and colour masks, and the part of each layer that a nearer layer covers is
filled by continuing the neighbouring far scenery (Back continues the sky, ring and
water under all the mountains; Middle continues the ridges a little way under the
near mountains).

Run it again when the artwork changes; it rewrites every file it owns. Needs
Pillow and numpy (numpy is only used for the icon layers).
"""

import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ARTWORK = ROOT / "port/apple/RingArtwork.png"
CATALOG = ROOT / "port/tvos/Assets.xcassets"
BRAND = CATALOG / "App Icon & Top Shelf Image.brandassets"

INFO = {"version": 1, "author": "xcode"}

# the icon is the artwork's full width and 5:3, starting at this artwork row
ARTWORK_SIZE = 1254
CROP_TOP = 120
CROP_BOX = (0, CROP_TOP, ARTWORK_SIZE, CROP_TOP + round(ARTWORK_SIZE * 3 / 5))

# these polygons trace the mountain silhouettes in artwork pixels
# inner boundary of the mountain masses, roughly along the light rim / tree line
MOUNTAINS_LEFT = [
    (0, 0), (300, 0), (300, 484), (305, 505), (317, 561), (362, 548), (407, 601), (445, 677),
    (486, 667), (525, 722), (600, 742), (540, 760), (450, 780), (410, 795), (407, 805),
    (430, 815), (480, 830), (500, 840), (485, 852), (520, 865), (550, 880), (560, 900),
    (540, 910), (400, 925), (250, 950), (0, 990)]
MOUNTAINS_RIGHT = [
    (1254, 0), (950, 0), (950, 484), (950, 520), (915, 607), (870, 580), (850, 657),
    (822, 650), (800, 675), (750, 700), (715, 702), (730, 725), (800, 735), (850, 755),
    (860, 772), (840, 772), (780, 780), (730, 792), (725, 802), (750, 810), (900, 830),
    (970, 845), (975, 860), (910, 895), (890, 915), (910, 930), (1000, 950), (1254, 1015)]
# the nearer mountain tier: everything below these crest lines is the front layer
NEAR_LEFT = [
    (0, 462), (45, 463), (70, 510), (95, 555), (150, 572), (230, 610), (300, 650),
    (380, 695), (440, 735), (520, 770), (620, 800), (620, 1254), (0, 1254)]
NEAR_RIGHT = [
    (1254, 550), (1180, 598), (1090, 650), (990, 690), (900, 705), (850, 722),
    (700, 715), (700, 1254), (1254, 1254)]

LUMA = np.array([0.3, 0.59, 0.11], dtype="float32")


# ---------------------------------------------------------------- files

def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")


# ---------------------------------------------------------------- masks

def to_image(mask: np.ndarray) -> Image.Image:
    return Image.fromarray((mask * 255).astype("uint8"))


def polygon_mask(points: list) -> np.ndarray:
    mask = Image.new("L", (ARTWORK_SIZE, ARTWORK_SIZE), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return np.array(mask) > 0


def flood(mask: np.ndarray, seed: tuple) -> np.ndarray:
    """the pixels of `mask` connected to `seed`"""
    image = to_image(mask)
    ImageDraw.floodfill(image, seed, 128)
    return np.array(image) == 128


def filtered(mask: np.ndarray, image_filter: ImageFilter.Filter) -> np.ndarray:
    return np.array(to_image(mask).filter(image_filter)) > 127


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    return filtered(mask, ImageFilter.MaxFilter(2 * radius + 1))


def erode(mask: np.ndarray, radius: int) -> np.ndarray:
    return filtered(mask, ImageFilter.MinFilter(2 * radius + 1))


def water_mask(art: np.ndarray) -> np.ndarray:
    r, b = art[..., 0].astype(int), art[..., 2].astype(int)
    return (r < 90) & (b > 190)


def segment(art: np.ndarray) -> tuple:
    """the masks (mountains, near mountains) of the artwork in artwork coordinates"""
    a = art.astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    sky_colour = (r < 14) & (g < 40) & (b > 25) & (b < 75)
    barrier = dilate(~sky_colour, 1)
    sky = flood(~barrier, (5, 5)) | flood(~barrier, (1240, 5))
    # everything not sky and connected to the lake is the solid scene; stars are holes in the sky
    solid = flood(~sky, (600, 1100))
    sky = ~solid

    inside = dilate(polygon_mask(MOUNTAINS_LEFT) | polygon_mask(MOUNTAINS_RIGHT), 4)
    water = (r < 80) & (b > 150) & (g > 110)
    near_sky = dilate(sky, 12)
    mountain = solid & inside & ~(water & ~near_sky)
    # drop specks and fill pinholes
    mountain = filtered(mountain, ImageFilter.MedianFilter(5))
    mountain = erode(dilate(mountain, 12), 12) & solid & inside & ~((r < 60) & (b > 200))
    near = mountain & (polygon_mask(NEAR_LEFT) | polygon_mask(NEAR_RIGHT))
    return mountain, near


# ---------------------------------------------------------------- colour extension

def box_blur(arr: np.ndarray, radius: int, axis: int) -> np.ndarray:
    n = arr.shape[axis]
    pad = [(0, 0)] * arr.ndim
    pad[axis] = (radius + 1, radius)
    total = np.cumsum(np.pad(arr, pad, mode="edge"), axis=axis, dtype="float64")
    high = np.take(total, range(2 * radius + 1, 2 * radius + 1 + n), axis=axis)
    low = np.take(total, range(0, n), axis=axis)
    return ((high - low) / (2 * radius + 1)).astype("float32")


def blur(arr: np.ndarray, sigma: float) -> np.ndarray:
    """approximate gaussian: three box blurs per axis"""
    radius = max(1, round(sigma * 0.8))
    for _ in range(3):
        arr = box_blur(box_blur(arr, radius, 0), radius, 1)
    return arr


def inpaint(rgb: np.ndarray, hole: np.ndarray) -> np.ndarray:
    """fill `hole` with a smooth extension of the known pixels (normalised multi-scale blur)"""
    image = rgb.astype("float32")
    known = (~hole).astype("float32")[..., None]
    out = image * known
    filled = known.copy()
    for sigma in (3, 6, 12, 24, 48, 96, 192):
        estimate = blur(image * known, sigma) / np.maximum(blur(known, sigma), 1e-6)
        take = (filled < 0.5) & (blur(known, sigma) > 0.02)
        out = np.where(take, estimate, out)
        filled = np.where(take, 1.0, filled)
    return out


def shifted_source(done: np.ndarray, rgb: np.ndarray, axis: int, sign: int) -> tuple:
    """`done` and `rgb` moved one pixel along `axis`, without wrapping around the edge"""
    src_done = np.roll(done, sign, axis)
    src_rgb = np.roll(rgb, sign, axis)
    edge = [slice(None)] * 2
    edge[axis] = slice(0, 1) if sign == 1 else slice(-1, None)
    src_done[tuple(edge)] = False
    return src_done, src_rgb


def extend(rgb: np.ndarray, known: np.ndarray, steps: int, smooth: int = 2,
           bright_steps: int = None, priority: tuple = None) -> np.ndarray:
    """continue the flat colours of the known pixels into the unknown ones: each step copies
    the colour of a known 4-neighbour (nearest-pixel extension, so no blurred mixes), then
    the new pixels are lightly smoothed; pixels farther than `steps` are filled by blurred
    extension. `bright_steps`: after that many steps only dark pixels are copied, so light
    rims, clouds and shore highlights do not make pale streaks. `priority=(mask, n)`: for the
    first n steps only pixels in `mask` (e.g. water) are copied from."""
    out = rgb.astype("float32").copy()
    done = known.copy()
    luma = (out * LUMA).sum(axis=2)
    preferred = None if priority is None else priority[0] & known
    for step in range(steps):
        use = preferred if preferred is not None and step < priority[1] else None
        new = np.zeros_like(done)
        pick = np.zeros_like(out)
        for axis, sign in ((0, 1), (0, -1), (1, 1), (1, -1)):
            src_done, src_rgb = shifted_source(done, out, axis, sign)
            take = src_done & ~done & ~new
            if use is not None:
                take &= np.roll(use, sign, axis)
            if bright_steps is not None and step >= bright_steps:
                take &= np.roll(luma, sign, axis) < 130
            pick[take] = src_rgb[take]
            new |= take
        if not new.any():
            continue
        out[new] = pick[new]
        luma[new] = (pick[new] * LUMA).sum(axis=1)
        done |= new
        if use is not None:
            preferred = preferred | new
    grown = done & ~known
    if smooth and grown.any():
        out = np.where(grown[..., None], blur(out, smooth), out)
    if not done.all():
        out = np.where(done[..., None], out, inpaint(out, ~done))
    return out


# ---------------------------------------------------------------- layers

def build_layers(art: np.ndarray) -> dict:
    """the full-size layers in artwork coordinates: name -> (rgb, alpha mask or None)"""
    mountain, near = segment(art)
    far_ridge = mountain & ~near
    # Back: the far scene (sky, stars, ring, valley, river, lake); the mountains are painted
    # out by continuing the neighbouring far pixels (the hole grown past the light rim's
    # antialiasing)
    back = extend(art, ~dilate(mountain, 4), 40, smooth=4, bright_steps=5,
                  priority=(water_mask(art), 14))
    # Middle: the far ridges; beneath the near mountains it continues the ridge colours a
    # little way
    middle_mask = far_ridge | (near & dilate(far_ridge, 28))
    middle = extend(art, erode(far_ridge, 1), 32, smooth=3)
    # Front: the near mountains, colour continued past the edge so the feathered edge has
    # no fringe
    front = extend(art, erode(near, 1), 10)
    return {"Front": (front, near), "Middle": (middle, middle_mask), "Back": (back, None)}


def render_layer(rgb: np.ndarray, mask: np.ndarray, size: tuple) -> Image.Image:
    """the layer cropped to the icon window and scaled to `size`"""
    image = Image.fromarray(np.clip(rgb, 0, 255).astype("uint8"))
    image = image.crop(CROP_BOX).resize(size, Image.LANCZOS)
    if mask is None:
        return image
    alpha = to_image(mask).filter(ImageFilter.GaussianBlur(1.2))
    image = image.convert("RGBA")
    image.putalpha(alpha.crop(CROP_BOX).resize(size, Image.LANCZOS))
    return image


def imagestack(name: str, base: tuple, scales: tuple, layers: dict) -> None:
    stack = BRAND / f"{name}.imagestack"
    # the stack lists its layers from the front to the back; the last must be opaque
    write_json(stack / "Contents.json", {
        "layers": [{"filename": f"{layer}.imagestacklayer"} for layer in layers],
        "info": INFO,
    })
    for layer, (rgb, mask) in layers.items():
        folder = stack / f"{layer}.imagestacklayer"
        write_json(folder / "Contents.json", {"info": INFO})
        images = []
        for scale in scales:
            filename = f"{layer}{'' if scale == 1 else f'@{scale}x'}.png"
            image = render_layer(rgb, mask, (base[0] * scale, base[1] * scale))
            save(image, folder / "Content.imageset" / filename)
            images.append({"filename": filename, "idiom": "tv", "scale": f"{scale}x"})
        write_json(folder / "Content.imageset/Contents.json", {"images": images, "info": INFO})


# ---------------------------------------------------------------- top shelf

def cover(art: Image.Image, size: tuple) -> Image.Image:
    """the artwork scaled to fill the frame, the overflow cropped evenly"""
    scale = max(size[0] / art.width, size[1] / art.height)
    scaled = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
    x = (scaled.width - size[0]) // 2
    y = (scaled.height - size[1]) // 2
    return scaled.crop((x, y, x + size[0], y + size[1]))


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
    layers = build_layers(np.array(art.convert("RGB")))
    if BRAND.exists():
        shutil.rmtree(BRAND)
    write_json(CATALOG / "Contents.json", {"info": INFO})
    imagestack("App Icon", (400, 240), (1, 2), layers)
    imagestack("App Icon - App Store", (1280, 768), (1,), layers)
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
