// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/language_list.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import '../library/widgets/persistent_search_bar/persistent_search_bar.dart';
import 'quick_search_toggle/quick_search_toggle_tile.dart';
import 'widgets/force_portrait_tile.dart';

class GeneralScreen extends ConsumerWidget {
  const GeneralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Native desktop draws the toolbar in the shell bar instead of an app
    // bar.
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.general);
    final scaffold = Scaffold(
      appBar: topBar ? null : AppBar(title: title),
      body: SettingsHighlightScope(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              children: [
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'appLanguage',
                      child: ListTile(
                        title: Text(context.l10n.appLanguage),
                        subtitle: Text(
                          getLanguageNameFormLocale(context.currentLocale),
                        ),
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
                      ),
                    ),
                    const SettingsHighlightTarget(
                      id: 'lockToPortrait',
                      child: ForcePortraitTile(),
                    ),
                    // Moved here from Library: it changes the header of every
                    // page, so it is an app setting, not a library one. Same
                    // provider and tile, just a new home.
                    const SettingsHighlightTarget(
                      id: 'persistentSearchBar',
                      child: PersistentSearchBarTile(),
                    ),
                    // A keyboard shortcut is the only way to open quick
                    // search, so on a touch device this switch turned on
                    // something unreachable. Same gate the Keyboard shortcuts
                    // entry already uses.
                    if (isKeyboardRuntime)
                      const SettingsHighlightTarget(
                        id: 'quickSearch',
                        child: QuickSearchToggleTile(),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}
