import 'dart:async';

import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';

final _userFieldsProbe = parseString(
  '{ __type(name: "ChapterType") { fields { name } } }',
);

class LegacyUserFieldsDetection {
  bool? _hasUser;
  Future<bool?>? _probe;

  Future<bool?> _detect(Request request, NextLink forward) async {
    try {
      final response = await forward(
        Request(
          operation: Operation(document: _userFieldsProbe),
          context: request.context,
        ),
      ).first;
      if (response.errors?.isNotEmpty ?? false) return null;
      final fields = response.data?['__type']?['fields'];
      if (fields is! List ||
          fields.any((field) => field is! Map || field['name'] is! String)) {
        return null;
      }
      return _hasUser = fields.any((field) => field['name'] == 'user');
    } catch (_) {
      // A failed probe must not prevent the original operation from running.
      return null;
    }
  }

  Future<bool?> detect(Request request, NextLink forward) async {
    if (_hasUser != null) return _hasUser;
    final probe = _probe ??= _detect(request, forward);
    try {
      return await probe;
    } finally {
      if (identical(_probe, probe)) _probe = null;
    }
  }
}

/// Compatibility with stable servers predating MangaType.user/ChapterType.user.
class LegacyUserFieldsLink extends Link {
  LegacyUserFieldsLink({LegacyUserFieldsDetection? detection, NextLink? probe})
    : _detection = detection ?? LegacyUserFieldsDetection(),
      _probe = probe;

  final LegacyUserFieldsDetection _detection;
  final NextLink? _probe;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final next = forward!;
    if (_detection._hasUser == null &&
        !_LegacyDocument(
          request.operation.document,
          request.variables,
        ).needsRewrite) {
      yield* next(request);
      return;
    }
    final hasUser = await _detection.detect(request, _probe ?? next);
    if (hasUser != false) {
      yield* next(request);
      return;
    }
    final original = request.operation.document;
    final adapter = _LegacyDocument(original, request.variables);
    final rewritten = transform(original, [adapter]);
    final outgoing = Request(
      operation: Operation(
        document: rewritten,
        operationName: request.operation.operationName,
      ),
      variables: request.variables,
      context: request.context,
    );
    await for (final response in next(outgoing)) {
      yield Response(
        data: adapter.reshape(response.data, request.operation.operationName),
        errors: response.errors,
        response: response.response,
        context: response.context,
      );
    }
  }
}

final _backgroundLinks = <String, LegacyUserFieldsLink>{};

Future<Object?> postWithLegacyUserFields({
  required String endpoint,
  required String query,
  required Map<String, Object?> variables,
  required Future<Object?> Function(
    String query,
    Map<String, Object?> variables,
    bool probe,
  )
  post,
}) async {
  final DocumentNode document;
  try {
    document = parseString(query);
  } catch (_) {
    return post(query, variables, false);
  }
  final original = Request(
    operation: Operation(document: document),
    variables: variables,
  );
  Object? result;
  final response = await (_backgroundLinks[endpoint] ??= LegacyUserFieldsLink())
      .request(original, (outgoing) async* {
        final probe = identical(outgoing.operation.document, _userFieldsProbe);
        result = await post(
          identical(outgoing.operation.document, original.operation.document)
              ? query
              : printNode(outgoing.operation.document),
          outgoing.variables,
          probe,
        );
        yield Response(
          data: result is Map<String, Object?>
              ? (result as Map<String, Object?>).cast<String, dynamic>()
              : null,
          response: const {},
        );
      })
      .first;
  return result is Map<String, Object?> ? response.data : result;
}

const _mangaFields = {
  'inLibrary',
  'inLibraryAt',
  'bookmarkCount',
  'downloadCount',
  'unreadCount',
  'firstUnreadChapter',
  'lastReadChapter',
  'latestReadChapter',
};
const _chapterFields = {
  'isBookmarked',
  'isDownloaded',
  'isRead',
  'lastPageRead',
  'lastReadAt',
};

String _key(FieldNode field) => field.alias?.value ?? field.name.value;

class _LegacyDocument extends TransformingVisitor {
  _LegacyDocument(this.document, this.variables)
    : fragments = {
        for (final fragment
            in document.definitions.whereType<FragmentDefinitionNode>())
          fragment.name.value: fragment,
      };

  final DocumentNode document;
  final Map<String, dynamic> variables;
  final Map<String, FragmentDefinitionNode> fragments;

  bool _hoisted(FieldNode field) =>
      field.name.value == 'user' &&
      field.selectionSet != null &&
      field.selectionSet!.selections.isNotEmpty &&
      field.selectionSet!.selections.every(
        (child) =>
            child is FieldNode &&
            (_mangaFields.contains(child.name.value) ||
                _chapterFields.contains(child.name.value) ||
                const {
                  '__typename',
                  'mangaId',
                  'chapterId',
                }.contains(child.name.value)),
      );

  bool get needsRewrite {
    bool containsUser(SelectionSetNode set) => set.selections.any(
      (selection) => switch (selection) {
        FieldNode() =>
          _hoisted(selection) ||
              (selection.selectionSet != null &&
                  containsUser(selection.selectionSet!)),
        InlineFragmentNode() => containsUser(selection.selectionSet),
        _ => false,
      },
    );
    return document.definitions.any(
      (definition) => switch (definition) {
        OperationDefinitionNode() => containsUser(definition.selectionSet),
        FragmentDefinitionNode() => containsUser(definition.selectionSet),
        _ => false,
      },
    );
  }

