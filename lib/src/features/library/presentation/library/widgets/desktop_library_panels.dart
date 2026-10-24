// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/manga_cover/providers/manga_cover_providers.dart';
import '../../../../tracking/data/tracker_repository.dart';
import '../../../domain/library_group.dart';
import '../controller/library_controller.dart';
import '../controller/library_grouping.dart';
import 'library_filter_content.dart';
import 'library_filter_segments.dart';
import 'library_manga_badges.dart';

/// [rect] must use the nearest Overlay's coordinates; a branch Navigator excludes the sidebar.
RelativeRect menuAnchorForRect(BuildContext context, Rect rect) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(rect, Offset.zero & overlay.size);
}

/// Aligns below the anchor's right edge, clamped to an 8 px overlay margin.
class _LibraryPanelLayout extends SingleChildLayoutDelegate {
  _LibraryPanelLayout(this.anchor);

  /// Button rect in overlay coordinates; only its edges matter.
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final fromRight = size.width - (anchor.left + anchor.width);
    var x = anchor.left > fromRight
        ? anchor.left + anchor.width - childSize.width
        : anchor.left;
    var y = anchor.top;
    x = x.clamp(
      8.0,
      (size.width - childSize.width - 8.0).clamp(8.0, size.width),
    );
    y = y.clamp(
      8.0,
      (size.height - childSize.height - 8.0).clamp(8.0, size.height),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_LibraryPanelLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

/// Anchored menu route without showMenu's 280 px width cap.
class _LibraryPanelRoute extends PopupRoute<void> {
  _LibraryPanelRoute({
    required this.position,
    required this.panelWidth,
    this.panelHeight,
    required this.panel,
    required this.capturedThemes,
    required this.barrierLabel,
    this.popUpAnimationStyle,
  });

  final RelativeRect position;
  final double panelWidth;

  /// Null sizes to content, capped at overlay height minus 140; overflow scrolls.
  final double? panelHeight;
  final Widget panel;
  final CapturedThemes capturedThemes;
  final AnimationStyle? popUpAnimationStyle;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      popUpAnimationStyle?.duration ?? const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final overlay = Offset.zero & constraints.biggest;
          final anchor = position.toRect(overlay);
          final fixedHeight = panelHeight;
          final Widget sheet = Builder(
            builder: (context) {
              final scheme = context.theme.colorScheme;
              return Material(
                color: scheme.surfaceContainer,
                elevation: 3,
                shadowColor: scheme.shadow,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: MediaQuery(
                  data: mediaQuery.copyWith(padding: EdgeInsets.zero),
                  child: panel,
                ),
              );
            },
          );
          final Widget sized = fixedHeight != null
              ? SizedBox.fromSize(
                  size: Size(panelWidth, fixedHeight),
                  child: sheet,
                )
              : SizedBox(
                  width: panelWidth,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (overlay.height - 140).clamp(
                        200.0,
                        overlay.height,
                      ),
                    ),
                    child: sheet,
                  ),
                );
          return CustomSingleChildLayout(
            delegate: _LibraryPanelLayout(anchor),
            child: capturedThemes.wrap(
              Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.of(context).pop();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: sized,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: popUpAnimationStyle?.curve ?? Curves.easeOut,
      reverseCurve: popUpAnimationStyle?.reverseCurve ?? Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

Future<void> _openPanel({
  required BuildContext context,
  required GlobalKey buttonKey,
  required FocusNode focusNode,
  required double panelWidth,
  double? panelHeight,
  required Widget child,
}) async {
  final box = buttonKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return;
  // Use overlay-relative coordinates because the branch Navigator excludes the sidebar.
  final overlayBox =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final bottomRight = box.localToGlobal(
    box.size.bottomRight(Offset.zero),
    ancestor: overlayBox,
  );
  final rect = Rect.fromPoints(topLeft, bottomRight);
  final navigator = Navigator.of(context);
  await navigator.push(
    _LibraryPanelRoute(
      // Anchor at the button's bottom-right; the layout delegate already applies panel width.
      position: menuAnchorForRect(
        context,
        Rect.fromLTWH(rect.right, rect.bottom + 6, 0, 0),
      ),
      panelWidth: panelWidth,
      panelHeight: panelHeight,
      panel: child,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      popUpAnimationStyle: context.motionStyle,
    ),
  );
  if (context.mounted) focusNode.requestFocus();
}

/// Opens a 720 px two-column panel; changes apply live.
Future<void> showLibraryFilterPanel({
  required BuildContext context,
  required GlobalKey buttonKey,
  required FocusNode focusNode,
}) => _openPanel(
  context: context,
  buttonKey: buttonKey,
  focusNode: focusNode,
  panelWidth: 720,
  panelHeight: 600,
  child: const DesktopLibraryFilterPanel(),
);

/// Opens an 820 px three-column panel; changes apply live and height is capped to the viewport.
Future<void> showLibraryDisplayPanel({
  required BuildContext context,
  required GlobalKey buttonKey,
  required FocusNode focusNode,
}) => _openPanel(
  context: context,
  buttonKey: buttonKey,
  focusNode: focusNode,
  panelWidth: 820,
  child: const DesktopLibraryDisplayPanel(),
);

class DesktopLibraryFilterPanel extends StatelessWidget {
  const DesktopLibraryFilterPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: LibraryFilterContent(twoColumns: true),
    );
  }
}

// Flexible bounds tall content for scrolling while allowing short panels to size to content.
class DesktopLibraryDisplayPanel extends StatelessWidget {
  const DesktopLibraryDisplayPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.display,
            style: context.theme.textTheme.titleMedium,
          ),
          const Flexible(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    key: ValueKey('displayColumn1'),
                    child: _DisplayColumn(),
                  ),
                  SizedBox(width: 24),
                  Expanded(
                    key: ValueKey('displayColumn2'),
                    child: _BadgesColumn(),
                  ),
                  SizedBox(width: 24),
                  Expanded(
                    key: ValueKey('displayColumn3'),
                    child: _GroupColumn(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelRadioRow<T> extends StatelessWidget {
  const _PanelRadioRow({
    required this.value,
    required this.onChanged,
    required this.title,
    this.leading,
  });

  final T value;
  final ValueChanged<T?> onChanged;
  final String title;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(value),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Radio<T>(
              value: value,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 12),
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Expanded(
              child: Text(
                title,
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

class _PanelCheckRow extends ConsumerWidget {
  const _PanelCheckRow({
    required this.title,
    required this.provider,
    required this.onChanged,
  });

  final String title;
  final ProviderListenable<bool?> provider;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = ref.watch(provider) ?? true;
    return InkWell(
      onTap: () => onChanged(!checked),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Icon(
              checked
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: checked
                  ? context.theme.colorScheme.primary
                  : context.theme.unselectedWidgetColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
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

class _DisplayColumn extends ConsumerWidget {
  const _DisplayColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final selectedMode =
        displayMode ?? DBKeys.libraryDisplayMode.initial as DisplayMode;
    final gridStyle =
        ref.watch(libraryGridStyleKeyProvider) ?? LibraryGridStyle.uniform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(context.l10n.displayMode),
        RadioGroup<DisplayMode>(
          groupValue: selectedMode,
          onChanged: (mode) =>
              ref.read(libraryDisplayModeProvider.notifier).update(mode),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in DisplayMode.libraryDisplayList)
                _PanelRadioRow<DisplayMode>(
                  value: mode,
                  onChanged: (next) => ref
                      .read(libraryDisplayModeProvider.notifier)
                      .update(next),
                  title: mode.toLibraryLocale(context),
                ),
            ],
          ),
        ),
        FilterSectionHeading(context.l10n.gridStyle),
        RadioGroup<LibraryGridStyle>(
          groupValue: gridStyle,
          onChanged: (style) =>
              ref.read(libraryGridStyleKeyProvider.notifier).update(style),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in LibraryGridStyle.values)
                _PanelRadioRow<LibraryGridStyle>(
                  value: style,
                  onChanged: (next) => ref
                      .read(libraryGridStyleKeyProvider.notifier)
                      .update(next),
                  title: style.toLocale(context),
                  leading: Icon(style.icon, size: 20),
                ),
            ],
          ),
        ),
        if (selectedMode == DisplayMode.comfortableGrid ||
            selectedMode == DisplayMode.list ||
            selectedMode == DisplayMode.descriptiveList)
          _PanelCheckRow(
            title: context.l10n.limitTitleLines,
            provider: limitTitleLinesProvider,
            onChanged: ref.read(limitTitleLinesProvider.notifier).update,
          ),
        _PanelCheckRow(
          title: context.l10n.outlineOnCovers,
          provider: outlineOnCoversProvider,
          onChanged: ref.read(outlineOnCoversProvider.notifier).update,
        ),
      ],
    );
  }
}

