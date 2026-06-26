# First-run onboarding

A three-step first-run wizard — **pick a theme → connect a server → done** — shown until setup is complete. Lives under `lib/src/features/onboarding/`.

## The wizard

`presentation/onboarding_screen.dart` — `OnboardingScreen` (`HookConsumerWidget`), three steps:

- **Theme** (`_ThemeStep`): brand logo + `ThemeSelector`. Always completable.
- **Connect your server** (`_ServerStep`): the real work. Gated — `Next` unlocks only when `serverVerified` is true.
- **Finish** (`_FinishStep`): done screen. `finish()` sets `onboardingCompleteProvider` true and routes to the library.

A top-right **Skip** escape (on the theme and server steps) also finishes onboarding.

### Connecting a server

Two helpers, both on `_ServerStep`:

- **Search my network** → `data/server_discovery.dart`: `discoverServerOnLan()` sweeps the device's Wi-Fi /24 subnet on port **4567** (`Socket.connect`, 120 ms timeout, concurrent batches), returning `http://<ip>:4567` for the first responder. Native-only (`dart:io`), called inside a `kIsWeb` guard.
- **Test connection** → `data/server_resolver.dart`: a pure, fully-injectable resolver.
  - `connectionCandidates(input)` turns fuzzy input (bare host, `host:port`, http/https, IPv6) into an ordered candidate ladder, trying the default port 4567 first.
  - `resolveServer()` walks the ladder; `probeServer()` runs a two-request protocol against `/api/graphql` with redirects off — the auth-exempt `aboutServer` confirms it's Suwayomi, and the `@RequireAuth` `downloadStatus` probe detects whether a login is needed. Outcomes: connected / needs-login / unreachable / reached-but-not-Suwayomi.
  - When a login is required, the auth sub-form appears (auth-type dropdown + credentials + **Sign in**). `validateCredentials()` checks the entered credential against a *protected* surface before persisting — for Basic it requires both `basicAuthConfirms` (it really is Suwayomi) and `authProbeAuthorized` (the credential actually unlocks `@RequireAuth`), closing the "wrong type still succeeds" trap. `verifyAuthMode()` is the only reliable simple-vs-ui discriminator, since Suwayomi's `/login.html` returns 303 + cookie in both modes.

On web there is no redirect-off probe; `testWeb()` falls back to the existing GraphQL client's `getAbout()`.

The "I don't have a server yet" link opens the setup docs and unlocks `Next`, so a user can finish without a server (the library then shows its empty state).

`onboardingHttpClientProvider` is an `http.Client` factory, overridable in widget tests so the whole flow can run against a `MockClient`.

## Completion + the router gate

`data/onboarding_complete.dart` — `OnboardingComplete`, a `bool` backed by `SharedPreferenceClientMixin` at `DBKeys.onboardingComplete`. `serverConfiguredForOnboarding(url)` is true when a real (non-default) server URL is stored; a one-time startup migration uses it to seed existing installs as already-onboarded, so the wizard never appears for them.

The gate is a redirect in `lib/src/routes/router_config.dart`:

```dart
redirect: (context, state) {
  final complete = ref.read(onboardingCompleteProvider) ?? false;
  final atOnboarding =
      state.matchedLocation == const OnboardingRoute().location;
  if (!complete && !atOnboarding) return const OnboardingRoute().location;
  if (complete && atOnboarding) {
    return const LibraryRoute(categoryId: 0).location;
  }
  return null;
},
```

Every navigation reads `onboardingCompleteProvider`: until it's true, all routes redirect to `/onboarding` (no deep-linking past it); once true, `/onboarding` itself redirects to the library. Calling `update(true)` invalidates the provider, so the next navigation sees the new value.

## Gotchas

- **Web is a reduced path**: no LAN discovery, no redirect-off probe, no auth auto-detection — the user types the full URL and `testWeb()` validates via the existing client.
- The "no server yet" link sets `serverVerified = true`, so onboarding can complete with no working server configured (the library shows its empty state).
- The migration seed checks only that a non-default URL exists, not that it ever connected successfully.
