# Theming & Localization

## Theming

Tsumiru ships a **curated, branded named-theme system** (replacing the old
`flex_color_scheme` picker). Every colour is explicit — Material never generates
a palette. The source of truth for the dark hexes is the external **theme-kit**
(`~/Projects/theme-kit/themes/<id>.css`, mirrored token-for-token); the in-repo
Dart mirrors those values verbatim.

### Layers

`Sorayomi.build()` sets `theme:`/`darkTheme:` to `buildAppTheme(...)` and
`themeMode:` to `appThemeModeProvider`. The construction stack:

| File | Responsibility |
|---|---|
| `constants/app_theme.dart` | `AppTheme` enum (the curated set + `custom`) + `swatch` (picker preview accents) + `AppThemeLabel.label()`. |
| `utils/theme/theme_tokens.dart` | `ThemeTokens` (bg, bg2, ink, muted, faint, accent, accent2, danger, border) — one **dark** + one **light** const per theme. `tokensFor(AppTheme, Brightness)` resolves them. Dark = theme-kit verbatim; light = hand-designed (contrast-adjusted accents; Catppuccin Latte / Nord Snow-Storm where they exist). |
| `utils/theme/app_color_scheme.dart` | `schemeFromTokens(tokens, brightness)` builds an **explicit** Material 3 `ColorScheme` — no `ColorScheme.fromSeed`. Surfaces map straight to `bg`/`bg2`, `surfaceTint: Colors.transparent` (no elevation tinting). `applyAmoled(scheme)` post-processes a dark scheme to near/true black. |
| `utils/theme/app_theme_builder.dart` | `buildAppTheme({theme, brightness, customSeed, amoled})` — the single global `ThemeData`. Named themes → `schemeFromTokens`; `custom` → `ColorScheme.fromSeed(customSeed)`. Sets every component theme (appBar, navigationBar/Rail, listTile, card, divider, chip, switch, slider, FAB, filled/elevated/outlined/text buttons) from the scheme. |
| `utils/theme/brand.dart` | The **brand component layer** — the gradient/glow things `ThemeData` cannot express. See below. |

### Brand component layer (`brand.dart`)

Material `ButtonStyle` can't express a gradient, so brand visuals live in
reusable widgets driven by the active `ColorScheme` (so every theme recolours
them for free). **Do not inline gradients/colours at call sites — use these.**

- `brandGradient(cs)` — the `--grad` (135°, `primary`→`secondary`).
- `brandGlow(cs)` — the `--glow` soft shadow (primary @ 0.35).
- `onBrandGradient` (`#0B0D1A`) — dark content colour on the bright gradient.
- `brandBrightAccent(cs)` — lighter accent for text/outline actions.
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
