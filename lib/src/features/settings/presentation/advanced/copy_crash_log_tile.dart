import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/crash/copy_crash_log.dart';
import '../../../../utils/crash/crash_log.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/platform/current_platform_description.dart';
import '../../../about/presentation/about/controllers/about_controller.dart';

class CopyCrashLogTile extends ConsumerWidget {
  const CopyCrashLogTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(context.l10n.copyCrashLog),
      subtitle: Text(context.l10n.copyCrashLogSubtitle),
      leading: const Icon(Icons.bug_report_rounded),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        tooltip: context.l10n.clearCrashLog,
        onPressed: () async {
          clearCrashLog(await initCrashLog());
          if (context.mounted) {
            ref.read(toastProvider)?.show(context.l10n.crashLogCleared);
          }
        },
      ),
      onTap: () async {
        final serverVersion = ref.exists(aboutProvider)
            ? ref.read(aboutProvider).value?.version
            : null;
        final packageInfo = ref.read(packageInfoProvider);
        final header = crashLogHeader(
          appVersion: packageInfo.version,
          buildNumber: packageInfo.buildNumber,
          serverVersion: serverVersion ?? 'unknown',
          platform: currentPlatformDescription(),
        );
        final log = crashLogForClipboard(await initCrashLog(), header: header);
        if (!context.mounted) return;
        final toast = ref.read(toastProvider);
        if (log == null) {
          toast?.show(context.l10n.noCrashLog);
          return;
        }
        await Clipboard.setData(ClipboardData(text: log));
        if (context.mounted) toast?.show(context.l10n.crashLogCopied);
      },
    );
  }
}
