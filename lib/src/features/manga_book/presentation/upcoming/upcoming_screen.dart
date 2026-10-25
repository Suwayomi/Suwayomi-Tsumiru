// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../widgets/desktop/desktop_window.dart';
import '../../../../widgets/emoticons.dart';
import 'controller/upcoming_controller.dart';
import 'widgets/upcoming_calendar.dart';

class UpcomingScreen extends HookConsumerWidget {
  const UpcomingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = calendarDay(DateTime.now());
    final desktop = context.usesDesktopShell;
    final anchor = useState(today);
    final selectedDay = useState(today);
    final view = ref.watch(upcomingViewProvider) ?? UpcomingView.week;
    final showPast = ref.watch(upcomingShowPastReleasesProvider) ?? true;
    final scrollController = useMemoized(ItemScrollController.new);
    final upcoming = ref.watch(upcomingProvider);
    final month = DateTime(anchor.value.year, anchor.value.month);
    final week = anchor.value;
    final monthStart = calendarWeekStart(context, month);
    final monthEnd = DateTime.utc(month.year, month.month + 1);
    final monthDays = monthEnd
        .difference(
          DateTime.utc(monthStart.year, monthStart.month, monthStart.day),
        )
        .inDays;
    final monthRows = (monthDays / 7).ceil();
    final start = !desktop || view == UpcomingView.week ? week : monthStart;
    final end = !desktop || view == UpcomingView.week
        ? DateTime(week.year, week.month, week.day + 7)
        : DateTime(
            monthStart.year,
            monthStart.month,
            monthStart.day + monthRows * 7,
          );
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final pastEnd = end.isBefore(tomorrow) ? end : tomorrow;
    final pastProvider = upcomingPastReleasesProvider(
      start: desktop ? start : today,
      end: desktop ? pastEnd : tomorrow,
    );
    final past = !desktop || (showPast && start.isBefore(pastEnd))
        ? ref.watch(pastProvider)
        : const AsyncData<Map<DateTime, List<CalendarSeries>>>({});

    void close() {
      if (context.canPop()) {
        context.pop();
      } else {
        const UpdatesRoute().go(context);
      }
    }

    void openSeries(CalendarSeries series) {
      final router = GoRouter.of(context);
      if (desktop) close();
      router.push(MangaRoute(mangaId: series.id).location);
    }

    void move(int direction) {
      anchor.value = desktop && view == UpcomingView.month
          ? DateTime(month.year, month.month + direction)
          : DateTime(
              anchor.value.year,
              anchor.value.month,
              anchor.value.day + direction * 7,
            );
    }

