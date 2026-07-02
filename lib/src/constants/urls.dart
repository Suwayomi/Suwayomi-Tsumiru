// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

enum AppUrls {
  sorayomiGithubUrl(url: "https://github.com/Suwayomi/Suwayomi-Tsumiru"),
  sorayomiLatestReleaseUrl(
      url: "https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest"),
  tachideskHelp(url: "https://tsumiru.app/docs/guides/getting-started"),
  // What's New points at the GitHub Releases page so it always shows the
  // current release notes — the old docs-site changelog was hand-maintained and
  // went stale (stuck at v0.6.1 while the app shipped v0.7.1).
  sorayomiWhatsNew(url: "https://github.com/Suwayomi/Suwayomi-Tsumiru/releases"),
  sorayomiLatestReleaseApiUrl(
    url: "https://api.github.com/repos/Suwayomi/Suwayomi-Tsumiru/releases/latest",
  ),
  flareSolverr(
      url:
          "https://github.com/FlareSolverr/FlareSolverr?tab=readme-ov-file#installation");

  const AppUrls({required this.url});

  final String url;
}
