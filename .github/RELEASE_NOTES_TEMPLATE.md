A fast, multiplatform reader for your [Suwayomi](https://suwayomi.org/) server.

## What's new in vX.Y.Z

<!-- Summarise the headline changes here, grouped by area. -->

## Install

You'll need a running Suwayomi server. See [Getting started](https://tsumiru.app/docs/guides/getting-started).

**Linux - Flatpak (recommended, auto-updates):**
```sh
flatpak remote-add --if-not-exists tsumiru https://suwayomi.github.io/Suwayomi-Tsumiru/index.flatpakrepo
flatpak install tsumiru io.github.aaronbamblett.tsumiru
```
> Added the `tsumiru` remote before? It may still point at the old `tsumiru-app.github.io` URL. Run `flatpak remote-delete tsumiru` first, then the commands above.

**Linux - AppImage (portable):** download the `…-linux-x86_64.AppImage` below, `chmod +x`, run.

**Android:** grab the universal APK (or a per-ABI build). **Windows / macOS / Web:** attached below.

**iOS (sideload only — advanced):** the `…-ios.ipa` below is **unsigned**, so you can't just download and open it. Apple requires every app to be signed to your own account first, using one of these tools:

- **[SideStore](https://sidestore.io/)** — signs and refreshes the app *on-device*, no computer needed after setup. Best choice for most people.
- **[AltStore](https://altstore.io/)** — also signs the app, but it expires every 7 days and only auto-refreshes while a computer running AltServer is powered on and on the same Wi-Fi as your phone.
- **[TrollStore](https://ios.cfw.guide/installing-trollstore/)** — permanent install with no expiry, but only works on older iPhones/iOS versions with the required vulnerability.

With SideStore or AltStore the app must be re-signed periodically (the tools automate this); only TrollStore avoids that. There is no App Store build.

Full docs at [tsumiru.app](https://tsumiru.app/).
