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

### Mobile

**Android:** download the universal APK below and open it to install. Smaller APKs for specific chip types are also attached.

**iOS:** the `…-ios.ipa` below is unsigned and has to be sideloaded. Add `https://tsumiru.app/apps.json` as a source in [SideStore](https://sidestore.io/) or [AltStore](https://altstore.io/) to install it and get later releases as updates.

<details>
<summary>Which sideloading tool should I use?</summary>

- **[SideStore](https://sidestore.io/)** signs and refreshes the app on the device itself, with no computer needed after setup. Best for most people.
- **[AltStore](https://altstore.io/)** expires every 7 days and only refreshes while a computer running AltServer is switched on and on the same Wi-Fi as your phone.
- **[TrollStore](https://ios.cfw.guide/installing-trollstore/)** installs permanently with no expiry, but only works on older iPhones and iOS versions with the required vulnerability.

With SideStore or AltStore the app is re-signed periodically, which those tools automate. There is no App Store build.
</details>

### Desktop

**Windows:** download `…-windows-x64.zip`, extract it anywhere, and run `tsumiru.exe`.

**macOS:** download `…-macos-x64.zip`, extract it, and move the app to Applications. If macOS blocks the first launch, approve it under System Settings → Privacy & Security.

**Linux:** the Flatpak is recommended and auto-updates.

```sh
flatpak remote-add --if-not-exists tsumiru https://flatpak.tsumiru.app/index.flatpakrepo
flatpak install tsumiru app.tsumiru.Tsumiru
```

Existing Flatpak installs keep receiving updates under `io.github.aaronbamblett.tsumiru`; no data, settings or logins move. AppImage/deb also keep that ID.

For a portable option, download `…-linux-x86_64.AppImage`, mark it executable with `chmod +x`, and run it.

### Web

Download `…-web.zip` and serve its contents with any static web server.

[Full documentation](https://tsumiru.app/)
