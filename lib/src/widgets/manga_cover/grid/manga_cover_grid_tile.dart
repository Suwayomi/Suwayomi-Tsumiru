// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/enum.dart';
import '../../../constants/gen/assets.gen.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../../features/manga_book/presentation/manga_thumbnail_viewer/manga_thumbnail_viewer.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../utils/theme/brand.dart';
import '../../custom_circular_progress_indicator.dart';
import '../../server_image.dart';
import '../../web_route_link.dart';
import '../providers/manga_cover_providers.dart';
import '../widgets/continue_reading_button.dart';
import '../widgets/manga_badges.dart';

const double _kBookAspectRatio = 2 / 3;

/// Height/width bounds prevent long-strip overflow and extremely wide cover collapse.
const double _kFreeformMinHeightFactor = 1.0;
const double _kFreeformMaxHeightFactor = 10 / 3;

const double _kTitleFontSize = 12;
const double _kTitleLineFactor = 1.5;
const double _kTitlePadding = 4;

/// Cap title share to prevent overflow at extreme text scales.
const double _kMaxTitleShare = .45;

double _titleBlockHeight(BuildContext context, int maxLines) =>
    MediaQuery.textScalerOf(context).scale(_kTitleFontSize) *
        _kTitleLineFactor *
        maxLines +
    _kTitlePadding * 2;

class MangaCoverGridTile extends StatefulWidget {
  const MangaCoverGridTile({
    super.key,
    required this.manga,
    this.onPressed,
    this.onLongPress,
    this.onContinueReading,
    this.showTitle = true,
    this.titleBelow = false,
    this.showBadges = true,
    this.showCountBadges = false,
    this.showDarkOverlay = true,
    this.selected = false,
    this.gridStyle = LibraryGridStyle.uniform,
    this.outlineOnCovers = false,
    this.limitTitleLines = true,
    this.highlighted = false,
    this.linkLocation,
  });
  final MangaDto manga;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// Non-null adds a button opening the next unread chapter.
  final VoidCallback? onContinueReading;
  final bool showCountBadges;
  final bool showTitle;

  /// Draw the title below the cover; showTitle does not control this title.
  final bool titleBelow;
  final bool showBadges;
  final bool showDarkOverlay;

  final bool selected;

  /// Uniform fills the cell; freeform styles derive height from the cover art.
  final LibraryGridStyle gridStyle;

  /// The selected border takes precedence over this cover outline.
  final bool outlineOnCovers;

  /// False uses the whole available title slot instead of a two-line cap.
  final bool limitTitleLines;

  /// Let an embedding row drive the same highlight as cover hover/focus.
  final bool highlighted;

  final String? linkLocation;

  @override
  State<MangaCoverGridTile> createState() => _MangaCoverGridTileState();
}

