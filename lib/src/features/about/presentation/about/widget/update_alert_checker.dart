import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../../constants/urls.dart';
import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/logger/logger.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../settings/presentation/server/data/web_interface_repository.dart';
import '../../../data/about_repository.dart';
import '../../../data/server_update_alerts_repository.dart';
import '../../../domain/server_update/server_update.dart';
import 'update_alert_dialog.dart';

class UpdateAlertChecker {
  UpdateAlertChecker(this.context, this.container);
  final BuildContext context;
  final ProviderContainer container;
  late final serverReminder = UpdateReminderStore(
    container.read(sharedPreferencesProvider),
    'server',
  );
  late final webReminder = UpdateReminderStore(
    container.read(sharedPreferencesProvider),
    'webUI',
  );
  Timer? _timer;
  bool _active = true, _busy = false;
  bool get _valid => _active && context.mounted;
  bool get _canManage => container
      .read(settledAccountAccessProvider)
      .allows(Enum$UserPermission.MANAGE_SETTINGS);
  Future<void> start() async {
    await _tick(check: false);
    if (!_valid || !_canManage) return;
    final remaining =
        updateCheckInterval.inMilliseconds -
        (DateTime.now().millisecondsSinceEpoch -
            serverReminder.lastUpdateCheck);
    _timer = Timer(
      Duration(
        milliseconds: remaining.clamp(0, updateCheckInterval.inMilliseconds),
      ),
      () {
        _timer = Timer.periodic(updateCheckInterval, (_) => _tick());
        _tick();
      },
    );
  }

  void dispose() {
    _active = false;
    _timer?.cancel();
  }

  Future<void> _open(Widget dialog) => !_valid
      ? Future.value()
      : showDialog<void>(
          context: context,
          barrierDismissible: false,
          animationStyle: context.motionStyle,
          builder: (_) => PopScope(canPop: false, child: dialog),
        );
  Future<void> _tick({bool check = true}) async {
    if (!_valid || _busy) return;
    _busy = true;
    try {
      await container.read(startupWebRevisionProvider.future);
      if (!_valid) return;
      if (check && _canManage) {
        await serverReminder.checked();
      }
      final settings = await container
          .read(serverUpdateAlertsRepositoryProvider)
          .settings();
      final about = await container.read(aboutRepositoryProvider).getAbout();
      if (!context.mounted || !_active || settings == null) return;
      final l10n = context.l10n;
      Future<void> showUpdated({
        required String? previous,
        required String current,
        required bool inform,
        required UpdatedVersionDialog dialog,
        required void Function(String) store,
      }) async {
        if (current.isBlank) return;
        if (previous.isNotBlank && previous != current && inform) {
          await _open(dialog);
        }
        if (_valid) store(current);
      }

      if (about != null) {
        await showUpdated(
          previous: container.read(lastSeenServerVersionProvider),
          current: about.version,
          inform: settings.informVersionUpdated,
          dialog: UpdatedVersionDialog(
            info: l10n.serverVersionUpdated(about.version, about.buildType),
            changelog: about.buildType.toLowerCase() == 'stable'
                ? 'https://github.com/Suwayomi/Suwayomi-Server/releases/tag/${about.version}'
                : 'https://github.com/Suwayomi/Suwayomi-Server/blob/master/CHANGELOG.md',
          ),
          store: container.read(lastSeenServerVersionProvider.notifier).update,
        );
      }
      if (!_valid) return;
      final hosted = container.read(serverHostedWebProvider);
      final repository = container.read(webInterfaceRepositoryProvider);
      final installed = hosted ? await repository.installed() : null;
      final changelog = installed?.channel == Enum$WebUIChannel.STABLE
          ? AppUrls.latestReleaseUrl.url
          : AppUrls.whatsNew.url;
      if (installed != null) {
        await showUpdated(
          previous: container.read(lastSeenWebUIVersionProvider),
          current: installed.tag,
          inform: settings.webUIInformVersionUpdated,
          dialog: UpdatedVersionDialog(
            info: l10n.tsumiruVersionUpdated(
              installed.tag,
              installed.channel.name,
            ),
            changelog: changelog,
          ),
          store: container.read(lastSeenWebUIVersionProvider.notifier).update,
        );
      }
      if (!_valid || !_canManage || !check) return;
      ServerUpdate? serverUpdate;
      if (settings.informAvailableUpdate) {
        final updates = await container
            .read(aboutRepositoryProvider)
            .checkServerUpdate();
        serverUpdate = updates
            ?.where((update) => update.channel == about?.buildType)
            .firstOrNull;
      }
      final webSettings = _valid && _canManage && hosted
          ? await repository.settings()
          : null;
      if (!_valid || !_canManage) return;
      final checkWeb =
          webSettings?.webUIFlavor == Enum$WebUIFlavor.TSUMIRU &&
          webSettings?.webUIUpdateCheckInterval == 0 &&
          settings.webUIInformAvailableUpdate;
      final webUpdate = checkWeb ? await repository.check() : null;
      if (!_valid || !_canManage) return;
      final update = serverUpdate;
      if (context.mounted &&
          settings.informAvailableUpdate &&
          about != null &&
          (update?.tag).isNotBlank &&
          update!.tag != about.version &&
          update.url != null &&
          serverReminder.show(update.tag!) &&
          GoRouter.of(context).routeInformationProvider.value.uri.path !=
              const AboutRoute().location) {
        await _open(
          UpdateAlertDialog(
            info: l10n.serverVersionAvailable(
              update.tag!,
              update.channel ?? '',
            ),
            downloadUrl: update.url,
            onRemindLater: serverReminder.remindLater,
            onIgnore: () => serverReminder.ignore(update.tag!),
          ),
        );
      }
      if (_valid &&
          _canManage &&
          checkWeb &&
          webUpdate?.updateAvailable == true &&
          webReminder.show(webUpdate!.tag)) {
        await _open(
          UpdateAlertDialog(
            info: l10n.tsumiruVersionAvailable(
              webUpdate.tag,
              webUpdate.channel.name,
            ),
            changelogUrl: changelog,
            onRemindLater: webReminder.remindLater,
            onIgnore: () => webReminder.ignore(webUpdate.tag),
          ),
        );
      }
    } catch (error, stack) {
      logger.w('Update check failed', error: error, stackTrace: stack);
    } finally {
      _busy = false;
    }
  }
}
