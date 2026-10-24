// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Brand marks from the separately bundled Font Awesome Free Brands font.
abstract final class BrandIcons {
  static const github = IconData(0xf09b, fontFamily: 'FontAwesomeBrands');
  static const discord = IconData(0xf392, fontFamily: 'FontAwesomeBrands');
}

/// Font Awesome license: icons CC BY 4.0, font SIL OFL 1.1.
void registerBrandIconsLicense() => LicenseRegistry.addLicense(() async* {
  yield LicenseEntryWithLineBreaks([
    'Font Awesome',
  ], await rootBundle.loadString('assets/licenses/font-awesome.txt'));
});
