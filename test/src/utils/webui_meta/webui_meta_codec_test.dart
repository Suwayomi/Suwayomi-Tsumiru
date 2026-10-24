import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/webui_meta/webui_meta_codec.dart';

Map<String, String> applyWrite(Map<String, String> existing, String? value) {
  final plan = planWebUiWrite(existing, 'notes', value);
  return {...existing, ...plan.set}
    ..removeWhere((key, _) => plan.delete.contains(key));
}

void main() {
  test('short values use the default device key and round-trip', () {
    final plan = planWebUiWrite({}, 'notes', 'A note');
    expect(webUiKey('notes'), 'webUI_notes');
    expect(plan.set, {'webUI_notes': 'A note'});
    expect(plan.delete, isEmpty);
    expect(readWebUiValue(plan.set, 'notes'), 'A note');
    expect(readWebUiValue(applyWrite({}, ''), 'notes'), '');
  });

  test('4000 code units stay plain and 4001 split into two chunks', () {
    final boundary = 'a' * 4000;
    expect(planWebUiWrite({}, 'notes', boundary).set, {
      'webUI_notes': boundary,
    });
    final plan = planWebUiWrite({}, 'notes', '${boundary}b');
    expect(plan.set, {
      'webUI_notes_0': boundary,
      'webUI_notes_1': 'b',
      'webUI_notes_length': '2',
    });
    expect(readWebUiValue(plan.set, 'notes'), '${boundary}b');
  });

  test(
    'non-ASCII and emoji split at UTF-16 boundaries, including surrogates',
    () {
      final value = '${'界' * 3999}😀é';
      final plan = planWebUiWrite({}, 'notes', value);
      expect(plan.set['webUI_notes_0']!.length, 4000);
      expect(plan.set['webUI_notes_0']!.codeUnitAt(3999), 0xd83d);
      expect(plan.set['webUI_notes_1']!.codeUnits, [0xde00, 0xe9]);
      expect(readWebUiValue(plan.set, 'notes'), value);
      expect(planWebUiWrite({}, 'notes', '😀' * 2000).set.keys, [
        'webUI_notes',
      ]);
    },
  );

  test('shrinking to plain deletes the length and all old chunks', () {
    final existing = applyWrite({}, 'a' * 8001);
    final plan = planWebUiWrite(existing, 'notes', 'short');
    expect(plan.delete, [
      'webUI_notes_length',
      'webUI_notes_0',
      'webUI_notes_1',
      'webUI_notes_2',
    ]);
    expect(applyWrite(existing, 'short'), {'webUI_notes': 'short'});
  });

  test('growing to chunks deletes the plain key', () {
    final existing = {'webUI_notes': 'short'};
    final plan = planWebUiWrite(existing, 'notes', 'a' * 4001);
    expect(plan.delete, ['webUI_notes']);
    expect(
      readWebUiValue(applyWrite(existing, 'a' * 4001), 'notes'),
      'a' * 4001,
    );
  });

  test('fewer chunks delete extras, including contiguous stale chunks', () {
    final existing = {...applyWrite({}, 'a' * 12001), 'webUI_notes_4': 'stale'};
    final plan = planWebUiWrite(existing, 'notes', 'b' * 4001);
    expect(plan.delete, ['webUI_notes_2', 'webUI_notes_3', 'webUI_notes_4']);
    expect(
      readWebUiValue(applyWrite(existing, 'b' * 4001), 'notes'),
      'b' * 4001,
    );
  });

  test('null deletes plain, length and chunks while preserving other keys', () {
    final existing = {
      ...applyWrite({}, 'a' * 4001),
      'webUI_notes': 'old',
      'webUI_notes_4': 'orphan',
      'webUI_notes_other': 'keep',
      'webUI_other': 'keep',
    };
    expect(planWebUiWrite(existing, 'notes', null).set, isEmpty);
    expect(applyWrite(existing, null), {
      'webUI_notes_other': 'keep',
      'webUI_other': 'keep',
    });
  });

  test('reads a hand-built WebUI saved-search fixture', () {
    final prefix = '{"Long search":{"query":"${'x' * 3975}';
    expect(prefix.length, 4000);
    final fixture = {
      'webUI_savedSearches_0': prefix,
      'webUI_savedSearches_1': '","filters":[]}}',
      'webUI_savedSearches_length': '2',
    };
    expect(readWebUiValue(fixture, 'savedSearches'), '$prefix","filters":[]}}');
  });

  test('missing chunks return null and a plain value takes precedence', () {
    final fixture = {'webUI_notes_length': '2', 'webUI_notes_0': 'first'};
    expect(readWebUiValue(fixture, 'notes'), isNull);
    expect(
      readWebUiValue({...fixture, 'webUI_notes': 'plain'}, 'notes'),
      'plain',
    );
    expect(readWebUiValue({}, 'notes'), isNull);
    for (final count in ['0', '-1', 'invalid']) {
      expect(
        readWebUiValue({...fixture, 'webUI_notes_length': count}, 'notes'),
        isNull,
      );
    }
  });

  test('boolean converters use WebUI literal true semantics', () {
    expect(encodeWebUiBool(true), 'true');
    expect(encodeWebUiBool(false), 'false');
    expect(decodeWebUiBool('true'), isTrue);
    for (final value in ['false', 'TRUE', '1', 'null', '']) {
      expect(decodeWebUiBool(value), isFalse);
    }
  });

  test(
    'integer converters accept numeric WebUI values and default invalid ones',
    () {
      expect(encodeWebUiInt(42), '42');
      for (final value in ['42', ' 42 ', '42.0', '4.2e1']) {
        expect(decodeWebUiInt(value, defaultValue: 7), 42);
      }
      expect(decodeWebUiInt('', defaultValue: 7), 0);
      for (final value in ['invalid', '0x2a', '0b101', '0o52', 'NaN']) {
        expect(decodeWebUiInt(value, defaultValue: 7), 7);
      }
    },
  );
}
