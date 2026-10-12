// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

class OperationEntry {
  const OperationEntry({
    required this.name,
    required this.operation,
    required this.file,
  });

  final String name;
  final OperationDefinitionNode operation;
  final String file;
}

class GqlFieldInfo {
  const GqlFieldInfo(this.name, this.type);
  final String name;
  final TypeNode type;
}

class GqlTypeInfo {
  GqlTypeInfo({
    required this.name,
    required this.kind,
    this.fields = const {},
    this.interfaces = const [],
    this.unionMembers = const [],
    this.enumValues = const [],
  });

  final String name;
  final String kind;
  final Map<String, GqlFieldInfo> fields;
  final List<String> interfaces;
  final List<String> unionMembers;
  final List<String> enumValues;

  bool get isComposite =>
      kind == 'object' || kind == 'interface' || kind == 'union';
}

class SchemaInfo {
  SchemaInfo(this.types);

  final Map<String, GqlTypeInfo> types;

  static SchemaInfo fromDocument(DocumentNode document) {
    final types = <String, GqlTypeInfo>{};
    for (final definition in document.definitions) {
      if (definition is ObjectTypeDefinitionNode) {
        types[definition.name.value] = GqlTypeInfo(
          name: definition.name.value,
          kind: 'object',
          fields: {
            for (final field in definition.fields)
              field.name.value: GqlFieldInfo(field.name.value, field.type),
          },
          interfaces: [
            for (final type in definition.interfaces) type.name.value,
          ],
        );
      } else if (definition is InterfaceTypeDefinitionNode) {
        types[definition.name.value] = GqlTypeInfo(
          name: definition.name.value,
          kind: 'interface',
          fields: {
            for (final field in definition.fields)
              field.name.value: GqlFieldInfo(field.name.value, field.type),
          },
          interfaces: [
            for (final type in definition.interfaces) type.name.value,
          ],
        );
      } else if (definition is UnionTypeDefinitionNode) {
        types[definition.name.value] = GqlTypeInfo(
          name: definition.name.value,
          kind: 'union',
          unionMembers: [for (final type in definition.types) type.name.value],
        );
      } else if (definition is EnumTypeDefinitionNode) {
        types[definition.name.value] = GqlTypeInfo(
          name: definition.name.value,
          kind: 'enum',
          enumValues: [for (final value in definition.values) value.name.value],
        );
      } else if (definition is ScalarTypeDefinitionNode) {
        types[definition.name.value] = GqlTypeInfo(
          name: definition.name.value,
          kind: 'scalar',
        );
      } else if (definition is InputObjectTypeDefinitionNode) {
        types[definition.name.value] = GqlTypeInfo(
          name: definition.name.value,
          kind: 'input',
        );
      }
    }
    return SchemaInfo(types);
  }

  GqlFieldInfo? fieldOf(String typeName, String fieldName) {
    final visited = <String>{};
    GqlFieldInfo? search(String name) {
      if (!visited.add(name)) return null;
      final type = types[name];
      if (type == null) return null;
      final direct = type.fields[fieldName];
      if (direct != null) return direct;
      for (final parent in type.interfaces) {
        final found = search(parent);
        if (found != null) return found;
      }
      return null;
    }

    return search(typeName);
  }

  List<String> concreteTypesOf(String typeName) {
    final type = types[typeName];
    if (type == null) return const [];
    if (type.kind == 'object') return [typeName];
    if (type.kind == 'union') {
      return [
        for (final member in type.unionMembers) ...concreteTypesOf(member),
      ];
    }
    if (type.kind == 'interface') {
      final result = <String>[];
      for (final candidate in types.values) {
        if (candidate.kind == 'object' &&
            _implements(candidate.name, typeName)) {
          result.add(candidate.name);
        }
      }
      if (result.isEmpty) {
        for (final candidate in types.values) {
          if (candidate.kind == 'interface' &&
              candidate.name != typeName &&
              _implements(candidate.name, typeName)) {
            result.addAll(concreteTypesOf(candidate.name));
          }
        }
      }
      return result;
    }
    return const [];
  }

  bool _implements(String typeName, String interfaceName) {
    final visited = <String>{};
    bool search(String name) {
      if (!visited.add(name)) return false;
      final type = types[name];
      if (type == null) return false;
      if (type.interfaces.contains(interfaceName)) return true;
      return type.interfaces.any(search);
    }

    return search(typeName);
  }

