import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';

import 'logger.dart';

/// Counts GraphQL operations in debug builds only.
class GraphQLRequestStats {
  static final Map<String, int> _counts = {};
  static int total = 0;

  static void record(String operation) {
    total++;
    _counts[operation] = (_counts[operation] ?? 0) + 1;
  }

  /// Call counts, most frequent first.
  static String report() {
    final sorted = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final lines = [
      for (final e in sorted.take(25))
        '  ${e.value.toString().padLeft(5)}  ${e.key}',
    ];
    return 'GraphQL: $total requests, ${_counts.length} distinct operations\n'
        '${lines.join('\n')}';
  }

  static void reset() {
    _counts.clear();
    total = 0;
  }
}

class LoggerLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    if (kDebugMode) {
      // Generated requests omit operationName; read it from the definition node.
      final name =
          request.operation.operationName ??
          request.operation.document.definitions
              .whereType<OperationDefinitionNode>()
              .firstOrNull
              ?.name
              ?.value ??
          'unnamed';
      GraphQLRequestStats.record(name);
      logger.i('GQL#${GraphQLRequestStats.total} $name');
    }
    Stream<Response> response = forward!(request)
        .map((Response fetchResult) => fetchResult)
        .handleError((error) {
          throw error;
        });

    return response;
  }

  LoggerLink();
}
