// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';

class _Collector extends RecursiveVisitor {
  final spreads = <String>{};
  final variables = <String>{};

  @override
  void visitFragmentSpreadNode(FragmentSpreadNode node) {
    spreads.add(node.name.value);
    super.visitFragmentSpreadNode(node);
  }

  @override
  void visitVariableNode(VariableNode node) {
    variables.add(node.name.value);
    super.visitVariableNode(node);
  }

  // A variable's own declaration isn't a use of it.
  @override
  void visitVariableDefinitionNode(VariableDefinitionNode node) {}
}

/// GraphQL requires an operation to declare every variable used by the
/// fragments it spreads, however deep. The server rejects one that doesn't,
/// at run time and only for that screen, while codegen accepts it. MangaDto's
/// `@include(if: $withFirstUnread)` makes every operation spreading it, even
/// through another fragment, need that declaration.
void main() {
  test('every operation declares the variables its fragments use', () {
    final fragments = <String, FragmentDefinitionNode>{};
    final operations = <(String, OperationDefinitionNode)>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File ||
          !file.path.endsWith('.graphql') ||
          file.path.endsWith('schema.graphql')) {
        continue;
      }
      final document = parseString(file.readAsStringSync());
      for (final definition in document.definitions) {
        if (definition is FragmentDefinitionNode) {
          fragments[definition.name.value] = definition;
        } else if (definition is OperationDefinitionNode) {
          operations.add((file.path, definition));
        }
      }
    }
    expect(operations, isNotEmpty);

    final missing = <String>[];
    for (final (path, operation) in operations) {
      final used = <String>{};
      final seen = <String>{};
      final pending = <Node>[operation];
      while (pending.isNotEmpty) {
        final collector = _Collector();
        pending.removeLast().accept(collector);
        used.addAll(collector.variables);
        for (final name in collector.spreads) {
          final fragment = fragments[name];
          if (fragment != null && seen.add(name)) pending.add(fragment);
        }
      }
      final declared = {
        for (final definition in operation.variableDefinitions)
          definition.variable.name.value,
      };
      for (final variable in used.difference(declared)) {
        missing.add('${operation.name?.value} ($path) uses \$$variable');
      }
    }
    expect(missing, isEmpty);
  });
}
