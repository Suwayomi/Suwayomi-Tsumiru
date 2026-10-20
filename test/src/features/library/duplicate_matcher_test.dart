import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/duplicate_matcher.dart';

DupEntry e(int id, String t, {String? d, List<TrackerPair> tp = const []}) =>
    (id: id, title: t, description: d, trackerPairs: tp);

void main() {
  group('titleDuplicates', () {
    test('normalized-exact title match, no substring hits, self excluded', () {
      final lib = [
        e(1, 'Berserk of Gluttony'),
        e(2, 'BERSERK!!'),
        e(9, 'Berserk'),
      ];
      expect(
        titleDuplicates(
          candidateId: 9,
          candidateTitle: 'Berserk',
          entries: lib,
        ).map((x) => x.id),
        [2],
      );
    });
  });

  group('findLibraryDuplicateGroups', () {
    test(
      'title edge + tracker edge chain transitively into one group of 3',
      () {
        const pair = (trackerId: 5, remoteId: '900', remoteTitle: 'x');
        final a = e(1, 'Solo Leveling');
        final b = e(2, 'Solo Leveling', tp: [pair]);
        final c = e(3, 'Something Else', tp: [pair]);
        final groups = findLibraryDuplicateGroups([
          a,
          b,
          c,
        ], checkDescriptions: false);
        expect(groups, hasLength(1));
        expect(groups.single.memberIds, [1, 2, 3]);
        expect(groups.single.reasons, {DupReason.title, DupReason.tracker});
      },
    );
  });
}
