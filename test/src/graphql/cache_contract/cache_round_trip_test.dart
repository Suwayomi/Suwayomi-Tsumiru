// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';

import 'graphql_documents.dart';

void main() {
  final documents = loadGraphQLDocuments();

  for (final entry in documents.operations) {
    test('${entry.name} (${entry.file})', () async {
      final definitions = variableDefinitionsOf(entry.operation);
      final dirVars = directiveVariables(
        entry.operation,
        documents.fragments,
      ).toList()..sort();
      final document = executableDocument(entry, documents.fragments);

      final combos = <Map<String, dynamic>>[];
      final total = 1 << dirVars.length;
      for (var mask = 0; mask < total; mask++) {
        combos.add({
          for (var i = 0; i < dirVars.length; i++)
            dirVars[i]: (mask >> i) & 1 == 1,
        });
      }
      final omittedVars = <String>{};
      for (final variable in dirVars) {
        final definition = definitions[variable];
        if (definition != null && hasDefaultValue(definition)) {
          combos.add({
            for (final other in dirVars)
              if (other != variable) other: true,
          });
          omittedVars.add(variable);
        }
      }

      for (final combo in combos) {
        final omitted = dirVars
            .where(
              (variable) =>
                  omittedVars.contains(variable) &&
                  !combo.containsKey(variable),
            )
            .toSet();
        final clientVariables = placeholderVariables(
          entry.operation,
          documents.schema,
          overrides: combo,
        );
        for (final variable in omitted) {
          clientVariables.remove(variable);
        }
        final effectiveVariables = Map<String, dynamic>.from(clientVariables);
        for (final variable in omitted) {
          effectiveVariables[variable] = defaultValueOf(definitions[variable]!);
        }
        for (final entryCombo in combo.entries) {
          effectiveVariables[entryCombo.key] = entryCombo.value;
        }

        final payload = buildResponsePayload(
          entry: entry,
          documents: documents,
          effectiveVariables: effectiveVariables,
        );

        final client = GraphQLClient(
          link: Link.function(
            (request, [forward]) =>
                Stream.value(Response(data: payload, response: const {})),
          ),
          cache: GraphQLCache(store: InMemoryStore()),
          defaultPolicies: DefaultPolicies(
            query: Policies(fetch: FetchPolicy.noCache),
          ),
        );

        final QueryResult<Object?> result;
        switch (entry.operation.type) {
          case OperationType.query:
            result = await client.query(
              QueryOptions(document: document, variables: clientVariables),
            );
          case OperationType.mutation:
            result = await client.mutate(
              MutationOptions(document: document, variables: clientVariables),
            );
          case OperationType.subscription:
            result = await client
                .subscribe(
                  SubscriptionOptions(
                    document: document,
                    variables: clientVariables,
                  ),
                )
                .first;
        }

        expect(
          result.hasException,
          isFalse,
          reason:
              '${entry.name} (${entry.file}) combo=$combo '
              'omitted=$omitted exception=${result.exception}',
        );
        expect(
          result.data,
          isNotNull,
          reason:
              '${entry.name} (${entry.file}) combo=$combo '
              'omitted=$omitted returned no data',
        );
      }
    });
  }
}
