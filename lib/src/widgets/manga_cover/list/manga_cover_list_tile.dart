// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../constants/app_sizes.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../server_image.dart';
import '../../web_route_link.dart';
import '../widgets/continue_reading_button.dart';
import '../widgets/manga_badges.dart';

class MangaCoverListTile extends StatefulWidget {
  const MangaCoverListTile({
    super.key,
    required this.manga,
    this.onPressed,
    this.onLongPress,
    this.onContinueReading,
    this.trailing,
    this.showBadges = true,
    this.showCountBadges = false,
    this.selected = false,
    this.scale = 1.0,
    this.limitTitleLines = true,
    this.linkLocation,
  });

  final String? linkLocation;

  final MangaDto manga;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// When non-null, a play button at the row end opens the next unread chapter.
  final VoidCallback? onContinueReading;

  /// An optional action widget pinned to the row end (e.g. a Migrate button).
  final Widget? trailing;
  final bool showCountBadges;
  final bool showBadges;
  final bool selected;

  /// Scale covers here; callers must scale row text through MediaQuery.
  final double scale;

  /// False wraps fully only if the caller lets the row grow.
  final bool limitTitleLines;

  @override
  State<MangaCoverListTile> createState() => _MangaCoverListTileState();
}

class _MangaCoverListTileState extends State<MangaCoverListTile> {
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

  bool get _keyboardFocused =>
      _focused &&
      !_pointerFocused &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.24)
          : Colors.transparent,
      child: WebRouteLink(
        location: widget.linkLocation,
        builder: (context, openInNewTab) => InkWell(
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
          onTap: widget.onPressed == null
              ? null
              : () {
                  _focusNode.requestFocus();
                  WebRouteLink.handleTap(openInNewTab, widget.onPressed!);
                },
          onLongPress: widget.onLongPress,
          child: Row(
            children: [
              Padding(
                padding: KEdgeInsets.a8.size,
                child: Container(
                  foregroundDecoration:
                      widget.selected || _hovered || _keyboardFocused
                      ? BoxDecoration(
                          borderRadius: KBorderRadius.r8.radius,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: widget.selected ? 3 : 2,
                          ),
                        )
                      : null,
                  child: ClipRRect(
                    borderRadius: KBorderRadius.r8.radius,
                    child: ServerImage(
                      imageUrl: widget.manga.displayCoverUrl,
                      fallbackImageUrl: widget.manga.thumbnailUrl,
                      memCacheWidth: (kCompactCoverWidth *
                              widget.scale *
                              MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(1, 1 << 16),
                      size: Size(
                        kCompactCoverWidth * widget.scale,
                        mangaCoverBoxHeight(kCompactCoverWidth * widget.scale,
                            coverInset: 0),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: KEdgeInsets.h8.size,
                  // Skia uncapped ellipsis collapses to one line; use clip for wrapping.
                  child: Text(
                    widget.manga.title,
                    softWrap: true,
                    overflow: widget.limitTitleLines
                        ? TextOverflow.ellipsis
                        : TextOverflow.clip,
                    maxLines: widget.limitTitleLines ? 3 : null,
                  ),
                ),
              ),
              if (widget.showBadges)
                MangaBadgesRow(
                  manga: widget.manga,
                  showCountBadges: widget.showCountBadges),
              if (widget.onContinueReading != null)
                Padding(
                  padding: KEdgeInsets.h8.size,
                  child: ContinueReadingButton(
                    onPressed: widget.onContinueReading!,
                    size: 28,
                  ),
                ),
              ?widget.trailing,
            ],
          ),
        ),
      ),
    );
  }
}
