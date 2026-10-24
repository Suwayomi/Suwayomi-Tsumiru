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
      final positions = (filter['positions'] as List).cast<int>();
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
