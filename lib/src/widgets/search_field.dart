// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../constants/app_sizes.dart';
import '../features/library/domain/library_search_query.dart';
import '../utils/extensions/custom_extensions.dart';

class SearchField extends HookWidget {
  const SearchField({
    super.key,
    this.onChanged,
    this.onClose,
    this.initialText,
    this.onSubmitted,
    this.hintText,
    this.autofocus = true,
    this.actions,
    this.highlightDsl = false,
  });
  final String? hintText;
  final String? initialText;
  final ValueChanged<String?>? onChanged;
  final ValueChanged<String?>? onSubmitted;
  final VoidCallback? onClose;
  final bool autofocus;
  final List<Widget>? actions;

  /// Colour recognized DSL metatag prefixes (`tag:`, `genre:`, `rating:`…) as
  /// the user types, so the search box reads as a query language, not free text.
  final bool highlightDsl;

  @override
  Widget build(BuildContext context) {
    final controller = useMemoized(
      () => highlightDsl
          ? DslSearchController(text: initialText)
          : TextEditingController(text: initialText),
      [highlightDsl],
    );
    useEffect(() => controller.dispose, [controller]);

    final closeIcon = onClose != null
        ? IconButton(
            onPressed: () {
              onClose?.call();
              onChanged?.call(null);
              onSubmitted?.call(null);
            },
            icon: const Icon(Icons.close_rounded),
          )
        : null;

    return SizedBox(
      width: context.isLargeTablet ? context.widthScale(scale: .5) : null,
      child: Padding(
        padding: KEdgeInsets.h16v4.size,
        child: TextField(
          onChanged: onChanged,
          autofocus: autofocus,
          controller: controller,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            labelText: hintText ?? context.l10n.search,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...?actions,
                if (closeIcon != null) closeIcon,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Text controller that renders recognized DSL metatag prefixes
/// (`tag:`, `genre:`, `rating:`…, plus a leading `-`) in the theme accent as the
/// user types, so the library search box reads as a query language.
class DslSearchController extends TextEditingController {
  DslSearchController({super.text});

  static final RegExp _pattern = RegExp(
    '(^|[\\s,])(-?)(${librarySearchMetatagKeys.join('|')}):',
    caseSensitive: false,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final accent = base.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final children = <TextSpan>[];
    var last = 0;
    for (final m in _pattern.allMatches(text)) {
      // group(1) is the leading boundary (start/space/comma) — keep it normal;
      // colour the `-?key:` prefix.
      final keyStart = m.start + (m.group(1)?.length ?? 0);
      if (keyStart > last) {
        children.add(TextSpan(text: text.substring(last, keyStart), style: base));
      }
      children.add(TextSpan(text: text.substring(keyStart, m.end), style: accent));
      last = m.end;
    }
    if (last < text.length) {
      children.add(TextSpan(text: text.substring(last), style: base));
    }
    return TextSpan(style: base, children: children);
  }
}
