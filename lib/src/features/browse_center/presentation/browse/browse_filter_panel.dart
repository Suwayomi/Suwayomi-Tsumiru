// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/db_keys.dart';
import '../../../../constants/language_list.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../library/presentation/library/widgets/desktop_library_panels.dart';
import '../../../library/presentation/library/widgets/desktop_library_toolbar.dart';
import '../../domain/source/source_model.dart';
import '../extension/controller/extension_controller.dart';
import '../source/controller/source_controller.dart' hide SourceLanguageFilter;

bool _sameAsDefault(List<String>? current, List<String> initial) {
  if (current == null) return true;
  if (current.length != initial.length) return false;
  return current.toSet().containsAll(initial);
}

List<String> _languageFilterDefault(Object? initial) =>
    (initial as List?)?.cast<String>() ?? const [];

class BrowseFilterButton extends HookConsumerWidget {
  const BrowseFilterButton({super.key, required this.tabIndex});

  final int tabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buttonKey = useMemoized(GlobalKey.new);
    final focusNode = useMemoized(FocusNode.new);
    useEffect(() {
      return focusNode.dispose;
    }, [focusNode]);
    final sourceDefault = _languageFilterDefault(
      DBKeys.sourceLanguageFilter.initial,
    );
    final extensionDefault = _languageFilterDefault(
      DBKeys.extensionLanguageFilter.initial,
    );
    final active = tabIndex == 0
        ? !_sameAsDefault(
            ref.watch(sourceLanguageFilterProvider),
            sourceDefault,
          )
        : !_sameAsDefault(
            ref.watch(extensionLanguageFilterProvider),
            extensionDefault,
          );
    final scheme = context.theme.colorScheme;
    return DesktopToolbarBox(
      key: buttonKey,
      borderColor: active ? scheme.primary : null,
      child: InkWell(
        focusNode: focusNode,
        onTap: () => showAnchoredPanel(
          context: context,
          buttonKey: buttonKey,
          focusNode: focusNode,
          panelWidth: 300,
          child: BrowseFilterPanel(tabIndex: tabIndex),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 6),
          child: Row(
            spacing: 8,
            children: [
              const Icon(FluentIcons.filter_24_regular, size: 20),
              Text(context.l10n.filter),
              const Icon(FluentIcons.caret_down_24_filled, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class BrowseFilterPanel extends ConsumerWidget {
  const BrowseFilterPanel({super.key, required this.tabIndex});

  final int tabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSources = tabIndex == 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.filter,
                  style: context.theme.textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () {
                  final defaults = isSources
                      ? _languageFilterDefault(
                          DBKeys.sourceLanguageFilter.initial,
                        )
                      : _languageFilterDefault(
                          DBKeys.extensionLanguageFilter.initial,
                        );
                  if (isSources) {
                    ref
                        .read(sourceLanguageFilterProvider.notifier)
                        .update(defaults);
                  } else {
                    ref
                        .read(extensionLanguageFilterProvider.notifier)
                        .update(defaults);
                  }
                },
                child: Text(context.l10n.reset),
              ),
            ],
          ),
          Text(
            context.l10n.languages,
            style: context.theme.textTheme.titleSmall,
          ),
          Flexible(
            child: SingleChildScrollView(
              child: isSources
                  ? const _SourceLanguageChecklist()
                  : const _ExtensionLanguageChecklist(),
            ),
          ),
          if (isSources) ...[
            const Divider(),
            _HiddenSourcesRow(
              onOpen: (location) {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push(location);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceLanguageChecklist extends ConsumerWidget {
  const _SourceLanguageChecklist();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langMap = ref.watch(sourceFilterLangMapProvider);
    final codes = langMap.keys.toList()
      ..sort((a, b) {
        final ae = langMap[a].ifNull();
        final be = langMap[b].ifNull();
        return ae == be ? a.compareTo(b) : be.toIntWithNegative;
      });
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final code in codes)
          _CheckRow(
            value: langMap[code].ifNull(),
            label: languageMap[code]?.displayName ?? code,
            onChanged: (value) => ref
                .read(sourceFilterLangMapProvider.notifier)
                .toggleLang(code, value),
          ),
      ],
    );
  }
}

class _ExtensionLanguageChecklist extends ConsumerWidget {
  const _ExtensionLanguageChecklist();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codes = ref.watch(extensionFilterLangListProvider).toList()..sort();
    final enabled = ref.watch(extensionLanguageFilterProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final raw in codes)
          Builder(
            builder: (context) {
              final code = raw.toLowerCase();
              final isOn = enabled?.contains(code) ?? true;
              return _CheckRow(
                value: isOn,
                label: languageMap[code]?.displayName ?? code,
                onChanged: (value) {
                  if (value) {
                    ref
                        .read(extensionLanguageFilterProvider.notifier)
                        .update({...?enabled, code}.toList());
                  } else {
                    ref
                        .read(extensionLanguageFilterProvider.notifier)
                        .update([...?enabled]..remove(code));
                  }
                },
              );
            },
          ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (next) => onChanged(next ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HiddenSourcesRow extends ConsumerWidget {
  const _HiddenSourcesRow({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hiddenCount =
        ref.watch(sourceListProvider).value?.where((s) => s.isHidden).length ??
        0;
    return InkWell(
      onTap: () => onOpen(const SourceFilterRoute().location),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Icon(
              FluentIcons.eye_off_24_regular,
              size: 20,
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hiddenCount > 0
                    ? '${context.l10n.hiddenSources} ($hiddenCount)'
                    : context.l10n.hiddenSources,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: context.theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
