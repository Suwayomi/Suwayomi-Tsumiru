import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
import 'package:tsumiru/src/utils/misc/graphql_undefined_field.dart';

GraphQLError _error(String message, {Map<String, dynamic>? extensions}) =>
    GraphQLError(message: message, extensions: extensions);

void main() {
  test('every undefined field message form matches the right type and field', () {
    for (final message in [
      "Validation error (FieldUndefined@[user]) : Field 'user' in type 'Query' is undefined",
      'Cannot query field "user" on type "Query".',
      "Cannot query field 'user' on type 'Query'.",
    ]) {
      expect(
        isUndefinedFieldError(_error(message), type: 'Query', field: 'user'),
        isTrue,
        reason: message,
      );
    }
  });
  test('a nested validation path still names its field and type', () {
    expect(
      isUndefinedFieldError(
        _error(
          "Validation error (FieldUndefined@[settings/syncYomiEnabled]) : Field 'syncYomiEnabled' in type 'SettingsType' is undefined",
        ),
        type: 'SettingsType',
        field: 'syncYomiEnabled',
      ),
      isTrue,
    );
  });
  test('a different type does not match', () {
    expect(
      isUndefinedFieldError(
        _error('Cannot query field "user" on type "UserType".'),
        type: 'Query',
        field: 'user',
      ),
      isFalse,
    );
  });
  test('a different field does not match when a field is given', () {
    expect(
      isUndefinedFieldError(
        _error('Cannot query field "username" on type "Query".'),
        type: 'Query',
        field: 'user',
      ),
      isFalse,
    );
  });
  test('any field matches when no field is given', () {
    expect(
      isUndefinedFieldError(
        _error("Cannot query field 'syncYomiEnabled' on type 'SettingsType'."),
        type: 'SettingsType',
      ),
      isTrue,
    );
  });
  test('a contradicting classification does not match', () {
    expect(
      isUndefinedFieldError(
        _error(
          "Validation error (FieldUndefined@[user]) : Field 'user' in type 'Query' is undefined",
          extensions: {'classification': 'DataFetchingException'},
        ),
        type: 'Query',
        field: 'user',
      ),
      isFalse,
    );
  });
  test('empty extensions match', () {
    expect(
      isUndefinedFieldError(
        _error(
          "Validation error (FieldUndefined@[user]) : Field 'user' in type 'Query' is undefined",
          extensions: const {},
        ),
        type: 'Query',
        field: 'user',
      ),
      isTrue,
    );
  });
  test('onlyUndefinedFieldErrors is false for an empty error list', () {
    expect(
      onlyUndefinedFieldErrors(
        OperationException(graphqlErrors: const []),
        type: 'Query',
        field: 'user',
      ),
      isFalse,
    );
  });
  test('onlyUndefinedFieldErrors is false for a mix of errors', () {
    expect(
      onlyUndefinedFieldErrors(
        OperationException(
          graphqlErrors: [
            _error('Cannot query field "user" on type "Query".'),
            _error('Internal server error'),
          ],
        ),
        type: 'Query',
        field: 'user',
      ),
      isFalse,
    );
  });
  test('onlyUndefinedFieldErrors unwraps OperationMessageException', () {
    expect(
      onlyUndefinedFieldErrors(
        OperationMessageException(
          OperationException(
            graphqlErrors: [
              _error('Cannot query field "user" on type "Query".'),
            ],
          ),
        ),
        type: 'Query',
        field: 'user',
      ),
      isTrue,
    );
  });
}
