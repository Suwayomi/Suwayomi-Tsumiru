// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart'
    show menuAnchorForPoint;
import '../../../domain/content_rating.dart';
import '../../../domain/extension/extension_model.dart';
import 'extension_context_menu.dart';
import 'extension_info_dialog.dart';
import 'extension_list_tile.dart';

class ExtensionCard extends HookConsumerWidget {
  const ExtensionCard({super.key, required this.extension});

  final Extension extension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runningAction = useState<String?>(null);

    Future<void> openMenu(RelativeRect position) => showExtensionContextMenu(
      context: context,
      ref: ref,
      position: position,
      extension: extension,
    );

    void openMenuAt(Offset point) =>
        openMenu(menuAnchorForPoint(context, point));

    return GestureDetector(
      onSecondaryTapDown: (details) => openMenuAt(details.globalPosition),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openExtensionInfo(context, pkgName: extension.pkgName),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: KBorderRadius.r8.radius,
                  child: ServerImageWithCpi(
                    url: extension.iconUrl,
                    outerSize: const Size.square(48),
                    innerSize: const Size.square(24),
                    isLoading: runningAction.value != null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        extension.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.textTheme.titleSmall,
                      ),
                      _CardSubtitle(extension: extension),
                    ],
                  ),
                ),
                ExtensionListTileTailing(
                  extension: extension,
                  runningAction: runningAction,
                  ref: ref,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardSubtitle extends ConsumerWidget {
  const _CardSubtitle({required this.extension});

  final Extension extension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(settledAccountAccessProvider);
    return Text.rich(
      TextSpan(
        text: '${extension.language?.displayName} ',
        style: const TextStyle(fontWeight: FontWeight.w600),
        children: [
          if (!access.allows(
            extension.isInstalled.ifNull()
                ? Enum$UserPermission.UNINSTALL_EXTENSIONS
                : Enum$UserPermission.INSTALL_EXTENSIONS,
          ))
            TextSpan(
              text: '${context.l10n.accountPermissionDenied} ',
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          if (extension.versionName.isNotBlank)
            TextSpan(
              text: '${extension.versionName} ',
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          if (isNsfwFromWarning(extension.contentWarning))
            TextSpan(
              text: context.l10n.nsfw18,
              style: TextStyle(
                fontWeight: FontWeight.w400,
                color: context.colorScheme.error,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.theme.textTheme.bodySmall,
    );
  }
}
