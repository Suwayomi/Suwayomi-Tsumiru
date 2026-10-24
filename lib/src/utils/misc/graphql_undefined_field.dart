import 'package:graphql/client.dart';

import '../extensions/custom_extensions.dart';

final _messagePatterns = [
  RegExp(
    r"^Validation error \(FieldUndefined@\[[^\]]*\]\) : Field '([^']+)' in type '([^']+)' is undefined$",
  ),
  RegExp(r'^Cannot query field "([^"]+)" on type "([^"]+)"\.$'),
  RegExp(r"^Cannot query field '([^']+)' on type '([^']+)'\.$"),
];

bool isUndefinedFieldError(
  GraphQLError error, {
  required String type,
  String? field,
}) {
  // Suwayomi validation errors may have empty extensions; only contradictory classifications rule them out.
  final extensions = error.extensions;
  final classification = extensions?['classification'];
  final code = extensions?['code'];
  if (classification != null && classification != 'ValidationError') {
    return false;
  }
  if (code != null && code != 'GRAPHQL_VALIDATION_FAILED') return false;
  return _messagePatterns.any((pattern) {
    final match = pattern.firstMatch(error.message);
    if (match == null) return false;
    return match.group(2) == type && (field == null || match.group(1) == field);
  });
}

bool onlyUndefinedFieldErrors(
  Object? error, {
  required String type,
  String? field,
}) {
  final cause = error is OperationMessageException ? error.exception : error;
  final errors = cause is OperationException
      ? cause.graphqlErrors
      : const <GraphQLError>[];
  return errors.isNotEmpty &&
      errors.every(
        (graphqlError) =>
            isUndefinedFieldError(graphqlError, type: type, field: field),
      );
}