    final actions = <Widget>[
      IconButton(
        icon: const Icon(FluentIcons.question_circle_24_regular),
        tooltip: context.l10n.upcomingGuide,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.l10n.upcoming),
            content: Text(ctx.l10n.upcomingGuideBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(ctx.l10n.close),
              ),
            ],
          ),
          animationStyle: context.motionStyle,
        ),
      ),
      if (desktop) ...[
        PopupMenuButton<bool>(
          tooltip: context.l10n.upcomingCalendarOptions,
          icon: const Icon(FluentIcons.more_vertical_24_regular),
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              value: !showPast,
              checked: showPast,
              child: Text(context.l10n.upcomingShowPastReleases),
            ),
          ],
          onSelected: ref
              .read(upcomingShowPastReleasesProvider.notifier)
              .update,
        ),
        IconButton(
          tooltip: context.l10n.close,
          onPressed: close,
          icon: const Icon(FluentIcons.dismiss_24_regular),
        ),
      ],
    ];

    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              desktop && view == UpcomingView.month
                  ? DateFormat.yMMMM(context.currentLocale.toLanguageTag())
                        .format(month)
                  : calendarWeekLabel(context, week),
              style: context.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: () => move(-1),
            icon: const Icon(FluentIcons.chevron_left_24_regular),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: () => move(1),
            icon: const Icon(FluentIcons.chevron_right_24_regular),
          ),
          if (desktop) ...[
            OutlinedButton(
              onPressed: () {
                anchor.value = today;
                selectedDay.value = today;
              },
              child: Text(context.l10n.today),
            ),
            const SizedBox(width: 24),
            UpcomingViewSwitch(
              value: view,
              onChanged: ref.read(upcomingViewProvider.notifier).update,
            ),
          ],
        ],
      ),
    );

    Widget content(UpcomingData predictions) {
      final days = <DateTime, List<CalendarSeries>>{
        ...?past.asData?.value,
        for (final group in predictions.groups)
          group.date: <int, CalendarSeries>{
            for (final series
                in past.asData?.value[group.date] ?? <CalendarSeries>[])
              series.id: series,
            for (final manga in group.mangas)
              manga.id: (
                id: manga.id,
                title: manga.title,
                thumbnailUrl: manga.thumbnailUrl,
              ),
          }.values.toList(),
      };
      if (desktop) {
        return UpcomingCalendar(
          view: view,
          start: start,
          month: month,
          rows: monthRows,
          days: days,
          onOpen: openSeries,
        );
      }
      final dates = days.keys
          .where(
            (day) => desktop
                ? !day.isBefore(start) && day.isBefore(end)
                : !day.isBefore(today) && days[day]!.isNotEmpty,
          )
          .toSet();
      final sorted = dates.toList()..sort();
      final rows = <({DateTime? date, CalendarSeries? series})>[];
      final indices = <DateTime, int>{};
      for (final day in sorted) {
        indices[day] = rows.length;
        rows.add((date: day, series: null));
        for (final series in days[day] ?? <CalendarSeries>[]) {
          rows.add((date: day, series: series));
        }
      }
      final list = rows.isEmpty
          ? Center(child: Text(context.l10n.upcomingEmpty))
          : ScrollablePositionedList.builder(
              itemScrollController: scrollController,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final series = row.series;
                final day = row.date!;
                return Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Opacity(
                      opacity: day.isBefore(today) ? .55 : 1,
                      child: series == null
                          ? _DateHeading(
                              date: day,
                              count: days[day]?.length ?? 0,
                            )
                          : UpcomingSeriesTile(
                              series: series,
                              coverSize: const Size(40, 56),
                              onTap: () => openSeries(series),
                            ),
                    ),
                  ),
                );
              },
            );
      return Column(
        children: [
          if (!desktop) ...[
            UpcomingWeekStrip(
              start: week,
              selected: selectedDay.value,
              days: days,
              onSelected: (day) {
                selectedDay.value = day;
                int? index;
                for (final date in sorted) {
                  if (!date.isBefore(day)) {
                    index = indices[date];
                    break;
                  }
                }
                if (index == null || !scrollController.isAttached) return;
                if (context.reduceMotion) {
                  scrollController.jumpTo(index: index);
                } else {
                  scrollController.scrollTo(
                    index: index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
            ),
            const Divider(height: 16),
          ],
          Expanded(child: list),
        ],
      );
    }

    final body = Column(
      children: [
        if (desktop)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.upcoming,
                    style: context.textTheme.titleMedium,
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        controls,
        if (past.isLoading) const LinearProgressIndicator(),
        if (past.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    past.error.toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(pastProvider),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        Expanded(
          child: upcoming.when(
            loading: () => const CenterSorayomiShimmerIndicator(),
            error: (e, _) => Emoticons(
              title: e.toString(),
              button: TextButton(
                onPressed: () => ref.invalidate(upcomingProvider),
                child: Text(context.l10n.retry),
              ),
            ),
            data: content,
          ),
        ),
      ],
    );
    if (desktop) return DesktopWindow(onClose: close, child: body);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.upcoming), actions: actions),
      body: body,
    );
  }
}

class _DateHeading extends StatelessWidget {
  const _DateHeading({required this.date, required this.count});
  final DateTime date;
  final int count;

  @override
  Widget build(BuildContext context) {
    final today = calendarDay(DateTime.now());
    final label = date == today
        ? context.l10n.today
        : date == DateTime(today.year, today.month, today.day + 1)
        ? context.l10n.tomorrow
        : DateFormat.MMMEd(context.currentLocale.toLanguageTag()).format(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            label,
            style: context.textTheme.titleSmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          UpcomingCountChip(count: count),
        ],
      ),
    );
  }
}
