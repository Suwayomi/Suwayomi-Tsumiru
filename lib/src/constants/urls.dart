// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

enum AppUrls {
  sorayomiGithubUrl(url: "https://github.com/tsumiru-app/tsumiru"),
  sorayomiLatestReleaseUrl(
      url: "https://github.com/tsumiru-app/tsumiru/releases/latest"),
  tachideskHelp(url: "https://tsumiru-app.github.io/docs/guides/getting-started"),
  sorayomiWhatsNew(url: "https://tsumiru-app.github.io/changelogs/"),
  sorayomiLatestReleaseApiUrl(
    url: "https://api.github.com/repos/tsumiru-app/tsumiru/releases/latest",
  ),
  flareSolverr(
      url:
          "https://github.com/FlareSolverr/FlareSolverr?tab=readme-ov-file#installation");

  const AppUrls({required this.url});

  final String url;
}
