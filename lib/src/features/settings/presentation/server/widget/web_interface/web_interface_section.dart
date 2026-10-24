import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../global_providers/global_providers.dart';
import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/compact_switch.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../../about/data/about_repository.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../../account/domain/account_access.dart';
import '../../../../search/settings_search_registry.dart';
import '../../../../widgets/settings_group_card/settings_group_card.dart';
import '../../data/graphql/__generated__/web_interface.graphql.dart';
import '../../data/web_interface_repository.dart';

class WebInterfaceSection extends ConsumerStatefulWidget {
  const WebInterfaceSection({super.key});

  @override
  ConsumerState<WebInterfaceSection> createState() =>
      _WebInterfaceSectionState();
}

class _WebInterfaceSectionState extends ConsumerState<WebInterfaceSection> {
  Query$CheckWebInterfaceUpdate$checkForWebUIUpdate? _check;
  Fragment$WebInterfaceUpdateStatusDto? _status;
  Enum$WebUIFlavor? _originalFlavor;
  Enum$WebUIFlavor? _checkedFlavor;
  Timer? _pollTimer;
  StreamSubscription? _socketSub;
  bool _socketLive = false;
  bool _busy = false;
  bool _installStarted = false;
  bool _installing = false;
  String? _error;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socketSub?.cancel();
    super.dispose();
  }

  void _acceptInstallStatus(Fragment$WebInterfaceUpdateStatusDto? status) {
    if (!mounted) return;
    final finished = status?.state == Enum$UpdateState.FINISHED;
    setState(() {
      _status = status;
      _installing = !finished && status?.state != Enum$UpdateState.ERROR;
      if (finished) {
        _check = null;
        _originalFlavor = null;
      }
    });
    if (!_installing) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
    if (finished) {
      _socketSub?.cancel();
      _socketSub = null;
      _socketLive = false;
      ref.invalidate(installedWebInterfaceProvider);
      ref.read(webBuildReloadRequiredProvider.notifier).check();
    }
  }

  Future<void> _pollStatus() async {
    _pollTimer = null;
    if (!mounted || !_installing) return;
    try {
      final status = await ref.read(webInterfaceRepositoryProvider).status();
      _acceptInstallStatus(status);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
    if (mounted && _installing && !_socketLive) {
      _pollTimer = Timer(const Duration(seconds: 2), _pollStatus);
    }
  }

  void _watchSocket() {
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _socketSub = ref
          .read(graphQlSubscriptionClientProvider)
          .subscribe$WebInterfaceUpdateStatusChange(
            Options$Subscription$WebInterfaceUpdateStatusChange(),
          )
          .getData((data) => data.webUIUpdateStatusChange)
          .listen(
            (status) {
              _pollTimer?.cancel();
              _pollTimer = null;
              _socketLive = true;
              _acceptInstallStatus(status);
            },
            onError: (_) {
              _socketLive = false;
              if (mounted &&
                  _installing &&
                  (_pollTimer == null || !_pollTimer!.isActive)) {
                _pollTimer = Timer(const Duration(seconds: 2), _pollStatus);
              }
            },
          );
    } catch (_) {
      _socketLive = false;
    }
  }

  Future<void> _install() => _run(() async {
    setState(() {
      _installStarted = true;
      _installing = true;
      _status = null;
      _socketLive = false;
    });
    try {
      final status = await ref.read(webInterfaceRepositoryProvider).install();
      if (status == null) {
        throw StateError('Missing web interface install response');
      }
      _acceptInstallStatus(status);
      if (mounted && _installing) {
        _watchSocket();
        _pollTimer = Timer(const Duration(seconds: 2), _pollStatus);
      }
    } catch (_) {
      if (mounted) setState(() => _installing = false);
      rethrow;
    }
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(Input$PartialSettingsTypeInput patch) => _run(() async {
    final result = await ref.read(webInterfaceRepositoryProvider).write(patch);
    if (result == null) {
      throw StateError('Missing web interface settings response');
    }
    if (!mounted) return;
    setState(() => _check = null);
    ref.invalidate(webInterfaceSettingsProvider);
  });

  Future<void> _pick<T>({
    required String title,
    required T value,
    required List<T> options,
    required String Function(T) name,
    String Function(T)? description,
    required Future<void> Function(T) write,
    bool confirmReplacement = false,
  }) async {
    final selected = await showDialog<T>(
      context: context,
      builder: (context) => RadioListPopup<T>(
        title: title,
        value: value,
        optionList: options,
        getOptionTitle: name,
        getOptionSubtitle: description,
        onChange: (value) => Navigator.pop(context, value),
      ),
      animationStyle: context.motionStyle,
    );
    if (selected == null || selected == value || !mounted) return;
    if (confirmReplacement &&
        !await confirmAction(
          context,
          title: context.l10n.confirmWebInterfaceChangeTitle,
          message: context.l10n.confirmWebInterfaceChangeMessage,
          action: context.l10n.save,
        )) {
      return;
    }
    if (mounted) await write(selected);
  }

  String _flavorName(Enum$WebUIFlavor flavor) => switch (flavor) {
    Enum$WebUIFlavor.WEBUI => context.l10n.webInterfaceWebUI,
    Enum$WebUIFlavor.VUI => context.l10n.webInterfaceVUI,
    Enum$WebUIFlavor.TSUMIRU => context.l10n.webInterfaceTsumiru,
    Enum$WebUIFlavor.CUSTOM => context.l10n.webInterfaceCustom,
    Enum$WebUIFlavor.$unknown => context.l10n.webInterfaceUnknown,
  };

  String _flavorDescription(Enum$WebUIFlavor flavor) => switch (flavor) {
    Enum$WebUIFlavor.WEBUI => context.l10n.webInterfaceWebUIDescription,
    Enum$WebUIFlavor.VUI => context.l10n.webInterfaceVUIDescription,
    Enum$WebUIFlavor.TSUMIRU => context.l10n.webInterfaceTsumiruDescription,
    Enum$WebUIFlavor.CUSTOM => context.l10n.webInterfaceCustomDescription,
    Enum$WebUIFlavor.$unknown => context.l10n.webInterfaceUnknown,
  };

  String _interfaceName(Enum$WebUIInterface value) => switch (value) {
    Enum$WebUIInterface.BROWSER => context.l10n.webInterfaceBrowser,
    Enum$WebUIInterface.ELECTRON => context.l10n.webInterfaceElectron,
    Enum$WebUIInterface.$unknown => context.l10n.webInterfaceUnknown,
  };

  String _channelName(Enum$WebUIChannel channel) => switch (channel) {
    Enum$WebUIChannel.BUNDLED => context.l10n.webInterfaceBundled,
    Enum$WebUIChannel.STABLE => context.l10n.webInterfaceStable,
    Enum$WebUIChannel.PREVIEW => context.l10n.webInterfacePreview,
    Enum$WebUIChannel.$unknown => context.l10n.webInterfaceUnknown,
  };

  String _channelDescription(Enum$WebUIChannel channel) => switch (channel) {
    Enum$WebUIChannel.BUNDLED => context.l10n.webInterfaceBundledDescription,
    Enum$WebUIChannel.STABLE => context.l10n.webInterfaceStableDescription,
    Enum$WebUIChannel.PREVIEW => context.l10n.webInterfacePreviewDescription,
    Enum$WebUIChannel.$unknown => context.l10n.webInterfaceUnknown,
  };

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(settledAccountAccessProvider);
    final canManage = access.allows(Enum$UserPermission.MANAGE_SETTINGS);
    final authenticated = access.capability != AccountCapability.unknown;
    final settings = ref.watch(webInterfaceSettingsProvider);
    final installed = ref.watch(installedWebInterfaceProvider);
    final data = settings.value;
    final flavors = canManage && data != null
        ? ref.watch(webInterfaceFlavorsProvider)
        : const AsyncData<List<Enum$WebUIFlavor>>([]);
    final custom = data?.webUIFlavor == Enum$WebUIFlavor.CUSTOM;
    final downloading = _installing;
    final enabled = !_busy && !downloading;
    final bundledAllowed = data?.webUIFlavor == Enum$WebUIFlavor.WEBUI;
    final check = _check;
    final info = installed.value;
    final error =
        _error ??
        settings.error?.toString() ??
        flavors.error?.toString() ??
        installed.error?.toString();

    final String? updateText;
    if (error != null) {
      updateText = context.l10n.webInterfaceError(error);
    } else if (downloading) {
      updateText = context.l10n.webInterfaceInstalling(_status?.progress ?? 0);
    } else if (_installStarted && _status?.state == Enum$UpdateState.ERROR) {
      updateText = context.l10n.webInterfaceUpdateFailed;
    } else if (_installStarted && _status?.state == Enum$UpdateState.FINISHED) {
      updateText = context.l10n.webInterfaceInstalled;
    } else if (check != null) {
      updateText = check.updateAvailable
          ? _originalFlavor != null &&
                    _originalFlavor != _checkedFlavor &&
                    _checkedFlavor != null
                ? context.l10n.webInterfaceInstallSwitch(
                    _flavorName(_checkedFlavor!),
                  )
                : context.l10n.webInterfaceUpdateAvailable(check.tag)
          : context.l10n.webInterfaceUpToDate;
    } else {
      updateText = null;
    }

    final showInterfaceCard = canManage && data != null;
    final showUpdatesCard = showInterfaceCard || (authenticated && !custom);
    final installedInCard = showInterfaceCard && authenticated;
    final customNoteInCard = showInterfaceCard && custom;

    Widget installedVersionRow() => ListTile(
      title: Text(context.l10n.webInterfaceInstalledVersion),
      subtitle: info == null
          ? null
          : Text('${info.tag} · ${_channelName(info.channel)}'),
    );

    Widget customUpdatesNote() =>
        ListTile(subtitle: Text(context.l10n.webInterfaceCustomUpdates));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (canManage && settings.isLoading && !settings.hasValue)
          const ListTile(title: LinearProgressIndicator()),
        if (canManage && settings.hasValue && data == null)
          ListTile(subtitle: Text(context.l10n.webInterfaceUnsupported)),
        if (!canManage)
          ListTile(
            subtitle: Text(context.l10n.manageSettingsPermissionRequired),
          ),
        if (showInterfaceCard)
          SettingsGroupCard(
            children: [
              SettingsHighlightTarget(
                id: 'webInterfaceFlavor',
                // Keep this row separate from neighboring switches in the semantics tree.
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: ListTile(
                    title: Text(context.l10n.webInterfaceInterface),
                    subtitle: Text(_flavorName(data.webUIFlavor)),
                    onTap:
                        enabled && flavors.hasValue && flavors.value!.isNotEmpty
                        ? () => _pick(
                            title: context.l10n.webInterfaceInterface,
                            confirmReplacement: true,
                            value: data.webUIFlavor,
                            options: flavors.value!,
                            name: _flavorName,
                            description: _flavorDescription,
                            write: (value) async {
                              _originalFlavor ??= data.webUIFlavor;
                              await _write(
                                Input$PartialSettingsTypeInput(
                                  webUIFlavor: value,
                                ),
                              );
                            },
                          )
                        : null,
                  ),
                ),
              ),
              SettingsHighlightTarget(
                id: 'webInterfaceInterface',
                // Keep this row separate from neighboring switches in the semantics tree.
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: ListTile(
                    title: Text(context.l10n.webInterfaceOpenWith),
                    subtitle: Text(_interfaceName(data.webUIInterface)),
                    onTap: enabled
                        ? () => _pick(
                            title: context.l10n.webInterfaceOpenWith,
                            value: data.webUIInterface,
                            options: const [
                              Enum$WebUIInterface.BROWSER,
                              Enum$WebUIInterface.ELECTRON,
                            ],
                            name: _interfaceName,
                            description: (value) =>
                                context.l10n.webInterfaceLaunchDescription,
                            write: (value) => _write(
                              Input$PartialSettingsTypeInput(
                                webUIInterface: value,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              if (data.webUIInterface == Enum$WebUIInterface.ELECTRON)
                SettingsHighlightTarget(
                  id: 'electronPath',
                  // Keep this row separate from neighboring switches in the semantics tree.
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: SettingsPropTile(
                      title: context.l10n.electronPath,
                      subtitle: data.electronPath.isNotEmpty
                          ? data.electronPath
                          : context.l10n.electronPathDefault,
                      description: context.l10n.electronPathDescription,
                      type: SettingsPropType.textField(
                        hintText: context.l10n.enterProp(
                          context.l10n.electronPath,
                        ),
                        value: data.electronPath,
                        onChanged: enabled
                            ? (value) => _write(
                                Input$PartialSettingsTypeInput(
                                  electronPath: value,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              SettingsHighlightTarget(
                id: 'initialOpenInBrowserEnabled',
                child: CompactSwitchListTile(
                  title: Text(context.l10n.initialOpenInBrowserEnabled),
                  value: data.initialOpenInBrowserEnabled,
                  onChanged: enabled
                      ? (value) => _write(
                          Input$PartialSettingsTypeInput(
                            initialOpenInBrowserEnabled: value,
                          ),
                        )
                      : null,
                ),
              ),
              if (installedInCard) installedVersionRow(),
              if (customNoteInCard) customUpdatesNote(),
            ],
          ),
        if (showUpdatesCard) ...[
          SettingsGroupHeading(label: context.l10n.updates),
          SettingsGroupCard(
            children: [
              if (showInterfaceCard)
                SettingsHighlightTarget(
                  id: 'webInterfaceChannel',
                  // Keep this row separate from neighboring switches in the semantics tree.
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: ListTile(
                      title: Text(context.l10n.webInterfaceChannel),
                      subtitle: Text(
                        data.webUIChannel == Enum$WebUIChannel.BUNDLED &&
                                !bundledAllowed
                            ? '${_channelName(data.webUIChannel)}\n${context.l10n.webInterfaceBundledOnly}'
                            : _channelName(data.webUIChannel),
                      ),
                      onTap: enabled && !custom
                          ? () => _pick(
                              title: context.l10n.webInterfaceChannel,
                              confirmReplacement: true,
                              value: data.webUIChannel,
                              options: [
                                if (bundledAllowed) Enum$WebUIChannel.BUNDLED,
                                Enum$WebUIChannel.STABLE,
                                Enum$WebUIChannel.PREVIEW,
                              ],
                              name: _channelName,
                              description: _channelDescription,
                              write: (value) => _write(
                                Input$PartialSettingsTypeInput(
                                  webUIChannel: value,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              if (showInterfaceCard)
                SettingsHighlightTarget(
                  id: 'webInterfaceAutomaticUpdates',
                  // Keep this row separate from neighboring switches in the semantics tree.
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: ListTile(
                      title: Text(context.l10n.webInterfaceAutomaticUpdates),
                      subtitle: Text(
                        data.webUIUpdateCheckInterval == 0
                            ? context.l10n.webInterfaceOff
                            : context.l10n.webInterfaceHours(
                                data.webUIUpdateCheckInterval.toInt(),
                              ),
                      ),
                      onTap: enabled && !custom
                          ? () => _pick(
                              title: context.l10n.webInterfaceAutomaticUpdates,
                              value: data.webUIUpdateCheckInterval.toInt(),
                              options: List.generate(24, (index) => index),
                              name: (value) => value == 0
                                  ? context.l10n.webInterfaceOff
                                  : context.l10n.webInterfaceHours(value),
                              write: (value) => _write(
                                Input$PartialSettingsTypeInput(
                                  webUIUpdateCheckInterval: value.toDouble(),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              if (authenticated && !custom)
                SettingsHighlightTarget(
                  id: 'webInterfaceCheckUpdate',
                  // Keep this row separate from neighboring switches in the semantics tree.
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: ListTile(
                      title: Text(context.l10n.webInterfaceCheckUpdate),
                      subtitle: updateText == null && !_busy
                          ? null
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (updateText != null)
                                  Text(
                                    updateText,
                                    style:
                                        error != null ||
                                            _status?.state ==
                                                Enum$UpdateState.ERROR
                                        ? TextStyle(
                                            color:
                                                context.theme.colorScheme.error,
                                          )
                                        : null,
                                  ),
                                if (downloading || _busy)
                                  LinearProgressIndicator(
                                    value: downloading
                                        ? (_status?.progress ?? 0).clamp(
                                                0,
                                                100,
                                              ) /
                                              100
                                        : null,
                                  ),
                              ],
                            ),
                      trailing: check?.updateAvailable == true && !downloading
                          ? TextButton(
                              onPressed: enabled ? _install : null,
                              child: Text(
                                context.l10n.webInterfaceInstallUpdate,
                              ),
                            )
                          : null,
                      onTap: enabled
                          ? () => _run(() async {
                              final result = await ref
                                  .read(webInterfaceRepositoryProvider)
                                  .check();
                              if (result == null) {
                                throw StateError(
                                  'Missing web interface update response',
                                );
                              }
                              if (mounted) {
                                setState(() {
                                  _check = result;
                                  _installStarted = false;
                                  _status = null;
                                  _checkedFlavor = data?.webUIFlavor;
                                });
                              }
                            })
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (authenticated && !installedInCard) installedVersionRow(),
        if (custom && !customNoteInCard) customUpdatesNote(),
      ],
    );
  }
}
