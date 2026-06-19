# Settings

The largest feature area (~103 files). Split into two persistence tiers: **client-local** (SharedPreferences) and **server-side** (Suwayomi GraphQL mutations).

## Structure & routing

Entry is the "More" tab (`more_screen.dart`, a shell-nav destination) — it inlines `ServerUrlTile` + `AppThemeModeTile`, then links to `BackupRoute` and `SettingsRoute`. `SettingsScreen` is the hub for eight sections:

| Section | Screen |
|---|---|
| General | `presentation/general/general_screen.dart` |
| Appearance | `presentation/appearance/` (see [theming-l10n.md](theming-l10n.md)) |
| Library | `presentation/library/library_settings_screen.dart` |
| Downloads | `presentation/downloads/downloads_settings_screen.dart` |
| Reader | `presentation/reader/reader_settings_screen.dart` |
| Browse | `presentation/browse/browse_settings_screen.dart` |
| Backup & Restore | `presentation/backup/backup_screen.dart` |
| Server | `presentation/server/server_screen.dart` |

## Notable subsystems

- **Server connection** (`server/widget/client/`): `serverUrlProvider` (web defaults to `Uri.base.origin`, strips trailing `/`), `serverPortProvider` + `serverPortToggleProvider` (port appended to URLs only when toggle on), `ServerSearchButton` (LAN /24 scan via `network_info_plus` + `Socket.connect`). **Timeout settings live in General**, not Server (`serverRequestTimeout` 5000ms, `autoRefreshOnTimeout`, `autoRefreshRetryDelay` 1000ms).
- **Authentication** (`server/widget/authentication/` + `credential_popup/`): see [auth.md](auth.md). Auth type in SharedPreferences; credentials in secure storage; Test Connection surfaces typed failures.
- **Server screen** (GraphQL-backed): `ServerBindingSection`, `SocksProxySection`, `CloudFlareSection`, `MiscSettingsSection` — all watch `settingsProvider` and only render when `valueOrNull != null`; mutations return `SettingsDto` → `updateState(result)`.
- **Backup & Restore**: manual create (flags + returns URL) / restore (file picker → validate → missing-sources dialog → async restore polled via `RestoreStatusProgress`); automatic backup (server-side path/time/interval/TTL).
- **Reader/Library/Downloads/Browse settings**: Reader is all client-local (~14 tiles); Library/Downloads/Browse are mostly server-side via `settingsProvider`.

## Persistence (two tiers)

**Client-local:** the `DBKeys` + `SharedPreference[Enum]ClientMixin` pattern — see [shared-infrastructure.md](shared-infrastructure.md). `DBKeys` is the single registry; key string = enum case `.name`.

**Server-side:** fetch once via `Query$ServerSettings` → `settingsProvider`; each typed `setSettings` mutation returns the full `SettingsDto` → `settingsProvider.notifier.updateState(result)` (no refetch). DTOs are `typedef`s over codegen fragments.

`SettingsPropTile` is the universal tile (a `SettingsPropType` union: textField / numberPicker / numberSlider / switchTile).

## Gotchas

- **Two distinct "server port" concepts:** `serverPortProvider` (client connects TO, SharedPreferences, default 4567) vs `ServerBindingSection` (the port the server LISTENS ON, GraphQL). Independent.
- **`serverPortToggleProvider` is architecture-critical** — it globally gates whether the port is appended to all API URLs (`Endpoints.baseApi(..., addPort:)`). Defaults `true` (non-web).
- **`backup_settings_repository.dart:47` copy-paste bug** — `includeChapters` is set to `includeCategories`; the user's `includeChapters` choice is never sent.
- **`reader_continuous_reading_tile.dart` is an empty (0-byte) file** — dead placeholder.
- **`more_screen.dart` ≠ `settings_screen.dart`** — MoreScreen is a main tab with its own inline URL/theme tiles (same providers as the Server section).
- **Server-side sections silently show nothing if the server is offline** (no error UI).
