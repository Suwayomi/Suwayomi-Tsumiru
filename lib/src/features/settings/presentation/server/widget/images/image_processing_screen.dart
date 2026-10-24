import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../../account/domain/account_access.dart';
import '../../../../data/user_settings.dart';
import 'data/images_repository.dart';
import 'graphql/__generated__/images.graphql.dart';
import 'image_conversions.dart';

class ImageProcessingScreen extends ConsumerStatefulWidget {
  const ImageProcessingScreen({super.key, required this.kind});

  final ImageProcessingKind kind;

  @override
  ConsumerState<ImageProcessingScreen> createState() =>
      _ImageProcessingScreenState();
}

class _RuleState {
  _RuleState(this.rule)
    : mime = TextEditingController(text: rule.mimeType),
      target = TextEditingController(text: rule.target),
      compression = TextEditingController(
        text: rule.compressionLevel?.toString() ?? '',
      ),
      callTimeout = TextEditingController(
        text: isoDurationSeconds(rule.callTimeout)?.toString() ?? '',
      ),
      connectTimeout = TextEditingController(
        text: isoDurationSeconds(rule.connectTimeout)?.toString() ?? '',
      );

  final ImageConversion rule;
  final TextEditingController mime;
  final TextEditingController target;
  final TextEditingController compression;
  final TextEditingController callTimeout;
  final TextEditingController connectTimeout;
  bool showSearchParams = false;
  bool showHeaders = false;

  /// Unparsable text is invalid and blocks Save instead of being silently dropped.
  /// Only fields visible for the current target mode count: hidden fields keep
  /// their stale text but must not block Save after a mode switch.
  bool get hasInvalidNumericInput {
    switch (rule.mode) {
      case ImageConversionTargetMode.disabled:
        return false;
      case ImageConversionTargetMode.image:
        return !isValidCompressionText(compression.text);
      case ImageConversionTargetMode.url:
        return !isValidTimeoutText(callTimeout.text) ||
            !isValidTimeoutText(connectTimeout.text);
    }
  }

  void dispose() {
    mime.dispose();
    target.dispose();
    compression.dispose();
    callTimeout.dispose();
    connectTimeout.dispose();
  }
}

class _ImageProcessingScreenState extends ConsumerState<ImageProcessingScreen> {
  List<ImageConversion>? _baseline;
  List<_RuleState>? _rules;
  bool _saving = false;

  ImageProcessingKind get _kind => widget.kind;

  bool get _isDownload => _kind == ImageProcessingKind.download;

