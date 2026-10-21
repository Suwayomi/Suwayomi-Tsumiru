// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_distribution.dart';
import '../../../../../constants/brand_icons.dart';
import '../../../../../constants/urls.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../data/about_repository.dart';
import '../../../data/web_update_browser.dart';

void appUpdateDialog({
  required String title,
  required String newRelease,
  required BuildContext context,
  required Toast? toast,
  String? url,
  bool isServerUpdate = false,
  void Function(bool skip)? onSkipChanged,
}) {
  if (!isServerUpdate && isGooglePlayBuild) return;
  if (kIsWeb &&
      !isServerUpdate &&
      ProviderScope.containerOf(context).read(serverHostedWebProvider)) {
    return;
  }
  showDialog(
    context: context,
    builder: (context) {
      bool skip = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.l10n.newUpdateAvailable),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.versionAvailable(title, newRelease)),
              if (onSkipChanged != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: skip,
                  onChanged: (v) {
                    setState(() => skip = v ?? false);
                    onSkipChanged(skip);
                  },
                  title: Text(context.l10n.skipThisVersion),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.close),
            ),
            if (url != null || !isGooglePlayBuild)
              ElevatedButton.icon(
                onPressed: () {
                  launchUrlInWeb(
                    context,
                    url ?? AppUrls.sorayomiLatestReleaseUrl.url,
                    toast,
                  );
                  Navigator.pop(context);
                },
                icon: const Icon(BrandIcons.github),
                label: Text(context.l10n.gitHub),
              ),
          ],
        ),
      );
    },
    animationStyle: context.motionStyle,
  );
}

MaterialBanner webBuildReloadBanner(BuildContext context) => MaterialBanner(
  content: Text(context.l10n.serverInstalledNewTsumiru),
  actions: [
    TextButton(
      onPressed: reloadWebBuild,
      child: Text(context.l10n.reloadWebBuild),
    ),
  ],
);
