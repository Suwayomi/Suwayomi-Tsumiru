# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""Split the logo artwork into a foreground layer and a recolourable shadow layer.

The dark art's shadow is the saturated part of the artwork (the cyan->blue
offset). The on-light art's shadow is its saturated bright offset; the extra
value floor keeps the navy ink out of it. In both cases the shadow's colour is
stored as a grayscale shade so the app can tint it with a theme's accent pair;
the foreground keeps the original pixels untouched.
"""

import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
DARK_SRC = ROOT / "assets/icons/dark_icon.png"
DARK_FOREGROUND = ROOT / "assets/icons/logo_foreground.png"
DARK_SHADOW = ROOT / "assets/icons/logo_shadow.png"
LIGHT_SRC = ROOT / "assets/icons/logo_on_light.png"
LIGHT_FOREGROUND = ROOT / "assets/icons/logo_on_light_foreground.png"
LIGHT_SHADOW = ROOT / "assets/icons/logo_on_light_shadow.png"

# Mirrors the approved mockups (.claude/mockups/themed-logo/gen.py and
# gen_light_v2.py).
SATURATION_MIN = 0.30
RAMP_START = 188.0
RAMP_END = 222.0
LIGHT_VALUE_MIN = 0.45


def hue_degrees(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return np.degrees(np.arctan2(np.sqrt(3) * (g - b), 2 * r - g - b)) % 360


def unit(color: np.ndarray) -> np.ndarray:
    return color / color.max()


def shadow_mask(source: np.ndarray, value_min: float | None = None) -> np.ndarray:
    rgb = source[..., :3].astype(np.float64) / 255
    alpha = source[..., 3]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    saturation = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    mask = (saturation > SATURATION_MIN) & (alpha > 0)
    if value_min is not None:
        mask &= mx > value_min
    return mask


def split(source: np.ndarray, mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    alpha = source[..., 3]

    foreground = np.zeros_like(source)
    foreground[..., :3] = source[..., :3]
    foreground[..., 3] = np.where(mask, 0, alpha)

    shadow = np.zeros_like(source)
    shadow[..., :3] = source[..., :3].max(-1)[..., None]
    shadow[..., 3] = np.where(mask, alpha, 0)
    return foreground, shadow


def verify(
    source: np.ndarray,
    foreground: np.ndarray,
    shadow: np.ndarray,
    mask: np.ndarray,
    label: str,
) -> None:
    alpha = source[..., 3].astype(np.int32)
    fg_alpha = foreground[..., 3].astype(np.int32)
    sh_alpha = shadow[..., 3].astype(np.int32)
    lost = int(((alpha > 0) & (fg_alpha == 0) & (sh_alpha == 0)).sum())
    extra = int(((alpha == 0) & ((fg_alpha > 0) | (sh_alpha > 0))).sum())
    overlap = int(((fg_alpha > 0) & (sh_alpha > 0)).sum())
    gap = int((fg_alpha + sh_alpha != alpha).sum())
    print(
        f"{label} coverage: lost={lost} extra={extra} "
        f"overlap={overlap} alpha_sum_mismatch={gap}"
    )
    print(f"{label} shadow pixels: {int(mask.sum())}")
    assert lost == 0 and extra == 0 and overlap == 0 and gap == 0, label


def verify_ramp(source: np.ndarray, mask: np.ndarray) -> None:
    rgb = source[..., :3].astype(np.float64) / 255
    alpha = source[..., 3]
    mx = rgb.max(-1)
    hue = hue_degrees(rgb)

    cyan = unit(rgb[mask & (hue >= RAMP_START) & (hue < RAMP_START + 2)].mean(0))
    blue = unit(rgb[mask & (hue >= RAMP_END) & (hue < RAMP_END + 2)].mean(0))
    t = np.clip((hue - RAMP_START) / (RAMP_END - RAMP_START), 0, 1)[..., None]
    ramp = cyan[None, None] * (1 - t) + blue[None, None] * t
    recoloured = ramp * mx[..., None]
    check = mask & (alpha > 127)
    diff = np.abs(recoloured[check] * 255 - source[..., :3][check])
    print(
        f"recolour: max abs rgb diff={diff.max():.2f}/255 "
        f"mean={diff.mean():.2f} over {check.sum()} px (alpha>0.5, shadow)"
    )
    print(f"endpoints: cyan={np.round(cyan * 255).astype(int)} "
          f"blue={np.round(blue * 255).astype(int)}")


def run(
    src: pathlib.Path,
    foreground_path: pathlib.Path,
    shadow_path: pathlib.Path,
    label: str,
    *,
    value_min: float | None = None,
    expected_size: tuple[int, int] | None = None,
) -> None:
    image = Image.open(src).convert("RGBA")
    if expected_size is not None and image.size != expected_size:
        raise SystemExit(f"expected a {expected_size} canvas, got {image.size}")
    source = np.asarray(image)
    mask = shadow_mask(source, value_min)
    foreground, shadow = split(source, mask)
    Image.fromarray(foreground, "RGBA").save(foreground_path)
    Image.fromarray(shadow, "RGBA").save(shadow_path)
    verify(source, foreground, shadow, mask, label)
    if value_min is None:
        verify_ramp(source, mask)
    print(f"wrote {foreground_path.relative_to(ROOT)}")
    print(f"wrote {shadow_path.relative_to(ROOT)}")


def main() -> None:
    run(DARK_SRC, DARK_FOREGROUND, DARK_SHADOW, "dark", expected_size=(512, 512))
    run(LIGHT_SRC, LIGHT_FOREGROUND, LIGHT_SHADOW, "light", value_min=LIGHT_VALUE_MIN)


if __name__ == "__main__":
    main()
