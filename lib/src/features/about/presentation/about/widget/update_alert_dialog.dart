import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../settings/presentation/server/data/web_interface_installer.dart';
import '../../../../settings/presentation/server/data/web_interface_repository.dart';
import '../../../data/web_update_browser.dart';

class UpdateAlertDialog extends ConsumerStatefulWidget {
  const UpdateAlertDialog({
    super.key,
    required this.info,
    required this.onRemindLater,
    required this.onIgnore,
    this.downloadUrl,
    this.changelogUrl,
    this.onInstalled,
  });

  final String info;
  final Future<void> Function() onRemindLater;
  final Future<void> Function() onIgnore;
  final String? downloadUrl;
  final String? changelogUrl;
  final VoidCallback? onInstalled;

  @override
  ConsumerState<UpdateAlertDialog> createState() => _UpdateAlertDialogState();
}

class _UpdateAlertDialogState extends ConsumerState<UpdateAlertDialog> {
  final _closeMenu = GlobalKey<PopupMenuButtonState<bool>>();
  bool _installing = false;
  int _progress = 0;

  WebInterfaceInstaller? _installer;

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
          widget.onInstalled?.call();
          if (mounted) Navigator.pop(context);
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
          if (ignore) {
            await widget.onIgnore();
          } else {
            await widget.onRemindLater();
          }
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
            : widget.downloadUrl != null
            ? () => launchUrlInWeb(
                context,
                widget.downloadUrl!,
                ref.read(toastProvider),
              )
            : _install,
        child: Text(
          _installing
              ? context.l10n.tsumiruUpdating(_progress.toStringAsFixed(0))
              : widget.downloadUrl != null
              ? context.l10n.download
              : context.l10n.update,
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
    this.refresh = false,
    this.onConfirm,
  });

  final String info;
  final String changelog;
  final bool refresh;
  final Future<void> Function()? onConfirm;

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
        onPressed: () async {
          await onConfirm?.call();
          if (!context.mounted) return;
          Navigator.pop(context);
          if (refresh) reloadWebBuild();
        },
        child: Text(refresh ? context.l10n.refresh : context.l10n.ok),
      ),
    ],
  );
}
