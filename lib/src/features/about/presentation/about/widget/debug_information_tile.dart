// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/platform/current_platform_description.dart';
import '../../../domain/about/about_dto.dart';
import '../controllers/about_controller.dart';

String buildDebugInfoText({
  required String clientName,
  required String clientVersion,
  required String platform,
  required String serverName,
  required String serverVersion,
  required String serverChannel,
  required String serverBuildTime,
  String? webUiFlavor,
  String? webUiVersion,
}) {
  final lines = [
    'Client: $clientName v$clientVersion ($platform)',
    'Server: $serverName $serverVersion ($serverChannel, build time $serverBuildTime)',
    if (webUiFlavor.isNotBlank && webUiVersion.isNotBlank)
      'Web interface: $webUiFlavor $webUiVersion',
  ];
  return lines.join('\n');
}

class DebugInformationTile extends ConsumerWidget {
  const DebugInformationTile({
    super.key,
    required this.about,
    this.webUiFlavor,
    this.webUiVersion,
  });

  final AboutDto about;
  final String? webUiFlavor;
  final String? webUiVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(packageInfoProvider);
    return ListTile(
      title: Text(context.l10n.debugInformation),
      trailing: const Icon(FluentIcons.copy_24_regular),
      onTap: () async {
        final text = buildDebugInfoText(
          clientName: packageInfo.appName,
          clientVersion: packageInfo.version,
          platform: currentPlatformDescription(),
          serverName: about.name,
          serverVersion: about.version,
          serverChannel: about.buildType,
          serverBuildTime: about.buildTime.toDateString,
          webUiFlavor: webUiFlavor,
          webUiVersion: webUiVersion,
        );
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          ref.read(toastProvider)?.show(context.l10n.copiedToClipboard);
        }
      },
    );
  }
}
