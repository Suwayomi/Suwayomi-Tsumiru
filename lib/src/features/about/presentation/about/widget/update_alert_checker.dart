import 'dart:async';
import 'dart:math';
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
import '../../../../settings/presentation/server/data/graphql/__generated__/web_interface.graphql.dart';
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
  ServerUpdate? _serverUpdate;
  Query$CheckWebInterfaceUpdate$checkForWebUIUpdate? _webUpdate;
  bool get _valid => _active && context.mounted;
  bool get _canManage => container
      .read(settledAccountAccessProvider)
      .allows(Enum$UserPermission.MANAGE_SETTINGS);
  Future<void> start() async {
    await _tick(check: false);
    if (!_valid || !_canManage) return;
    final lastCheck = container.read(serverHostedWebProvider)
        ? max(serverReminder.lastUpdateCheck, webReminder.lastUpdateCheck)
        : serverReminder.lastUpdateCheck;
    final remaining =
        updateCheckInterval.inMilliseconds -
        (DateTime.now().millisecondsSinceEpoch - lastCheck);
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
        if (container.read(serverHostedWebProvider)) {
          await webReminder.checked();
        }
      }
      final settings = await container
          .read(serverUpdateAlertsRepositoryProvider)
          .settings();
      final about = await container.read(aboutRepositoryProvider).getAbout();
      if (!context.mounted || !_active || settings == null) return;
      final l10n = context.l10n;
      if (about != null) {
        final decision = decideServerUpdateAlerts(
          currentVersion: about.version,
          lastSeenVersion: container.read(lastSeenServerVersionProvider),
          informVersionUpdated: settings.informVersionUpdated,
        );
        if (decision.showUpdatedNotice) {
          await _open(
            UpdatedVersionDialog(
              info: l10n.serverVersionUpdated(about.version, about.buildType),
              changelog: about.buildType.toLowerCase() == 'stable'
                  ? 'https://github.com/Suwayomi/Suwayomi-Server/releases/tag/${about.version}'
                  : 'https://github.com/Suwayomi/Suwayomi-Server/blob/master/CHANGELOG.md',
            ),
          );
        }
        if (_valid && decision.storeVersion) {
          container
              .read(lastSeenServerVersionProvider.notifier)
              .update(about.version);
        }
      }
      if (!_valid) return;
      final hosted = container.read(serverHostedWebProvider);
      final repository = container.read(webInterfaceRepositoryProvider);
      final installed = hosted ? await repository.installed() : null;
      final changelog = installed?.channel == Enum$WebUIChannel.STABLE
          ? AppUrls.latestReleaseUrl.url
          : AppUrls.whatsNew.url;
      if (installed != null) {
        final previous = container.read(lastSeenWebUIVersionProvider);
        if (previous != null &&
            previous != installed.tag &&
            settings.webUIInformVersionUpdated) {
          await _open(
            UpdatedVersionDialog(
              info: l10n.tsumiruVersionUpdated(
                installed.tag,
                installed.channel.name,
              ),
              changelog: changelog,
            ),
          );
        }
        if (_valid) {
          container
              .read(lastSeenWebUIVersionProvider.notifier)
              .update(installed.tag);
        }
      }
      if (!_valid || !_canManage || !check) return;
      if (settings.informAvailableUpdate) {
        final updates = await container
            .read(aboutRepositoryProvider)
            .checkServerUpdate();
        _serverUpdate = updates
            ?.where((update) => update.channel == about?.buildType)
            .firstOrNull;
      }
      final webSettings = _valid && _canManage && hosted
          ? await repository.settings()
          : null;
      final checkWeb =
          webSettings?.webUIFlavor == Enum$WebUIFlavor.TSUMIRU &&
          webSettings?.webUIUpdateCheckInterval == 0 &&
          settings.webUIInformAvailableUpdate;
      if (checkWeb) _webUpdate = await repository.check();
      if (!_valid || !_canManage) return;
      final update = _serverUpdate;
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
      final webUpdate = _webUpdate;
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
