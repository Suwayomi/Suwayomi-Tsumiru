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

  test('inline Boolean with a default is reported', () {
    const source = '''
query InlineCase(\$x: Boolean = false) {
  thing {
    name @include(if: \$x)
  }
}
''';
    final entry = operationFromSource(source);
    final violations = directiveVariableViolations(
      entry,
      fragmentsFromSource(source),
    );
    expect(violations, hasLength(1));
    expect(violations.single, contains('InlineCase'));
    expect(violations.single, contains(r'$x'));
  });

  test('inline Boolean defaulting to true for @include is accepted', () {
    const source = '''
query InlineCase(\$x: Boolean = true) {
  thing {
    name @include(if: \$x)
  }
}
''';
    final entry = operationFromSource(source);
    final violations = directiveVariableViolations(
      entry,
      fragmentsFromSource(source),
    );
    expect(violations, isEmpty);
  });

  test('inline nullable Boolean with no default is reported', () {
    const source = '''
query InlineCase(\$x: Boolean) {
  thing {
    name @include(if: \$x)
  }
}
''';
    final entry = operationFromSource(source);
    final violations = directiveVariableViolations(
      entry,
      fragmentsFromSource(source),
    );
    expect(violations, hasLength(1));
    expect(violations.single, contains('InlineCase'));
    expect(violations.single, contains(r'$x'));
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