class _MangaCoverGridTileState extends State<MangaCoverGridTile> {
  var _hovered = false;
  var _focused = false;
  var _pointerFocused = false;
  late final _focusNode = FocusNode(onKeyEvent: _onKeyEvent);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_pointerFocused && event is KeyDownEvent) {
      setState(() => _pointerFocused = false);
    }
    return KeyEventResult.ignored;
  }

  bool get _overlayTitle => widget.showTitle && !widget.titleBelow;

  bool get _keyboardFocused =>
      _focused &&
      !_pointerFocused &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  Widget build(BuildContext context) {
    final freeform = widget.gridStyle.isFreeform;
    final card = _card(
      context,
      outline: widget.outlineOnCovers,
      freeform: freeform,
    );
    return WebRouteLink(
      location: widget.linkLocation,
      builder: (context, openInNewTab) => InkResponse(
        focusNode: _focusNode,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        focusColor: Colors.transparent,
        onTapDown: (_) => setState(() => _pointerFocused = true),
        onHover: (hovered) => setState(() => _hovered = hovered),
        onFocusChange: (focused) => setState(() {
          _focused = focused;
          if (!focused) _pointerFocused = false;
        }),
        onTap: () {
          _focusNode.requestFocus();
          if (widget.onPressed != null) {
            WebRouteLink.handleTap(openInNewTab, widget.onPressed!);
          } else {
            Navigator.push(
              context,
              PageRouteBuilder(
                fullscreenDialog: true,
                opaque: false,
                pageBuilder: (context, _, _) => MangaThumbnailViewer(
                  imageUrl: widget.manga.displayCoverUrl,
                  fallbackImageUrl: widget.manga.thumbnailUrl,
                  coverVersion: widget.manga.coverVersion,
                ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      if (context.reduceMotion) {
                        return ReducedRouteTransition(
                          animation: animation,
                          child: child,
                        );
                      }

                      const begin = Offset(-1.0, 0.0);
                      const end = Offset.zero;
                      const curve = Curves.ease;

                      final tween = Tween(begin: begin, end: end);
                      final curvedAnimation = CurvedAnimation(
                        parent: animation,
                        curve: curve,
                      );

                      return SlideTransition(
                        position: tween.animate(curvedAnimation),
                        child: child,
                      );
                    },
              ),
            );
          }
        },
        onLongPress: widget.onLongPress,
        child: freeform
            // Avoid vertical stretch; bottom-align variable covers within each aligned-grid row.
            ? Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment:
                    widget.gridStyle == LibraryGridStyle.nonUniform
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  card,
                  if (widget.titleBelow)
                    _TitleBlock(
                      title: widget.manga.title,
                      limitLines: widget.limitTitleLines,
                    ),
                ],
              )
            : widget.titleBelow
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final twoLines = _titleBlockHeight(context, 2);
                  final cap = constraints.hasBoundedHeight
                      ? constraints.maxHeight * _kMaxTitleShare
                      : twoLines;
                  final blockHeight = widget.limitTitleLines
                      ? min(twoLines, cap)
                      : cap;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: card),
                      SizedBox(
                        height: blockHeight,
                        child: _TitleBlock(
                          title: widget.manga.title,
                          limitLines: widget.limitTitleLines,
                        ),
                      ),
                    ],
                  );
                },
              )
            : card,
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required bool outline,
    required bool freeform,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: KBorderRadius.r12.radius,
        side: widget.selected
            ? BorderSide(color: context.theme.colorScheme.primary, width: 3)
            : _hovered || _keyboardFocused || widget.highlighted
            ? BorderSide(color: context.theme.colorScheme.primary, width: 2)
            : outline
            ? BorderSide(
                color: context.theme.colorScheme.outlineVariant,
                width: 1,
              )
            : BorderSide.none,
      ),
      // GridTile uses Positioned.fill; a freeform Stack must size itself from the cover.
      child: Stack(
        fit: freeform ? StackFit.loose : StackFit.passthrough,
        children: [
          _cover(context, freeform: freeform),
          if (_overlayTitle)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _overlayTitleBar(context),
            ),
          if (widget.showBadges)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MangaBadgesRow(
                manga: widget.manga,
                showCountBadges: widget.showCountBadges,
              ),
            ),
          if (widget.selected)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                FluentIcons.checkmark_circle_24_filled,
                color: context.theme.colorScheme.primary,
                shadows: const [Shadow(blurRadius: 4)],
              ),
            ),
          // Overlay only without an overlaid title; otherwise share the footer to avoid covering text.
          if (widget.onContinueReading != null &&
              !widget.selected &&
              !_overlayTitle)
            Positioned(
              right: 6,
              bottom: 6,
              child: ContinueReadingButton(
                onPressed: widget.onContinueReading!,
              ),
            ),
          if (widget.showBadges)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _CoverReadProgressBar(manga: widget.manga),
            ),
        ],
      ),
    );
  }

  Widget _overlayTitleBar(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    dense: true,
    title: Text(
      widget.manga.title,
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
      // Cover-art text stays white over a black scrim, independent of the theme.
      style: const TextStyle(
        color: OnImage.text,
        fontSize: 12,
        height: 1.5,
        shadows: [Shadow(color: OnImage.shadow, blurRadius: 4)],
      ),
    ),
    trailing: widget.onContinueReading != null
        ? ContinueReadingButton(
            onPressed: widget.onContinueReading!,
            size: 28,
            iconSize: 16,
          )
        : null,
  );

  Widget _cover(BuildContext context, {required bool freeform}) {
    final coverUrl = widget.manga.displayCoverUrl;
    if (coverUrl.isBlank) {
      final fallback = ImageIcon(
        AssetImage(Assets.icons.darkIcon.path),
        size: context.height * .2,
      );
      return freeform
          ? AspectRatio(
              aspectRatio: _kBookAspectRatio,
              child: FittedBox(fit: BoxFit.scaleDown, child: fallback),
            )
          : SizedBox(height: context.height * .3, child: fallback);
    }

    final Widget image = Container(
      foregroundDecoration: BoxDecoration(
        border: Border.all(width: 0, color: context.theme.canvasColor),
        boxShadow: widget.showDarkOverlay
            ? [
                BoxShadow(
                  color: context.theme.canvasColor.withValues(alpha: .5),
                ),
              ]
            : null,
        gradient: _overlayTitle
            ? const LinearGradient(
                begin: Alignment(0, 1 / 3),
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, OnImage.scrim],
              )
            : null,
      ),
      // Decode at tile size to keep full-resolution covers from exhausting the image-cache budget.
      child: LayoutBuilder(
        builder: (context, constraints) => ServerImage(
          imageUrl: coverUrl,
          fallbackImageUrl: widget.manga.thumbnailUrl,
          coverVersion: widget.manga.coverVersion,
          memCacheWidth: constraints.hasBoundedWidth
              ? (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(1, 1 << 16)
              : null,
          // Match shimmer to cover geometry so decoded art does not shift the grid.
          progressIndicatorBuilder: freeform
              ? (context, url, progress) => const _FreeformCoverPlaceholder()
              : null,
        ),
      ),
    );
    if (!freeform) return image;

    // Loosen height only; preserve the column width.
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 0.0;
          return ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: width * _kFreeformMinHeightFactor,
              maxHeight: width * _kFreeformMaxHeightFactor,
            ),
            child: image,
          );
        },
      ),
    );
  }
}

