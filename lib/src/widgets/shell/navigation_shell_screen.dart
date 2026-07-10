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

import '../../features/about/data/about_repository.dart';
import '../../features/about/presentation/about/controllers/about_controller.dart';
import '../../features/about/presentation/about/widget/app_update_dialog.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../../utils/misc/toast/toast.dart';
import 'big_screen_navigation_bar.dart';
import 'incognito_banner.dart';
import 'small_screen_navigation_bar.dart';

class NavigationShellScreen extends HookConsumerWidget {
  const NavigationShellScreen({
    super.key,
    required this.child,
  });
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      Future.microtask(
        () async {
          if (!context.mounted) return;
          await checkForUpdate(
            title: ref.read(packageInfoProvider).appName,
            context: context,
            ref: ref,
            updateCallback: ref.read(aboutRepositoryProvider).checkUpdate,
            toast: ref.read(toastProvider),
          );
        },
      );
      return;
    }, []);

    // Handle different navigation indices for tablet vs phone
    int getAdjustedIndex(int index) {
      if (context.isTablet) {
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
      if (context.isTablet) {
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

    final Widget scaffold;
    if (context.isTablet) {
      scaffold = Scaffold(
        // No bottom bar here, so the rail + content would draw under the system
        // navigation controls (and any landscape cutout). SafeArea keeps both
        // out of that unusable strip so the controls never overlap a cover.
        body: SafeArea(
          child: Row(
            children: [
              BigScreenNavigationBar(
                selectedIndex: child.currentIndex,
                onDestinationSelected: switchTo,
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: child),
                    const IncognitoBanner(),
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
            Expanded(child: child),
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
        if (child.currentIndex != homeBranch && !GoRouter.of(context).canPop()) {
          child.goBranch(homeBranch);
          return true; // handled — do not exit
        }
        return false;
      },
      child: scaffold,
    );
  }
}
