# /// script
# dependencies = ["pillow"]
# ///
"""Render brand raster sources from the approved SVG artwork."""

import copy
import io
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "design/brand"
NS = "{http://www.w3.org/2000/svg}"
ET.register_namespace("", NS[1:-1])


def svg(name):
    return ET.parse(BRAND / name).getroot()


def render(art, size):
    result = subprocess.run(
        ["rsvg-convert", "--width", str(size), "--height", str(size)],
        input=ET.tostring(art), capture_output=True, check=True,
    )
    return Image.open(io.BytesIO(result.stdout)).convert("RGBA")


def save(path, image):
    image.save(ROOT / path, compress_level=9)
    print(path, f"{image.width}x{image.height}")


def fitted(art, box):
    art = copy.deepcopy(art)
    left, top, right, bottom = render(art, 1024).getchannel("A").getbbox()
    x, y, width, height = box
    scale = min(width / (right - left), height / (bottom - top))
    tx = x + (width - (right - left) * scale) / 2 - left * scale
    ty = y + (height - (bottom - top) * scale) / 2 - top * scale
    group = ET.Element(NS + "g", {"transform": f"translate({tx} {ty}) scale({scale})"})
    for child in list(art):
        if child.tag != NS + "defs":
            art.remove(child)
            group.append(child)
    art.append(group)
    art.set("viewBox", "0 0 1024 1024")
    return art


def greyscale_shade(image):
    alpha = image.getchannel("A")
    shade = image.convert("RGB").convert("L")
    brightest = max(value for value, count in enumerate(shade.histogram(mask=alpha)) if count)
    shade = shade.point(lambda value: round(255 * .88 + .12 * value * 255 / brightest))
    return Image.merge("RGBA", (shade, shade, shade, alpha))


def main():
    if shutil.which("rsvg-convert") is None:
        raise SystemExit("rsvg-convert is required; install librsvg to render brand assets.")
    mark = fitted(svg("tsumiru-mark.svg"), (192, 216, 694, 638))
    light = fitted(svg("tsumiru-mark-on-light.svg"), (192, 216, 696, 640))
    round_icon = svg("tsumiru-icon.svg")
    fullbleed = svg("tsumiru-icon-fullbleed.svg")
    for path, art, size in [
        ("design/brand/tsumiru-mark-transparent.png", mark, 1024),
        ("design/brand/tsumiru-icon-fullbleed.png", fullbleed, 1254),
        ("design/brand/tsumiru-org-avatar.png", round_icon, 512),
        ("assets/icons/launcher/tsumiru_icon.png", fullbleed, 1024),
        ("assets/icons/launcher/tsumiru_icon_rounded.png", round_icon, 1024),
        ("assets/icons/launcher/splash_icon.png", mark, 1024),
        ("assets/icons/dark_icon.png", mark, 512),
        ("assets/icons/logo_on_light.png", light, 512),
        ("flatpak/app.tsumiru.Tsumiru.png", round_icon, 512),
        ("flatpak/io.github.aaronbamblett.tsumiru.png", round_icon, 512),
    ]:
        save(path, render(art, size))
    desktop = Image.new("RGBA", (1024, 1024))
    desktop.alpha_composite(render(round_icon, 826), (99, 99))
    save("assets/icons/launcher/tsumiru_icon_desktop.png", desktop)

    background = copy.deepcopy(fullbleed)
    background.remove(background.find(NS + "g"))
    save("assets/icons/launcher/tsumiru_icon_bg.png", render(background, 1024))
    foreground = copy.deepcopy(fullbleed)
    foreground.remove(foreground.find(NS + "rect"))
    scale = 66 / 108  # Android adaptive icon safe zone: 66dp of the 108dp layer
    group = foreground.find(NS + "g")
    wrapper = ET.Element(NS + "g", {
        "transform": f"translate(256 256) scale({scale}) translate(-256 -256)"
    })
    foreground.remove(group)
    wrapper.append(group)
    foreground.append(wrapper)
    save("assets/icons/launcher/tsumiru_icon_fg.png", render(foreground, 1024))

    for art, prefix, size in [(mark, "logo", 512), (light, "logo_on_light", 512)]:
        for name in ("foreground", "shadow"):
            isolated = copy.deepcopy(art)
            isolated_group = isolated.find(NS + "g")
            for child in list(isolated_group):
                if child.get("id") != name:
                    isolated_group.remove(child)
            image = render(isolated, size)
            if name == "shadow":
                image = greyscale_shade(image)
            save(f"assets/icons/{prefix}_{name}.png", image)

    silhouette = svg("tsumiru-mark.svg")
    for group in silhouette.findall(NS + "g"):
        group.set("fill", "#ffffff")
    silhouette = fitted(silhouette, (85, 117, 864, 789))
    for density, size in [("mdpi", 24), ("hdpi", 36), ("xhdpi", 48),
                          ("xxhdpi", 72), ("xxxhdpi", 96)]:
        save(f"android/app/src/main/res/drawable-{density}/ic_stat_tsumiru.png",
             render(silhouette, size))


if __name__ == "__main__":
    main()
