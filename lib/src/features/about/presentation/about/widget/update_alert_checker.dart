import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/logger/logger.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../account/domain/account_access.dart';
import '../../../../settings/presentation/server/data/graphql/__generated__/web_interface.graphql.dart';
import '../../../../settings/presentation/server/data/web_interface_repository.dart';
import '../../../data/about_repository.dart';
import '../../../data/hosted_web_update.dart';
import '../../../data/server_update_alerts_repository.dart';
import '../../../domain/about/about_dto.dart';
import '../../../domain/server_update/server_update.dart';
import 'update_alert_dialog.dart';

class UpdateAlertChecker {
  UpdateAlertChecker(this.context, this.container)
    : router = GoRouter.of(context),
      serverReminder = UpdateReminderStore(
        container.read(sharedPreferencesProvider),
        'server',
      ),
      webReminder = UpdateReminderStore(
        container.read(sharedPreferencesProvider),
        'webUI',
      );

  final BuildContext context;
  final ProviderContainer container;
  final GoRouter router;
  final UpdateReminderStore serverReminder;
  final UpdateReminderStore webReminder;
  Timer? _timer;
  ProviderSubscription<bool>? _reloadSubscription;
  DialogRoute<void>? _dialog;
  bool _active = true, _running = false, _rerun = false, _needsCheck = false;
  bool _checkWeb = false;
  AboutDto? _about;
  ServerUpdate? _serverUpdate;
  ServerUpdateAlertSettings? _settings;
  Query$InstalledWebInterface$aboutWebUI? _installed;
  Query$CheckWebInterfaceUpdate$checkForWebUIUpdate? _webUpdate;

  bool get _valid => _active && context.mounted;
  bool get _canManage => container.read(settledAccountAccessProvider)
      .allows(Enum$UserPermission.MANAGE_SETTINGS);
  bool get _hosted => container.read(serverHostedWebProvider);
  bool get _onAbout => router.routeInformationProvider.value.uri.path == const AboutRoute().location;

  Future<void> start() async {
    await container.read(startupWebRevisionProvider.future);
    if (!_valid) return;
    router.routeInformationProvider.addListener(_routeChanged);
    _reloadSubscription = container.listen(webBuildReloadRequiredProvider, (_, required) {
      if (required) _run(check: true);
    });
    await _run(check: true);
  }

  void dispose() {
    _active = false;
    _timer?.cancel();
    _reloadSubscription?.close();
    router.routeInformationProvider.removeListener(_routeChanged);
    _removeDialog();
  }

