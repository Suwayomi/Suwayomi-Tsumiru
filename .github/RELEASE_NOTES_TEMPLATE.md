A manga and webtoon reader for your [Suwayomi](https://suwayomi.org/) server.

<!-- Verb-led single-line bullets with no trailing period, each ending with the
     author's (@handle). Use only the sections that have content. "Fixed X"
     beats explaining what broke; root-cause detail belongs in the PR, not
     here. Setting and button names bold and exactly as the app shows them. -->

### ✨ New Features

### ⚙️ Changes

### 🚀 Improvements

### 🧩 Fixes

## Install

You'll need a running Suwayomi server. See [Getting started](https://tsumiru.app/docs/guides/getting-started).

**Android:** download the universal APK below and open it to install (smaller APKs for specific chip types are also attached).

**Windows:** download the `…-windows-x64.zip` below, extract it anywhere, and run `tsumiru.exe`.

**Linux - Flatpak (recommended, auto-updates):**
```sh
flatpak remote-add --if-not-exists tsumiru https://suwayomi.github.io/Suwayomi-Tsumiru/index.flatpakrepo
flatpak install tsumiru io.github.aaronbamblett.tsumiru
```
> Added the `tsumiru` remote before? It may still point at the old `tsumiru-app.github.io` URL. Run `flatpak remote-delete tsumiru` first, then the commands above.

**Linux - AppImage (portable):** download the `…-linux-x86_64.AppImage` below, mark it executable (`chmod +x`), and run it.

**iOS (sideload only, advanced):** the `…-ios.ipa` below is **unsigned**, so you can't just download and open it. Apple requires every app to be signed to your own account first, using one of these tools:

- **[SideStore](https://sidestore.io/):** signs and refreshes the app *on-device*, no computer needed after setup. For most people this is the best option.
- **[AltStore](https://altstore.io/):** also signs the app, but it expires every 7 days and only auto-refreshes while a computer running AltServer is powered on and on the same Wi-Fi as your phone.
- **[TrollStore](https://ios.cfw.guide/installing-trollstore/):** permanent install with no expiry, but only works on older iPhones/iOS versions with the required vulnerability.

With SideStore or AltStore the app must be re-signed periodically (the tools automate this). Only TrollStore avoids that. There is no App Store build.

**macOS:** download the `…-macos-x64.zip` below, extract it, and move the app to Applications. If macOS blocks the first launch, approve the app under System Settings → Privacy & Security (Open Anyway).

**Web:** download the `…-web.zip` below and serve its contents with any static web server.

Full docs at [tsumiru.app](https://tsumiru.app/).
