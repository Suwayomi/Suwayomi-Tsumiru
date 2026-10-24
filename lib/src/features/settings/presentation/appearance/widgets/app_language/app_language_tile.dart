// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/language_list.dart';
import '../../../../../../global_providers/global_providers.dart';
import '../../../../../../l10n/generated/app_localizations.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/popup_widgets/radio_list_popup.dart';

/// App language row, moved here from General: both Komikku and WebUI list
/// the language under Appearance.
class AppLanguageTile extends ConsumerWidget {
  const AppLanguageTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(context.l10n.appLanguage),
      subtitle: Text(getLanguageNameFormLocale(context.currentLocale)),
      onTap: () => showDialog(
        context: context,
        builder: (context) => RadioListPopup<Locale>(
          title: context.l10n.appLanguage,
          optionList: AppLocalizations.supportedLocales,
          value: context.currentLocale,
          onChange: (locale) {
            ref.read(l10nProvider.notifier).update(locale);
            Navigator.pop(context);
          },
          getOptionTitle: getLanguageNameFormLocale,
          getOptionSubtitle: getLanguageNameInEnFormLocale,
        ),
        animationStyle: context.motionStyle,
      ),
    );
  }
}
