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

`AuthType` is stored in SharedPreferences (`DBKeys.authType`); username in SharedPreferences (`DBKeys.authUsername`). **Credentials go to `flutter_secure_storage`**: `auth.password`, `auth.simple.cookie`, `auth.ui.accessToken`, `auth.ui.refreshToken`, `auth.basic.credentials`.

## Token lifecycle (ui_login)

- `uiAccessTokenExpiresAt` derived from JWT `exp` on every set; **not persisted** (recomputed on `build()`).
- **Proactive refresh:** `AuthCoordinator` schedules a Timer at `exp − 60s` (capped 24h). Transient failure → backoff `[30s,60s,120s,300s]`. Auth failure → clear tokens, set `NeedsReauth`. App-resume observer covers Doze gaps.
- **On-demand (401 path in `SuwayomiAuthLink`):** detect 401 → (`simpleLogin`: call reauth immediately; `uiLogin`: `refreshUiAccessToken()`) → single-flight via file-static `Completer` → refresh via a **raw un-authed client** → on success retry once (retry 401 → reauth); auth-failure → clear + reauth; transient → yield original 401.
- **Reauth flow:** `NeedsReauth=true` → `ReauthBannerHost` banner → `LoginCredentialsPopup` → coordinator login → `NeedsReauth=false`.

## Gotchas (security-sensitive)

- **Single-flight is a file-static `_refreshInFlight`, not an instance field** — survives Riverpod invalidation mid-refresh. Tests must call `debugResetAuthCoordinatorSingleFlight()` in `setUp`.
- **Bare token in WS `connection_init`** (`{Authorization: <token>}`, no "Bearer ") — adding the prefix silently breaks subscriptions. Differs from the HTTP header.
- **Simple Login leaks server-side sessions on Test Connection** — `POST /login.html` always creates a session; discarding the cookie doesn't destroy it; no logout-without-cookie endpoint.
- **`decodeJwtExp` does NOT verify the signature** — intentional (expiry is for Timer sizing only; the server enforces access).
- **`uiAccessTokenExpiresAt` not persisted** — if the JWT is malformed, expiry is null and no proactive Timer is scheduled (refresh only happens reactively on 401).
- **Migrated basic creds live under `auth.basic.credentials`**, tracked by a separate `credentialsProvider`, not `AuthCredentialsState`. Logout must call `clearBasicCredentials()` or they persist invisibly.
- **Refresh client must stay un-authed** — if it ever gains a `SuwayomiAuthLink`, refresh recurses infinitely.
- **`isLocalAddress` suppresses the insecure-transport warning** for `localhost`/`127.x`/`10.x`/`172.16–31.x`/`192.168.x` only.
