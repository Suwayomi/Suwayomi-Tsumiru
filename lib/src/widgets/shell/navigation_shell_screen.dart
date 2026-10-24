// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../constants/app_distribution.dart';
import '../../features/about/data/about_repository.dart';
import '../../features/about/data/server_update_alerts_repository.dart';
import '../../features/about/data/web_update_browser.dart';
import '../../features/about/presentation/about/controllers/about_controller.dart';
import '../../features/about/presentation/about/widget/app_update_dialog.dart';
import '../../features/account/data/account_providers.dart';
import '../../features/offline/data/account_storage_recovery_state.dart';
import '../../features/offline/presentation/account_storage_recovery_banner.dart';
import '../../graphql/__generated__/schema.graphql.dart';
import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../../utils/misc/toast/toast.dart';
import '../desktop/desktop_top_bar.dart';
import 'big_screen_navigation_bar.dart';
import 'incognito_banner.dart';
import 'small_screen_navigation_bar.dart';
import 'update_banner_state.dart';
import 'update_progress_banner.dart';

class NavigationShellScreen extends HookConsumerWidget {
  const NavigationShellScreen({super.key, required this.child});
  final StatefulNavigationShell child;

  Future<void> checkForUpdate({
    required String? title,
    required BuildContext context,
    required WidgetRef ref,
    required Future<AsyncValue<Version?>> Function() updateCallback,
    required Toast? toast,
  }) async {
    final AsyncValue<Version?> versionResult = await updateCallback();
    toast?.close();
    if (!context.mounted) return;
    versionResult.whenOrNull(
      data: (version) {
        if (version == null) return;
        // Respect a version the user chose to skip: only prompt again once a
        // release newer than the skipped one is available.
        final dismissed = ref.read(dismissedUpdateVersionProvider);
        if (dismissed != null && dismissed.isNotEmpty) {
          Version? skipped;
          try {
            skipped = Version.parse(dismissed);
          } catch (_) {
            skipped = null;
          }
          if (skipped != null && version.compareTo(skipped) <= 0) return;
        }
        appUpdateDialog(
          title: title ?? context.l10n.appTitle,
          newRelease: "v${version.canonicalizedVersion}",
          context: context,
          toast: toast,
          onSkipChanged: (skip) => ref
              .read(dismissedUpdateVersionProvider.notifier)
              .update(skip ? version.canonicalizedVersion : ''),
        );
      },
    );
  }

