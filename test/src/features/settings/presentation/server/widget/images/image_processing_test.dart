// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/data/images_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/image_conversions.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/images_section.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

List<ServerConversion> _serverMap() => [
  ServerConversion(mimeType: 'default', target: 'image/png'),
  ServerConversion(
    mimeType: 'image/jpeg',
    target: 'image/webp',
    compressionLevel: 0.8,
  ),
  ServerConversion(
    mimeType: 'image/png',
    target: 'https://converter.example/process?quality=80&format=webp',
    callTimeout: 'PT30S',
    connectTimeout: 'PT10S',
    headers: [ServerConversionHeader(name: 'X-Token', value: 'abc')],
  ),
];

void main() {
  group('image processing conversions', () {
    test(
      'server map round-trips through the editor mapping (WebUI shape)',
      () {
        final editor = editorConversionsFromServer(_serverMap());
        expect(editor, hasLength(3));

        // Without a default rule the editor prepends a blank one, exactly
        // like WebUI's maybeAddDefault.
        final prepended = editorConversionsFromServer(
          _serverMap().sublist(1),
        );
        expect(prepended.first.mimeType, 'default');
        expect(prepended.first.target, isEmpty);

        final rules = editor;
        expect(
          rules.map((r) => r.mode),
          [
            ImageConversionTargetMode.image,
            ImageConversionTargetMode.image,
            ImageConversionTargetMode.url,
          ],
        );
        expect(
          rules.map((r) => r.mimeType),
          ['default', 'jpeg', 'png'],
        );
        final url = rules.last;
        expect(url.compressionLevel, isNull);
        expect(
          url.searchParams.map((p) => (p.name, p.value)),
          [('quality', '80'), ('format', 'webp')],
        );

        final inputs = toServerConversionInputs(editor);
        expect(inputs, hasLength(3));
        final back = inputs
            .map(
              (i) => (
                mimeType: i.mimeType,
                target: i.target,
                compressionLevel: i.compressionLevel,
                callTimeout: i.callTimeout,
                connectTimeout: i.connectTimeout,
                headers: i.headers
                    ?.map((h) => (h.name, h.value))
                    .toList(),
              ),
            )
            .toList();
        expect(back[0].mimeType, 'default');
        expect(back[0].target, 'image/png');
        expect(back[1].mimeType, 'image/jpeg');
        expect(back[1].target, 'image/webp');
        expect(back[1].compressionLevel, 0.8);
        expect(back[2].mimeType, 'image/png');
        expect(
          back[2].target,
          'https://converter.example/process?quality=80&format=webp',
        );
        expect(back[2].callTimeout, 'PT30S');
        expect(back[2].connectTimeout, 'PT10S');
        expect(back[2].headers, [('X-Token', 'abc')]);
      },
    );

    test('invalid MIME target or duplicate key blocks Save', () {
      ImageConversion rule({
        required String mime,
        required String target,
        required ImageConversionTargetMode mode,
      }) => ImageConversion(id: 0, mimeType: mime, target: target, mode: mode);

      // A URL-mode rule with a non-URL target, like WebUI's
      // `isInvalidTarget`.
      expect(
        imageConversionsAreInvalid([
          rule(mime: 'png', target: 'webp', mode: ImageConversionTargetMode.url),
        ]),
        isTrue,
      );
      // A duplicate MIME type, like WebUI's `isDuplicateConversion`.
      expect(
        imageConversionsAreInvalid([
          rule(
            mime: 'jpeg',
            target: 'webp',
            mode: ImageConversionTargetMode.image,
          ),
          rule(
            mime: 'jpeg',
            target: 'avif',
            mode: ImageConversionTargetMode.image,
          ),
        ]),
        isTrue,
      );
      // A clean map leaves Save enabled.
      expect(
        imageConversionsAreInvalid(
          editorConversionsFromServer(_serverMap()).sublist(1),
        ),
        isFalse,
      );
    });

    testWidgets('images section hides when the fields are undefined', (
      tester,
    ) async {
      final client = GraphQLClient(
        link: HttpLink('http://localhost/'),
        cache: GraphQLCache(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            graphQlClientProvider.overrideWithValue(client),
            settledAccountAccessProvider.overrideWithValue(
              AccountAccess(capability: AccountCapability.unsupported),
            ),
            imagesDownloadSettingsProvider.overrideWith(
              (ref) async => null,
            ),
            serveConversionsProvider.overrideWith((ref) async => null),
            clearCachedImagesSupportProvider.overrideWith(
              (ref) async => false,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SingleChildScrollView(child: ImagesSection())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Images'), findsNothing);
      expect(find.text('Clear cache'), findsNothing);
      expect(find.text('Image download processing'), findsNothing);
      expect(find.text('Image serve processing'), findsNothing);
    });
  });
}
