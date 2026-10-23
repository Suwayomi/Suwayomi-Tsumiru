import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/server_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/cloud_flare/cloud_flare_section.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _UndefinedFieldLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    yield Response(
      response: {},
      errors: [
        GraphQLError(
          message:
              "Validation error (FieldUndefined@[flareSolverrAsResponseFallback]) : Field 'flareSolverrAsResponseFallback' in type 'SettingsType' is undefined",
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'unsupported response fallback resolves null and hides its switch',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: AccountCapability.unsupported),
          ),
          serverSettingsRepositoryProvider.overrideWith(
            (ref) => ServerSettingsRepository(
              GraphQLClient(link: _UndefinedFieldLink(), cache: GraphQLCache()),
              permissions: ref.watch(accountPermissionGuardProvider),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(flareSolverrFallbackProvider.future), isNull);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CloudFlareSection(
                cloudFlareDto: Fragment$CloudFlareBypassDto(
                  flareSolverrEnabled: true,
                  flareSolverrSessionName: 'default',
                  flareSolverrSessionTtl: 15,
                  flareSolverrTimeout: 60,
                  flareSolverrUrl: 'http://localhost:8191',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Response fallback'), findsNothing);
    },
  );
}
