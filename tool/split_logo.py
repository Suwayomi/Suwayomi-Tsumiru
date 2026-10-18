# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""Split the dark logo into a cream foreground layer and a recolourable shadow layer.

The shadow is the saturated part of the artwork (the cyan->blue offset). Its colour
is stored as a grayscale shade so the app can tint it with the active theme's
accent gradient; the foreground keeps the original pixels untouched.
"""

import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/icons/dark_icon.png"
FOREGROUND = ROOT / "assets/icons/logo_foreground.png"
SHADOW = ROOT / "assets/icons/logo_shadow.png"

# Mirrors the approved mockup (.claude/mockups/themed-logo/gen.py).
SATURATION_MIN = 0.30
RAMP_START = 188.0
RAMP_END = 222.0


def hue_degrees(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return np.degrees(np.arctan2(np.sqrt(3) * (g - b), 2 * r - g - b)) % 360


def unit(color: np.ndarray) -> np.ndarray:
    return color / color.max()


def split(source: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    rgb = source[..., :3].astype(np.float64) / 255
    alpha = source[..., 3]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    saturation = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    is_shadow = (saturation > SATURATION_MIN) & (alpha > 0)

    foreground = np.zeros_like(source)
    foreground[..., :3] = source[..., :3]
    foreground[..., 3] = np.where(is_shadow, 0, alpha)

    shadow = np.zeros_like(source)
    shadow[..., :3] = source[..., :3].max(-1)[..., None]
    shadow[..., 3] = np.where(is_shadow, alpha, 0)
    return foreground, shadow


def verify(source: np.ndarray, foreground: np.ndarray, shadow: np.ndarray) -> None:
    alpha = source[..., 3]
    fg_alpha = foreground[..., 3]
    sh_alpha = shadow[..., 3]
    lost = int(((alpha > 0) & (fg_alpha == 0) & (sh_alpha == 0)).sum())
    extra = int(((alpha == 0) & ((fg_alpha > 0) | (sh_alpha > 0))).sum())
    gap = int((fg_alpha.astype(np.int32) + sh_alpha.astype(np.int32) != alpha).sum())
    print(f"coverage: lost={lost} extra={extra} alpha_sum_mismatch={gap}")

    rgb = source[..., :3].astype(np.float64) / 255
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    saturation = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    is_shadow = (saturation > SATURATION_MIN) & (alpha > 0)
    hue = hue_degrees(rgb)

    cyan = unit(rgb[is_shadow & (hue >= RAMP_START) & (hue < RAMP_START + 2)].mean(0))
    blue = unit(rgb[is_shadow & (hue >= RAMP_END) & (hue < RAMP_END + 2)].mean(0))
    t = np.clip((hue - RAMP_START) / (RAMP_END - RAMP_START), 0, 1)[..., None]
    ramp = cyan[None, None] * (1 - t) + blue[None, None] * t
    recoloured = ramp * mx[..., None]
    check = is_shadow & (alpha > 127)
    diff = np.abs(recoloured[check] * 255 - source[..., :3][check])
    print(
        f"recolour: max abs rgb diff={diff.max():.2f}/255 "
        f"mean={diff.mean():.2f} over {check.sum()} px (alpha>0.5, shadow)"
    )
    print(f"endpoints: cyan={np.round(cyan * 255).astype(int)} "
          f"blue={np.round(blue * 255).astype(int)}")


def main() -> None:
    image = Image.open(SRC).convert("RGBA")
    if image.size != (512, 512):
        raise SystemExit(f"expected a 512x512 canvas, got {image.size}")
    source = np.asarray(image)
    foreground, shadow = split(source)
    Image.fromarray(foreground, "RGBA").save(FOREGROUND)
    Image.fromarray(shadow, "RGBA").save(SHADOW)
    verify(source, foreground, shadow)
    print(f"wrote {FOREGROUND.relative_to(ROOT)}")
    print(f"wrote {SHADOW.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
