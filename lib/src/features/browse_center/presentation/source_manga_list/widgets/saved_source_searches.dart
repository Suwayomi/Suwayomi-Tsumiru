// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/webui_meta/saved_search_filters.dart';
import '../../../../../utils/webui_meta/webui_meta_codec.dart';
import '../../../../../utils/webui_meta/webui_meta_repository.dart';
import '../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../domain/filter/filter_model.dart';
import '../controller/source_manga_controller.dart';

class SavedSourceSearches extends HookConsumerWidget {
  const SavedSourceSearches({
    super.key,
    required this.sourceId,
    required this.currentQuery,
    required this.currentChanges,
    required this.onSelected,
  });
  final String sourceId;
  final String? Function() currentQuery;
  final List<FilterChange> Function() currentChanges;
  final void Function(String?, List<FilterChange>) onSelected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(sourceProvider(sourceId)).value;
    final metas = <String, String>{
      if (source != null)
        for (final meta in source.meta) meta.key: meta.value,
    };
    final savedValue = readWebUiValue(metas, 'savedSearches');
    Map<String, dynamic> searches;
    try {
      searches = _decodeSavedSearches(savedValue);
    } on FormatException {
      searches = {};
    }
    final saving = useState(false);
    final nameController = useTextEditingController();
    Future<void> writeSearch(String name, Map<String, dynamic>? search) async {
      saving.value = true;
      try {
        await AppUtils.guard(() async {
          final repository = WebUiMetaRepository(ref.read(graphQlClientProvider));
          var latestMetas = await repository.readSourceMetas(sourceId);
          var next = _decodeSavedSearches(
            readWebUiValue(latestMetas, 'savedSearches'),
          );
          if (!context.mounted) return;
          if (search != null) {
            if (next.containsKey(name)) {
              if (!await confirmAction(
                    context,
                    title: context.l10n.confirmOverwriteSearchTitle,
                    message: context.l10n.confirmOverwriteSearchMessage,
                    action: context.l10n.confirmOverwriteAction,
                  ) ||
                  !context.mounted) {
                return;
              }
              latestMetas = await repository.readSourceMetas(sourceId);
              next = _decodeSavedSearches(
                readWebUiValue(latestMetas, 'savedSearches'),
              );
            }
            next[name] = search;
          } else {
            next.remove(name);
          }
          if (!context.mounted) return;
          await repository.writeSourceValue(
            sourceId,
            'savedSearches',
            jsonEncode(next),
            latestMetas,
          );
          ref.invalidate(sourceProvider(sourceId));
        }, ref.read(toastProvider));
      } finally {
        if (context.mounted) saving.value = false;
      }
    }

    Future<void> saveSearch() async {
      nameController.clear();
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.saveCurrentSearch),
          content: TextField(
            controller: nameController,
            autofocus: true,
            maxLength: 50,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) Navigator.pop(context, name);
              },
              child: Text(context.l10n.save),
            ),
          ],
        ),
      );
      if (name == null || !context.mounted) return;
      final query = currentQuery();
      await writeSearch(name, {
        'query': ?query,
          'filters': filtersToWebUi(currentChanges()),
      });
    }

    Future<void> deleteSearch(String name) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.deleteSearch),
          content: Text(name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.delete),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        await writeSearch(name, null);
      }
    }

    return Padding(
      padding: KEdgeInsets.h16v4.size,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.savedSearches,
                  style: context.textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: saving.value || source == null ? null : saveSearch,
                child: Text(context.l10n.save),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in searches.entries)
                InputChip(
                  label: Text(entry.key),
                  onPressed: saving.value
                      ? null
                      : () {
                          final search = entry.value as Map<String, dynamic>;
                          onSelected(
                            search['query'] as String?,
                            filtersFromWebUi(search['filters'] as List? ?? []),
                          );
                        },
                  deleteButtonTooltipMessage: context.l10n.deleteSearch,
                  deleteIcon: const Icon(
                    FluentIcons.dismiss_24_regular,
                  ),
                  onDeleted: saving.value
                      ? null
                      : () => deleteSearch(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _decodeSavedSearches(String? value) {
  if (value == null) return {};
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid saved searches');
  }
  for (final search in decoded.values) {
    if (search is! Map<String, dynamic> ||
        (search['query'] != null && search['query'] is! String) ||
        (search['filters'] != null && search['filters'] is! List)) {
      throw const FormatException('Invalid saved search');
    }
    try {
      filtersFromWebUi(search['filters'] as List? ?? []);
    } catch (_) {
      throw const FormatException('Invalid saved search filters');
    }
  }
  return decoded;
}
