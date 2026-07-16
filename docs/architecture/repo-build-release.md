# Repo, Build & Release Model

> **The #1 rule:** `Suwayomi/Suwayomi-Tsumiru` `main` is the canonical source of truth. **Before building, branching, or releasing, run `git fetch origin` and verify your local base against `origin/main` and the latest GitHub release.** Building on a stale base produces an app missing the in-app branding, version, and fixes that shipped in the latest release.

## Remotes & branch model

Tsumiru is its **own application** published at `Suwayomi/Suwayomi-Tsumiru` inside the Suwayomi org. It descends from Tachidesk-Sorayomi (kept for attribution and the occasional upstream sync), but the project lives and ships on its own now.

| Remote | URL | Role |
|---|---|---|
| `origin` | `github.com/Suwayomi/Suwayomi-Tsumiru` | **The app — canonical.** A fresh `git clone` / `gh repo clone` lands here; `main` and releases are ground truth |
| `upstream` | `github.com/Suwayomi/Tachidesk-Sorayomi` | Optional remote for the project Tsumiru descends from (attribution / occasional sync) |
| `ariqpradipa` | `github.com/ariqpradipa/Tachidesk-Sorayomi` | Optional remote for the author of adopted reader PR #362 |

**Workflow:** Tsumiru uses **pull requests** (public project). Branch off `main`, open a PR, let CI gate it, then merge. Branch and commit names are plain/human — no `feat/`-style prefixes. Push/PR-create/merge happen on `origin`.

## Version scheme

`pubspec.yaml`: `version: 0.8.5+41`

- **Public version** (`0.8.5`) matches the release tag line (`v0.8.5`). Release tags carry a `v` prefix; the pubspec version does not.
- **Build number** (`+41`) is a monotonically increasing integer (inherited from the upstream `0.6.4+N` series). It MUST increase on every build pushed to a device — Android rejects a same-or-lower build number as a downgrade. CI does not enforce this; bump it manually before tagging.

## Release flow

A release is **maintainer-initiated as a draft, then auto-published once every platform builds:**

1. `gh release create vX.Y.Z --target <sha> --notes-file notes.md --draft` — create the draft with its notes.
2. `git tag vX.Y.Z <sha> && git push origin vX.Y.Z` — the tag push fires two workflows in parallel.

**`release-fork.yml`** (primary release builder) — Flutter read from `.fvmrc` (currently 3.44.6). A **6-job** build matrix (`fail-fast: false`):

| Job | Runner | Output |
|---|---|---|
| android | ubuntu-latest | 4 APKs (universal + arm64-v8a + armeabi-v7a + x86_64), debug-keystore signed via repo secrets so upgrades stay clean |
| linux | ubuntu-latest | AppImage (fastforge + appimagetool) |
| web | ubuntu-latest | `*-web.zip` |
| macos | macos-latest | `.app` zip |
| ios | macos-latest | **unsigned** `.ipa` (no Apple Developer account; users re-sign via AltStore / SideStore / TrollStore) |
| windows | **windows-2022** (pinned, not `latest`) | `*-windows-x64.zip` |

- Each platform attaches its artifact to the **draft** release (guarded by `startsWith(github.ref, 'refs/tags/')`). A separate **`publish`** job flips the draft to published (`--latest`) only after all six builds succeed — and refuses to publish if the release notes are empty, so an incomplete or blank release never goes public. A failed platform leaves the release a draft. On publish it best-effort triggers a `tsumiru.app` rebuild so the new release shows immediately.
- **Weekly dry run:** a Monday 06:00 UTC cron builds all platforms with no tag ref — it catches iOS/macOS breakage before release day (the PR check builds only a single platform) and, without a tag, skips the attach + publish steps entirely.
- Android signing secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
- Linux build deps: `clang cmake ninja-build pkg-config libgtk-3-dev libx11-dev libblkid-dev liblzma-dev libsecret-1-dev libjsoncpp-dev` (last two needed for `flutter_secure_storage_linux`).

**`flatpak.yml`** (self-hosted Flatpak repo → GitHub Pages) — three sequential jobs: build the Linux bundle, package + GPG-sign in the `freedesktop:24.08` flatter container, deploy to Pages at `suwayomi.github.io/Suwayomi-Tsumiru` (the app repo's own Pages — it moved with the repo; the docs site lives at `tsumiru.app`, served from `tsumiru-app/tsumiru-app.github.io` behind Cloudflare). Needs secrets `FLATPAK_GPG_PRIVATE_KEY` + `FLATPAK_GPG_KEY_ID`. Manifest id is still `io.github.aaronbamblett.tsumiru`.

## CI quality gates

**`pr-checks.yml`** runs on every PR to `main`: `flutter pub get → flutter gen-l10n → build_runner build → flutter analyze → flutter test`. Analyze runs with `--no-fatal-warnings --no-fatal-infos`, so only real errors (or a failing test) block the merge — the repo's inherited warnings/infos are reported but don't gate. This is the safety net that keeps a broken build from merging.

## Automated dependency updates (Renovate)

**`renovate.yml`** runs self-hosted Renovate weekly (Mondays 06:00 UTC) and on demand, opening small, CI-gated PRs to keep dependencies current. It authenticates with a fine-grained PAT in the `RENOVATE_TOKEN` secret — not the default `GITHUB_TOKEN`, whose PRs wouldn't trigger `pr-checks.yml`. Config lives in `renovate.json` + `.github/renovate-global.js`. This is the mechanism that cleared the dependency backlog and drove the Riverpod 3 / freezed 3 / graphql_codegen 3 / go_router 17 migration.

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
