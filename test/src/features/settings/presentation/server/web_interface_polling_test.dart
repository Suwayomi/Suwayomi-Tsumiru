import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/graphql/__generated__/web_interface.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/web_interface_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/web_interface/web_interface_section.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

final _access = AccountAccess(capability: AccountCapability.unsupported);
final _downloading = Fragment$WebInterfaceUpdateStatusDto(
  state: Enum$UpdateState.DOWNLOADING,
  progress: 20,
  info: Fragment$WebInterfaceUpdateStatusDto$info(
    tag: 'new',
    channel: Enum$WebUIChannel.STABLE,
  ),
);

class _Repository extends WebInterfaceRepository {
  _Repository(super.client)
    : super(permissions: AccountPermissionGuard(() => _access));
  int polls = 0;
  @override
  Future<Query$CheckWebInterfaceUpdate$checkForWebUIUpdate?> check() async =>
      Query$CheckWebInterfaceUpdate$checkForWebUIUpdate(
        tag: 'new',
        channel: Enum$WebUIChannel.STABLE,
        updateAvailable: true,
      );
  @override
  Future<Fragment$WebInterfaceUpdateStatusDto?> install() async => _downloading;
  @override
  Future<Fragment$WebInterfaceUpdateStatusDto?> status() async {
    polls++;
    return _downloading;
  }
}

void main() {
  testWidgets(
    'socket failure resumes polling after a socket event cancelled it',
    (tester) async {
      final socket = StreamController<Response>();
      final client = GraphQLClient(
        link: Link.function((_, [forward]) => socket.stream),
        cache: GraphQLCache(),
      );
      final repository = _Repository(client);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settledAccountAccessProvider.overrideWithValue(_access),
            graphQlSubscriptionClientProvider.overrideWithValue(client),
            webInterfaceRepositoryProvider.overrideWithValue(repository),
            webInterfaceSettingsProvider.overrideWith((ref) async => null),
            installedWebInterfaceProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(child: WebInterfaceSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for update'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Install'));
      await tester.pump();
      socket.add(
        Response(
          data: {'webUIUpdateStatusChange': _downloading.toJson()},
          response: const {},
        ),
      );
      await tester.pump();
      socket.addError(Exception('disconnected'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(repository.polls, 1);
      await tester.pumpWidget(const SizedBox());
      unawaited(socket.close());
      await tester.pump();
    },
  );
}
