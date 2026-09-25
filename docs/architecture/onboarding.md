# First-run onboarding

A three-step first-run wizard — **pick a theme → connect a server → done** — shown until setup is complete. Lives under `lib/src/features/onboarding/`.

## The wizard

`presentation/onboarding_screen.dart` — `OnboardingScreen` (`HookConsumerWidget`), three steps:

- **Theme** (`_ThemeStep`): brand logo, an **Appearance** picker, then `ThemeSelector`. Always completable.
- **Connect your server** (`_ServerStep`): the real work. `Next` checks an unverified address, submits the displayed login form, or continues once verified.
- **Finish** (`_FinishStep`): done screen. `finish()` sets `onboardingCompleteProvider` true and routes to the library.

A top-right **Skip** escape (on the theme and server steps) also finishes onboarding.

The wizard is a centred column capped at 620 px (`BoxConstraints(maxWidth: 620)`), so wide desktop windows keep the content in a readable measure. The desktop app opens at 1280×900 (`kDefaultWindowSize` in `utils/desktop/desktop_window.dart`, mirrored by `linux/my_application.cc` and `windows/runner/main.cpp`).

### The theme step

Three pieces, top to bottom:

- The big **brand mark**. `_brandLogo(context)` picks the asset for the active brightness: `logoOnLight` (dark ink, drawn for pale surfaces) in light mode, `darkIcon` otherwise. On a short landscape window `_compactLogo` (height < 1000 and wider than tall) shrinks the mark from 160 to 96 px so the theme row still fits; portrait phones keep it full size.
- **Appearance** — a `SegmentedButton<ThemeMode>` (System / Light / Dark) that writes `appThemeModeProvider`.
- `ThemeSelector(title: …)` — the curated theme picker. Its header carries the title plus ‹ › scroll arrows, shown only while the cards overflow.

### Connecting a server

The connection actions share `_ServerStep`:

- **Next** runs the connection check when needed, then shows the login form or advances to Finish for an open server. The pending check and advance intent survive session replacement when the address is saved. Errors stay on the server step for correction and retry.

- **Search my network** → `data/server_discovery.dart`: `discoverServersOnLan()` sweeps the device's Wi-Fi /24 subnet on ports **4567-4570** (`kSuwayomiScanPorts`). Every host×port is TCP-pinged (`Socket.connect`, 1 s timeout) in batches of 128, then each port that answered is confirmed through `confirmLanServer` (`onboarding_screen.dart`) with at most 8 confirmations in flight. `confirmLanServer` keeps a host only when it answers as Suwayomi or is Basic-gated (a Basic-challenged port can't prove what it is before sign-in, and Test connection handles its login), and sends the configured custom headers. Native-only (`dart:io`), called inside a `kIsWeb` guard. One result fills the URL field and tests it; several open a picker sheet. `lanServerScanProvider` is the test seam.
- **Test connection** → `data/server_resolver.dart`: a pure, fully-injectable resolver.
  - `connectionCandidates(input)` turns fuzzy input (bare host, `host:port`, http/https, IPv6) into an ordered candidate ladder, trying the default port 4567 first.
  - `resolveServer()` walks the ladder; `probeServer()` runs a two-request protocol against `/api/graphql` with redirects off — the auth-exempt `aboutServer` confirms it's Suwayomi, and the `@RequireAuth` `downloadStatus` probe detects whether a login is needed. Outcomes: connected / needs-login / unreachable / reached-but-not-Suwayomi.
  - When a login is required, the auth sub-form appears (auth-type dropdown + credentials + **Sign in**). `ProbeResult.detectedAuthType` pre-selects the dropdown unless the user has already changed it (`userChangedAuth`); when detection returns nothing (or the user changed it), Basic stays selected. `detectAuthType()` reads the `@RequireAuth` probe response, plus a redirect-off root GET (`readRootStatus`, which appends a trailing slash so a proxy's path-canonicalising redirect can't hide the hop):
    - 401 with `WWW-Authenticate: Basic` → `AuthType.basic`.
    - 200 whose body reads Unauthorized, with a root GET redirecting (303 among others) to `login.html` → `AuthType.simpleLogin`.
    - The same 200 with a root serving 200 → `AuthType.uiLogin`; on web there is no root hop, so it reads as UI login too. A root redirecting anywhere else, or a native root read that fails, gives nothing.
    - Anything else → null.

    A Basic challenge on the protected probe also marks the candidate login-required, even when its body was empty and read as open.
  - `validateCredentials()` checks the entered credential against a *protected* surface before persisting — for Basic it requires both `basicAuthConfirms` (it really is Suwayomi) and `authProbeAuthorized` (the credential actually unlocks `@RequireAuth`), closing the "wrong type still succeeds" trap. `verifyAuthMode()` is the only reliable simple-vs-ui discriminator, since Suwayomi's `/login.html` returns 303 + cookie in both modes.

On web the browser has already followed any redirect and never exposes the root hop, so `testWeb()` tests the typed address through the existing GraphQL client's `getAbout()` and detects the sign-in method with `webAuthProbe()`, the same `@RequireAuth` probe the native resolver runs with `rootStatus: null`.

The "I don't have a server yet" link opens the setup docs and unlocks `Next`, so a user can finish without a server (the library then shows its empty state).

`onboardingHttpClientProvider` is an `http.Client` factory, overridable in widget tests so the whole flow can run against a `MockClient`.

## Completion + the router gate

`data/onboarding_complete.dart` — `OnboardingComplete`, a `bool` backed by `SharedPreferenceClientMixin` at `DBKeys.onboardingComplete`. `serverConfiguredForOnboarding(url)` is true when a real (non-default) server URL is stored; a one-time startup migration (`lib/main.dart`) calls `seedFirstRunPreferences`, which uses it to seed existing installs as already-onboarded, so the wizard never appears for them.

`seedFirstRunPreferences` also starts genuinely new installs in **Dark**: when no server URL is configured and `DBKeys.themeMode` is unset, it writes `ThemeMode.dark`. `DBKeys.themeMode`'s own default stays `ThemeMode.system`, so an install that already stored a mode — every existing user — keeps following the system. The wizard's Appearance picker reads that stored value.

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

- **Web is a reduced path**: no LAN discovery, and no redirect-off probe — the user types the full URL and `testWeb()` validates via the existing client. Auth detection there is partial: the browser hides the root hop, so a 401 Basic challenge and a 200 + Unauthorized server are still detected (Basic and UI login), but simple login can't be told apart and reads as UI login.
- The "no server yet" link sets `serverVerified = true`, so onboarding can complete with no working server configured (the library shows its empty state).
- The migration seed checks only that a non-default URL exists, not that it ever connected successfully.
