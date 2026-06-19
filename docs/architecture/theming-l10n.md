# Theming & Localization

## Theming (current state)

`Sorayomi.build()` constructs both `theme:` and `darkTheme:` inline via `FlexThemeData.light/dark(scheme: appScheme, useMaterial3: true, useMaterial3ErrorColors: true)`, then `.copyWith(appBarTheme: AppBarTheme(centerTitle: false), tabBarTheme: TabBarThemeData(tabAlignment: center))`.

- `appScheme` — a `FlexScheme` enum from `appSchemeProvider` (default `FlexScheme.material`). The picker iterates the **full** `FlexColor.schemes` set — there is no curated palette or seed color.
- `darkIsTrueBlack` — from `isTrueBlackProvider` (default `false`), passed only to `FlexThemeData.dark`.
- `themeMode` — `appThemeModeProvider` (default `ThemeMode.system`).
- No `ColorScheme.fromSeed`, no Material You / dynamic color.

> A redesign to a curated branded named-theme system (Indigo Night + Carbon + Plum + custom seed) is planned — see the vault plans. This doc reflects the current flex_color_scheme implementation.

## Appearance settings

`AppearanceScreen` (`features/settings/presentation/appearance/`) is a `ListView` of four controls:

| Widget | Provider | DBKey | Default |
|---|---|---|---|
| `AppThemeModeTile` | `appThemeModeProvider` | `themeMode` | `ThemeMode.system` |
| `IsTrueBlackTile` | `isTrueBlackProvider` | `isTrueBlack` | `false` (shown only when mode ≠ Light) |
| `AppThemeSelector` | `appSchemeProvider` | `flexScheme` | `FlexScheme.material` |
| `GridCoverWidthSlider` | `gridMinWidthProvider` | `gridMangaCoverWidth` | `192.0` |

The **language** picker is in **General** settings (`l10nProvider` / `DBKeys.l10n`), not Appearance.

All five providers use `SharedPreference[Enum]ClientMixin` and live in the same file as their widget (`part 'foo.g.dart'`).

## Localization

Config (`l10n.yaml`): `arb-dir: lib/src/l10n`, `template-arb-file: app_en.arb`, `output-dir: lib/src/l10n/generated`, `synthetic-package: false` (generated files committed).

- 27 ARB locales; English is the source of truth. New locales arrive via Weblate post-merge.
- Generate with `flutter gen-l10n` (manual / not auto-run by build_runner) → `app_localizations_<lang>.dart`.
- Wired in `Sorayomi` via `AppLocalizations.localizationsDelegates` + `supportedLocales`; `locale:` is `ref.watch(l10nProvider)` (nullable → OS default).
- Access in widgets: `context.l10n.someKey` (`context_extensions.dart`: `AppLocalizations.of(this)!`).
- Locale persisted as a JSON map (`{languageCode, scriptCode?, countryCode?}`) under `DBKeys.l10n`.

## Gotchas

- **True black is dark-only** — `darkIsTrueBlack` is passed only to the dark theme; toggling it in light mode persists but does nothing visible.
- **`appTitle` in `app_en.arb` is already "Tsumiru"** — the rebrand lives in l10n too, not just the app name.
- **`synthetic-package: false`** — regenerate l10n manually (`flutter gen-l10n`) after ARB changes; build_runner does not.
- **`copyWith` overrides** (`centerTitle: false`, `tabAlignment: center`) are applied after `FlexThemeData` — any future theme work that conflicts must also use `copyWith`.
- **`FlexScheme.material` is the default but not necessarily first in the picker** — the picker scrolls all `FlexColor.schemes.keys` in insertion order; the highlight is by equality.
