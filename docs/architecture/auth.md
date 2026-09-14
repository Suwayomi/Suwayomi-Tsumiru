# Auth

> Security-sensitive subsystem. Read the gotchas before changing anything here.

## Purpose

Pluggable authentication for all traffic (queries, mutations, subscriptions, image fetches) to a Suwayomi-Server. Four modes: `none`, `basic`, `simpleLogin`, `uiLogin` (JWT), with token refresh, proactive expiry rotation, secure storage, and a reauth banner.

## Key files

| Path | Responsibility |
|---|---|
| `features/auth/data/auth_state.dart` | `NeedsReauth` notifier (keepAlive bool) — set on 401 death, cleared on reauth |
| `features/auth/data/auth_credentials_store.dart` | `AuthCredentialsStore` AsyncNotifier — in-memory snapshot, writes through to secure storage |
| `features/auth/data/secure_credentials_provider.dart` | Thin wrapper over `FlutterSecureStorage` (`encryptedSharedPreferences: true` on Android) |
| `features/auth/data/suwayomi_auth_link.dart` | GraphQL `Link` — injects headers, handles 401 → refresh → retry (ui) / reauth signal (simple) |
| `features/auth/data/auth_coordinator.dart` | `AuthCoordinator` — login, refresh, test-connection, proactive-refresh Timer, single-flight `Completer` |
| `features/auth/data/simple_login_client.dart` | Raw client POSTing `/login.html`, returns the `JSESSIONID` |
| `features/auth/data/jwt_utils.dart` | `decodeJwtExp()` — parses JWT `exp` (no signature verification; for Timer sizing only) |
| `features/auth/data/auth_lifecycle_observer.dart` | On app resume, refresh if due (covers Android Doze Timer gaps) |
| `features/auth/data/basic_auth_migration.dart` | One-shot legacy basic-auth → secure storage migration |
| `features/auth/presentation/reauth_banner.dart` | `ReauthBannerHost` — shows/clears a `MaterialBanner` on `needsReauthProvider` |
| `.../settings/.../authentication/` + `credential_popup/` | Auth-type picker, credentials entry, Test Connection, logout |

## Modes & credential injection

| Mode | HTTP | WebSocket | Images |
|---|---|---|---|
| `none` | — | — | — |
| `basic` | `AuthLink`: `Authorization: Basic …` | WS handshake header | header |
| `simpleLogin` | `SuwayomiAuthLink`: `Cookie: JSESSIONID=…` | WS handshake header | cookie header |
| `uiLogin` | `SuwayomiAuthLink`: `Authorization: Bearer <jwt>` | WS `initialPayload` `{Authorization: <bare token>}` | `?token=` query param |

`AuthType` is stored in SharedPreferences (`DBKeys.authType`); username in SharedPreferences (`DBKeys.authUsername`). **Credentials go to `flutter_secure_storage`**: `auth.password`, `auth.simple.cookie`, `auth.ui.accessToken`, `auth.ui.refreshToken`, `auth.ui.accountBinding`, `auth.basic.credentials`.

## Token lifecycle (ui_login)

- `uiAccessTokenExpiresAt` derived from JWT `exp` on every set; **not persisted** (recomputed on `build()`).
- **Proactive refresh:** `AuthCoordinator` schedules a Timer at `exp − 60s` (capped 24h). Transient failure → backoff `[30s,60s,120s,300s]`. Auth failure → clear tokens, set `NeedsReauth`. App-resume observer covers Doze gaps.
- **On-demand (401 path in `SuwayomiAuthLink`):** detect 401 → (`simpleLogin`: call reauth immediately; `uiLogin`: `refreshUiAccessToken()`) → single-flight via file-static `Completer` → refresh via a **raw un-authed client** → on success retry once (retry 401 → reauth); auth-failure → clear + reauth; transient → yield original 401.
- **Reauth flow:** `NeedsReauth=true` → `ReauthBannerHost` banner → `LoginCredentialsPopup` → coordinator login → `NeedsReauth=false`.

## Gotchas (security-sensitive)

