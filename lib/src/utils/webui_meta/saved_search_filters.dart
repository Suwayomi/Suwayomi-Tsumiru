import '../../features/browse_center/domain/filter/filter_model.dart';

const _stateTypes = [
  'checkBoxState',
  'triState',
  'selectState',
  'textState',
  'sortState',
];

List<FilterChange> filtersFromWebUi(List<dynamic> filters) =>
    filters.map((entry) {
      final filter = entry as Map<String, dynamic>;
      final positions = _positionsFromEntry(filter, entry);
      final type = filter['type'] as String;
      if (positions.isEmpty || !_stateTypes.contains(type)) {
        throw FormatException('Invalid saved search filter', entry);
      }
      Map<String, dynamic> change = {
        'position': positions.last,
        type: filter['state'],
      };
      for (final position in positions.reversed.skip(1)) {
        change = {'position': position, 'groupChange': change};
      }
      return FilterChange.fromJson(change);
    }).toList();

List<int> _positionsFromEntry(Map<String, dynamic> filter, Object? entry) {
  final raw = filter['positions'];
  if (raw is List) return raw.cast<int>();
  final position = filter['position'];
  final group = filter['group'];
  if (position is! int || (group != null && group is! int)) {
    throw FormatException('Invalid saved search filter', entry);
  }
  return group != null ? [group, position] : [position];
}

bool savedSearchFitsSource(List<Filter> filters, List<FilterChange> changes) {
  const expectedTypenames = {
    'selectState': 'SelectFilter',
    'textState': 'TextFilter',
    'checkBoxState': 'CheckBoxFilter',
    'triState': 'TriStateFilter',
    'sortState': 'SortFilter',
  };
  try {
    final entries = filtersToWebUi(changes);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final positions = entry['positions'] as List<int>;
      final expected = expectedTypenames[entry['type']];
      if (expected == null) return false;
      List<PrimitiveFilter> level = filters;
      PrimitiveFilter? found;
      for (var depth = 0; depth < positions.length; depth++) {
        final position = positions[depth];
        if (position < 0 || position >= level.length) return false;
        final filter = level[position];
        if (depth == positions.length - 1) {
          found = filter;
        } else if (filter is FilterGroup) {
          level = filter.groupState;
        } else {
          return false;
        }
      }
      final filter = found;
      if (filter == null || filter.$__typename != expected) return false;
      var leaf = changes[i];
      while (leaf.groupChange != null) {
        leaf = leaf.groupChange!;
      }
      if (leaf.selectState != null) {
        if (filter is! FilterSelect ||
            leaf.selectState! < 0 ||
            leaf.selectState! >= filter.displayValues.length) {
          return false;
        }
      } else if (leaf.sortState != null) {
        if (filter is! FilterSort ||
            leaf.sortState!.index < 0 ||
            leaf.sortState!.index >= filter.displayValues.length) {
          return false;
        }
      } else if (leaf.triState != null) {
        if (leaf.triState == TriState.$unknown) return false;
      }
    }
  } on StateError {
    return false;
  }
  return true;
}

List<Map<String, dynamic>> filtersToWebUi(List<FilterChange> filters) =>
    filters.map((filter) {
      final positions = <int>[];
      var change = filter;
      while (true) {
        positions.add(change.position);
        if (change.groupChange == null) break;
        change = change.groupChange!;
      }
      final json = change.toJson();
      final type = _stateTypes.singleWhere((key) => json[key] != null);
      return {'type': type, 'positions': positions, 'state': json[type]};
    }).toList();
