// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../features/library/domain/library_search_query.dart';
import '../utils/extensions/custom_extensions.dart';

enum SearchFieldHintBehavior { auto, forceHint, forceLabel }

class SearchField extends HookWidget {
  const SearchField({
    super.key,
    this.onChanged,
    this.onClose,
    this.initialText,
    this.onSubmitted,
    this.labelText,
    this.hintText,
    this.autofocus = true,
    this.actions,
    this.highlightDsl = false,
    this.hintBehavior = SearchFieldHintBehavior.auto,
  });
  final String? labelText;
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

  final SearchFieldHintBehavior hintBehavior;

  @override
  Widget build(BuildContext context) {
    final controller = useMemoized(
      () => highlightDsl
          ? DslSearchController(text: initialText)
          : TextEditingController(text: initialText),
      [highlightDsl],
    );
    useEffect(() => controller.dispose, [controller]);

    final focusNode = useFocusNode();
    useListenable(focusNode);

    void closeAction() {
      controller.clear();
      onClose?.call();
      onChanged?.call(null);
      onSubmitted?.call(null);
    }

    void prefixAction() {
      if (focusNode.hasFocus) {
        focusNode.unfocus();
        closeAction();
      } else {
        focusNode.requestFocus();
      }
    }

    final unfocusedText = labelText ?? context.l10n.search;
    final focusedText = hintText ?? unfocusedText;
    final (String? decorationLabel, String? decorationHint) = switch (hintBehavior) {
      SearchFieldHintBehavior.auto => (unfocusedText, hintText),
      SearchFieldHintBehavior.forceHint => (
          null,
          focusNode.hasFocus ? focusedText : unfocusedText
        ),
      SearchFieldHintBehavior.forceLabel => (
          focusNode.hasFocus ? focusedText : unfocusedText,
          null
        ),
    };

    final closeIcon = onClose != null
        ? IconButton(
            onPressed: closeAction,
            icon: const Icon(Icons.close_rounded),
          )
        : null;

    return TextField(
      onChanged: onChanged,
      autofocus: autofocus,
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: decorationLabel,
        hintText: decorationHint,
        prefixIcon: IconButton(
          icon: Icon(focusNode.hasFocus
              ? Icons.arrow_back_rounded
              : Icons.search_rounded),
          onPressed: prefixAction,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...?actions,
            if (closeIcon != null) closeIcon,
          ],
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