class _BadgesColumn extends ConsumerWidget {
  const _BadgesColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadMode =
        ref.watch(unreadBadgeStyleProvider) ?? UnreadBadgeMode.count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(context.l10n.badges),
        FilterSectionHeading(context.l10n.unreadBadgeMode),
        RadioGroup<UnreadBadgeMode>(
          groupValue: unreadMode,
          onChanged: (mode) =>
              ref.read(unreadBadgeStyleProvider.notifier).update(mode),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in UnreadBadgeMode.values)
                _PanelRadioRow<UnreadBadgeMode>(
                  value: mode,
                  onChanged: (next) =>
                      ref.read(unreadBadgeStyleProvider.notifier).update(next),
                  title: mode.toLocale(context),
                ),
            ],
          ),
        ),
        _PanelCheckRow(
          title: context.l10n.downloaded,
          provider: downloadedBadgeProvider,
          onChanged: ref.read(downloadedBadgeProvider.notifier).update,
        ),
        _PanelCheckRow(
          title: context.l10n.onDevice,
          provider: onDeviceBadgeProvider,
          onChanged: ref.read(onDeviceBadgeProvider.notifier).update,
        ),
        _PanelCheckRow(
          title: context.l10n.readProgressBar,
          provider: readProgressBarProvider,
          onChanged: ref.read(readProgressBarProvider.notifier).update,
        ),
        _PanelCheckRow(
          title: context.l10n.continueReadingButton,
          provider: showContinueReadingButtonProvider,
          onChanged: ref
              .read(showContinueReadingButtonProvider.notifier)
              .update,
        ),
        _PanelCheckRow(
          title: context.l10n.sourceBadge,
          provider: sourceBadgeProvider,
          onChanged: ref.read(sourceBadgeProvider.notifier).update,
        ),
        _PanelCheckRow(
          title: context.l10n.languageBadge,
          provider: languageBadgeProvider,
          onChanged: ref.read(languageBadgeProvider.notifier).update,
        ),
        FilterSectionHeading(context.l10n.badgeLayout),
        const BadgeLayoutList(),
      ],
    );
  }
}

