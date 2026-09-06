// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';

String _shown(String serverMessage) => OperationMessageException(
      OperationException(
        graphqlErrors: [GraphQLError(message: serverMessage)],
      ),
    ).toString();

void main() {
  group('what a Suwayomi error says on screen', () {
    test('a Kotlin stack trace collapses to the sentence that matters', () {
      expect(
        _shown(
          "Exception while fetching data (/updateExtension) : Extension can't "
          "be updated to the same version. Reinstall the extension instead\n"
          "\n"
          "java.lang.IllegalStateException: Extension can't be updated to the "
          "same version. Reinstall the extension instead\n"
          "\tat suwayomi.tachidesk.manga.impl.extension.Extension."
          "installExtension(Extension.kt:451)\n"
          "\tat kotlin.coroutines.jvm.internal.BaseContinuationImpl."
          "resumeWith(ContinuationImpl.kt:34)",
        ),
        "Extension can't be updated to the same version. "
        "Reinstall the extension instead",
      );
    });

    test('a null message leaves nothing to show, so the UI can fall back', () {
      expect(
        _shown(
          "Exception while fetching data (/updateExtension) : null\n"
          "\n"
          "java.lang.NullPointerException\n"
          "\tat suwayomi.tachidesk.manga.impl.extension.Extension."
          "installExtension(Extension.kt:451)",
        ),
        isEmpty,
      );
    });

    test('a plain server error is shown exactly as sent', () {
      expect(_shown('Unauthorized'), 'Unauthorized');
    });

    test('two errors still read as one list', () {
      final e = OperationMessageException(OperationException(graphqlErrors: [
        const GraphQLError(message: 'Unauthorized'),
        const GraphQLError(
            message: 'Exception while fetching data (/x) : Not found\n'
                '\tat suwayomi.Thing.run(Thing.kt:1)'),
      ]));
      expect(e.toString(), 'Unauthorized, Not found');
    });

    test('a transport failure still reports its own cause', () {
      final e = OperationMessageException(OperationException(
          linkException: HttpLinkParserException(
              originalException: const SocketException('server unreachable'),
              originalStackTrace: StackTrace.empty,
              response: http.Response('', 500))));
      expect(e.toString(), contains('server unreachable'));
    });
  });
}
