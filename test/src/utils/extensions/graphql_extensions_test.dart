// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';

String _shown(String serverMessage) => OperationMessageException(
  OperationException(graphqlErrors: [GraphQLError(message: serverMessage)]),
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
  });
}