  @override
  SelectionSetNode visitSelectionSetNode(SelectionSetNode node) {
    return SelectionSetNode(
      selections: [
        for (final selection in node.selections)
          if (selection is FieldNode && _hoisted(selection))
            for (final child
                in selection.selectionSet!.selections.whereType<FieldNode>())
              if (child.name.value != '__typename')
                FieldNode(
                  name:
                      const {'mangaId', 'chapterId'}.contains(child.name.value)
                      ? const NameNode(value: 'id')
                      : child.name,
                  alias:
                      const {'mangaId', 'chapterId'}.contains(child.name.value)
                      ? child.alias ?? child.name
                      : child.alias,
                  arguments: child.arguments,
                  directives: [...selection.directives, ...child.directives],
                  selectionSet: child.selectionSet,
                )
              else
                // Fetch the parent's type, never the legacy user's typename.
                FieldNode(
                  name: const NameNode(value: '__typename'),
                  directives: selection.directives,
                )
          else
            selection,
      ],
    );
  }

  bool _included(List<DirectiveNode> directives) {
    for (final directive in directives) {
      if (!const {'skip', 'include'}.contains(directive.name.value)) continue;
      final value = directive.arguments
          .firstWhere((argument) => argument.name.value == 'if')
          .value;
      final condition = switch (value) {
        BooleanValueNode() => value.value,
        VariableNode() => variables[value.name.value],
        _ => null,
      };
      if (directive.name.value == 'skip' && condition == true ||
          directive.name.value == 'include' && condition == false) {
        return false;
      }
    }
    return true;
  }

  Iterable<FieldNode> _fields(
    SelectionSetNode selection,
    Map<String, dynamic> data, [
    Set<String> seen = const {},
  ]) sync* {
    for (final node in selection.selections) {
      if (node is FieldNode && _included(node.directives)) {
        yield node;
      } else if (node is InlineFragmentNode && _included(node.directives)) {
        final type = node.typeCondition?.on.name.value;
        if (data['__typename'] == null ||
            type == null ||
            data['__typename'] == type) {
          yield* _fields(node.selectionSet, data, seen);
        }
      } else if (node is FragmentSpreadNode &&
          _included(node.directives) &&
          !seen.contains(node.name.value)) {
        final fragment = fragments[node.name.value];
        if (fragment != null &&
            (data['__typename'] == null ||
                data['__typename'] == fragment.typeCondition.on.name.value)) {
          yield* _fields(fragment.selectionSet, data, {
            ...seen,
            node.name.value,
          });
        }
      }
    }
  }

  dynamic _reshape(dynamic value, List<SelectionSetNode> selections) {
    if (value is List) {
      return [for (final item in value) _reshape(item, selections)];
    }
    if (value is! Map<String, dynamic>) return value;
    final result = Map<String, dynamic>.from(value);
    final fields = [for (final set in selections) ..._fields(set, value)];
    final direct = <String, List<FieldNode>>{};
    final users = <String, List<FieldNode>>{};
    for (final field in fields) {
      ((_hoisted(field) ? users : direct)[_key(field)] ??= []).add(field);
    }
    for (final entry in direct.entries) {
      final sets = [
        for (final field in entry.value)
          if (field.selectionSet != null) field.selectionSet!,
      ];
      if (sets.isNotEmpty && value.containsKey(entry.key)) {
        result[entry.key] = _reshape(value[entry.key], sets);
      }
    }
    for (final entry in users.entries) {
      final children = [
        for (final field in entry.value)
          ...field.selectionSet!.selections.whereType<FieldNode>(),
      ];
      final user = <String, dynamic>{};
      final manga = children.any(
        (child) => _mangaFields.contains(child.name.value),
      );
      final chapter = children.any(
        (child) => _chapterFields.contains(child.name.value),
      );
      final type = manga
          ? 'MangaUserType'
          : chapter
          ? 'ChapterUserType'
          : value['__typename'] == 'MangaType'
          ? 'MangaUserType'
          : value['__typename'] == 'ChapterType'
          ? 'ChapterUserType'
          : null;
      final childFields = <String, List<FieldNode>>{};
      for (final child in children) {
        if (_included(child.directives)) {
          (childFields[_key(child)] ??= []).add(child);
        }
      }
      for (final entry in childFields.entries) {
        final key = entry.key;
        if (entry.value.first.name.value == '__typename') {
          if (type != null) user[key] = type;
        } else if (value.containsKey(key)) {
          final sets = [
            for (final child in entry.value)
              if (child.selectionSet != null) child.selectionSet!,
          ];
          user[key] = sets.isEmpty ? value[key] : _reshape(value[key], sets);
          if (!direct.containsKey(key)) result.remove(key);
        }
      }
      result[entry.key] = user;
    }
    // __typename may have been added solely to identify an ambiguous user.
    if (!direct.values
            .expand((fields) => fields)
            .any(
              (field) =>
                  field.name.value == '__typename' &&
                  _key(field) == '__typename',
            ) &&
        users.isNotEmpty) {
      result.remove('__typename');
    }
    return result;
  }

  Map<String, dynamic>? reshape(Map<String, dynamic>? data, String? name) {
    if (data == null) return null;
    final operations = document.definitions
        .whereType<OperationDefinitionNode>();
    final operation = name == null
        ? operations.first
        : operations.firstWhere((operation) => operation.name?.value == name);
    return _reshape(data, [operation.selectionSet]) as Map<String, dynamic>;
  }
}
