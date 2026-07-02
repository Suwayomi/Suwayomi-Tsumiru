<p align="center">
 <img width=120px height=120px src="assets/icons/launcher/tsumiru_icon.png" alt="Tsumiru logo"/>
</p>

<h1 align="center">Tsumiru</h1>

<div align="center">

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Linux%20%7C%20Windows%20%7C%20macOS%20%7C%20Web-lightgrey)](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/Suwayomi/Suwayomi-Tsumiru?label=download)](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest)

</div>

<p align="center">
A native client for reading manga &amp; manhwa from a
<a href="https://github.com/Suwayomi/Suwayomi-Server">Suwayomi-Server</a> instance,
built for long webtoon binges on your phone.
</p>

> **Tsumiru** *(積みる)* — a play on *tsundoku* (積ん読), the art of letting unread
> books pile up. For everyone whose backlog grows faster than they can read it.

---

## What it is

Tsumiru is a fork of [Tachidesk-Sorayomi](https://github.com/Suwayomi/Tachidesk-Sorayomi),
the Flutter client for the self-hosted [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server)
manga server. It connects to a Suwayomi server you already run. Tsumiru itself is only the reader (the server handles sources and downloads).

Runs on **Android, Linux, Windows, macOS, and Web**.

## What's different from upstream Sorayomi

This fork focuses on making it a great daily driver, especially for **webtoon / manhwa** reading:

- **Offline reading:** download chapters to your device and read them with no connection to your server. Tsumiru keeps an on-device catalog with auto-keep rules and falls back to local copies automatically when the server isn't reachable.
- **Rebuilt webtoon reader:** multi-chapter continuous scrolling tuned for long manhwa strips, with pinch-to-zoom that keeps working while you scroll.
- **First-run onboarding:** a guided setup that finds your Suwayomi server on the network and walks you through connecting it.
- **Incognito mode:** pause reading history while you catch up, plus hideable library categories (Komikku parity).
- **13 built-in themes:** plus a custom accent colour and an AMOLED black mode.
- **Native authentication:** `simple_login` and `ui_login`, with credentials kept in your device's secure storage.
- **Flexible library:** sort by last read, last chapter date, or total chapters; filter by reading status and bookmarks; and queue whole chapter ranges with bulk-download presets.

## Download

Grab the latest build for your platform from the
[**Releases**](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest) page
(Android APKs — universal + per-ABI — plus Linux, Windows, macOS, and Web).

**Android, with auto-updates:** add this repo to
[Obtainium](https://github.com/ImranR98/Obtainium) and it will install and keep
Tsumiru updated straight from GitHub Releases (no app store needed).

## Requirements

You need a running [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server)
that Tsumiru can reach. On first launch, point it at your server's address.

## Building

Flutter 3.35.7 / Dart 3.9.2 (pinned).

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter build apk            # or: linux / windows / macos / web
```

## Credits & license

Tsumiru stands on the work of the [Suwayomi](https://github.com/Suwayomi) project:
[Tachidesk-Sorayomi](https://github.com/Suwayomi/Tachidesk-Sorayomi) (the client this
forks) and [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) (the server it
talks to). Huge thanks to those maintainers and contributors.

Licensed under the **Mozilla Public License 2.0** (see [LICENSE](LICENSE)). As with the
upstream project, source files retain their MPL-2.0 headers.
