# Repo, Build & Release Model

> **The #1 rule:** `tsumiru-app/tsumiru` `main` (git remote `tsumiru`) is the canonical source of truth. **Before building, branching, or releasing, run `git fetch tsumiru` and verify your local base against `tsumiru/main` AND the latest GitHub release.** Building on a stale base produces an app missing the in-app branding, version, and fixes that shipped in the latest release.

## Remotes & branch model

Tsumiru is its **own application** published at `tsumiru-app/tsumiru` — not a personal fork. It descends from Tachidesk-Sorayomi (kept for attribution and the occasional upstream sync), but the project lives and ships on its own now.

| Remote | URL | Role |
|---|---|---|
| `origin` | `github.com/tsumiru-app/tsumiru` | **The app — canonical.** A fresh `git clone` / `gh repo clone` lands here; `main` and releases are ground truth |
| `upstream` | `github.com/Suwayomi/Tachidesk-Sorayomi` | The project Tsumiru descends from (attribution / occasional sync) |
| `ariqpradipa` | `github.com/ariqpradipa/Tachidesk-Sorayomi` | Author of adopted reader PR #362 |

**Workflow:** Tsumiru uses **pull requests** (public project). Branch off `main`, open a PR, let CI gate it, then merge. Branch and commit names are plain/human — no `feat/`-style prefixes. Push/PR-create/merge happen on `origin`.

## Version scheme

`pubspec.yaml`: `version: 0.6.0+32`

- **Public version** (`0.6.0`) matches the release tag line (`v0.6.0`). Release tags carry a `v` prefix; the pubspec version does not.
- **Build number** (`+32`) is a monotonically increasing integer (inherited from the upstream `0.6.4+N` series). It MUST increase on every build pushed to a device — Android rejects a same-or-lower build number as a downgrade. CI does not enforce this; bump it manually before tagging.

## Release flow

Pushing a `v*.*.*` tag fires two workflows in parallel:

**`release-fork.yml`** (primary release builder) — Flutter pinned to `3.35.7` (stable). A 5-job matrix (`fail-fast: false`):

| Job | Runner | Output |
|---|---|---|
| android | ubuntu-latest | 4 APKs (universal + arm64-v8a + armeabi-v7a + x86_64), debug-keystore signed via repo secrets so upgrades stay clean |
| linux | ubuntu-latest | AppImage (fastforge + appimagetool) |
| web | ubuntu-latest | `*-web.zip` |
| macos | macos-latest | `.app` zip |
| windows | **windows-2022** (pinned, not `latest`) | `*-windows-x64.zip` |

- Android signing secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
- Linux build deps: `clang cmake ninja-build pkg-config libgtk-3-dev libx11-dev libblkid-dev liblzma-dev libsecret-1-dev libjsoncpp-dev` (last two needed for `flutter_secure_storage_linux`).
- Artifacts attach to the release only on a tag push (guarded by `startsWith(github.ref, 'refs/tags/')`); `workflow_dispatch` builds but does not attach.

**`flatpak.yml`** (self-hosted Flatpak repo → GitHub Pages) — three sequential jobs: build the Linux bundle, package + GPG-sign in the `freedesktop:24.08` flatter container, deploy to Pages at `suwayomi.github.io/Suwayomi-Tsumiru` (the app repo's own Pages — it moved with the repo; the docs site lives at `tsumiru.app`, served from `tsumiru-app/tsumiru-app.github.io` behind Cloudflare). Needs secrets `FLATPAK_GPG_PRIVATE_KEY` + `FLATPAK_GPG_KEY_ID`. Manifest id is still `io.github.aaronbamblett.tsumiru`.

**Manual-only / vestigial:**
- `publish.yml` — inherited upstream (winget/homebrew/Play/iOS). Stale: still names `tachidesk-sorayomi`, needs secrets this fork lacks. `workflow_dispatch` only; do not run.
- `web.yml` — inherited upstream Pages deployer (`baseHref: /Tachidesk-Sorayomi/`). Stale; Web is covered by `release-fork.yml`.

## CI quality gates

- `claude-code-review.yml` — Claude code-review commentary on PRs (needs `CLAUDE_CODE_OAUTH_TOKEN`). Not a build/test gate.
- `claude.yml` — `@claude` interactive assistant. Not a gate.
- **Gap:** there is currently **no workflow that runs `flutter analyze` / `flutter test` on PRs** — a broken build can merge undetected until a release tag. (A visual-verification + test gate is planned; see the vault plans.)

## Codegen — what regenerates and when

Every CI build step runs, before building:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```

`build_runner` regenerates: `*.g.dart` (riverpod_generator, json_serializable, go_router_builder), `*.freezed.dart` (freezed), and `*.graphql.dart` (graphql_codegen). `flutter gen-l10n` regenerates `lib/src/l10n/generated/` from the ARB files (`l10n.yaml`: `synthetic-package: false`). `flutter_native_splash` / `flutter_launcher_icons` / `flutter_gen` (`lib/src/constants/gen/`) are NOT run in the build — flutter_gen was dropped from the pipeline (incompatible with build_runner_core 9.x on Dart 3.9), so `gen/assets.gen.dart` is committed and treated as source, alongside the committed splash/icon outputs.

`analysis_options.yaml` excludes generated files; adds `prefer_relative_imports` and `directives_ordering`; suppresses `invalid_annotation_target` (common with freezed/riverpod).

## Pinned git dependencies (instability vectors)

- `scrollable_positioned_list` → `github.com/yakagami/scrollable_positioned_list@4641e83` (fork exposing `ScrollOffsetController.position`, needed for pinch-zoom coordination). The reader will not compile against the pub.dev package.
- `flutter_android_volume_keydown` → `github.com/DattatreyaReddy/flutter_android_volume_keydown` (floating HEAD, no ref pinned).

## Local build / run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d chrome      # web (no native toolchain needed)
flutter run -d linux       # native Linux desktop (requires cmake/ninja/GTK dev libs)
flutter build apk --debug  # local Android APK
```
