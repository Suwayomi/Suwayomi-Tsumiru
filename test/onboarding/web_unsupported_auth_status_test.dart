// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Web Test connection verdicts surface as the onboarding status row.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/domain/about/about_dto.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';

const _unsupportedMessage =
    "This server uses a sign-in method the browser version can't use. Set the server's authentication mode to UI login, or use the Android, iOS or desktop app.";
const _unconfirmedMessage =
    "This server didn't accept the browser's request. If it uses Basic auth or Simple login, set its authentication mode to UI login, or use the Android, iOS or desktop app. Otherwise check the address.";

class _FailingAbout extends AboutRepository {
  _FailingAbout(this.failure)
    : super(
        client: GraphQLClient(
          link: Link.function(
            (request, [forward]) => Stream.error(StateError('unused')),
          ),
          cache: GraphQLCache(),
        ),
        packageInfo: PackageInfo(
          appName: 'test',
          packageName: 'test',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

  final Object failure;

  @override
  Future<AboutDto?> getAbout() => throw failure;
}

Object _unauthorizedAbout() => OperationMessageException(
  OperationException(graphqlErrors: [GraphQLError(message: 'Unauthorized')]),
);

Future<void> _pumpWebOnboarding(
  WidgetTester tester,
  Object aboutFailure,
) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({'onboarding.step': 1});
  final preferences = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(1080, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        isWebProvider.overrideWithValue(true),
        aboutRepositoryProvider.overrideWithValue(_FailingAbout(aboutFailure)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OnboardingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _testConnection(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Server URL'),
    'http://server:4567',
  );
  await tester.tap(find.text('Test connection'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a rejected about query shows the unsupported-mode row', (
    tester,
  ) async {
    await _pumpWebOnboarding(tester, _unauthorizedAbout());
    await _testConnection(tester);

    expect(find.text(_unsupportedMessage), findsOneWidget);
    expect(find.text(_unconfirmedMessage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
