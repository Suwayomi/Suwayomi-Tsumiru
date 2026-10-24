// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/settings/presentation/incognito/incognito_mode.dart';
import '../../utils/extensions/custom_extensions.dart';

class IncognitoBanner extends ConsumerWidget {
  const IncognitoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(incognitoModeProvider)) return const SizedBox.shrink();
    final scheme = context.theme.colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: () => ref.read(incognitoModeProvider.notifier).set(false),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FluentIcons.incognito_24_filled,
                size: 16,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.incognitoMode,
                style: TextStyle(
                  color: scheme.onSecondaryContainer,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
