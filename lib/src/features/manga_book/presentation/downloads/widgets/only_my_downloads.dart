import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../widgets/compact_switch.dart';

part 'only_my_downloads.g.dart';

@riverpod
class OnlyMyDownloads extends _$OnlyMyDownloads
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.onlyMyDownloads);
}

class OnlyMyDownloadsTile extends ConsumerWidget {
  const OnlyMyDownloadsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CompactSwitchListTile(
      title: Text(context.l10n.onlyMyDownloads),
      onChanged: ref.read(onlyMyDownloadsProvider.notifier).update,
      value: ref.watch(onlyMyDownloadsProvider).ifNull(),
    );
  }
}
