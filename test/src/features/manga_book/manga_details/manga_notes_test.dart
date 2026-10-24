import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/manga_notes_screen.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/manga_notes_save.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/webui_meta/webui_meta_codec.dart';

void main() {
  testWidgets('failed notes save retains the draft and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    final server = <String, String>{};
    final working = _fakeMetaClient(server);
    final client = GraphQLClient(
      link: Link.function((request, [forward]) {
        if (++attempts == 1) throw Exception('down');
        return working.link.request(request);
      }),
      cache: GraphQLCache(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [graphQlClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MangaNotesScreen(
                    mangaId: 7,
                    seriesTitle: 'Series',
                    initialNotes: '',
                    existingMetas: {},
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'draft');
    await tester.tap(find.byIcon(FluentIcons.arrow_left_24_regular));
    await tester.pumpAndSettle();
    expect(find.byType(MangaNotesScreen), findsOneWidget);
    expect(find.text('draft'), findsOneWidget);
    await tester.tap(find.byIcon(FluentIcons.arrow_left_24_regular));
    await tester.pumpAndSettle();
    expect(find.byType(MangaNotesScreen), findsNothing);
    expect(server['webUI_notes'], 'draft');
  });

  test(
    'long notes save as chunks through a fake client and read back intact',
    () async {
      final server = <String, String>{
        'webUI_notes': 'another client wrote this',
      };
      final client = _fakeMetaClient(server);

      var saved = false;
      final note = "${'ab' * 2050}   \n  ";
      final ok = await persistMangaNotes(
        client: client,
        mangaId: 7,
        rawText: note,
        existingMetas: const {},
        onSaved: () => saved = true,
      );

      expect(ok, isTrue);
      expect(saved, isTrue);
      expect(server.containsKey('webUI_notes'), isFalse);
      expect(server['webUI_notes_length'], '2');
      expect(readWebUiValue(server, 'notes'), 'ab' * 2050);

      saved = false;
      final cleared = await persistMangaNotes(
        client: client,
        mangaId: 7,
        rawText: '   \n ',
        existingMetas: server,
        onSaved: () => saved = true,
      );
      expect(cleared, isTrue);
      expect(saved, isTrue);
      expect(readWebUiValue(server, 'notes'), isNull);
    },
  );
}

GraphQLClient _fakeMetaClient(Map<String, String> server) => GraphQLClient(
  link: Link.function((request, [forward]) {
    if (request.variables.containsKey('id')) {
      return Stream.value(
        Response(
          data: {
            '__typename': 'Query',
            'manga': {
              '__typename': 'MangaType',
              'meta': [
                for (final entry in server.entries)
                  {
                    '__typename': 'MangaMetaType',
                    'key': entry.key,
                    'value': entry.value,
                  },
              ],
            },
          },
          response: const {},
        ),
      );
    }
    final input =
        (request.variables['input'] as Map<String, dynamic>)['items'] as List;
    final item = (input.first as Map<String, dynamic>);
    if (item.containsKey('metas')) {
      for (final meta in (item['metas'] as List).cast<Map<String, dynamic>>()) {
        server[meta['key'] as String] = meta['value'] as String;
      }
      return Stream.value(
        Response(
          data: const {
            'setMangaMetas': {'__typename': 'SetMangaMetasPayload'},
            '__typename': 'Mutation',
          },
          response: const {},
        ),
      );
    }
    for (final key in (item['keys'] as List).cast<String>()) {
      server.remove(key);
    }
    return Stream.value(
      Response(
        data: const {
          'deleteMangaMetas': {'__typename': 'DeleteMangaMetasPayload'},
          '__typename': 'Mutation',
        },
        response: const {},
      ),
    );
  }),
  cache: GraphQLCache(),
);
