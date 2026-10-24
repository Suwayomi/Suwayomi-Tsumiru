// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../constants/app_theme.dart';
import '../constants/gen/assets.gen.dart';
import '../features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import '../utils/theme/app_theme_builder.dart';

/// Indigo Night uses original artwork; other themes tint shadows with their dark accent pair.
class TsumiruLogo extends ConsumerWidget {
  const TsumiruLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final theme = ref.watch(appThemeKeyProvider) ?? AppTheme.indigoNight;
    final isDark = scheme.brightness == Brightness.dark;

    if (theme == AppTheme.indigoNight) {
      return Image.asset(
        isDark ? Assets.icons.darkIcon.path : Assets.icons.logoOnLight.path,
        width: size,
        height: size,
      );
    }

    final (background, foreground) = isDark
        ? (Assets.icons.logoShadow.path, Assets.icons.logoForeground.path)
        : (
            Assets.icons.logoOnLightShadow.path,
            Assets.icons.logoOnLightForeground.path,
          );
    final gradientScheme = isDark
        ? scheme
        : schemeFor(
            theme,
            Brightness.dark,
            Color(ref.watch(customThemeColorProvider) ?? 0xFF7C7BFF),
          );

    return Stack(
      alignment: Alignment.center,
      children: [
        ShaderMask(
          blendMode: BlendMode.modulate,
          shaderCallback: logoShadowGradient(gradientScheme).createShader,
          child: Image.asset(background, width: size, height: size),
        ),
        Image.asset(foreground, width: size, height: size),
      ],
    );
  }
}

LinearGradient logoShadowGradient(ColorScheme scheme) {
  final (
    top,
    bottom,
  ) = scheme.primary.computeLuminance() > scheme.secondary.computeLuminance()
      ? (scheme.primary, scheme.secondary)
      : (scheme.secondary, scheme.primary);
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [top, bottom],
  );
}
