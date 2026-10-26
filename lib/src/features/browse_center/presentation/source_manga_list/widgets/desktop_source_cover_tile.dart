// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart'
    show menuAnchorForPoint, menuAnchorForRect;
import 'source_manga_cover_menu.dart';

class DesktopSourceCoverTile extends HookConsumerWidget {
  const DesktopSourceCoverTile({
    super.key,
    required this.manga,
    required this.selecting,
    required this.selected,
    required this.onToggleSelection,
    required this.onAddToLibrary,
    this.addEnabled = true,
    required this.child,
  });

  final MangaDto manga;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelection;
  final ValueChanged<MangaDto> onAddToLibrary;
  final bool addEnabled;
  final Widget child;

  Future<void> _openMenu(BuildContext context, WidgetRef ref, Offset point) =>
      showSourceMangaCoverMenu(
        context: context,
        ref: ref,
        position: menuAnchorForPoint(context, point),
        manga: manga,
        onSelect: onToggleSelection,
        onAddToLibrary: onAddToLibrary,
        addEnabled: addEnabled,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hovered = useState(false);
    final inLibrary = manga.user.inLibrary.ifNull();
    final scheme = context.theme.colorScheme;
    return MouseRegion(
      onEnter: (_) => hovered.value = true,
      onExit: (_) => hovered.value = false,
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _openMenu(context, ref, details.globalPosition),
        child: Stack(
          children: [
            child,
            if (inLibrary && !selecting)
              Positioned(
                top: 0,
                left: 0,
                width: 64,
                height: 40,
                child: Tooltip(
                  message: context.l10n.inLibrary,
                  child: const SizedBox.expand(),
                ),
              ),
            if (selecting)
              Positioned(
                top: 8,
                left: 8,
                child: GestureDetector(
                  onTap: onToggleSelection,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary
                          : scheme.inverseSurface.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.onInverseSurface,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            FluentIcons.checkmark_24_regular,
                            size: 16,
                            color: scheme.onPrimary,
                          )
                        : null,
                  ),
                ),
              ),
            if (hovered.value && !selecting)
              Positioned(
                top: 6,
                right: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!inLibrary) ...[
                      _CoverActionButton(
                        tooltip: context.l10n.addToLibrary,
                        icon: FluentIcons.heart_24_regular,
                        onPressed: addEnabled
                            ? () => onAddToLibrary(manga)
                            : null,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Builder(
                      builder: (buttonContext) => _CoverActionButton(
                        tooltip: context.l10n.more,
                        icon: FluentIcons.more_vertical_24_regular,
                        onPressed: () {
                          final box =
                              buttonContext.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          showSourceMangaCoverMenu(
                            context: context,
                            ref: ref,
                            position: menuAnchorForRect(
                              context,
                              box.localToGlobal(Offset.zero) & box.size,
                            ),
                            manga: manga,
                            onSelect: onToggleSelection,
                            onAddToLibrary: onAddToLibrary,
                            addEnabled: addEnabled,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoverActionButton extends StatelessWidget {
  const _CoverActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: scheme.inverseSurface.withValues(alpha: .8),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          color: scheme.onInverseSurface,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