/// Uncapped titles wrap in growing tiles; uniform tiles cap at a whole-line boundary.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.limitLines});

  final String title;
  final bool limitLines;

  static const _style = TextStyle(
    fontSize: _kTitleFontSize,
    height: _kTitleLineFactor,
  );

  /// Skia ellipsis with null maxLines collapses to one line; uncapped text must wrap.
  static Widget _text(String title, int? maxLines) => Text(
    title,
    maxLines: maxLines,
    softWrap: true,
    overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    style: _style,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(_kTitlePadding),
      child: limitLines
          ? _text(title, 2)
          : LayoutBuilder(
              builder: (context, constraints) {
                if (!constraints.hasBoundedHeight) {
                  return _text(title, null);
                }
                final lineHeight =
                    MediaQuery.textScalerOf(context).scale(_kTitleFontSize) *
                    _kTitleLineFactor;
                return _text(
                  title,
                  max(1, (constraints.maxHeight / lineHeight).floor()),
                );
              },
            ),
    );
  }
}

class _FreeformCoverPlaceholder extends StatelessWidget {
  const _FreeformCoverPlaceholder();

  @override
  Widget build(BuildContext context) => const AspectRatio(
    aspectRatio: _kBookAspectRatio,
    child: Center(child: SorayomiShimmerIndicator()),
  );
}

/// Read fraction in (0,1], or null for no chapters/read progress; inconsistent counts are clamped.
double? coverReadFraction({
  required int totalChapters,
  required int unreadCount,
}) {
  if (totalChapters <= 0) return null;
  final read = (totalChapters - unreadCount).clamp(0, totalChapters);
  return read <= 0 ? null : read / totalChapters;
}

class _CoverReadProgressBar extends ConsumerWidget {
  const _CoverReadProgressBar({required this.manga});

  final MangaDto manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(readProgressBarProvider).ifNull()) {
      return const SizedBox.shrink();
    }
    final fraction = coverReadFraction(
      totalChapters: manga.chapters.totalCount,
      unreadCount: manga.user.unreadCount.getValueOnNullOrNegative(),
    );
    if (fraction == null) return const SizedBox.shrink();
    return LinearProgressIndicator(
      value: fraction,
      minHeight: 3,
      backgroundColor: Colors.black.withValues(alpha: 0.35),
      valueColor: AlwaysStoppedAnimation(context.theme.colorScheme.primary),
    );
  }
}
