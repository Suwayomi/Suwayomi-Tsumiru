import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/endpoints.dart';
import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../../../widgets/section_title.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../../account/domain/account_access.dart';
import '../../data/graphql/__generated__/web_interface.graphql.dart';
import '../../data/web_interface_repository.dart';
import '../client/server_port_tile/server_port_tile.dart';
import '../client/server_url_tile/server_url_tile.dart';

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
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_pollStatus);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollStatus() async {
    if (!mounted) return;
    final authenticated =
        ref.read(settledAccountAccessProvider).capability !=
        AccountCapability.unknown;
    if (authenticated) {
      try {
        final status = await ref.read(webInterfaceRepositoryProvider).status();
        if (!mounted) return;
        final finished =
            status?.state == Enum$UpdateState.FINISHED &&
            _status?.state != Enum$UpdateState.FINISHED;
        setState(() => _status = status);
        if (finished) {
          setState(() {
            _check = null;
            _originalFlavor = null;
          });
          ref.invalidate(installedWebInterfaceProvider);
        }
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    }
    if (mounted) _pollTimer = Timer(const Duration(seconds: 2), _pollStatus);
  }

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
    if (selected != null && selected != value && mounted) await write(selected);
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
    final downloading = _status?.state == Enum$UpdateState.DOWNLOADING;
    final enabled = !_busy && !downloading;
    final bundledAllowed = data?.webUIFlavor == Enum$WebUIFlavor.WEBUI;
    final sameServer =
        kIsWeb &&
        isServerWebInterface(
          Endpoints.baseApi(
            baseUrl: ref.watch(serverUrlProvider),
            port: ref.watch(serverPortProvider),
            addPort: ref.watch(serverPortToggleProvider).ifNull(),
            appendApiToUrl: false,
          ),
          Uri.base,
        );
    final check = _check;
    final info = installed.value;
    final error =
        _error ??
        settings.error?.toString() ??
        flavors.error?.toString() ??
        installed.error?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: context.l10n.webInterface),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            sameServer
                ? context.l10n.webInterfaceExplanationCurrent
                : context.l10n.webInterfaceExplanation,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (canManage && settings.isLoading && !settings.hasValue)
          const ListTile(title: LinearProgressIndicator()),
        if (canManage && settings.hasValue && data == null)
          ListTile(subtitle: Text(context.l10n.webInterfaceUnsupported)),
        if (!canManage)
          ListTile(
            subtitle: Text(context.l10n.manageSettingsPermissionRequired),
          ),
        if (canManage && data != null) ...[
          ListTile(
            title: Text(context.l10n.webInterfaceFlavor),
            subtitle: Text(_flavorName(data.webUIFlavor)),
            onTap: enabled && flavors.hasValue && flavors.value!.isNotEmpty
                ? () => _pick(
                    title: context.l10n.webInterfaceFlavor,
                    value: data.webUIFlavor,
                    options: flavors.value!,
                    name: _flavorName,
                    description: _flavorDescription,
                    write: (value) async {
                      _originalFlavor ??= data.webUIFlavor;
                      await _write(
                        Input$PartialSettingsTypeInput(webUIFlavor: value),
                      );
                    },
                  )
                : null,
          ),
          ListTile(
            title: Text(context.l10n.webInterfaceChannel),
            subtitle: Text(_channelName(data.webUIChannel)),
            onTap: enabled && !custom
                ? () => _pick(
                    title: context.l10n.webInterfaceChannel,
                    value: data.webUIChannel,
                    options: [
                      if (bundledAllowed) Enum$WebUIChannel.BUNDLED,
                      Enum$WebUIChannel.STABLE,
                      Enum$WebUIChannel.PREVIEW,
                    ],
                    name: _channelName,
                    description: _channelDescription,
                    write: (value) => _write(
                      Input$PartialSettingsTypeInput(webUIChannel: value),
                    ),
                  )
                : null,
          ),
          if (!bundledAllowed && !custom)
            ListTile(subtitle: Text(context.l10n.webInterfaceBundledOnly)),
          ListTile(
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
        ],
        if (authenticated)
          ListTile(
            title: Text(context.l10n.webInterfaceInstalledVersion),
            subtitle: info == null
                ? null
                : Text('${info.tag} · ${_channelName(info.channel)}'),
          ),
        if (custom)
          ListTile(subtitle: Text(context.l10n.webInterfaceCustomUpdates)),
        if (canManage &&
            data != null &&
            _originalFlavor != null &&
            check == null &&
            !custom)
          ListTile(subtitle: Text(context.l10n.webInterfaceCheckAfterChange)),
        if (authenticated && !custom) ...[
          ListTile(
            title: Text(context.l10n.webInterfaceCheckUpdate),
            onTap: enabled
                ? () => _run(() async {
                    final result = await ref
                        .read(webInterfaceRepositoryProvider)
                        .check();
                    if (result == null) {
                      throw StateError('Missing web interface update response');
                    }
                    if (mounted) {
                      setState(() {
                        _check = result;
                        _checkedFlavor = data?.webUIFlavor;
                      });
                    }
                  })
                : null,
          ),
          if (check != null)
            ListTile(
              subtitle: Text(
                check.updateAvailable
                    ? _originalFlavor != null &&
                              _originalFlavor != _checkedFlavor &&
                              _checkedFlavor != null
                          ? context.l10n.webInterfaceInstallSwitch(
                              _flavorName(_checkedFlavor!),
                            )
                          : context.l10n.webInterfaceUpdateAvailable(check.tag)
                    : context.l10n.webInterfaceUpToDate,
              ),
            ),
          if (check?.updateAvailable == true)
            ListTile(
              title: Text(context.l10n.webInterfaceInstallUpdate),
              onTap: enabled
                  ? () => _run(() async {
                      final status = await ref
                          .read(webInterfaceRepositoryProvider)
                          .install();
                      if (status == null) {
                        throw StateError(
                          'Missing web interface install response',
                        );
                      }
                      if (mounted) setState(() => _status = status);
                    })
                  : null,
            ),
        ],
        if (_busy) const ListTile(title: LinearProgressIndicator()),
        if (downloading)
          ListTile(
            title: Text(context.l10n.webInterfaceInstalling(_status!.progress)),
            subtitle: LinearProgressIndicator(
              value: _status!.progress.clamp(0, 100) / 100,
            ),
          ),
        if (_status?.state == Enum$UpdateState.FINISHED)
          ListTile(subtitle: Text(context.l10n.webInterfaceInstalled)),
        if (_status?.state == Enum$UpdateState.ERROR)
          ListTile(subtitle: Text(context.l10n.webInterfaceUpdateFailed)),
        if (error != null)
          ListTile(
            subtitle: Text(
              context.l10n.webInterfaceError(error),
              style: TextStyle(color: context.theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