  bool typeConditionMatches(String? condition, String concreteType) {
    if (condition == null) return true;
    if (condition == concreteType) return true;
    final conditionType = types[condition];
    if (conditionType == null) return false;
    if (conditionType.kind == 'interface') {
      return _implements(concreteType, condition);
    }
    if (conditionType.kind == 'union') {
      return conditionType.unionMembers.contains(concreteType);
    }
    return false;
  }
}

class GraphQLDocuments {
  const GraphQLDocuments({
    required this.operations,
    required this.fragments,
    required this.schema,
  });

  final List<OperationEntry> operations;
  final Map<String, FragmentDefinitionNode> fragments;
  final SchemaInfo schema;
}

Directory findProjectRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/lib/src/graphql/schema.graphql').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not locate project root from ${Directory.current.path}',
      );
    }
    directory = parent;
  }
}

String relativeGraphQLPath(Directory root, File file) {
  final rootPath = '${root.path}/';
  return file.path.startsWith(rootPath)
      ? file.path.substring(rootPath.length)
      : file.path;
}

GraphQLDocuments loadGraphQLDocuments() {
  final root = findProjectRoot();
  final files =
      Directory('${root.path}/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.graphql'))
          .where((file) => !file.path.endsWith('schema.graphql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final operations = <OperationEntry>[];
  final fragments = <String, FragmentDefinitionNode>{};
  for (final file in files) {
    final relative = relativeGraphQLPath(root, file);
    final document = gql_lang.parseString(file.readAsStringSync());
    for (final definition in document.definitions) {
      if (definition is OperationDefinitionNode) {
        final name = definition.name?.value;
        if (name != null) {
          operations.add(
            OperationEntry(name: name, operation: definition, file: relative),
          );
        }
      } else if (definition is FragmentDefinitionNode) {
        fragments[definition.name.value] = definition;
      }
    }
  }
  operations.sort((a, b) {
    final byFile = a.file.compareTo(b.file);
    return byFile != 0 ? byFile : a.name.compareTo(b.name);
  });

  final schemaDocument = gql_lang.parseString(
    File('${root.path}/lib/src/graphql/schema.graphql').readAsStringSync(),
  );
  return GraphQLDocuments(
    operations: operations,
    fragments: fragments,
    schema: SchemaInfo.fromDocument(schemaDocument),
  );
}

OperationEntry operationFromSource(String source, {String file = '<inline>'}) {
  final document = gql_lang.parseString(source);
  final operation = document.definitions
      .whereType<OperationDefinitionNode>()
      .first;
  return OperationEntry(
    name: operation.name?.value ?? '<anonymous>',
    operation: operation,
    file: file,
  );
}

Map<String, FragmentDefinitionNode> fragmentsFromSource(String source) {
  final document = gql_lang.parseString(source);
  return {
    for (final definition in document.definitions)
      if (definition is FragmentDefinitionNode)
        definition.name.value: definition,
  };
}

Set<String> transitiveFragmentNames(
  OperationDefinitionNode operation,
  Map<String, FragmentDefinitionNode> fragments,
) {
  final result = <String>{};
  void visitSelectionSet(SelectionSetNode selectionSet) {
    for (final selection in selectionSet.selections) {
      if (selection is FragmentSpreadNode) {
        final name = selection.name.value;
        if (result.add(name)) {
          final fragment = fragments[name];
          if (fragment != null) visitSelectionSet(fragment.selectionSet);
        }
      } else if (selection is FieldNode) {
        final nested = selection.selectionSet;
        if (nested != null) visitSelectionSet(nested);
      } else if (selection is InlineFragmentNode) {
        visitSelectionSet(selection.selectionSet);
      }
    }
  }

  visitSelectionSet(operation.selectionSet);
  return result;
}

DocumentNode executableDocument(
  OperationEntry entry,
  Map<String, FragmentDefinitionNode> fragments,
) {
  final names = transitiveFragmentNames(entry.operation, fragments);
  return DocumentNode(
    definitions: [
      entry.operation,
      for (final name in names)
        if (fragments[name] != null) fragments[name]!,
    ],
  );
}

bool? directiveIfValue(
  List<DirectiveNode> directives,
  Map<String, dynamic> variables,
) {
  for (final directive in directives) {
    final name = directive.name.value;
    if (name != 'include' && name != 'skip') continue;
    for (final argument in directive.arguments) {
      if (argument.name.value != 'if') continue;
      final value = argument.value;
      bool? evaluated;
      if (value is BooleanValueNode) {
        evaluated = value.value;
      } else if (value is VariableNode) {
        final variableValue = variables[value.name.value];
        if (variableValue is bool) evaluated = variableValue;
      }
      if (evaluated == null) return null;
      return name == 'include' ? evaluated : !evaluated;
    }
  }
  return null;
}

bool isIncludedByServer(
  List<DirectiveNode> directives,
  Map<String, dynamic> variables,
) {
  return directiveIfValue(directives, variables) ?? true;
}

Map<String, Set<String>> directiveVariableUses(
  OperationDefinitionNode operation,
  Map<String, FragmentDefinitionNode> fragments,
) {
  final result = <String, Set<String>>{};
  final visitedFragments = <String>{};

  void collectDirectives(List<DirectiveNode> directives) {
    for (final directive in directives) {
      final directiveName = directive.name.value;
      if (directiveName != 'include' && directiveName != 'skip') {
        continue;
      }
      for (final argument in directive.arguments) {
        if (argument.name.value == 'if' && argument.value is VariableNode) {
          final variable = (argument.value as VariableNode).name.value;
          result.putIfAbsent(variable, () => <String>{}).add(directiveName);
        }
      }
    }
  }

  void visitSelectionSet(SelectionSetNode selectionSet) {
    for (final selection in selectionSet.selections) {
      if (selection is FieldNode) {
        collectDirectives(selection.directives);
        final nested = selection.selectionSet;
        if (nested != null) visitSelectionSet(nested);
      } else if (selection is FragmentSpreadNode) {
        collectDirectives(selection.directives);
        final name = selection.name.value;
        if (visitedFragments.add(name)) {
          final fragment = fragments[name];
          if (fragment != null) {
            collectDirectives(fragment.directives);
            visitSelectionSet(fragment.selectionSet);
          }
        }
      } else if (selection is InlineFragmentNode) {
        collectDirectives(selection.directives);
        visitSelectionSet(selection.selectionSet);
      }
    }
  }

  collectDirectives(operation.directives);
  visitSelectionSet(operation.selectionSet);
  return result;
}

Set<String> directiveVariables(
  OperationDefinitionNode operation,
  Map<String, FragmentDefinitionNode> fragments,
) {
  return directiveVariableUses(operation, fragments).keys.toSet();
}

Object? valueNodeToDart(ValueNode? value) {
  if (value == null || value is NullValueNode) return null;
  if (value is BooleanValueNode) return value.value;
  if (value is IntValueNode) return int.tryParse(value.value);
  if (value is FloatValueNode) return double.tryParse(value.value);
  if (value is StringValueNode) return value.value;
  if (value is EnumValueNode) return value.name.value;
  if (value is ListValueNode) {
    return [for (final item in value.values) valueNodeToDart(item)];
  }
  if (value is ObjectValueNode) {
    return {
      for (final field in value.fields)
        field.name.value: valueNodeToDart(field.value),
    };
  }
  if (value is VariableNode) return null;
  return null;
}

Object? defaultValueOf(VariableDefinitionNode definition) {
  return valueNodeToDart(definition.defaultValue?.value);
}

bool hasDefaultValue(VariableDefinitionNode definition) {
  return definition.defaultValue != null &&
      definition.defaultValue!.value != null;
}

Map<String, VariableDefinitionNode> variableDefinitionsOf(
  OperationDefinitionNode operation,
) {
  return {
    for (final definition in operation.variableDefinitions)
      definition.variable.name.value: definition,
  };
}

List<String> directiveVariableViolations(
  OperationEntry entry,
  Map<String, FragmentDefinitionNode> fragments,
) {
  final uses = directiveVariableUses(entry.operation, fragments);
  final definitions = variableDefinitionsOf(entry.operation);
  final violations = <String>[];
  final variables = uses.keys.toList()..sort();
  for (final variable in variables) {
    final definition = definitions[variable];
    final directives = uses[variable]!;
    if (definition == null) {
      violations.add(
        '${entry.name} (${entry.file}): \$$variable is used in '
        '@include/@skip but is not declared',
      );
      continue;
    }
    final type = definition.type;
    final isBooleanNonNull =
        type is NamedTypeNode && type.isNonNull && type.name.value == 'Boolean';
    final isNullableBoolean =
        type is NamedTypeNode &&
        !type.isNonNull &&
        type.name.value == 'Boolean';
    final hasDefault = hasDefaultValue(definition);
    if (isBooleanNonNull && !hasDefault) continue;
    if (hasDefault && directives.length > 1) {
      violations.add(
        '${entry.name} (${entry.file}): \$$variable is used by both '
        '@include and @skip and has a default value; the default cannot '
        'match both',
      );
      continue;
    }
    if (isNullableBoolean && hasDefault) {
      final defaultValue = defaultValueOf(definition);
      if (defaultValue is bool) {
        if (directives.contains('include') && defaultValue == true) continue;
        if (directives.contains('skip') && defaultValue == false) continue;
      }
      violations.add(
        '${entry.name} (${entry.file}): \$$variable has a default value '
        'that does not match the cache missing-variable behaviour for '
        '@include/@skip',
      );
      continue;
    }
    if (isNullableBoolean && !hasDefault) {
      violations.add(
        '${entry.name} (${entry.file}): \$$variable is nullable Boolean '
        'with no default value',
      );
      continue;
    }
    violations.add(
      '${entry.name} (${entry.file}): \$$variable must be declared as '
      'Boolean! with no default value, or nullable Boolean with a '
      'matching default',
    );
  }
  return violations;
}

Object? placeholderForType(TypeNode type, SchemaInfo schema) {
  if (type is ListTypeNode) {
    return <Object?>[placeholderForType(type.type, schema)];
  }
  if (type is NamedTypeNode) {
    final name = type.name.value;
    switch (name) {
      case 'Int':
        return 1;
      case 'Float':
        return 1.5;
      case 'Boolean':
        return true;
      case 'ID':
      case 'String':
        return 'placeholder';
    }
    final info = schema.types[name];
    if (info != null && info.kind == 'enum' && info.enumValues.isNotEmpty) {
      return info.enumValues.first;
    }
    if (info != null && info.kind == 'input') {
      return <String, dynamic>{};
    }
    return 'placeholder';
  }
  return 'placeholder';
}

Map<String, dynamic> placeholderVariables(
  OperationDefinitionNode operation,
  SchemaInfo schema, {
  Map<String, dynamic> overrides = const {},
}) {
  final result = <String, dynamic>{};
  for (final definition in operation.variableDefinitions) {
    final name = definition.variable.name.value;
    if (overrides.containsKey(name)) continue;
    result[name] = placeholderForType(definition.type, schema);
  }
  result.addAll(overrides);
  return result;
}

class PayloadGenerator {
  PayloadGenerator({
    required this.schema,
    required this.fragments,
    required this.effectiveVariables,
  });

  final SchemaInfo schema;
  final Map<String, FragmentDefinitionNode> fragments;
  final Map<String, dynamic> effectiveVariables;
  int _counter = 0;

  int _next() => ++_counter;

  Map<String, dynamic> generate(OperationDefinitionNode operation) {
    final rootType = switch (operation.type) {
      OperationType.query => 'Query',
      OperationType.mutation => 'Mutation',
      OperationType.subscription => 'Subscription',
    };
    final result = <String, dynamic>{'__typename': rootType};
    _expand(operation.selectionSet, rootType, rootType, result);
    return result;
  }

  void _expand(
    SelectionSetNode selectionSet,
    String parentType,
    String concreteType,
    Map<String, dynamic> out,
  ) {
    for (final selection in selectionSet.selections) {
      if (selection is FieldNode) {
        if (!isIncludedByServer(selection.directives, effectiveVariables)) {
          continue;
        }
        final fieldName = selection.name.value;
        final responseKey = selection.alias?.value ?? fieldName;
        if (fieldName == '__typename') {
          out[responseKey] = concreteType;
          continue;
        }
        final field =
            schema.fieldOf(parentType, fieldName) ??
            schema.fieldOf(concreteType, fieldName);
        if (field == null) {
          throw StateError('Unknown field $parentType.$fieldName');
        }
        final value = _valueFor(field.type, selection.selectionSet);
        _merge(out, responseKey, value);
      } else if (selection is FragmentSpreadNode) {
        if (!isIncludedByServer(selection.directives, effectiveVariables)) {
          continue;
        }
        final fragment = fragments[selection.name.value];
        if (fragment == null) {
          throw StateError('Unknown fragment ${selection.name.value}');
        }
        final condition = fragment.typeCondition.on.name.value;
        if (!schema.typeConditionMatches(condition, concreteType)) continue;
        if (!isIncludedByServer(fragment.directives, effectiveVariables)) {
          continue;
        }
        _expand(fragment.selectionSet, condition, concreteType, out);
      } else if (selection is InlineFragmentNode) {
        if (!isIncludedByServer(selection.directives, effectiveVariables)) {
          continue;
        }
        final condition = selection.typeCondition?.on.name.value;
        if (condition != null &&
            !schema.typeConditionMatches(condition, concreteType)) {
          continue;
        }
        _expand(
          selection.selectionSet,
          condition ?? parentType,
          concreteType,
          out,
        );
      }
    }
  }

  Object? _valueFor(TypeNode type, SelectionSetNode? selectionSet) {
    if (type is ListTypeNode) {
      return <Object?>[_valueFor(type.type, selectionSet)];
    }
    if (type is NamedTypeNode) {
      final name = type.name.value;
      switch (name) {
        case 'Int':
          return _next();
        case 'Float':
          return _next() + 0.5;
        case 'Boolean':
          return true;
        case 'ID':
          return '${_next()}';
        case 'String':
          return 'value-${_next()}';
      }
      final info = schema.types[name];
      if (info == null) return 'value-${_next()}';
      if (info.kind == 'enum') {
        return info.enumValues.isEmpty ? 'value' : info.enumValues.first;
      }
      if (info.kind == 'scalar') return 'value-${_next()}';
      if (info.isComposite) {
        if (selectionSet == null) return {'__typename': name};
        final concrete = _pickConcrete(name, selectionSet);
        final result = <String, dynamic>{'__typename': concrete};
        _expand(selectionSet, name, concrete, result);
        return result;
      }
      return 'value-${_next()}';
    }
    return 'value-${_next()}';
  }

  String _pickConcrete(String typeName, SelectionSetNode selectionSet) {
    final info = schema.types[typeName];
    if (info == null) return typeName;
    if (info.kind == 'object') return typeName;
    final candidates = schema.concreteTypesOf(typeName);
    if (candidates.isEmpty) return typeName;
    final conditions = <String>[];
    void collect(SelectionSetNode selections, Set<String> visited) {
      for (final selection in selections.selections) {
        if (selection is InlineFragmentNode) {
          final condition = selection.typeCondition?.on.name.value;
          if (condition != null) conditions.add(condition);
          collect(selection.selectionSet, visited);
        } else if (selection is FragmentSpreadNode) {
          final name = selection.name.value;
          if (!visited.add(name)) continue;
          final fragment = fragments[name];
          if (fragment == null) continue;
          conditions.add(fragment.typeCondition.on.name.value);
          collect(fragment.selectionSet, visited);
        } else if (selection is FieldNode) {
          final nested = selection.selectionSet;
          if (nested != null) collect(nested, visited);
        }
      }
    }

    collect(selectionSet, <String>{});
    for (final condition in conditions) {
      if (candidates.contains(condition)) return condition;
    }
    for (final condition in conditions) {
      for (final candidate in candidates) {
        if (schema.typeConditionMatches(condition, candidate)) {
          return candidate;
        }
      }
    }
    return candidates.first;
  }

  void _merge(Map<String, dynamic> out, String key, Object? value) {
    final existing = out[key];
    if (existing is Map<String, dynamic> && value is Map<String, dynamic>) {
      for (final entry in value.entries) {
        _merge(existing, entry.key, entry.value);
      }
      return;
    }
    if (existing is List && value is List) {
      if (existing.isNotEmpty &&
          value.isNotEmpty &&
          existing.first is Map<String, dynamic> &&
          value.first is Map<String, dynamic>) {
        final merged = Map<String, dynamic>.from(
          existing.first as Map<String, dynamic>,
        );
        for (final entry in (value.first as Map<String, dynamic>).entries) {
          _merge(merged, entry.key, entry.value);
        }
        out[key] = [merged, ...existing.skip(1)];
        return;
      }
    }
    out[key] = value;
  }
}

Map<String, dynamic> buildResponsePayload({
  required OperationEntry entry,
  required GraphQLDocuments documents,
  required Map<String, dynamic> effectiveVariables,
}) {
  return PayloadGenerator(
    schema: documents.schema,
    fragments: documents.fragments,
    effectiveVariables: effectiveVariables,
  ).generate(entry.operation);
}