  void _ensureLoaded(List<ServerConversion> records) {
    if (_rules != null) return;
    _baseline = editorConversionsFromServer(records);
    _rules = _baseline!.map((c) => _RuleState(c.copy())).toList();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final inputs = toServerConversionInputs(
        _rules!.map((r) => r.rule).toList(),
      );
      // Await the refreshed server value before rebuilding: invalidating and
      // clearing `_rules` in the same setState rebuilds from the stale list
      // (Riverpod still hands out the old data while refreshing), so the
      // editor would revert to the pre-save values.
      final List<ServerConversion>? records;
      if (_isDownload) {
        await ref
            .read(imagesRepositoryProvider)
            .writeDownload(
              Input$PartialSettingsTypeInput(downloadConversions: inputs),
            );
        final fresh = await ref.refresh(imagesDownloadSettingsProvider.future);
        records = fresh == null ? null : _downloadRecords(fresh);
      } else {
        await ref.read(serveConversionsRepositoryProvider).write(inputs);
        records = await ref.refresh(serveConversionsProvider.future);
      }
      if (mounted) {
        setState(() {
          for (final rule in _rules!) {
            rule.dispose();
          }
          if (records == null) {
            _rules = null;
            _baseline = null;
          } else {
            _baseline = editorConversionsFromServer(records);
            _rules = _baseline!.map((c) => _RuleState(c.copy())).toList();
          }
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ref.read(toastProvider)?.show(context.l10n.imageProcessingFailedToSave);
      }
    }
  }

  @override
  void dispose() {
    for (final rule in _rules ?? const <_RuleState>[]) {
      rule.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(settledAccountAccessProvider);
    final canManage = access.allows(Enum$UserPermission.MANAGE_SETTINGS);
    final personalState = ref.watch(personalSettingsStateProvider);
    final canEdit = _isDownload
        ? canManage
        : access.capability == AccountCapability.supported
        ? personalState == PersonalSettingsState.ready
        : canManage;
    final title = Text(
      _isDownload
          ? context.l10n.imageDownloadProcessing
          : context.l10n.imageServeProcessing,
    );

    final topBar = showsMergedTopBar(context);
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: Scaffold(
        appBar: topBar
            ? null
            : AppBar(
                leading: detailNavigationBackButton(context),
                title: title,
              ),
        body: _isDownload
            ? ref
                  .watch(imagesDownloadSettingsProvider)
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _loadError(context, ref, error),
                    data: (dto) {
                      if (dto == null) return const SizedBox.shrink();
                      return _editorBody(
                        context,
                        _downloadRecords(dto),
                        canEdit,
                      );
                    },
                  )
            : ref
                  .watch(serveConversionsProvider)
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _loadError(context, ref, error),
                    data: (records) {
                      if (records == null) return const SizedBox.shrink();
                      return _editorBody(context, records, canEdit);
                    },
                  ),
      ),
    );
  }

  Widget _loadError(BuildContext context, WidgetRef ref, Object error) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error.toString()),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _isDownload
                  ? ref.invalidate(imagesDownloadSettingsProvider)
                  : ref.invalidate(serveConversionsProvider),
              child: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      );

  Widget _editorBody(
    BuildContext context,
    List<ServerConversion> records,
    bool canEdit,
  ) {
    _ensureLoaded(records);
    final rules = _rules!.map((r) => r.rule).toList();
    final invalid =
        imageConversionsAreInvalid(rules) ||
        _rules!.any((r) => r.hasInvalidNumericInput);
    final changed = imageConversionsChanged(_baseline!, rules);
    return Center(
      child: ConstrainedBox(
        constraints: settingsPageConstraints(context),
        child: ListView(
          padding: settingsPagePadding(context, const EdgeInsets.all(16)),
          children: [
            for (var i = 0; i < _rules!.length; i++)
              _RuleCard(
                key: ValueKey(_rules![i].rule.id),
                state: _rules![i],
                index: i,
                rules: rules,
                canEdit: canEdit && !_saving,
                onChanged: () => setState(() {}),
                onDelete: () => setState(() => _removeRule(i)),
                onModeChanged: (mode) => _setMode(_rules![i], mode),
                onTargetChanged: (value) => _setTarget(_rules![i], value),
                onSearchParamsChanged: (params) =>
                    _setSearchParams(_rules![i], params),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(
                  onPressed: canEdit && !_saving
                      ? () => setState(_addRule)
                      : null,
                  child: Text(context.l10n.add),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: canEdit && !_saving && changed && !invalid
                      ? _save
                      : null,
                  child: Text(context.l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addRule() {
    _rules!.add(
      _RuleState(
        ImageConversion(
          id: freshEditorId(),
          mimeType: '',
          target: '',
          mode: ImageConversionTargetMode.image,
        ),
      ),
    );
  }

  void _removeRule(int index) {
    final removed = _rules!.removeAt(index);
    removed.dispose();
    if (!_rules!.any((r) => isDefaultMimeType(r.rule.mimeType))) {
      _rules!.insert(
        0,
        _RuleState(
          ImageConversion(
            id: -1,
            mode: ImageConversionTargetMode.image,
            mimeType: defaultMimeType,
            target: '',
          ),
        ),
      );
    }
  }

  void _setMode(_RuleState s, ImageConversionTargetMode mode) {
    final isUrlMode = s.rule.mode == ImageConversionTargetMode.url;
    s.rule.mode = mode;
    final target = mode == ImageConversionTargetMode.disabled
        ? targetDisabled
        : '';
    s.rule.target = target;
    if (s.target.text != target) s.target.text = target;
    if (!isUrlMode) {
      s.rule.headers = null;
      s.rule.searchParams = [];
      s.showSearchParams = false;
      s.showHeaders = false;
    }
    setState(() {});
  }

  void _setTarget(_RuleState s, String value) {
    s.rule.target = value;
    if (s.rule.mode != ImageConversionTargetMode.image) {
      s.rule.searchParams = _retainSearchParamIds(value, s.rule.searchParams);
    }
    setState(() {});
  }

  void _setSearchParams(_RuleState s, List<ConversionKeyValue> params) {
    s.rule.searchParams = params;
    final base = s.rule.target.split('?').first;
    final query = params
        .map(
          (p) =>
              '${Uri.encodeQueryComponent(p.name)}=${Uri.encodeQueryComponent(p.value)}',
        )
        .join('&');
    final target = query.isEmpty ? base : '$base?$query';
    s.rule.target = target;
    if (s.target.text != target) s.target.text = target;
    setState(() {});
  }
}

List<ServerConversion> _downloadRecords(
  Fragment$ImagesDownloadSettingsDto dto,
) => dto.downloadConversions
    .map(
      (c) => ServerConversion(
        mimeType: c.mimeType,
        target: c.target,
        compressionLevel: c.compressionLevel,
        callTimeout: c.callTimeout,
        connectTimeout: c.connectTimeout,
        headers: c.headers
            ?.map((h) => ServerConversionHeader(name: h.name, value: h.value))
            .toList(),
      ),
    )
    .toList();

List<ConversionKeyValue> _retainSearchParamIds(
  String url,
  List<ConversionKeyValue> existing,
) {
  final unused = existing.toList();
  return extractSearchParams(url).map((param) {
    ConversionKeyValue? match;
    for (final item in unused) {
      if (item.name == param.name) {
        match = item;
        unused.remove(item);
        break;
      }
    }
    return ConversionKeyValue(
      id: match?.id ?? freshEditorId(),
      name: param.name,
      value: param.value,
    );
  }).toList();
}

String _modeName(BuildContext context, ImageConversionTargetMode mode) {
  final l10n = context.l10n;
  return switch (mode) {
    ImageConversionTargetMode.disabled => l10n.imageProcessingDisabled,
    ImageConversionTargetMode.image => l10n.imageProcessingImage,
    ImageConversionTargetMode.url => l10n.imageProcessingUrl,
  };
}

String _modeDescription(BuildContext context, ImageConversionTargetMode mode) =>
    switch (mode) {
      ImageConversionTargetMode.disabled => '',
      ImageConversionTargetMode.image =>
        context.l10n.imageProcessingImageDescription,
      ImageConversionTargetMode.url =>
        context.l10n.imageProcessingUrlDescription,
    };

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    super.key,
    required this.state,
    required this.index,
    required this.rules,
    required this.canEdit,
    required this.onChanged,
    required this.onDelete,
    required this.onModeChanged,
    required this.onTargetChanged,
    required this.onSearchParamsChanged,
  });

  final _RuleState state;
  final int index;
  final List<ImageConversion> rules;
  final bool canEdit;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final ValueChanged<ImageConversionTargetMode> onModeChanged;
  final ValueChanged<String> onTargetChanged;
  final ValueChanged<List<ConversionKeyValue>> onSearchParamsChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rule = state.rule;
    final isDuplicate = isDuplicateConversion(rule.mimeType, index, rules);
    final isDefault = isDefaultMimeType(rule.mimeType) && !isDuplicate;
    final isRowDisabled =
        isDefault && rule.target.isEmpty && rule.compressionLevel == null;
    final isImageMode = rule.mode == ImageConversionTargetMode.image;
    final isUrlMode = rule.mode == ImageConversionTargetMode.url;
    final isDisabledMode = rule.mode == ImageConversionTargetMode.disabled;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: state.mime,
              enabled: canEdit && !isDefault,
              decoration: InputDecoration(
                labelText: l10n.imageProcessingMimeType,
                prefixText: '$mimeTypePrefix ',
                errorText: isDuplicate
                    ? l10n.imageProcessingInvalidInput
                    : null,
              ),
              onChanged: (value) {
                rule.mimeType = value.trim();
                onChanged();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.imageProcessingTargetMode),
              subtitle: Text(_modeName(context, rule.mode)),
              onTap: canEdit
                  ? () => showDialog(
                      context: context,
                      builder: (dialogContext) =>
                          RadioListPopup<ImageConversionTargetMode>(
                            title: l10n.imageProcessingTargetMode,
                            optionList: ImageConversionTargetMode.values,
                            value: rule.mode,
                            getOptionTitle: (mode) =>
                                _modeName(dialogContext, mode),
                            getOptionSubtitle: (mode) =>
                                _modeDescription(dialogContext, mode),
                            onChange: (mode) {
                              Navigator.pop(dialogContext);
                              onModeChanged(mode);
                            },
                          ),
                      animationStyle: context.motionStyle,
                    )
                  : null,
            ),
            if (!isDisabledMode)
              TextField(
                controller: state.target,
                enabled: canEdit,
                decoration: InputDecoration(
                  labelText: l10n.imageProcessingMimeTypeTarget,
                  prefixText: isImageMode ? '$mimeTypePrefix ' : null,
                  errorText:
                      !isImageMode &&
                          rule.target.isNotEmpty &&
                          !isUrlTargetMode(rule.target)
                      ? l10n.imageProcessingInvalidInput
                      : null,
                ),
                onChanged: (value) => onTargetChanged(value.trim()),
              ),
            if (isImageMode)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: state.compression,
                  enabled: canEdit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.imageProcessingCompressionLevel,
                    errorText: !isValidCompressionText(state.compression.text)
                        ? l10n.imageProcessingInvalidInput
                        : null,
                  ),
                  onChanged: (value) {
                    rule.compressionLevel = value.isEmpty
                        ? null
                        : double.tryParse(value);
                    onChanged();
                  },
                ),
              ),
            if (isUrlMode) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: state.callTimeout,
                  enabled: canEdit,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.imageProcessingCallTimeout,
                    suffixText: l10n.imageProcessingSecond,
                    errorText: !isValidTimeoutText(state.callTimeout.text)
                        ? l10n.imageProcessingInvalidInput
                        : null,
                  ),
                  onChanged: (value) {
                    final seconds = value.isEmpty ? null : int.tryParse(value);
                    rule.callTimeout = seconds == null
                        ? null
                        : isoDuration(seconds);
                    onChanged();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: state.connectTimeout,
                  enabled: canEdit,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.imageProcessingConnectTimeout,
                    suffixText: l10n.imageProcessingSecond,
                    errorText: !isValidTimeoutText(state.connectTimeout.text)
                        ? l10n.imageProcessingInvalidInput
                        : null,
                  ),
                  onChanged: (value) {
                    final seconds = value.isEmpty ? null : int.tryParse(value);
                    rule.connectTimeout = seconds == null
                        ? null
                        : isoDuration(seconds);
                    onChanged();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    state.showSearchParams
                        ? FilledButton(
                            onPressed: canEdit
                                ? () {
                                    state.showSearchParams = false;
                                    onChanged();
                                  }
                                : null,
                            child: Text(
                              l10n.imageProcessingSearchParametersCount(
                                rule.searchParams.length,
                              ),
                            ),
                          )
                        : OutlinedButton(
                            onPressed: canEdit && isUrlTargetMode(rule.target)
                                ? () {
                                    state.showSearchParams = true;
                                    onChanged();
                                  }
                                : null,
                            child: Text(
                              l10n.imageProcessingSearchParametersCount(
                                rule.searchParams.length,
                              ),
                            ),
                          ),
                    state.showHeaders
                        ? FilledButton(
                            onPressed: canEdit
                                ? () {
                                    state.showHeaders = false;
                                    onChanged();
                                  }
                                : null,
                            child: Text(
                              l10n.imageProcessingHeadersCount(
                                rule.headers?.length ?? 0,
                              ),
                            ),
                          )
                        : OutlinedButton(
                            onPressed: canEdit
                                ? () {
                                    state.showHeaders = true;
                                    onChanged();
                                  }
                                : null,
                            child: Text(
                              l10n.imageProcessingHeadersCount(
                                rule.headers?.length ?? 0,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ],
            if (isUrlMode && state.showSearchParams)
              _KeyValueList(
                title: l10n.imageProcessingSearchParameters,
                items: rule.searchParams,
                canEdit: canEdit,
                onChanged: onSearchParamsChanged,
              ),
            if (isUrlMode && state.showHeaders)
              _KeyValueList(
                title: l10n.imageProcessingHeaders,
                items: rule.headers ?? const [],
                canEdit: canEdit,
                onChanged: (headers) {
                  rule.headers = headers;
                  onChanged();
                },
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: l10n.delete,
                child: IconButton(
                  icon: const Icon(Icons.delete_rounded),
                  onPressed: canEdit && !isRowDisabled ? onDelete : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyValueList extends StatelessWidget {
  const _KeyValueList({
    required this.title,
    required this.items,
    required this.canEdit,
    required this.onChanged,
  });

  final String title;
  final List<ConversionKeyValue> items;
  final bool canEdit;
  final ValueChanged<List<ConversionKeyValue>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            _KeyValueRow(
              key: ValueKey(items[i].id),
              item: items[i],
              isDuplicate: isDuplicateKeyValueItem(items[i].name, i, items),
              canEdit: canEdit,
              onChanged: (updated) {
                final next = items.map((e) => e).toList();
                next[i] = updated;
                onChanged(next);
              },
              onDelete: () {
                final next = items.map((e) => e).toList()..removeAt(i);
                onChanged(next);
              },
            ),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: canEdit
                ? () => onChanged([
                    ...items,
                    ConversionKeyValue(
                      id: freshEditorId(),
                      name: '',
                      value: '',
                    ),
                  ])
                : null,
            child: Text(context.l10n.add),
          ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatefulWidget {
  const _KeyValueRow({
    super.key,
    required this.item,
    required this.isDuplicate,
    required this.canEdit,
    required this.onChanged,
    required this.onDelete,
  });

  final ConversionKeyValue item;
  final bool isDuplicate;
  final bool canEdit;
  final ValueChanged<ConversionKeyValue> onChanged;
  final VoidCallback onDelete;

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  late final TextEditingController _name;
  late final TextEditingController _value;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    _value = TextEditingController(text: widget.item.value);
  }

  @override
  void didUpdateWidget(_KeyValueRow old) {
    super.didUpdateWidget(old);
    if (old.item.name != widget.item.name && _name.text != widget.item.name) {
      _name.text = widget.item.name;
    }
    if (old.item.value != widget.item.value &&
        _value.text != widget.item.value) {
      _value.text = widget.item.value;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _name,
              enabled: widget.canEdit,
              decoration: InputDecoration(
                labelText: l10n.imageProcessingName,
                errorText: widget.isDuplicate
                    ? l10n.imageProcessingInvalidInput
                    : null,
              ),
              onChanged: (value) => widget.onChanged(
                ConversionKeyValue(
                  id: widget.item.id,
                  name: value,
                  value: widget.item.value,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _value,
              enabled: widget.canEdit,
              decoration: InputDecoration(labelText: l10n.imageProcessingValue),
              onChanged: (value) => widget.onChanged(
                ConversionKeyValue(
                  id: widget.item.id,
                  name: widget.item.name,
                  value: value,
                ),
              ),
            ),
          ),
          Tooltip(
            message: l10n.delete,
            child: IconButton(
              icon: const Icon(Icons.delete_rounded),
              onPressed: widget.canEdit ? widget.onDelete : null,
            ),
          ),
        ],
      ),
    );
  }
}
