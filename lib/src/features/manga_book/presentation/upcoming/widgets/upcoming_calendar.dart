// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../utils/extensions/custom_extensions.dart';

/// Month calendar for the Upcoming screen — a header (month/year + prev/next)
/// over a 7-column day grid. Each day shows its number, a small count of
/// predicted releases (top-right), and up to three dots (16sp labels, today
/// ring, dimmed past days, dots tinted by `(index + 1) * 0.3` alpha).
class UpcomingCalendar extends StatelessWidget {
  const UpcomingCalendar({
    super.key,
    required this.month,
    required this.events,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  /// Any date within the displayed month (only year+month are used).
  final DateTime month;

  /// Date (start-of-day) → number of predicted releases on that day.
  final Map<DateTime, int> events;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final ym = DateTime(month.year, month.month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          month: ym,
          onPrev: () => onMonthChanged(DateTime(ym.year, ym.month - 1)),
          onNext: () => onMonthChanged(DateTime(ym.year, ym.month + 1)),
        ),
        const SizedBox(height: 4),
        _Grid(month: ym, events: events, onDaySelected: onDaySelected),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.month, required this.onPrev, required this.onNext});
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final label = '${_monthName(context, month.month)} ${month.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.titleLarge),
          Row(
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.keyboard_arrow_left_rounded),
                tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.keyboard_arrow_right_rounded),
                tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid(
      {required this.month, required this.events, required this.onDaySelected});
  final DateTime month;
  final Map<DateTime, int> events;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final firstDow = ml.firstDayOfWeekIndex; // 0 = Sunday
    // Weekday header labels, starting from the locale's first day.
    final weekdayLabels = [
      for (var i = 0; i < 7; i++) ml.narrowWeekdays[(firstDow + i) % 7],
    ];

    final firstOfMonth = DateTime(month.year, month.month, 1);
    // DateTime.weekday: 1 = Monday .. 7 = Sunday. Map to a 0=Sunday index, then
    // offset by the locale's first day of week.
    final firstWeekdaySunday0 = firstOfMonth.weekday % 7;
    final leadingBlanks = (firstWeekdaySunday0 - firstDow + 7) % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final cells = <Widget>[
      for (final l in weekdayLabels)
        Center(
          child: Text(
            l,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        _Day(
          date: DateTime(month.year, month.month, d),
          count: events[DateTime(month.year, month.month, d)] ?? 0,
          onTap: () => onDaySelected(DateTime(month.year, month.month, d)),
        ),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: cells,
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.date, required this.count, required this.onTap});
  final DateTime date;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = date == today;
    final isPast = date.isBefore(today);
    final numberColor =
        isPast ? cs.onSurface.withValues(alpha: 0.38) : cs.onSurface;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: isToday
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cs.onSurface),
              )
            : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: numberColor),
            ),
            if (count > 0)
              Positioned(
                top: 2,
                right: 4,
                child: Text(
                  '$count',
                  style: TextStyle(fontSize: 8, color: cs.primary),
                ),
              ),
            Positioned(
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < (count > 3 ? 3 : count); i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.primary.withValues(alpha: (i + 1) * 0.3),
                        ),
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

String _monthName(BuildContext context, int month) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return names[month - 1];
}
