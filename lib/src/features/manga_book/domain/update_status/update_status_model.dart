// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../utils/extensions/custom_extensions.dart';
import 'graphql/__generated__/fragment.graphql.dart';

/// A library update's progress, as the server counts it.
typedef UpdateProgressDto = Fragment$UpdateProgressDto;

extension UpdateProgressExt on UpdateProgressDto {
  /// Series in the run: pending, running, complete and failed.
  int get total => totalJobs.getValueOnNullOrNegative();

  /// Series the run is done with, complete or failed.
  int get updateChecked => finishedJobs.getValueOnNullOrNegative();

  bool get isUpdateCheckCompleted => total == updateChecked;

  bool get isUpdateChecking =>
      (total).isGreaterThan(0) && !(isUpdateCheckCompleted);
}
