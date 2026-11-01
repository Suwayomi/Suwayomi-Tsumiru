# Tsumiru brand assets

The approved SVGs are the source of truth:

| File | Use |
|---|---|
| `tsumiru-mark.svg` | Transparent cream mark for dark surfaces, splash, logo layers and the Android notification icon. |
| `tsumiru-mark-on-light.svg` | Transparent ink mark for light surfaces and logo layers. |
| `tsumiru-icon.svg` | Round icon for desktop, Flatpak and the organisation avatar. |
| `tsumiru-icon-fullbleed.svg` | Full-bleed icon for iOS, web and Android legacy; gradient background and mark for Android adaptive icons. |

The PNGs in this folder are generated; edit the SVGs instead.

Rendering needs `rsvg-convert` (librsvg). Regenerate raster sources, then platform icons and splash assets:

```sh
uv run tool/render_brand.py
fvm dart run flutter_launcher_icons
fvm dart run flutter_native_splash:create
```

Shadow layers store luminance as greyscale remapped into [0.88, 1.00], with the
brightest shadow pixel at 255, retaining alpha for the widget's theme tint. Foreground layers retain the SVG colours.
`tsumiru-social-card.png` is maintained separately.
