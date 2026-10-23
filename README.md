<p align="center">
 <picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/icons/dark_icon.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/icons/logo_on_light.png">
  <img width=120px height=120px src="assets/icons/dark_icon.png" alt="Tsumiru logo"/>
 </picture>
</p>

<h1 align="center">Tsumiru</h1>

<div align="center">

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Linux%20%7C%20Windows%20%7C%20macOS%20%7C%20Web-lightgrey)](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/Suwayomi/Suwayomi-Tsumiru?label=download)](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Suwayomi/Suwayomi-Tsumiru/total?label=downloads)](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases)
[![Translation status](https://hosted.weblate.org/widget/suwayomi/suwayomi-tsumiru/svg-badge.svg)](https://hosted.weblate.org/engage/suwayomi/)

</div>

<p align="center">A manga and webtoon reader for your Suwayomi server</p>

> *Tsumiru* (積みる) takes the 積, "pile up", from *tsundoku* (積ん読), the Japanese habit of buying books faster than you can read them. It swaps the "read" for *miru*, "to look".

## About

Tsumiru is a client for [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server), so [you'll need a server running first](https://github.com/Suwayomi/Suwayomi-Server#downloading-and-running-the-app). Your library and reading progress are stored on the server, and Tsumiru reads them on Android, iOS, Linux, Windows, macOS or the web. Guides and the FAQ are at [tsumiru.app](https://tsumiru.app).

## Screenshots

<img src="./.github/readme-images/phone-series-framed.png" alt="A series page on Android" width="26%"/> <img src="flatpak/screenshots/02-series.png" alt="A series page on desktop" width="71%"/>

## Features

- **Offline reading.** Download chapters to your device and read them without a connection. When the server is unreachable, Tsumiru opens the copies on your device.
- **Webtoon reader.** Chapters scroll into each other, and pinch-to-zoom keeps working mid-scroll.
- **Guided setup.** The first launch looks for your server on the local network and connects to it.
- **Incognito mode.** Read without adding to your history. Library categories can be hidden too.
- **Themes.** 13 built-in themes, a custom accent colour and a pure black mode for OLED screens.
- **Server login.** Supports the server's `simple_login` and `ui_login` modes and keeps credentials in the device's secure storage.
- **Library tools.** Sort by last read, latest chapter or chapter count, filter by status and bookmarks, and download chapter ranges in bulk.

## Download

You need a running [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) that your device can reach. The [download page](https://tsumiru.app/download/) has install steps for each platform.

### Android

<a href="https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22io.github.aaronbamblett.tsumiru%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2FSuwayomi%2FSuwayomi-Tsumiru%22%2C%22author%22%3A%22Suwayomi%22%2C%22name%22%3A%22Tsumiru%22%7D"><img src=".github/readme-images/badge_obtainium.png" alt="Get it on Obtainium" height="60"/></a>
<a href="https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest"><img src="https://raw.githubusercontent.com/Kunzisoft/Github-badge/main/get-it-on-github.png" alt="Get it on GitHub" height="60"/></a>

Obtainium installs new releases straight from GitHub. Or grab the APK from [Releases](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest).

### iOS

<a href="https://tsumiru.app/open.html?r=sidestore%3A%2F%2Fsource%3Furl%3Dhttps%3A%2F%2Ftsumiru.app%2Fapps.json"><img src=".github/readme-images/get-it-on-sidestore.png" alt="Get it on SideStore" height="60"/></a>
<a href="https://tsumiru.app/open.html?r=altstore%3A%2F%2Fsource%3Furl%3Dhttps%3A%2F%2Ftsumiru.app%2Fapps.json"><img src=".github/readme-images/get-it-on-altstore.png" alt="Get it on AltStore" height="60"/></a>
<a href="https://tsumiru.app/open.html?r=feather%3A%2F%2Fsource%2Fhttps%3A%2F%2Ftsumiru.app%2Fapps.json"><img src=".github/readme-images/get-it-on-feather.png" alt="Get it on Feather" height="60"/></a>

The build is unsigned, so it has to be sideloaded. Each badge adds the Tsumiru source to that app, so new releases show up there. For TrollStore, grab the .ipa from [Releases](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest). See the [iOS guide](https://tsumiru.app/docs/guides/install-ios).

### Linux

```bash
flatpak remote-add --if-not-exists tsumiru https://suwayomi.github.io/Suwayomi-Tsumiru/index.flatpakrepo
flatpak install tsumiru io.github.aaronbamblett.tsumiru
```

The Flatpak updates itself. An AppImage is also on [Releases](https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest).

### Windows, macOS and web

<a href="https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest"><img src="https://raw.githubusercontent.com/Kunzisoft/Github-badge/main/get-it-on-github.png" alt="Get it on GitHub" height="60"/></a>

Download the build for your platform from Releases.

## Translations

Tsumiru is translated on [Hosted Weblate](https://hosted.weblate.org/projects/suwayomi/suwayomi-tsumiru/). Pick your language there to fix or add translations; changes come back to this repo as pull requests.

<a href="https://hosted.weblate.org/engage/suwayomi/">
  <img src="https://hosted.weblate.org/widget/suwayomi/suwayomi-tsumiru/multi-auto.svg" alt="Translation status" />
</a>

## Contributing

Pull requests are welcome. For larger changes, open an issue first so we can talk it through. Build steps are in the [contributing guide](CONTRIBUTING.md).

## Related projects

- [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server): the server Tsumiru connects to. It runs the sources and extensions and stores your library.
- [Suwayomi-Server-docker](https://github.com/Suwayomi/Suwayomi-Server-docker): the official Docker image, the quickest way to run the server on a home server or NAS.

## Contributors

Thank you to everyone who has contributed to Tsumiru and to Tachidesk-Sorayomi before it.

<a href="https://github.com/Suwayomi/Suwayomi-Tsumiru/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Suwayomi/Suwayomi-Tsumiru" alt="Tsumiru contributors" width="800"/>
</a>

## Disclaimer

Tsumiru hosts no content and has no affiliation with any content provider. It shows what your own Suwayomi server provides.

## Credits and license

Tsumiru started as a fork of [Tachidesk-Sorayomi](https://github.com/Suwayomi/Tachidesk-Sorayomi) and depends on [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server). Thanks to everyone who built and maintains both.

The app typeface is [Inter](https://github.com/rsms/inter) by Rasmus Andersson, bundled (Regular, Medium, SemiBold) under the SIL Open Font License 1.1. See [assets/fonts/inter/OFL.txt](assets/fonts/inter/OFL.txt). It is also registered with the app's licence list at startup, like the Font Awesome licence.

Licensed under the [Mozilla Public License 2.0](LICENSE). Source files keep their MPL-2.0 headers.
