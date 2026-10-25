// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/server_image.dart';
import '../controller/upcoming_controller.dart';

const _scrollbarGutter = 14.0;

DateTime calendarDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

DateTime calendarWeekStart(BuildContext context, DateTime date) {
  final firstDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;
  return DateTime(
    date.year,
    date.month,
    date.day - (date.weekday % 7 - firstDay + 7) % 7,
  );
}

String calendarWeekLabel(BuildContext context, DateTime start) {
  final end = DateTime(start.year, start.month, start.day + 6);
  final locale = context.currentLocale.toLanguageTag();
  final first = DateFormat.MMMd(locale).format(start);
  final last = start.month == end.month && start.year == end.year
      ? DateFormat.d(locale).format(end)
      : DateFormat.MMMd(locale).format(end);
  return '$first – $last';
}

class UpcomingViewSwitch extends StatelessWidget {
  const UpcomingViewSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final UpcomingView value;
  final ValueChanged<UpcomingView> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final labels = [
      context.l10n.upcomingViewMonth,
      context.l10n.upcomingViewWeek,
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final view in UpcomingView.values)
            Semantics(
              selected: value == view,
              inMutuallyExclusiveGroup: true,
              child: Material(
                color: value == view ? cs.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                child: InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: () => onChanged(view),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Text(
                      labels[view.index],
                      style: context.textTheme.labelLarge?.copyWith(
                        color: value == view ? cs.primary : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class UpcomingCountChip extends StatelessWidget {
  const UpcomingCountChip({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 22, minHeight: 20),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: context.colorScheme.primary,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      '$count',
      textAlign: TextAlign.center,
      style: context.textTheme.labelSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.colorScheme.onPrimary,
      ),
    ),
  );
}

class UpcomingWeekStrip extends StatelessWidget {
  const UpcomingWeekStrip({
    super.key,
    required this.start,
    required this.selected,
    required this.days,
    required this.onSelected,
  });

  final DateTime start;
  final DateTime selected;
  final Map<DateTime, List<CalendarSeries>> days;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final today = calendarDay(DateTime.now());
    final cs = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final day = DateTime(start.year, start.month, start.day + i);
                  final count = days[day]?.length ?? 0;
                  return Semantics(
                    selected: day == selected,
                    button: true,
                    child: Material(
                      color: day == selected
                          ? cs.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onSelected(day),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Text(
                                DateFormat.E(
                                  context.currentLocale.toLanguageTag(),
                                ).format(day),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${day.day}',
                                style: context.textTheme.titleMedium?.copyWith(
                                  color: day == today
                                      ? cs.primary
                                      : cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (count > 0)
                                UpcomingCountChip(count: count)
                              else
                                const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class UpcomingCalendar extends StatelessWidget {
  const UpcomingCalendar({
    super.key,
    required this.view,
    required this.start,
    required this.month,
    required this.rows,
    required this.days,
    required this.onOpen,
  });

  final UpcomingView view;
  final DateTime start;
  final DateTime month;
  final int rows;
  final Map<DateTime, List<CalendarSeries>> days;
  final ValueChanged<CalendarSeries> onOpen;

  @override
  Widget build(BuildContext context) {
    final today = calendarDay(DateTime.now());
    final cs = context.colorScheme;
    final locale = context.currentLocale.toLanguageTag();
    final dates = [
      for (var i = 0; i < 7; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    if (view == UpcomingView.week) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: _scrollbarGutter),
              child: Row(
                spacing: 6,
                children: [
                  for (final day in dates)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          border: Border(
                            bottom: BorderSide(color: cs.outlineVariant),
                          ),
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                DateFormat.E(locale).format(day).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${day.day}',
                              style: context.textTheme.titleLarge?.copyWith(
                                color: day == today
                                    ? cs.primary
                                    : day.isBefore(today)
                                    ? cs.onSurface.withValues(alpha: .55)
                                    : cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: _scrollbarGutter),
                child: Row(
                  spacing: 6,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final day in dates)
                      Expanded(
                        child: Opacity(
                          opacity: day.isBefore(today) ? .55 : 1,
                          child: Column(
                            children: [
                              for (final series
                                  in days[day] ?? <CalendarSeries>[])
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Material(
                                    color: cs.onSurface.withValues(alpha: .03),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: cs.outlineVariant,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: UpcomingSeriesTile(
                                      series: series,
                                      coverSize: const Size(52, 74),
                                      compact: true,
                                      titleMaxLines: 3,
                                      onTap: () => onOpen(series),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              for (final day in dates)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      DateFormat.E(locale).format(day).toUpperCase(),
                      style: context.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: Column(
              children: [
                for (var row = 0; row < rows; row++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var col = 0; col < 7; col++)
                          Expanded(
                            child: _MonthDay(
                              date: DateTime(
                                start.year,
                                start.month,
                                start.day + row * 7 + col,
                              ),
                              month: month,
                              days: days,
                              onOpen: onOpen,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthDay extends StatelessWidget {
  const _MonthDay({
    required this.date,
    required this.month,
    required this.days,
    required this.onOpen,
  });

  final DateTime date;
  final DateTime month;
  final Map<DateTime, List<CalendarSeries>> days;
  final ValueChanged<CalendarSeries> onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final today = calendarDay(DateTime.now());
    final past = date.isBefore(today);
    final otherMonth = date.month != month.month;
    final series = days[date] ?? <CalendarSeries>[];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: otherMonth ? cs.onSurface.withValues(alpha: .03) : null,
        border: Border.all(color: cs.outlineVariant, width: .5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context);
          double lineHeight(TextStyle? style) {
            final painter = TextPainter(
              text: TextSpan(text: ' ', style: style),
              textDirection: Directionality.of(context),
              textScaler: scale,
              maxLines: 1,
            )..layout();
            final height = painter.height;
            painter.dispose();
            return height;
          }

          final headingHeight = math.max(26.0, scale.scale(12) + 6);
          final entryHeight =
              math.max(26.0, lineHeight(context.textTheme.bodySmall)) + 6;
          final moreHeight = lineHeight(context.textTheme.labelSmall);
          final available = math.max(
            0.0,
            constraints.maxHeight - headingHeight,
          );
          final allFit = series.length * entryHeight <= available;
          final shown = allFit
              ? series.length
              : math.max(0, ((available - moreHeight) / entryHeight).floor());
          return ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: headingHeight,
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: date == today
                            ? BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.primary,
                              )
                            : null,
                        child: Text(
                          '${date.day}',
                          style: context.textTheme.labelSmall?.copyWith(
                            color: date == today
                                ? cs.onPrimary
                                : past || otherMonth
                                ? cs.onSurface.withValues(alpha: .38)
                                : cs.onSurface,
                          ),
                        ),
                      ),
                      if (!past && series.isNotEmpty)
                        Flexible(
                          child: Text(
                            ' ${series.length}',
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                for (final manga in series.take(shown))
                  SizedBox(
                    height: entryHeight,
                    child: Opacity(
                      opacity: past ? .55 : 1,
                      child: UpcomingSeriesTile(
                        series: manga,
                        coverSize: const Size(18, 26),
                        compact: true,
                        singleLine: true,
                        onTap: () => onOpen(manga),
                      ),
                    ),
                  ),
                if (shown < series.length)
                  SizedBox(
                    height: moreHeight,
                    child: Builder(
                      builder: (anchorContext) => InkWell(
                        onTap: () => _showDay(anchorContext, series, past),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            context.l10n.updatesGroupingShowMore(
                              series.length - shown,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.labelSmall?.copyWith(
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDay(BuildContext context, List<CalendarSeries> series, bool past) {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      constraints: const BoxConstraints.tightFor(width: 320),
      color: context.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colorScheme.outlineVariant),
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Builder(
            builder: (popupContext) => SizedBox(
              height: math.min(460, 48 + series.length * 52).toDouble(),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat.MMMEd(
                              context.currentLocale.toLanguageTag(),
                            ).format(date),
                            style: context.textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.close,
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          onPressed: () => Navigator.of(popupContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: series.length,
                      itemBuilder: (context, index) => Opacity(
                        opacity: past ? .55 : 1,
                        child: UpcomingSeriesTile(
                          series: series[index],
                          coverSize: const Size(28, 40),
                          onTap: () {
                            Navigator.of(popupContext).pop();
                            onOpen(series[index]);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class UpcomingSeriesTile extends StatelessWidget {
  const UpcomingSeriesTile({
    super.key,
    required this.series,
    required this.coverSize,
    required this.onTap,
    this.compact = false,
    this.singleLine = false,
    this.titleMaxLines = 2,
  });

  final CalendarSeries series;
  final Size coverSize;
  final VoidCallback onTap;
  final bool compact;
  final bool singleLine;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 16,
        vertical: singleLine
            ? 3
            : compact
            ? 4
            : 6,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: ServerImage(
              imageUrl: series.thumbnailUrl ?? '',
              size: coverSize,
            ),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Text(
              series.title,
              maxLines: singleLine ? 1 : titleMaxLines,
              overflow: TextOverflow.ellipsis,
              style:
                  (compact
                          ? context.textTheme.bodySmall
                          : context.textTheme.bodyMedium)
                      ?.copyWith(color: context.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    ),
  );
}
