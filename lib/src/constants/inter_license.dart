// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Inter's license, shown on the licences page next to the bundled font.
/// The OFL text is read from the copy shipped with the font files.
void registerInterLicense() => LicenseRegistry.addLicense(() async* {
  yield LicenseEntryWithLineBreaks(const [
    'Inter',
  ], await rootBundle.loadString('assets/fonts/inter/OFL.txt'));
});
