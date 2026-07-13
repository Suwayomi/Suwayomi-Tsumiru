// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/theme/brand.dart';
import '../../../../../settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import '../../controller/auto_scroll_controller.dart';

/// Komikku-style collapsible utils bar (`ExhUtils.kt` parity): an always-visible
/// centered pull-down chevron sits under [ReaderTopBar]; tapping it expands the
/// on-screen auto-motion controls for touch users. Seeded without Komikku's
/// Retry-All/Boost-Page grab-bag.
///
/// The one toggle adapts to the reading mode: in the vertical glide modes it's
/// "Auto scroll" (with a smooth/jump option), in the page-flip modes it's
/// "Auto advance" and turns a page per interval. Each keeps its own stored
/// interval so a page-flip pace can differ from a scroll pace.
class ReaderUtilsBar extends ConsumerWidget {
  const ReaderUtilsBar({
    super.key,
    required this.expanded,
    required this.readerMode,
  });

  /// Owned by [ReaderWrapper]; flipped by this bar's own chevron handle.
  final ValueNotifier<bool> expanded;

  /// Resolved reading mode, used to pick scroll-vs-advance wording, interval,
  /// and whether the smooth/jump option is meaningful.
  final ReaderMode readerMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final active = ref.watch(autoScrollActiveProvider);

    // Vertical glide vs page-flip: same toggle, but different label, a
    // different stored interval, and no smooth option when turning pages.
    final isScrollMode = readerMode == ReaderMode.webtoon ||
        readerMode == ReaderMode.continuousVertical;

    final smooth = ref.watch(smoothAutoScrollProvider) ??
        DBKeys.smoothAutoScroll.initial as bool;
    final int interval;
    if (isScrollMode) {
      interval = ref.watch(autoScrollIntervalSecondsProvider) ??
          DBKeys.autoScrollIntervalSeconds.initial as int;
    } else {
      interval = ref.watch(autoAdvanceIntervalSecondsProvider) ??
          DBKeys.autoAdvanceIntervalSeconds.initial as int;
    }

    void setInterval(int value) {
      final clamped = value.clamp(1, 30);
      if (isScrollMode) {
        ref.read(autoScrollIntervalSecondsProvider.notifier).update(clamped);
      } else {
        ref.read(autoAdvanceIntervalSecondsProvider.notifier).update(clamped);
      }
    }

    final label = isScrollMode
        ? context.l10n.autoScrollInterval
        : context.l10n.autoAdvanceInterval;

    return Material(
      color: readerNavSurface(cs),
      child: ValueListenableBuilder<bool>(
        valueListenable: expanded,
        builder: (context, isOpen, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Controls slide in above the handle.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.fastOutSlowIn,
              alignment: Alignment.topCenter,
              child: !isOpen
                  ? const SizedBox(width: double.infinity, height: 0)
                  : Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          Switch(
                            value: active,
                            activeThumbColor: cs.primary,
                            onChanged: (_) => ref
                                .read(autoScrollActiveProvider.notifier)
                                .toggle(),
                          ),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(color: cs.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Faster = shorter interval, so "-" lowers seconds.
                          IconButton(
                            icon: Icon(Icons.remove, color: cs.onSurface),
                            onPressed: () => setInterval(interval - 1),
                          ),
                          Text(
                            context.l10n.autoScrollSeconds(interval),
                            style: TextStyle(color: cs.onSurface),
                          ),
                          IconButton(
                            icon: Icon(Icons.add, color: cs.onSurface),
                            onPressed: () => setInterval(interval + 1),
                          ),
                          // Smooth/jump only matters while gliding; page-flip
                          // is always a discrete turn.
                          if (isScrollMode) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: context.l10n.smoothAutoScroll,
                              child: Switch(
                                value: smooth,
                                activeThumbColor: cs.primary,
                                thumbIcon: WidgetStateProperty.resolveWith(
                                  (states) => Icon(
                                    states.contains(WidgetState.selected)
                                        ? Icons.waves_rounded
                                        : Icons.arrow_downward_rounded,
                                    size: 16,
                                  ),
                                ),
                                onChanged: (value) => ref
                                    .read(smoothAutoScrollProvider.notifier)
                                    .update(value),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            // Always-visible centered pull-down handle (Komikku's chevron).
            // Komikku lets the IconButton keep its natural size so the arrow
            // gets even room above and below; a little bottom padding keeps it
            // off the seekbar that sits just under this bar.
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                height: 30,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 26,
                  visualDensity: VisualDensity.compact,
                  tooltip: label,
                  onPressed: () => expanded.value = !expanded.value,
                  icon: Icon(
                    isOpen
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