class _GroupColumn extends ConsumerWidget {
  const _GroupColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(libraryGroupTypeProvider) ?? kDefaultLibraryGroupType;
    final style =
        ref.watch(libraryGroupStyleKeyProvider) ?? LibraryGroupStyle.tabs;
    final hasTrackers =
        ref.watch(loggedInTrackersProvider).value?.isNotEmpty ?? false;
    final isGrid =
        (ref.watch(libraryDisplayModeProvider) ??
                DBKeys.libraryDisplayMode.initial as DisplayMode)
            .isGrid;
    final portraitCols = ref.watch(libraryPortraitColumnsProvider) ?? 0;
    final landscapeCols = ref.watch(libraryLandscapeColumnsProvider) ?? 0;
    final listScale =
        ref.watch(libraryListScaleProvider) ??
        DBKeys.listScale.initial as double;

    String groupLabel(int type) => switch (type) {
      LibraryGroup.byDefault => context.l10n.groupByDefault,
      LibraryGroup.byTag => context.l10n.groupByTag,
      LibraryGroup.bySource => context.l10n.groupBySource,
      LibraryGroup.byStatus => context.l10n.groupByStatus,
      LibraryGroup.byTrackStatus => context.l10n.groupByTrackStatus,
      LibraryGroup.byLanguage => context.l10n.groupByLanguage,
      _ => context.l10n.groupUngrouped,
    };

