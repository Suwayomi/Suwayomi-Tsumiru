// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/manga_book/data/updates/updates_repository.dart';
import '../../features/manga_book/domain/update_status/update_status_model.dart';
import '../../features/notifications/data/local_notification_service.dart';
import '../../features/settings/presentation/library/widgets/show_update_progress_banner/show_update_progress_banner.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import 'update_banner_state.dart';

/// App-root "Updating library…" strip, shown while a global/category update
/// runs. Mirrors Komikku's `AppStateBanners` "updating" strip
/// (`eu.kanade.presentation.components.Banners.kt`, `IndexingDownloadBanner`)
/// and reuses [IncognitoBanner]'s placement convention.
///
/// **Visibility rides on a running-only signal, NOT the full status feed.**
/// The full `updateStatusChanged` feed carries every manga in every job list;
/// the server can't resolve those job-list fields promptly during a large
/// library update, so that feed goes silent mid-run. If the banner learned
/// "is it running" from there, it would show nothing during exactly the
/// updates it exists for. So on/off comes from the cheap
/// [updateRunningSocketProvider] (just `isRunning`), and the percentage is a
/// best-effort enrichment layered on top — present on small/fast updates,
/// gracefully absent (plain "Updating library…") when the heavy feed stalls.
///
/// `isRunning` is debounced 1000ms **symmetrically** (both edges), matching
/// Komikku's `Flow<Boolean>.debounce(1000L)` in `BannerProgressStatus.kt` —
/// a run that finishes inside that window never flashes the banner at all.
class UpdateProgressBanner extends HookConsumerWidget {
  const UpdateProgressBanner({super.key});

  static const _debounce = Duration(milliseconds: 1000);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showPref =
        ref.watch(showUpdateProgressBannerProvider).ifNull(true);

    final runSocket = ref.watch(updateRunningSocketProvider);
    final runFallback = ref.watch(updateRunningSummaryProvider);
    // Never trust a frozen frame from before a socket error — once the
    // stream errors, prefer a fresh one-shot read until it recovers.
    final effectiveRun = runSocket.hasError ? runFallback : runSocket;

    final l10n = context.l10n;
    ref.listen(updateRunningSocketProvider, (previous, next) {
      if (next.hasError && !(previous?.hasError ?? false)) {
        ref.invalidate(updateRunningSummaryProvider);
      }
      // Hand the optimistic hold back to the real running signal.
      final running = next.value;
      if (running != null) {
        ref.read(updateOptimisticProvider.notifier).onRealRunning(running);
      }
      // Update just finished — notify if any series failed (Komikku parity).
      if ((previous?.value ?? false) && running == false) {
        _notifyUpdateErrors(ref, l10n);
      }
    });
    // Re-query the one-shot fallback on resume, so a running-state fetched
    // while backgrounded (or long before a socket error) isn't shown stale.
    useOnAppLifecycleStateChange((previous, current) {
      if (current == AppLifecycleState.resumed) {
        ref.invalidate(updateRunningSummaryProvider);
      }
    });

    final rawRunning = effectiveRun.value ?? false;

    final debouncedRunning = useState(false);
    final timer = useRef<Timer?>(null);
    useEffect(() {
      timer.value?.cancel();
      // Cancel the local `t`, not `timer.value` — by the time this dispose
      // runs (after the *next* effect body already reassigned timer.value),
      // reading timer.value here would cancel the wrong (new) timer.
      final t = Timer(_debounce, () {
        debouncedRunning.value = rawRunning;
      });
      timer.value = t;
      return t.cancel;
    }, [rawRunning]);

    // Optimistic hold shows the banner the instant an update is triggered,
    // before the server confirms it's running and before the appear-debounce.
    // The user's "hide the banner" preference folds in here (not an early
    // return) so that toggling it off mid-update publishes visible=false and
    // the shell restores the status-bar inset it dropped.
    final armed = ref.watch(updateOptimisticProvider);
    final visible = showPref && (debouncedRunning.value || armed);

    // Publish visibility so the shell can drop the redundant status-bar inset
    // on the content below while the banner occupies that space. Deferred to a
    // post-frame callback — writing a provider during build is disallowed.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(updateBannerVisibleProvider.notifier).set(visible);
      });
      return null;
    }, [visible]);

    // Only subscribe to the heavy status feed while the bar is actually shown
    // AND the real run is confirmed (not merely armed) — during the optimistic
    // window there are no counts yet, so the banner shows the indeterminate
    // "Updating library…".
    UpdateStatusDto? status;
    if (visible && debouncedRunning.value) {
      final heavySocket = ref.watch(updatesSocketProvider);
      final heavyFallback = ref.watch(updateSummaryProvider);
      status = (heavySocket.value?.total.isGreaterThan(0)).ifNull()
          ? heavySocket.value
          : heavyFallback.value;
    }

    // The colour fills up behind the status bar and the content pads below it
    // (Komikku's `windowInsetsPadding(statusBars)`). On phone the banner draws
    // into the status bar, so take the top inset from the raw window (shell-nav
    // descendants read MediaQuery insets as 0 — see project_shell_nav_bottom_
    // inset). On tablet the shell already wraps everything in a SafeArea, so
    // the banner is below the status bar and must add no inset of its own.
    final topInset = context.isTablet
        ? 0.0
        : View.of(context).viewPadding.top / View.of(context).devicePixelRatio;

    final scheme = context.theme.colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox.shrink()
          : Material(
              color: scheme.secondary,
              child: InkWell(
                onTap: () => const UpdateStatusRoute().push(context),
                child: Padding(
                  padding: EdgeInsets.only(top: topInset) +
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _label(context, status),
                        style: TextStyle(
                          color: scheme.onSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  String _label(BuildContext context, UpdateStatusDto? status) {
    final total = status?.total ?? 0;
    if (total <= 0) return context.l10n.updatingLibrary;
    final checked = status?.updateChecked ?? 0;
    final percent = (checked / total * 100).floor().clamp(0, 100);
    return context.l10n.updatingLibraryProgress(percent, checked, total);
  }
}

/// Notifies when a just-finished library update left failures (Komikku parity).
/// Best-effort + foreground-observed (our update runs server-side). Android only.
Future<void> _notifyUpdateErrors(WidgetRef ref, AppLocalizations l10n) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final summary = await ref.read(updatesRepositoryProvider).summaryUpdates();
    final failed = summary?.failedJobs.mangaList.length ?? 0;
    if (failed == 0) return;
    final service = LocalNotificationService();
    await service.init();
    await service.showLibraryUpdateError(
      l10n.notificationLibraryErrorTitle,
      l10n.notificationLibraryErrorBody(failed),
    );
  } catch (_) {
    // Best-effort — a missed error toast is not data loss.
  }
}
