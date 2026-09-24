<p align="center">
 <img width=120px height=120px src="assets/icons/launcher/tsumiru_icon.png" alt="Tsumiru logo"/>
</p>

<h1 align="center">Tsumiru</h1>

<div align="center">

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Linux%20%7C%20Windows%20%7C%20macOS%20%7C%20Web-lightgrey)](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/Suwayomi/Suwayomi-Tsumiru?label=download)](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest)

</div>

<p align="center">A manga and webtoon reader for your Suwayomi server</p>

> *Tsumiru* (積みる) comes from *tsundoku* (積ん読), buying books and letting them pile up unread.

## What it is

Tsumiru is a reader app for [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server), the self-hosted manga server. The server finds sources and downloads chapters. Tsumiru connects to it and reads them.

It runs on Android, iOS, Linux, Windows, macOS and the web. Guides and FAQ are at [tsumiru.app](https://tsumiru.app).

## Features

- **Offline reading.** Download chapters to your device and read them without a connection. When the server is unreachable, Tsumiru opens the copies on your device.
- **Webtoon reader.** Chapters scroll into each other, and pinch-to-zoom keeps working mid-scroll.
- **Guided setup.** The first launch looks for your server on the local network and connects to it.
- **Incognito mode.** Read without adding to your history. Library categories can be hidden too.
- **Themes.** 13 built-in themes, a custom accent colour and a pure black mode for OLED screens.
- **Server login.** Supports the server's `simple_login` and `ui_login` modes and keeps credentials in the device's secure storage.
- **Library tools.** Sort by last read, latest chapter or chapter count, filter by status and bookmarks, and download chapter ranges in bulk.

## Download

Get the latest build from [Releases](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest). The [download page](https://tsumiru.app/download/) has install steps for each platform.

- **Android:** add this repo to [Obtainium](https://github.com/ImranR98/Obtainium) to get updates straight from GitHub Releases.
- **Linux:** the Flatpak from our own repo updates itself. An AppImage is also on Releases.
- **iOS:** the build is unsigned, so it has to be sideloaded.

You need a running Suwayomi-Server that your device can reach.

## Building

The Flutter version is pinned in `.fvmrc`.

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter build apk            # or: ios / linux / windows / macos / web
```

## Credits and license

Tsumiru started as a fork of [Tachidesk-Sorayomi](https://github.com/Suwayomi/Tachidesk-Sorayomi) and depends on [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server). Thanks to everyone who built and maintains both.

Licensed under the [Mozilla Public License 2.0](LICENSE). Source files keep their MPL-2.0 headers.