    final isGrouped = LibraryGroup.isGrouped(current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(context.l10n.group),
        RadioGroup<int>(
          groupValue: current,
          onChanged: (value) =>
              ref.read(libraryGroupTypeProvider.notifier).update(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final type in LibraryGroup.all)
                if (type != LibraryGroup.byTrackStatus || hasTrackers)
                  _PanelRadioRow<int>(
                    value: type,
                    onChanged: (next) => ref
                        .read(libraryGroupTypeProvider.notifier)
                        .update(next),
                    title: groupLabel(type),
                  ),
            ],
          ),
        ),
        if (isGrouped) ...[
          FilterSectionHeading(context.l10n.groupStyle),
          RadioGroup<LibraryGroupStyle>(
            groupValue: style,
            onChanged: (value) =>
                ref.read(libraryGroupStyleKeyProvider.notifier).update(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PanelRadioRow<LibraryGroupStyle>(
                  value: LibraryGroupStyle.tabs,
                  onChanged: (next) => ref
                      .read(libraryGroupStyleKeyProvider.notifier)
                      .update(next),
                  title: context.l10n.groupStyleTabs,
                ),
                _PanelRadioRow<LibraryGroupStyle>(
                  value: LibraryGroupStyle.headers,
                  onChanged: (next) => ref
                      .read(libraryGroupStyleKeyProvider.notifier)
                      .update(next),
                  title: context.l10n.groupStyleSections,
                ),
              ],
            ),
          ),
          if (style == LibraryGroupStyle.tabs)
            _PanelCheckRow(
              title: context.l10n.categoryTabs,
              provider: categoryTabsProvider,
              onChanged: ref.read(categoryTabsProvider.notifier).update,
            )
          else
            _PanelCheckRow(
              title: context.l10n.sectionHeadersShowAllCategories,
              provider: sectionHeadersShowAllCategoriesProvider,
              onChanged: ref
                  .read(sectionHeadersShowAllCategoriesProvider.notifier)
                  .update,
            ),
          _PanelCheckRow(
            title: context.l10n.categoryNumberOfItems,
            provider: categoryNumberOfItemsProvider,
            onChanged: ref.read(categoryNumberOfItemsProvider.notifier).update,
          ),
          if (current == LibraryGroup.byDefault)
            _PanelCheckRow(
              title: context.l10n.showHiddenCategories,
              provider: showHiddenCategoriesProvider,
              onChanged: ref.read(showHiddenCategoriesProvider.notifier).update,
            ),
        ],
        if (isGrid) ...[
          FilterSectionHeading(context.l10n.libraryColumnsPortrait),
          _ColumnsSlider(
            value: portraitCols,
            onChanged: (value) =>
                ref.read(libraryPortraitColumnsProvider.notifier).update(value),
          ),
          FilterSectionHeading(context.l10n.libraryColumnsLandscape),
          _ColumnsSlider(
            value: landscapeCols,
            onChanged: (value) => ref
                .read(libraryLandscapeColumnsProvider.notifier)
                .update(value),
          ),
        ] else ...[
          FilterSectionHeading(context.l10n.listSize),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: listScale,
                  min: 0.7,
                  max: 1.6,
                  divisions: 18,
                  label: '${(listScale * 100).round()}%',
                  onChanged: (value) => ref
                      .read(libraryListScaleProvider.notifier)
                      .update(double.parse(value.toStringAsFixed(2))),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(listScale * 100).round()}%',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ColumnsSlider extends StatelessWidget {
  const _ColumnsSlider({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: value == 0 ? 'Auto' : '$value',
            onChanged: (next) => onChanged(next.round()),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(value == 0 ? 'Auto' : '$value', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
