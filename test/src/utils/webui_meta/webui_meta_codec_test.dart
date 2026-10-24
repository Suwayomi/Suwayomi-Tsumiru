import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/webui_meta/webui_meta_codec.dart';

Map<String, String> applyWrite(Map<String, String> existing, String? value) {
  final plan = planWebUiWrite(existing, 'notes', value);
  return {...existing, ...plan.set}
    ..removeWhere((key, _) => plan.delete.contains(key));
}

void main() {
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

  test('replacement removes orphan chunks and stray length rows', () {
    final stale = {
      'webUI_notes': 'old',
      'webUI_notes_4': 'orphan',
      'webUI_notes_12': 'orphan',
      'webUI_notes_length': 'invalid',
      'webUI_notes_other': 'keep',
    };
    expect(applyWrite(stale, 'new'), {
      'webUI_notes': 'new',
      'webUI_notes_other': 'keep',
    });
    final long = applyWrite(stale, 'a' * 4001);
    expect(
      long.keys,
      unorderedEquals([
        'webUI_notes_0',
        'webUI_notes_1',
        'webUI_notes_length',
        'webUI_notes_other',
      ]),
    );
    expect(readWebUiValue(long, 'notes'), 'a' * 4001);
  });

  test('shrinking and null deletion clean up obsolete chunks', () {
    final existing = applyWrite({}, 'a' * 8001);
    final plan = planWebUiWrite(existing, 'notes', 'short');
    expect(
      plan.delete,
      unorderedEquals([
      'webUI_notes_length',
      'webUI_notes_0',
      'webUI_notes_1',
      'webUI_notes_2',
      ]),
    );
    expect(applyWrite(existing, 'short'), {'webUI_notes': 'short'});
    final stale = {
      ...applyWrite({}, 'a' * 4001),
      'webUI_notes': 'old',
      'webUI_notes_4': 'orphan',
      'webUI_notes_other': 'keep',
      'webUI_other': 'keep',
    };
    expect(planWebUiWrite(stale, 'notes', null).set, isEmpty);
    expect(applyWrite(stale, null), {
      'webUI_notes_other': 'keep',
      'webUI_other': 'keep',
    });
  });
}
