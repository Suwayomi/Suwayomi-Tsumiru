import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/popup_widgets/confirm_action.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';
import '../data/reconcile_logic.dart';

Future<void> confirmDeleteChapterFromDevice(
  WidgetRef ref,
  int chapterId,
) async {
  final context = ref.context;
  final current = ref
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  if (!await confirmAction(
        context,
        title: context.l10n.removeFromDevice,
        message: context.l10n.confirmDeleteDeviceMessage,
        action: context.l10n.removeFromDevice,
      ) ||
      !context.mounted ||
      !current()) {
    return;
  }
  await deleteChapterFromDevice(ref, chapterId);
}

Future<bool> confirmKeepRuleChanges(
  WidgetRef ref,
  Iterable<int> mangaIds,
  OfflineKeepRule rule,
  int count,
) async {
  if (!ref.read(offlineActiveProvider)) return true;
  final context = ref.context;
  final current = ref
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  final db = ref.read(offlineDatabaseProvider);
  final nets = ref.read(safetyNetConfigProvider);
  final protected = ref.read(sessionReadChaptersProvider);
  final slots = ref.read(localDeleteSettingsProvider).deleteWhileReading;
  var deletes = false;
  for (final id in mangaIds) {
    final manga = await db.mangaById(id);
    if (manga == null ||
        (manga.keepRule == rule && manga.keepUnreadCount == count)) {
      continue;
    }
    if (!context.mounted || !current()) return false;
    final chapters = await db.chaptersForManga(id);
    final retained = retainedChapterIds(
      chapters,
      rule,
      count,
      sortAxis: manga.chapterSortMode,
    );
    final plan = applySafetyNets(
      downloaded: chapters
          .where((c) => c.deviceState == OfflineDeviceState.downloaded)
          .toList(),
      desired: retained,
      nets: nets,
      now: DateTime.now(),
      protected: {...protected, ...readChaptersInDeleteWindow(chapters, slots)},
    );
    if (plan.evict.isNotEmpty) {
      deletes = true;
      break;
    }
  }
  if (!context.mounted || !current()) return false;
  if (!deletes) return true;
  final confirmed = await confirmAction(
    context,
    title: context.l10n.confirmKeepRuleTitle,
    message: context.l10n.confirmKeepRuleMessage,
    action: context.l10n.save,
  );
  return confirmed && context.mounted && current();
}

Future<bool> confirmAndChangeKeepRule(
  WidgetRef ref,
  int mangaId,
  OfflineKeepRule rule,
  int count,
) async {
  if (!await confirmKeepRuleChanges(ref, [mangaId], rule, count) ||
      !ref.context.mounted) {
    return false;
  }
  await changeKeepRule(ref, mangaId, rule, count);
  return true;
}
