# Theming & Localization

## Theming

Tsumiru ships a **curated, branded named-theme system** (replacing the old
`flex_color_scheme` picker). Every colour is explicit — Material never generates
a palette. The source of truth is the external **theme-kit**
(`~/Projects/theme-kit/themes/<id>.css`, mirrored token-for-token); the in-repo
Dart copies its `[data-mode='dark']` and
`[data-theme='<id>'][data-mode='light']` blocks verbatim.

### Layers

`Sorayomi.build()` sets `theme:`/`darkTheme:` to `buildAppTheme(...)` and
`themeMode:` to `appThemeModeProvider`. The construction stack:

| File | Responsibility |
|---|---|
| `constants/app_theme.dart` | `AppTheme` enum (the curated set + `custom`) + `swatch` (picker preview accents) + `AppThemeLabel.label()`. |
| `utils/theme/theme_tokens.dart` | `ThemeTokens` (bg, bg2, ink, muted, faint, accent, accent2, danger, border) plus the light-only `onAccent`, `accentBg` and `grad` — one **dark** + one **light** const per theme. `tokensFor(AppTheme, Brightness)` resolves them. Both brightnesses are theme-kit verbatim: dark from the `[data-mode='dark']` block, light from the `[data-mode='light']` block. |
| `utils/theme/app_color_scheme.dart` | `schemeFromTokens(tokens, brightness)` builds an **explicit** Material 3 `ColorScheme` — no `ColorScheme.fromSeed`. Surfaces map straight to `bg`/`bg2`, `surfaceTint: Colors.transparent` (no elevation tinting). The light-only tokens feed the accent roles: `onAccent` becomes `onPrimary`/`onSecondary`/`onTertiary`, `accentBg` the container roles. Dark themes name neither, so those roles keep their derived fallbacks (an accent-over-`bg` lerp, and black-or-white chosen by the accent's own brightness). `grad` never reaches the scheme; `buildAppTheme` hands it to `BrandColors`. `applyAmoled(scheme)` post-processes a dark scheme to near/true black. |
| `utils/theme/app_theme_builder.dart` | `buildAppTheme({theme, brightness, customSeed, amoled})` — the single global `ThemeData`. Named themes → `schemeFromTokens`; `custom` → `ColorScheme.fromSeed(customSeed)`. Sets every component theme (appBar, navigationBar/Rail, listTile, card, divider, chip, switch, slider, FAB, filled/elevated/outlined/text buttons) from the scheme. The chip theme branches on brightness: light themes get an outlined unselected chip and an `accentBg`-tinted selected one with an accent border, dark keeps the primary-tinted fill. |
| `utils/theme/brand.dart` | The **brand component layer** — the gradient/glow things `ThemeData` cannot express. See below. |

### Brand component layer (`brand.dart`)

Material `ButtonStyle` can't express a gradient, so brand visuals live in
reusable widgets driven by the active theme. **Do not inline gradients/colours
at call sites — use these.**

- **`BrandColors`** — a `ThemeExtension` carrying the active theme's gradient and
  the colour to draw on it, registered by `buildAppTheme`. It holds `gradient`
  (the theme's `--grad`, or `schemeBrandGradient` when it has none), `onGradient`,
  `success` (`brandSuccessColor`) and `neutral` (true for Monochrome light: genre
  chips and the cover backdrop drop their hues). Read it with
  `BrandColors.of(context)`, which falls back to `schemeBrandGradient` plus dark
  ink when no extension is installed (widget tests).
- `schemeBrandGradient(cs)` — the fallback gradient for a theme with no `--grad`
  (every dark set, plus Custom): 135°, `primary`→`secondary`.
- `brandGlow(cs)` — the `--glow` soft shadow (primary @ 0.35).
- `brandBrightAccent(cs)` — lighter accent for text/outline actions; light mode
  keeps the deep `primary`, since lightening it would undo its contrast.
- `brandStarColor(brightness)` — star-rating colour: amber on dark, a darker
  amber on light.
- `OnImage` — colours for content drawn on the cover art rather than the theme
  surface (`text`, `shadow`, `scrim`). Theme-independent on purpose: the art
  underneath is, so these must not follow light/dark.
- `brandHueFor(label)` — deterministic hue from a string (per-genre chip colour).
- `brandGradientIcon(context, icon)` — ShaderMask gradient icon (downloaded check).
- Components: **`BrandButton`** (gradient pill + glow + dark text; the shared
  `AsyncElevatedButton` renders this), **`BrandGlassButton`** (glass + bright
  accent), **`BrandFab`** (gradient FAB — Update + Resume), **`BrandChip`**
  (genre chip, unique per-genre colour via `brandHueFor`).

### Themes shipped (13 + Custom)

Indigo Night *(default)* · Carbon · Plum · Regression · Ember · Synthwave ·
Terminal · Catppuccin Mocha · Nord · Gruvbox · Dracula · Monochrome · Royal —
plus **Custom** (user seed colour → `ColorScheme.fromSeed`).

> `AppTheme` values are **persisted by index** (`SharedPreferenceEnumClientMixin`
> stores `enumList.indexOf`). New themes are therefore **appended after `custom`**
> so existing users' stored indices (indigoNight 0 / carbon 1 / plum 2 / custom 3)
> never remap. The picker renders named themes first and `custom` last regardless
> of enum order.

### Guards

- `test/theme/no_hardcoded_colors_test.dart` fails on a literal colour
  (`Colors.<name>`, `Color(0x…)`, `Color.fromARGB`, `Color.fromRGBO`) anywhere in
  `lib/` app UI except `Colors.transparent`. Generated
  files and `lib/src/utils/theme/` are exempt, and an entries-with-reason
  allowlist covers the files whose literals are deliberate (nav vectors, reader
  canvases, cover overlays, theme swatches).
- `test/src/utils/theme/light_contrast_test.dart` asserts every light scheme
  clears WCAG ratios: `onSurface`/`surface` 7:1; `onSurfaceVariant`, `primary`,
  `onPrimary`, `onSecondaryContainer` and `error` against their surfaces 4.5:1;
  `outline` 3:1; and `onAccent` 4.5:1 against every `grad` stop.

## Appearance settings

`AppearanceScreen` (`features/settings/presentation/appearance/`) is the single
home for all visual settings:

| Widget | Provider | DBKey | Default |
|---|---|---|---|
| `AppThemeModeTile` | `appThemeModeProvider` | `themeMode` | `ThemeMode.system` |
| `IsTrueBlackTile` (Pure black / AMOLED) | `isTrueBlackProvider` | `isTrueBlack` | `false` (mode ≠ Light) |
| `ThemeSelector` (curated picker) | `appThemeKeyProvider` | `appTheme` | `AppTheme.indigoNight` |
| Custom colour tile | `customThemeColorProvider` | `customThemeColor` | `0xFF7C7BFF` (only when theme == custom) |
| `GridCoverWidthSlider` | `gridMinWidthProvider` | `gridMangaCoverWidth` | `192.0` |

`ThemeSelector` previews each card at the brightness currently in use, so light
mode does not show a wall of dark cards. Give it a `title` and the header row
carries that title plus ‹ › arrows, shown only while the cards overflow. Card
width is computed from the viewport so the row always ends on a half card, which
shows it scrolls at any width.

The **More** screen no longer carries a duplicate theme-mode tile; it has a
single **Appearance** shortcut (`AppearanceSettingsRoute`) for one-tap access.
This matches the Mihon/Komikku convention (More = hub, theming under Appearance).
The **language** picker is in **General** settings (`l10nProvider` / `DBKeys.l10n`).

## Localization

Config (`l10n.yaml`): `arb-dir: lib/src/l10n`, `template-arb-file: app_en.arb`,
`output-dir: lib/src/l10n/generated`, `synthetic-package: false` (generated files committed).

- 27 ARB locales; English is the source of truth. New locales arrive via Weblate post-merge.
- Generate with `flutter gen-l10n` (manual / not auto-run by build_runner).
- Wired in `Sorayomi` via `AppLocalizations.localizationsDelegates` + `supportedLocales`; `locale:` is `ref.watch(l10nProvider)` (nullable → OS default).
- Access in widgets: `context.l10n.someKey`.
- New theme display names use plain string literals in `AppThemeLabel.label()` (proper nouns / brand names — not localized); the original three still use l10n keys.

## Gotchas

- **Flutter web canvaskit lifts dark colours on wide-gamut (P3) displays** — the
  WebGL canvas isn't colour-managed like DOM, so `#0b0d1a` renders ~`(19,21,32)`
  instead of `(11,13,26)` in the web build on a P3 monitor. **Native (Android/Linux)
  renders correctly.** Judge final colour on a native build, NOT the web preview.
  There is no app-level fix (the DOM `html` renderer is gone; canvaskit + skwasm
  are both Skia-over-WebGL). `web/index.html` carries a best-effort
  `drawingBufferColorSpace='display-p3'` patch.
- **No `ColorScheme.fromSeed` for named themes** — surfaces are exact tokens; a
  Material elevation/tonal overlay would dull the brand colour. `surfaceTint` is
  transparent everywhere; badges use a flat `ColoredBox`, not a `Card`.
- **AMOLED is dark-only** — `applyAmoled` runs only on the dark scheme.
- **Index-based theme persistence** — never reorder `AppTheme`; only append.
- **`synthetic-package: false`** — regenerate l10n manually (`flutter gen-l10n`) after ARB changes.
