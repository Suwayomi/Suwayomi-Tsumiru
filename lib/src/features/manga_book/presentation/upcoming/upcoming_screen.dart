// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/server_image.dart';
import '../../domain/manga/manga_model.dart';
import 'controller/upcoming_controller.dart';
import 'widgets/upcoming_calendar.dart';

/// "Upcoming" calendar: predicted next-release dates across the library, on a
/// month grid with a date-grouped list below.
class UpcomingScreen extends HookConsumerWidget {
  const UpcomingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final selectedMonth = useState(DateTime(now.year, now.month));
    final itemScrollController = useMemoized(ItemScrollController.new);
    final upcoming = ref.watch(upcomingProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.upcoming),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
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
            ),
          ),
        ],
      ),
      body: upcoming.when(
        loading: () => const CenterSorayomiShimmerIndicator(),
        error: (e, _) => Emoticons(
          title: e.toString(),
          button: TextButton(
            onPressed: () => ref.invalidate(upcomingProvider),
            child: Text(context.l10n.retry),
          ),
        ),
        data: (data) {
          if (data.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(upcomingProvider),
              child: ListView(
                children: [
                  UpcomingCalendar(
                    month: selectedMonth.value,
                    events: data.events,
                    onMonthChanged: (m) => selectedMonth.value = m,
                    onDaySelected: (_) {},
                  ),
                  const SizedBox(height: 48),
                  Center(child: Text(context.l10n.upcomingEmpty)),
                ],
              ),
            );
          }

          // Flatten into a single scrollable list: calendar, then for each day
          // group a header followed by its manga rows. Track where each day's
          // header lands so tapping a calendar day can scroll to it.
          final rows = <_Row>[const _CalendarRow()];
          final dateToIndex = <DateTime, int>{};
          for (final g in data.groups) {
            dateToIndex[g.date] = rows.length;
            rows.add(_HeaderRow(g.date, g.mangas.length));
            for (final m in g.mangas) {
              rows.add(_MangaRow(m));
            }
          }

          void scrollToDay(DateTime day) {
            final idx = dateToIndex[DateTime(day.year, day.month, day.day)];
            if (idx != null) {
              itemScrollController.scrollTo(
                index: idx,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          }

          return ScrollablePositionedList.builder(
            itemScrollController: itemScrollController,
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              return switch (row) {
                _CalendarRow() => UpcomingCalendar(
                    month: selectedMonth.value,
                    events: data.events,
                    onMonthChanged: (m) => selectedMonth.value = m,
                    onDaySelected: scrollToDay,
                  ),
                _HeaderRow(:final date, :final count) =>
                  _DateHeading(date: date, count: count),
                _MangaRow(:final manga) => _UpcomingTile(manga: manga),
              };
            },
          );
        },
      ),
    );
  }
}

sealed class _Row {
  const _Row();
}

class _CalendarRow extends _Row {
  const _CalendarRow();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.date, this.count);
  final DateTime date;
  final int count;
}

class _MangaRow extends _Row {
  const _MangaRow(this.manga);
  final MangaDto manga;
}

class _DateHeading extends StatelessWidget {
  const _DateHeading({required this.date, required this.count});
  final DateTime date;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Text(
            _relativeDate(context, date),
            style: context.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  color: cs.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.manga});
  final MangaDto manga;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => MangaRoute(mangaId: manga.id).push(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: KBorderRadius.r8.radius,
              child: ServerImage(
                imageUrl: manga.thumbnailUrl ?? "",
                size: const Size(56, 80),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _relativeDate(BuildContext context, DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return context.l10n.today;
  if (diff == 1) return context.l10n.tomorrow;
  return DateFormat.MMMEd(context.currentLocale.toLanguageTag()).format(d);
}
