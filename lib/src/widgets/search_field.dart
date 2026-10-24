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
    this.controller,
    this.focusNode,
  });
  final String? labelText;
  final String? hintText;
  final String? initialText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String?>? onChanged;
  final ValueChanged<String?>? onSubmitted;
  final VoidCallback? onClose;
  final bool autofocus;
  final List<Widget>? actions;

  /// Highlight recognized DSL prefixes in the theme accent.
  final bool highlightDsl;

  final SearchFieldHintBehavior hintBehavior;

  @override
  Widget build(BuildContext context) {
    final ownController = useMemoized<TextEditingController?>(
      () {
        if (controller != null) return null;
        return highlightDsl
            ? DslSearchController(text: initialText)
            : TextEditingController(text: initialText);
      },
      [highlightDsl, controller],
    );
    useEffect(() => ownController?.dispose, [ownController]);
    final textController = controller ?? ownController!;

    final ownFocusNode = useFocusNode();
    final effectiveFocusNode = focusNode ?? ownFocusNode;
    useListenable(effectiveFocusNode);

    void closeAction() {
      textController.clear();
      onClose?.call();
      onChanged?.call(null);
      onSubmitted?.call(null);
    }

    void prefixAction() {
      if (effectiveFocusNode.hasFocus) {
        effectiveFocusNode.unfocus();
        closeAction();
      } else {
        effectiveFocusNode.requestFocus();
      }
    }

    final unfocusedText = labelText ?? context.l10n.search;
    final focusedText = hintText ?? unfocusedText;
    final (String? decorationLabel, String? decorationHint) = switch (hintBehavior) {
      SearchFieldHintBehavior.auto => (unfocusedText, hintText),
      SearchFieldHintBehavior.forceHint => (
          null,
          effectiveFocusNode.hasFocus ? focusedText : unfocusedText
        ),
      SearchFieldHintBehavior.forceLabel => (
          effectiveFocusNode.hasFocus ? focusedText : unfocusedText,
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
      controller: textController,
      focusNode: effectiveFocusNode,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: decorationLabel,
        hintText: decorationHint,
        prefixIcon: IconButton(
          icon: Icon(effectiveFocusNode.hasFocus
              ? Icons.arrow_back_rounded
              : Icons.search_rounded),
          onPressed: prefixAction,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...?actions,
            ?closeIcon,
          ],
        ),
      ),
    );
  }
}

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
      // Keep group(1), the leading boundary, outside the colored prefix.
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
