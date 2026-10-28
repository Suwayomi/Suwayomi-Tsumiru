// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../../utils/avif/avif_file_image_io.dart';

ImageProvider offlineImageProvider(String path) => Platform.isLinux
    ? AvifAwareFileImage(File(path))
    : FileImage(File(path));
