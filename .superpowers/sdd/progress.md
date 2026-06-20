# Theming build — progress ledger
Plan: ~/Documents/vault/sorayomi/plans/2026-06-19-theming-brand-identity-plan.md
Branch: theming (base d1a785f)

Task 1: complete (commit b1a9e29, 3 tests pass) — AppTheme enum + tokens
Task 2: complete (commit a475050, 2 tests pass) — ColorScheme builder
Task 3: complete (commit bccf390, 3 tests pass) — AMOLED transform
Task 4: complete (commit 5c1dcc5, 3 tests pass) — buildAppTheme
Logic layer (Tasks 1-4): reviewed clean. Minor (defer to final): app_theme_builder_test.dart:45-46 deprecated Color.red/.blue; app_theme.dart swatch custom placeholder comment.
Task 5: complete (commit 4d12659, 2 tests pass) — DBKeys appTheme+customThemeColor, providers (appThemeKeyProvider/customThemeColorProvider). Note: .g.dart gitignored, not committed.
Task 6: complete (commit 2b42155, analyze clean) — sorayomi.dart wired to buildAppTheme
Task 7: complete (commit c3d8e31, 101 tests pass, analyze clean) — Appearance UI: ThemeSelector + CustomColorTile + AMOLED relabel; flex_color_picker 3.7.1 added
Integration (Tasks 5-7): reviewed clean; Indigo Night migration verified. Minor (defer to final polish): dead l10n key appThemeTitle (render as picker header or drop); app_theme_selector.dart custom-picker update after async gap lacks context.mounted guard.
Task 8: complete (commit f23c84a, grep clean, 101 tests pass) — retired flex_color_scheme (+ router_config.dart leftover)
Polish: complete (commit 560541f) — section header (SectionTitle), async-gap guard, deprecated color accessors, swatch comment
Theme color-fidelity fix: surfaces now use exact bg/bg2 from theme-kit; no fromSeed for named themes.
Hero backdrop: blurred/faded cover glow behind manga-detail header, gradient-fades into surface (Komikku-style).
