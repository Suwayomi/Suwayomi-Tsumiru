// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'server_page_shell.dart';
import 'widget/misc_settings/misc_settings_section.dart';

class ServerLogsScreen extends StatelessWidget {
  const ServerLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ServerSettingsPageShell(
      title: Text(context.l10n.logs),
      whenData: (data) => [MiscSettingsSection(miscSettingsDto: data)],
    );
  }
}
