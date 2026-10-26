// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../library/presentation/library/widgets/desktop_library_toolbar.dart';

class CatalogueSearchBox extends HookWidget {
  const CatalogueSearchBox({
    super.key,
    required this.initialText,
    required this.hintText,
    required this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
  });

  final String? initialText;
  final String hintText;
  final FocusNode focusNode;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: initialText);
    useListenable(controller);
    useListenable(focusNode);
    final scheme = context.theme.colorScheme;
    return DesktopToolbarBox(
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            FluentIcons.search_24_regular,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              textInputAction: TextInputAction.search,
              style: context.theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: context.theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onChanged: onChanged,
              onSubmitted: (value) => onSubmitted?.call(value),
            ),
          ),
          if (controller.text.isNotEmpty)
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(FluentIcons.dismiss_24_regular),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                  onCleared?.call();
                },
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