- Refresh single-flight is keyed by `AuthCredentialsStore`: coordinator invalidation preserves the same flight, while a replacement application container receives an independent one. Tests call `debugResetAuthCoordinatorSingleFlight()` in `setUp`.
- **Bare token in WS `connection_init`** (`{Authorization: <token>}`, no "Bearer ") — adding the prefix silently breaks subscriptions. Differs from the HTTP header.
- **Simple Login leaks server-side sessions on Test Connection** — `POST /login.html` always creates a session; discarding the cookie doesn't destroy it; no logout-without-cookie endpoint.
- **`decodeJwtExp` does NOT verify the signature** — intentional (expiry is for Timer sizing only; the server enforces access).
- **`uiAccessTokenExpiresAt` not persisted** — if the JWT is malformed, expiry is null and no proactive Timer is scheduled (refresh only happens reactively on 401).
- **Migrated basic creds live under `auth.basic.credentials`**, tracked by a separate `credentialsProvider`, not `AuthCredentialsState`. Logout must call `clearBasicCredentials()` or they persist invisibly.
- **Refresh client must stay un-authed** — if it ever gains a `SuwayomiAuthLink`, refresh recurses infinitely.
- **`isLocalAddress` suppresses the insecure-transport warning** for `localhost`/`127.x`/`10.x`/`172.16–31.x`/`192.168.x` only.

## Account session boundary

`AuthCredentialsStore.withIdentityChange` closes request admission before credentials change and publishes a new session generation when the transition ends. HTTP and subscription clients follow that generation. Retained clients reject new requests and late responses once their session has ended; token refresh alone preserves the clients.

Login and credential checks use `unauthenticatedGraphQlClientProvider`. It includes proxy headers but excludes stored account credentials, because the multi-user server rejects login requests from an already authenticated caller.

Credential replacement and explicit logout enter this boundary at the store, including direct calls. Worker refresh uses a separate operation that requires the original refresh token; worker records also carry the originating authorization epoch and catalogue ID. A stale worker cannot replace the current login.

LAN/remote address failover preserves the session. The HTTP transport checks the captured session before endpoint resolution, after resolution and before every send, including delayed retries.

UI Login verifies the current account and its catalogue identity before saving credentials. The secure account binding includes the token pair, so an interrupted write cannot attach an old catalogue owner to new credentials. Refresh preserves the binding; replacement without a verified owner clears it. Login attempts retain the server address and write epoch captured before verification.

## Accounts and permissions

More → Account shows the signed-in account, password action, permissions and retained device catalogues. UI Login uses the current server's account API. An exact missing-account-field response identifies an older server; loading, failed or cached account results do not grant privileged access. See `features/account/data/account_providers.dart` and `domain/account_access.dart`.

The account screen presents nine operational grants: install extensions, install external extensions, uninstall extensions, download chapters, manage settings, manage users, manage extension stores, manage source preferences and manage cache. The unfinished NSFW grant is not shown. Reading chapters is not a download grant: the server's page-reading endpoint can remain available when `DOWNLOAD_CHAPTERS` is denied. Download entry points therefore check that grant separately. See `presentation/account_permission_labels.dart` and `features/offline/data/offline_download_permission.dart`.

Manage users requires supported accounts and current `MANAGE_USERS` access. It provides paged username search, direct creation, permission replacement, and registration/recovery code creation and revocation. Only ADMIN can change USER/ADMIN roles; other managers omit roles from updates. Built-in user 1 has immutable administration controls. Codes are shown once after issuance, with copy and expiry; revocation requires confirmation. The server has no user-deletion operation. See [Account administration](account-administration.md).

Personal password changes verify the original account before adopting replacement tokens. Built-in user 1 changes the configured `authPassword` through server settings; ordinary accounts use the account password mutation. The built-in path confirms a new login after the settings change and rejects leading or trailing whitespace. Both paths retain the original session/account checks across asynchronous work. See `features/account/data/account_actions.dart`.

Signing out or replacing an account closes request admission and drains foreground and background storage work before switching the active device catalogue. Once the old storage is detached, the transition invalidates all six database stream providers, including their family instances, before awaiting database closure. This releases subscriptions paused by hidden routes. Retained catalogues remain separate from the new account's library and read state. Server chapter files are shared server storage; device copies and their catalogue belong to the verified account. See [Offline reading](offline.md).
