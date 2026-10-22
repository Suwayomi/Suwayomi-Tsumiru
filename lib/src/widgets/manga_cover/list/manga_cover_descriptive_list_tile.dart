// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/enum.dart';
import '../../../features/browse_center/domain/source/source_model.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../web_route_link.dart';
import '../grid/manga_cover_grid_tile.dart';
import '../widgets/manga_badges.dart';
import '../widgets/manga_chips.dart';

class MangaCoverDescriptiveListTile extends StatefulWidget {
  const MangaCoverDescriptiveListTile({
    super.key,
    required this.manga,
    this.onPressed,
    this.onLongPress,
    this.onContinueReading,
    this.onTitleClicked,
    this.showBadges = true,
    this.showCountBadges = true,
    this.selected = false,
    this.belowStatus,
    this.outlineOnCovers = false,
    this.scale = 1.0,
    this.titleMaxLines = 2,
    this.linkLocation,
  });
  final String? linkLocation;
  final MangaDto manga;
  final bool showBadges;
  final bool showCountBadges;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// When non-null, a play button is overlaid on the cover that opens the next
  /// unread chapter.
  final VoidCallback? onContinueReading;
  final ValueChanged<String?>? onTitleClicked;
  final bool selected;
  /// Optional widget rendered below the status/source line (details screen only).
  /// When null — the default for library/browse callers — nothing is rendered.
  final Widget? belowStatus;

  /// Forwarded to the cover tile.
  final bool outlineOnCovers;

  /// Library list-size multiplier. Scales the cover box; the caller scales the
  /// text through a [MediaQuery] textScaler so the row grows as one unit.
  final double scale;

  /// Null lets the title wrap to its full length, which is what the details
  /// screen wants (Mihon caps it nowhere). List rows keep 2 so they stay even.
  final int? titleMaxLines;

  @override
  State<MangaCoverDescriptiveListTile> createState() =>
      _MangaCoverDescriptiveListTileState();
}

class _MangaCoverDescriptiveListTileState
    extends State<MangaCoverDescriptiveListTile> {
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
          child: Padding(
            padding: const EdgeInsets.all(kListTilePadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: kDescriptiveCoverWidth * widget.scale,
                  height: mangaCoverBoxHeight(
                  kDescriptiveCoverWidth * widget.scale),
                  child: MangaCoverGridTile(
                    manga: widget.manga,
                    showBadges: false,
                    showTitle: false,
                    showDarkOverlay: false,
                    selected: widget.selected,
                    highlighted: _hovered || _keyboardFocused,
                    onContinueReading: widget.onContinueReading,
                    outlineOnCovers: widget.outlineOnCovers,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: widget.onTitleClicked != null
                              ? () => widget.onTitleClicked!(widget.manga.title)
                              : null,
                          // Skia collapses an uncapped ellipsis to one line, so
                          // uncapped text has to clip instead.
                          child: Text(
                            widget.manga.title,
                            style: context.textTheme.titleLarge,
                            softWrap: true,
                            overflow: widget.titleMaxLines == null
                                ? TextOverflow.clip
                                : TextOverflow.ellipsis,
                            maxLines: widget.titleMaxLines,
                            semanticsLabel: widget.manga.title,
                          ),
                        ),
                        Gap(8),
                        InkWell(
                          onTap: widget.onTitleClicked != null &&
                              widget.manga.author.isNotBlank
                              ? () => widget.onTitleClicked!(widget.manga.author)
                              : null,
                          child: Text(
                            widget.manga.author ?? context.l10n.unknownAuthor,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodyMedium,
                          ),
                        ),
                        Gap(8),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ...[
                              Icon(
                                MangaStatus.fromJson(widget.manga.status.name).icon,
                                size: 16,
                                color: context.textTheme.bodySmall?.color,
                              ),
                              Text(
                                " ${MangaStatus.fromJson(widget.manga.status.name).toLocale(context)}",
                                style: context.textTheme.bodySmall,
                              ),
                            ],
                            if (widget.manga.source?.displayName != null) ...[
                              Text(" • "),
                              WebRouteLink(
                                location: (widget.manga.source?.id).isNotBlank
                                    ? SourceTypeRoute(
                                        sourceId: widget.manga.source!.id,
                                        sourceType: SourceType.POPULAR,
                                      ).location
                                    : null,
                                enabled: widget.linkLocation == null,
                                builder: (context, openSourceInNewTab) =>
                                    InkWell(
                                      onTap:
                                          (widget.manga.source?.id).isNotBlank
                                          ? () => WebRouteLink.handleTap(
                                              openSourceInNewTab,
                                              () => SourceTypeRoute(
                                                sourceId:
                                                    widget.manga.source!.id,
                                                sourceType: SourceType.POPULAR,
                                              ).go(context),
                                            )
                                          : null,
                                      child: Text(
                                        widget.manga.source?.displayName ??
                                            context.l10n.unknownSource,
                                        style: context.textTheme.bodySmall,
                                      ),
                                    ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.belowStatus != null) ...[
                          Gap(4),
                          widget.belowStatus!,
                        ],
                        // if (showLastReadChapter) ...[
                        //   Padding(
                        //     padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                        //     child: Text(
                        //       manga.lastChapterRead?.name ?? "",
                        //       overflow: TextOverflow.ellipsis,
                        //       style: context.textTheme.bodySmall,
                        //     ),
                        //   ),
                        //   Padding(
                        //     padding: const EdgeInsets.symmetric(vertical: 2.0),
                        //     child: Text(
                        //       manga.lastReadAt.toDaysAgoFromSeconds ?? "",
                        //       overflow: TextOverflow.ellipsis,
                        //       style: context.textTheme.bodySmall,
                        //     ),
                        //   ),
                        // ],
                        if (widget.showBadges)
                          context.windowSizeClass >= WindowSizeClass.medium
                              ? MangaChipsRow(
                                  manga: widget.manga,
                                  showCountBadges: widget.showCountBadges,
                                )
                              : MangaBadgesRow(
                                  padding: KEdgeInsets.v8.size,
                                  manga: widget.manga,
                                  showCountBadges: widget.showCountBadges,
                                ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
