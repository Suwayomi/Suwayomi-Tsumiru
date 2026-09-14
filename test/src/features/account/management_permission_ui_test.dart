import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_store_repository/extension_store_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/extension_store/extension_store_model.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/presentation/browse/browse_settings_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/browse/widgets/show_nsfw_switch/show_nsfw_switch.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../settings/data/user_settings_routing_test.dart' show FixedSettings;

void main() {
  for (final capability in [
    AccountCapability.unknown,
    AccountCapability.supported,
  ]) {
    testWidgets(
      '$capability cannot edit global browse settings but can change local NSFW',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            settledAccountAccessProvider.overrideWithValue(
              AccountAccess(capability: capability),
            ),
            settingsProvider.overrideWith(FixedSettings.new),
            extensionStoreListProvider.overrideWith(
              (ref) async => (stores: <ExtensionStore>[], totalCount: 0),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const BrowseSettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final localSwitch = tester.widget<SwitchListTile>(
          find.byType(SwitchListTile),
        );
        expect(localSwitch.onChanged, isNotNull);
        localSwitch.onChanged!(true);
        await tester.pumpAndSettle();
        expect(container.read(showNSFWProvider), true);
        final tiles = tester
            .widgetList<ListTile>(find.byType(ListTile))
            .where(
              (tile) =>
                  tile.leading is Icon &&
                  [
                    (Icons.swap_vert_rounded),
                    Icons.folder_rounded,
                  ].contains((tile.leading! as Icon).icon),
            );
        expect(tiles, hasLength(2));
        expect(tiles.every((tile) => tile.onTap == null), true);
      },
    );
  }
}
