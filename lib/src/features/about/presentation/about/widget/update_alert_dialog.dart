import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../settings/presentation/server/data/web_interface_installer.dart';
import '../../../../settings/presentation/server/data/web_interface_repository.dart';
import '../../../data/about_repository.dart';

class UpdateAlertDialog extends ConsumerStatefulWidget {
  const UpdateAlertDialog({
    super.key,
    required this.info,
    required this.onRemindLater,
    required this.onIgnore,
    this.downloadUrl,
    this.changelogUrl,
  });

  final String info;
  final Future<void> Function() onRemindLater, onIgnore;
  final String? downloadUrl, changelogUrl;

  @override
  ConsumerState<UpdateAlertDialog> createState() => _UpdateAlertDialogState();
}

class _UpdateAlertDialogState extends ConsumerState<UpdateAlertDialog> {
  final _closeMenu = GlobalKey<PopupMenuButtonState<bool>>();
  WebInterfaceInstaller? _installer;
  bool _installing = false;
  int _progress = 0;

  @override
  void dispose() {
    _installer?.dispose();
    super.dispose();
  }

  void _failed() {
    if (!mounted) return;
    _installer?.dispose();
    setState(() => _installing = false);
    ref.read(toastProvider)?.showError(context.l10n.couldNotUpdateTsumiru);
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    _installer?.dispose();
    _installer = WebInterfaceInstaller(
      ref.read(webInterfaceRepositoryProvider),
      ref.read(graphQlSubscriptionClientProvider),
      onStatus: (status) {
        if (!mounted) return;
        if (status.state == Enum$UpdateState.ERROR) {
          _failed();
        } else if (status.state == Enum$UpdateState.FINISHED) {
          ref.invalidate(installedWebInterfaceProvider);
          ref.read(webBuildReloadRequiredProvider.notifier).check();
          Navigator.pop(context);
        } else {
          setState(() => _progress = status.progress);
        }
      },
      onError: (_) => _failed(),
    );
    try {
      await _installer!.install();
    } catch (_) {
      _failed();
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.updateAvailableTitle),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.info),
        if (_installing)
          LinearProgressIndicator(value: _progress.clamp(0, 100) / 100),
      ],
    ),
    actions: [
      if (widget.changelogUrl != null)
        TextButton(
          onPressed: () => launchUrlInWeb(
            context,
            widget.changelogUrl!,
            ref.read(toastProvider),
          ),
          child: Text(context.l10n.updateChangelog),
        ),
      PopupMenuButton<bool>(
        key: _closeMenu,
        enabled: !_installing,
        onSelected: (ignore) async {
          await (ignore ? widget.onIgnore() : widget.onRemindLater());
          if (context.mounted) Navigator.pop(context);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: false,
            child: Text(context.l10n.updateRemindLater),
          ),
          PopupMenuItem(value: true, child: Text(context.l10n.updateIgnore)),
        ],
        child: TextButton(
          onPressed: _installing
              ? null
              : () => _closeMenu.currentState?.showButtonMenu(),
          child: Text(context.l10n.close),
        ),
      ),
      ElevatedButton(
        onPressed: _installing
            ? null
            : widget.downloadUrl == null
            ? _install
            : () => launchUrlInWeb(
                context,
                widget.downloadUrl!,
                ref.read(toastProvider),
              ),
        child: Text(
          _installing
              ? context.l10n.tsumiruUpdating(_progress.toString())
              : widget.downloadUrl == null
              ? context.l10n.install
              : context.l10n.download,
        ),
      ),
    ],
  );
}

class UpdatedVersionDialog extends ConsumerWidget {
  const UpdatedVersionDialog({
    super.key,
    required this.info,
    required this.changelog,
  });
  final String info, changelog;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AlertDialog(
    title: Text(context.l10n.updatedVersionTitle),
    content: Text(info),
    actions: [
      TextButton(
        onPressed: () =>
            launchUrlInWeb(context, changelog, ref.read(toastProvider)),
        child: Text(context.l10n.updateChangelog),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.ok),
      ),
    ],
  );
}
