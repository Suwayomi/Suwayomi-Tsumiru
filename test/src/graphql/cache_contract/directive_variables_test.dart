// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';

import 'graphql_documents.dart';

void main() {
  late GraphQLDocuments documents;

  setUpAll(() {
    documents = loadGraphQLDocuments();
  });

  test('inline Boolean defaults follow the directive rule', () {
    List<String> violationsOf(String variable) {
      final source =
          '''
query InlineCase(\$x: $variable) {
  thing {
    name @include(if: \$x)
  }
}
''';
      final entry = operationFromSource(source);
      return directiveVariableViolations(entry, fragmentsFromSource(source));
    }

    // A server default of false contradicts include's default of true.
    expect(violationsOf('Boolean = false'), hasLength(1));
    // No default is nullable, which @include does not accept.
    expect(violationsOf('Boolean'), hasLength(1));
    // Matching the directive's default is the accepted form.
    expect(violationsOf('Boolean = true'), isEmpty);
  });

  test('all operations satisfy the directive variable rule', () {
    final violations = <String>[];
    for (final entry in documents.operations) {
      violations.addAll(
        directiveVariableViolations(entry, documents.fragments),
      );
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
