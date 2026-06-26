# Tsumiru Architecture

Tsumiru is a Flutter client for [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) (the Tachidesk backend) — a manga/manhwa reader that runs on Android, Linux, Windows, macOS, and Web. It is its own application (published at `tsumiru-app/tsumiru`), originally based on [Tachidesk-Sorayomi](https://github.com/Suwayomi/Tachidesk-Sorayomi), focused on being a great daily-driver, especially for webtoon/manhwa reading.

This directory documents how the app is built and how each subsystem works, so contributors (human or AI) can orient quickly and change code safely.

## Read this first

- **[repo-build-release.md](repo-build-release.md)** — remotes, the branch model, the release flow, and the version scheme. **`tsumiru-app/tsumiru` `main` (remote `tsumiru`) is canonical.** Always `git fetch tsumiru` and verify your base against it and the latest release before building or branching.

## Subsystem maps

| Doc | Covers |
|---|---|
| [overview.md](overview.md) | Tech stack, layered structure, the conventions every feature reuses |
| [app-shell-navigation.md](app-shell-navigation.md) | App bootstrap, `go_router` route tree, the nav shell (rail vs bottom bar) |
| [onboarding.md](onboarding.md) | The first-run wizard, LAN discovery + the connection resolver, the onboarding-complete router gate |
| [data-layer.md](data-layer.md) | GraphQL clients, the repository pattern, Riverpod + codegen, `DBKeys`, image/auth plumbing |
| [theming-l10n.md](theming-l10n.md) | Curated named-theme system (`AppTheme` + theme-kit tokens + brand component layer), Appearance settings, localization |
| [auth.md](auth.md) | Auth modes (none/basic/simpleLogin/uiLogin), token lifecycle, the GraphQL auth link |
| [reader.md](reader.md) | Reader modes, the webtoon/infinity continuous scroll, pinch-to-zoom |
| [library.md](library.md) | Categories, sort/filter/display, badges |
| [manga-details-downloads.md](manga-details-downloads.md) | Manga details, chapter list + actions, the download queue |
| [offline.md](offline.md) | On-device catalog, the download pipeline + background service, keep-rules, server-unreachable read fallback |
| [browse-sources-extensions.md](browse-sources-extensions.md) | Extensions, sources, source browsing, global search |
| [settings.md](settings.md) | The settings sections, server connection, backup & restore, the two-tier persistence model |
| [other-features.md](other-features.md) | about/update-check, history, migration, quick_open |
| [shared-infrastructure.md](shared-infrastructure.md) | `constants/`, `utils/`, shared `widgets/`, the conventions reused everywhere |

## How these docs are maintained

These maps describe the code as of the `docs-architecture` work (June 2026). When you change a subsystem materially, update its doc in the same PR. Gotchas and "non-obvious things" sections are the highest-value content — keep them current.
