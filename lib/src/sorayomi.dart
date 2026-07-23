// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'constants/app_theme.dart';
import 'features/auth/presentation/reauth_banner.dart';
import 'features/notifications/data/background/notification_worker.dart';
import 'features/notifications/data/local_notification_service.dart';
import 'features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import 'features/settings/presentation/appearance/widgets/is_true_black/is_true_black_tile.dart';
import 'features/settings/presentation/general/widgets/force_portrait_tile.dart';
import 'features/settings/presentation/incognito/incognito_mode.dart';
import 'features/settings/widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'global_providers/global_providers.dart';
import 'l10n/generated/app_localizations.dart';
import 'routes/router_config.dart';
import 'utils/extensions/custom_extensions.dart';
import 'utils/launch_url_in_web.dart';
import 'utils/misc/toast/toast.dart';
import 'utils/theme/app_theme_builder.dart';
import 'widgets/desktop/desktop_window_scaffold.dart';

class Sorayomi extends HookConsumerWidget {
  const Sorayomi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routerConfigProvider);

    // Also drains a cold-start tap that launched the app. Android-only — the
    // plugin is initialized with Android settings.
    useEffect(() {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        return null;
      }
      void go(NotificationPayload p) {
        if (p.mangaId != null && p.chapterId != null) {
          routes.go(ReaderRoute(mangaId: p.mangaId!, chapterId: p.chapterId!)
              .location);
        } else {
          routes.go(const UpdatesRoute().location);
        }
      }

      void onResponse(NotificationResponse r) {
        final action = r.actionId;
        // Also handled headlessly when the app is dead — no navigation needed.
        if (action == kNotifActionMarkRead || action == kNotifActionDownload) {
          handleNotificationAction(action, r.payload);
          return;
        }
        final raw = r.payload;
        if (raw != null && raw.startsWith('url:')) {
          launchUrlInWeb(context, raw.substring(4), ref.read(toastProvider));
          return;
        }
        final p = NotificationPayload.decode(r.payload);
        if (action == kNotifActionView && p.mangaId != null) {
          routes.go(MangaRoute(mangaId: p.mangaId!).location);
        } else {
          go(p);
        }
      }

      final service = LocalNotificationService();
      service
          .init(onTap: onResponse, onBackgroundTap: notificationActionCallback)
          .then((_) async {
        final launch = await service.launchPayload();
        if (launch != null) go(launch);
      });
      return null;
    }, const []);

    final themeMode = ref.watch(appThemeModeProvider);
    final appLocale = ref.watch(l10nProvider);
    final appTheme = ref.watch(appThemeKeyProvider) ?? AppTheme.indigoNight;
    final customSeed = ref.watch(customThemeColorProvider);
    final isTrueBlack = ref.watch(isTrueBlackProvider).ifNull();
    final client = ref.watch(graphQlClientHolderProvider);
    // Idempotent, so re-applying on every rebuild is harmless.
    applyForcePortrait(ref.watch(forcePortraitProvider).ifNull());
    return GraphQLProvider(
      client: client,
      child: MaterialApp.router(
        builder: (context, child) {
          final toastWrapped = FToastBuilder()(context, child);
          return DesktopWindowScaffold(
            child: ReauthBannerHost(
              child: _IncognitoNotificationBridge(child: toastWrapped),
            ),
          );
        },
        onGenerateTitle: (context) => context.l10n.appTitle,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(
          theme: appTheme,
          brightness: Brightness.light,
          customSeed: Color(customSeed ?? 0xFF7C7BFF),
          amoled: false,
        ),
        darkTheme: buildAppTheme(
          theme: appTheme,
          brightness: Brightness.dark,
          customSeed: Color(customSeed ?? 0xFF7C7BFF),
          amoled: isTrueBlack,
        ),
        themeMode: themeMode ?? ThemeMode.system,
        scrollBehavior: const AppScrollBehavior(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: appLocale,
        routerConfig: routes,
      ),
    );
  }
}

/// Must live below [MaterialApp] — `context.l10n` is null above it, which
/// crashed the root at launch.
class _IncognitoNotificationBridge extends ConsumerWidget {
  const _IncognitoNotificationBridge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final incognitoTitle = context.l10n.notificationIncognitoTitle;
      final incognitoBody = context.l10n.notificationIncognitoBody;
      ref.listen<bool>(incognitoModeProvider, (_, on) async {
        final service = LocalNotificationService();
        await service.init();
        if (on) {
          await service.showIncognito(incognitoTitle, incognitoBody);
        } else {
          await service.cancelIncognito();
        }
      });
    }
    return child;
  }
}

/// Lets mouse/trackpad drag-scroll — Flutter's desktop default only responds
/// to wheel/touch.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}