  /// WebUI's server-update notices, once per launch: a short toast when the
  /// server version changed since this device last saw it, and one with an
  /// About action when a newer server is available. Server managers only;
  /// every failure is silent so startup never breaks.
  Future<void> checkServerUpdateAlerts({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    // Captured before the first await: the toast action below fires long
    // after this method returns, when the build context is gone.
    final goRouter = GoRouter.of(context);
    final aboutLocation = const AboutRoute().location;
    try {
      final canManage = ref
          .read(settledAccountAccessProvider)
          .allows(Enum$UserPermission.MANAGE_SETTINGS);
      final settings = canManage
          ? await ref.read(serverUpdateAlertsRepositoryProvider).settings()
          : null;
      final about = await ref.read(aboutRepositoryProvider).getAbout();
      if (!context.mounted) return;
      final currentVersion = about?.version ?? '';
      final decision = decideServerUpdateAlerts(
        canManage: canManage,
        currentVersion: currentVersion,
        lastSeenVersion: ref.read(lastSeenServerVersionProvider),
        informVersionUpdated: settings?.informVersionUpdated ?? true,
        informAvailableUpdate: settings?.informAvailableUpdate ?? true,
      );
      if (decision.storeVersion) {
        ref.read(lastSeenServerVersionProvider.notifier).update(currentVersion);
      }
      final toast = ref.read(toastProvider);
      if (decision.showUpdatedNotice && context.mounted) {
        toast?.show(context.l10n.serverUpdatedTo(currentVersion));
      }
      if (!decision.checkAvailable) return;
      final updates = await ref
          .read(aboutRepositoryProvider)
          .checkServerUpdate();
      if (!context.mounted) return;
      String? newestTag;
      for (final entry in updates ?? []) {
        if (entry.channel == about?.buildType) {
          newestTag = entry.tag;
          break;
        }
      }
      if (isNewerServerVersion(currentVersion, newestTag) && context.mounted) {
        toast?.showWithAction(
          context.l10n.serverUpdateAvailable,
          actionLabel: context.l10n.about,
          onAction: () => goRouter.push(aboutLocation),
        );
      }
    } catch (_) {
      // Launch notices never break startup.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverHosted = ref.watch(serverHostedWebProvider);
    useEffect(() {
      if (!serverHosted) {
        if (isGooglePlayBuild) return null;
        Future.microtask(() async {
          await ref.read(startupWebRevisionProvider.future);
          if (!context.mounted || ref.read(serverHostedWebProvider)) return;
          await checkForUpdate(
            title: ref.read(packageInfoProvider).appName,
            context: context,
            ref: ref,
            updateCallback: ref.read(aboutRepositoryProvider).checkUpdate,
            toast: ref.read(toastProvider),
          );
          if (!context.mounted) return;
          await checkServerUpdateAlerts(context: context, ref: ref);
        });
        return null;
      }

      // Widget subscriptions pause when About or Settings covers this shell.
      final container = ProviderScope.containerOf(context, listen: false);
      final messenger = ScaffoldMessenger.of(context);
      ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>?
      banner;
      bool active = true;
      final reloadSubscription = container.listen(
        webBuildReloadRequiredProvider,
        (previous, required) {
          if (!required || banner != null) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (active && context.mounted && banner == null) {
              banner = messenger.showMaterialBanner(
                webBuildReloadBanner(context),
              );
            }
          });
          WidgetsBinding.instance.ensureVisualUpdate();
        },
        fireImmediately: true,
      );
      void checkInstalledBuild() {
        container.read(webBuildReloadRequiredProvider.notifier).check();
      }

      checkInstalledBuild();
      final removeListeners = listenForWebUpdate(checkInstalledBuild);
      return () {
        active = false;
        removeListeners();
        reloadSubscription.close();
        if (messenger.mounted) banner?.close();
      };
    }, [serverHosted]);

    // Handle different navigation indices for tablet vs phone
    int getAdjustedIndex(int index) {
      if (context.windowSizeClass >= WindowSizeClass.medium) {
        // Tablet: Library(0), Updates(1), History(2), Browse(3), Downloads(4), More(5)
        return index;
      } else {
        // Phone: Library(0), Updates(1), Browse(2), Downloads(3), More(4)
        // Skip history index (2) by adjusting indices
        if (index >= 2) {
          return index +
              1; // Browse becomes 3, Downloads becomes 4, More becomes 5
        }
        return index;
      }
    }

    int getReverseAdjustedIndex(int index) {
      if (context.windowSizeClass >= WindowSizeClass.medium) {
        return index;
      } else {
        // Convert back: if index > 2, subtract 1 to skip history
        if (index > 2) {
          return index - 1;
        }
        return index;
      }
    }

    // Branch 0 (Library) is home. Android Back from any other tab returns here
    // instead of exiting; only Library-at-root exits (#102). goBranch itself
    // builds no back-stack.
    const homeBranch = 0;
    void switchTo(int navBarIndex) {
      final target = getAdjustedIndex(navBarIndex);
      child.goBranch(target, initialLocation: target == child.currentIndex);
    }

    // While the update banner occupies the top (incl. the status-bar strip),
    // drop the redundant status-bar inset on the content below so the pushed-
    // down screen's own app bar doesn't reserve it a second time (dead gap).
    // A Builder is required to get the context inside the Scaffold's body.
    // There, resizeToAvoidBottomInset has already consumed the keyboard inset.
    // Using the outer context passes unconsumed insets down, making nested
    // Scaffolds apply the keyboard padding twice and overflow the layout.
    final updateBannerVisible = ref.watch(updateBannerVisibleProvider);
    final bannerVisible =
        updateBannerVisible ||
        ref.watch(accountStorageRecoveryProvider) != null;
    final content = bannerVisible
        ? Builder(
            builder: (context) => MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          )
        : child;

    final Widget scaffold;
    if (context.windowSizeClass >= WindowSizeClass.medium) {
      scaffold = Scaffold(
        // No bottom bar here, so the rail + content would draw under the system
        // navigation controls (and any landscape cutout). SafeArea keeps both
        // out of that unusable strip so the controls never overlap a cover.
        body: SafeArea(
          child: Column(
            children: [
              if (showsMergedTopBar(context)) const DesktopTopBar(),
              // Keyed so a breakpoint toggle moves the body instead of
              // remounting it: the page keeps its scroll, focus and drafts.
              Expanded(
                key: const ValueKey('shellBody'),
                child: Row(
                  children: [
                    BigScreenNavigationBar(
                      selectedIndex: child.currentIndex,
                      onDestinationSelected: switchTo,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          const UpdateProgressBanner(),
                          AccountStorageRecoveryBanner(
                            insetTop: !updateBannerVisible,
                          ),
                          Expanded(child: content),
                          const IncognitoBanner(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      scaffold = Scaffold(
        body: Column(
          children: [
            const UpdateProgressBanner(),
            AccountStorageRecoveryBanner(insetTop: !updateBannerVisible),
            Expanded(child: content),
            const IncognitoBanner(),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        bottomNavigationBar: SmallScreenNavigationBar(
          selectedIndex: getReverseAdjustedIndex(child.currentIndex),
          onDestinationSelected: switchTo,
        ),
      );
    }

    // Intercept the hardware Back BEFORE go_router's own handler: go_router
    // 14.x doesn't route Back to a shell PopScope when a branch is at its root,
    // so it exits the app instead of returning to the home tab (flutter
    // #145290/#188018). BackButtonListener fires on the legacy back path (which
    // the manifest forces on via enableOnBackInvokedCallback=false).
    return BackButtonListener(
      onBackButtonPressed: () async {
        // Within a branch (a pushed route) or on home → let the default handler
        // pop the route or exit. On any other tab at its root, go home instead.
        if (child.currentIndex != homeBranch &&
            !GoRouter.of(context).canPop()) {
          child.goBranch(homeBranch);
          return true; // handled — do not exit
        }
        return false;
      },
      child: scaffold,
    );
  }
}
