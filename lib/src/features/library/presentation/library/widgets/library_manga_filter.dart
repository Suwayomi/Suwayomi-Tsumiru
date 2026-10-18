// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'library_filter_content.dart';

/// The Filter tab inside the organizer (phone sheet, tablet drawer): the
/// same short headings and segmented controls as the desktop filter panel,
/// single column, then rating, Tracked, Categories and Tags. The sheet
/// scrolls.
class LibraryMangaFilter extends StatelessWidget {
  const LibraryMangaFilter({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: const [LibraryFilterContent()],
    );
  }
}
