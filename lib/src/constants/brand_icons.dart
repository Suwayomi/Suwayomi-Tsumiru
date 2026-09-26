// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The two brand marks the app shows (About, update dialog), from the Font
/// Awesome Free Brands font bundled on its own. The font_awesome_flutter
/// package also shipped its Solid and Regular fonts, ~500 KB nothing used.
abstract final class BrandIcons {
  static const github = IconData(0xf09b, fontFamily: 'FontAwesomeBrands');
  static const discord = IconData(0xf392, fontFamily: 'FontAwesomeBrands');
}

/// Font Awesome's license, which the package used to add to the licenses page
/// by itself (icons CC BY 4.0, font SIL OFL 1.1).
void registerBrandIconsLicense() => LicenseRegistry.addLicense(() async* {
  yield LicenseEntryWithLineBreaks([
    'Font Awesome',
  ], await rootBundle.loadString('assets/licenses/font-awesome.txt'));
});
