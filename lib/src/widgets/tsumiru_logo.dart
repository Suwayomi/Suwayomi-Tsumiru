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

/// The full-colour Tsumiru mark. Dark themes keep the cream foreground and tint
/// the brush shadow with the theme's accent pair; Indigo Night and light themes
/// use their artwork untouched.
class TsumiruLogo extends ConsumerWidget {
  const TsumiruLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (scheme.brightness == Brightness.light) {
      return Image.asset(
        Assets.icons.logoOnLight.path,
        width: size,
        height: size,
      );
    }
    final theme = ref.watch(appThemeKeyProvider) ?? AppTheme.indigoNight;
    if (theme == AppTheme.indigoNight) {
      return Image.asset(Assets.icons.darkIcon.path, width: size, height: size);
    }
    final (
      top,
      bottom,
    ) = scheme.primary.computeLuminance() > scheme.secondary.computeLuminance()
        ? (scheme.primary, scheme.secondary)
        : (scheme.secondary, scheme.primary);
    return Stack(
      alignment: Alignment.center,
      children: [
        ShaderMask(
          blendMode: BlendMode.modulate,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ).createShader(bounds),
          child: Image.asset(
            Assets.icons.logoShadow.path,
            width: size,
            height: size,
          ),
        ),
        Image.asset(
          Assets.icons.logoForeground.path,
          width: size,
          height: size,
        ),
      ],
    );
  }
}
