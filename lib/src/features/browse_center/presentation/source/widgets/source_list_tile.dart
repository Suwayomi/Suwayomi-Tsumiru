// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../widgets/server_image.dart';
import '../../../data/source_repository/source_repository.dart';
import '../../../domain/source/source_model.dart';
import '../controller/source_controller.dart';

class SourceListTile extends ConsumerWidget {
  const SourceListTile({super.key, required this.source});

  final SourceDto source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      onTap: (() async {
        ref.read(sourceLastUsedProvider.notifier).update(source.id);
        SourceTypeRoute(
          sourceId: source.id,
          sourceType: SourceType.POPULAR,
        ).go(context);
      }),
      leading: ClipRRect(
        borderRadius: KBorderRadius.r8.radius,
        child: ServerImage(
          imageUrl: source.iconUrl,
          size: const Size.square(48),
        ),
      ),
      title: Text(source.name),
      subtitle: (source.language?.displayName).isNotBlank
          ? Text(source.language?.displayName ?? "")
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (source.supportsLatest.ifNull())
            TextButton(
              onPressed: () async {
                ref.read(sourceLastUsedProvider.notifier).update(source.id);
                SourceTypeRoute(
                  sourceId: source.id,
                  sourceType: SourceType.LATEST,
                ).go(context);
              },
              child: Text(context.l10n.latest),
            ),
          _PinButton(source: source),
        ],
      ),
    );
  }
}

class _PinButton extends ConsumerWidget {
  const _PinButton({required this.source});

  final SourceDto source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = source.isPinned;
    return IconButton(
      tooltip: pinned ? context.l10n.unpinSource : context.l10n.pinSource,
      icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
      color: pinned ? context.theme.colorScheme.primary : null,
      onPressed: () async {
        try {
          await ref
              .read(sourceRepositoryProvider)
              .setSourcePinned(source.id, !pinned);
          ref.invalidate(sourceListProvider);
        } catch (e) {
          if (context.mounted) {
            ref.read(toastProvider)?.showError(e.toString());
          }
        }
      },
    );
  }
}
