// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'constants/app_theme.dart';
import 'features/auth/presentation/reauth_banner.dart';
import 'features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import 'features/settings/presentation/appearance/widgets/is_true_black/is_true_black_tile.dart';
import 'features/settings/presentation/general/widgets/force_portrait_tile.dart';
import 'features/settings/widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'global_providers/global_providers.dart';
import 'l10n/generated/app_localizations.dart';
import 'routes/router_config.dart';
import 'utils/extensions/custom_extensions.dart';
import 'utils/theme/app_theme_builder.dart';

class Sorayomi extends ConsumerWidget {
  const Sorayomi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routerConfigProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final appLocale = ref.watch(l10nProvider);
    final appTheme = ref.watch(appThemeKeyProvider) ?? AppTheme.indigoNight;
    final customSeed = ref.watch(customThemeColorProvider);
    final isTrueBlack = ref.watch(isTrueBlackProvider).ifNull();
    final client = ref.watch(graphQlClientHolderProvider);
    // Honour the portrait-lock preference on launch and whenever it changes
    // (phones only; idempotent so re-applying on rebuild is harmless).
    applyForcePortrait(ref.watch(forcePortraitProvider).ifNull());
    return GraphQLProvider(
      client: client,
      child: MaterialApp.router(
        builder: (context, child) {
          final toastWrapped = FToastBuilder()(context, child);
          return ReauthBannerHost(child: toastWrapped);
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

/// App-wide scroll behavior that lets the **mouse and trackpad** drag-scroll
/// (Flutter's desktop default only scrolls via wheel/touch). Fixes click-drag
/// on every scrollable — the theme picker, the webtoon reader, lists, etc.
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