  void _removeDialog() {
    final dialog = _dialog;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (dialog?.isActive == true) dialog!.navigator?.removeRoute(dialog);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _routeChanged() {
    if (_onAbout && _dialog?.settings.name == 'serverAvailable') _removeDialog();
    if (!_onAbout) _run();
  }

  Future<void> _run({bool check = false}) async {
    if (!_valid) return;
    _needsCheck |= check;
    _rerun = true;
    if (_running) return;
    _running = true;
    try {
      while (_valid && _rerun) {
        _rerun = false;
        if (_needsCheck) {
          _needsCheck = false;
          try {
            await _check();
            _schedule();
          } catch (error, stack) {
            logger.w('Update check failed', error: error, stackTrace: stack);
            _timer?.cancel();
            if (_valid) _timer = Timer(const Duration(minutes: 1), () => _run(check: true));
          }
        }
        if (_valid && _settings != null) await _present();
      }
    } catch (error, stack) {
      logger.w('Update dialog failed', error: error, stackTrace: stack);
    } finally {
      _running = false;
    }
  }

  Future<void> _check() async {
    if (container.read(settledAccountAccessProvider).capability == AccountCapability.unknown) {
      throw StateError('Account access unavailable');
    }
    _settings = await container.read(serverUpdateAlertsRepositoryProvider).settings();
    if (!_valid || _settings == null) return;
    _about = await container.read(aboutRepositoryProvider).getAbout();
    if (_canManage) {
      if (_settings!.informAvailableUpdate && serverReminder.nextCheck <= DateTime.now().millisecondsSinceEpoch) {
        final updates = await container.read(aboutRepositoryProvider).checkServerUpdate();
        _serverUpdate = updates?.where((update) => update.channel == _about?.buildType).firstOrNull;
        await serverReminder.checked();
      }
    }
    _checkWeb = false;
    if (!_valid || !_hosted) return;
    final repository = container.read(webInterfaceRepositoryProvider);
    _installed = await repository.installed();
    await container.read(webBuildReloadRequiredProvider.notifier).check();
    if (_canManage) {
      final settings = await repository.settings();
      _checkWeb = isTsumiruFlavor(settings?.webUIFlavor.name) &&
          settings?.webUIUpdateCheckInterval == 0 && _settings!.webUIInformAvailableUpdate;
      if (_checkWeb && webReminder.nextCheck <= DateTime.now().millisecondsSinceEpoch) {
        _webUpdate = await repository.check();
        await webReminder.checked();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    var next = now + updateCheckInterval.inMilliseconds;
    for (final reminder in [if (_canManage && _settings?.informAvailableUpdate == true) serverReminder, if (_checkWeb) webReminder]) {
      for (final timestamp in [reminder.nextCheck, reminder.reminderEnds]) {
        if (timestamp > now && timestamp < next) next = timestamp;
      }
    }
    if (_valid) _timer = Timer(Duration(milliseconds: next - now), () => _run(check: true));
  }

  Future<void> _open(Widget dialog, {String? name, bool dismissible = false}) async {
    if (!_valid) return;
    final route = DialogRoute<void>(
      context: context,
      settings: RouteSettings(name: name),
      barrierDismissible: dismissible,
      builder: (_) => PopScope(canPop: dismissible, child: dialog),
      animationStyle: context.motionStyle,
    );
    _dialog = route;
    try {
      await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      if (_dialog == route) _dialog = null;
    }
  }

  Future<void> _present() async {
    final settings = _settings!;
    final about = _about, update = _serverUpdate;
    if (_canManage && !_onAbout && settings.informAvailableUpdate && about != null &&
        (update?.tag).isNotBlank && update!.tag != about.version && update.url != null && serverReminder.show(update.tag!)) {
      await _open(UpdateAlertDialog(
        info: context.l10n.serverVersionAvailable(update.tag!, update.channel ?? ''),
        downloadUrl: update.url,
        onRemindLater: serverReminder.remindLater,
        onIgnore: () => serverReminder.ignore(update.tag!),
      ), name: 'serverAvailable');
    }
    if (!_valid || !context.mounted) return;
    if (about != null) {
      final decision = decideServerUpdateAlerts(currentVersion: about.version,
        lastSeenVersion: container.read(lastSeenServerVersionProvider), informVersionUpdated: settings.informVersionUpdated);
      if (decision.showUpdatedNotice) {
        await _open(UpdatedVersionDialog(
        info: context.l10n.serverVersionUpdated(about.version, about.buildType),
        changelog: about.buildType.toLowerCase() == 'stable'
            ? 'https://github.com/Suwayomi/Suwayomi-Server/releases/tag/${about.version}'
            : 'https://github.com/Suwayomi/Suwayomi-Server/blob/master/CHANGELOG.md',
        ));
      }
      if (_valid && decision.storeVersion) container.read(lastSeenServerVersionProvider.notifier).update(about.version);
    }
    if (!_valid || !context.mounted || !_hosted) return;
    final webUpdate = _webUpdate, installed = _installed;
    final channel = installed?.channel.name ?? '';
    final changelog = channel == 'STABLE' ? 'https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest' : 'https://github.com/Suwayomi/Suwayomi-Tsumiru/releases';
    if (_canManage && _checkWeb && webUpdate?.updateAvailable == true && webReminder.show(webUpdate!.tag)) {
      await _open(UpdateAlertDialog(
        info: context.l10n.tsumiruVersionAvailable(webUpdate.tag, webUpdate.channel.name),
        changelogUrl: changelog, onRemindLater: webReminder.remindLater,
        onIgnore: () => webReminder.ignore(webUpdate.tag),
        onInstalled: () { _webUpdate = null; _run(check: true); },
      ));
    }
    if (!_valid || !context.mounted || installed == null) return;
    final preferences = container.read(sharedPreferencesProvider);
    final previous = preferences.getString('webUIVersion');
    if (previous != null && previous != installed.tag && settings.webUIInformVersionUpdated) {
      final refresh = container.read(webBuildReloadRequiredProvider);
      await _open(UpdatedVersionDialog(info: context.l10n.tsumiruVersionUpdated(installed.tag, channel),
        changelog: changelog, refresh: refresh,
        onConfirm: () async { await preferences.setString('webUIVersion', installed.tag); },
      ), dismissible: refresh);
    }
    if (_valid && preferences.getString('webUIVersion') != installed.tag) {
      await preferences.setString('webUIVersion', installed.tag);
    }
  }
}
