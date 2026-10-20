import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/duplicate_matcher.dart';

DupEntry e(int id, String t, {String? d, List<TrackerPair> tp = const []}) =>
    (id: id, title: t, description: d, trackerPairs: tp);

void main() {
  group('normalizeTitle', () {
    test('case, punctuation, whitespace fold together', () {
      expect(normalizeTitle('Solo Leveling!!'), 'solo leveling');
      expect(normalizeTitle('  solo   LEVELING '), 'solo leveling');
      expect(
        normalizeTitle('Solo-Leveling: Ragnarok'),
        'solo leveling ragnarok',
      );
    });
    test('NFKC folds fullwidth forms', () {
      expect(normalizeTitle('ＢＥＲＳＥＲＫ'), 'berserk');
      expect(normalizeTitle('ｂｅｒｓｅｒｋ！'), 'berserk');
    });
    // Cases NFKC covers beyond full-width Latin; the folding tables must too.
  });

  group('titleDuplicates', () {
    test('normalized-exact only — no substring hits', () {
      final lib = [e(1, 'Berserk of Gluttony'), e(2, 'BERSERK!!')];
      expect(
        titleDuplicates(
          candidateId: 9,
          candidateTitle: 'Berserk',
          entries: lib,
        ).map((x) => x.id),
        [2],
      );
    });

    test('self-id is excluded even on an exact title match', () {
      final lib = [e(9, 'Berserk'), e(2, 'BERSERK!!')];
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

  group('trackerDuplicates', () {
    test('tracker pair matches regardless of title, self excluded', () {
      const p = (trackerId: 2, remoteId: '10087', remoteTitle: 'Solo Leveling');
      final lib = [
        e(1, 'Totally Different', tp: [p]),
        e(9, 'Me', tp: [p]),
      ];
      expect(
        trackerDuplicates(
          candidateId: 9,
          candidatePairs: [p],
          entries: lib,
        ).map((x) => x.id),
        [1],
      );
    });
  });

  group('descriptionDuplicates', () {
    test('candidate title found as an alt title in a description hits', () {
      final lib = [
        e(1, 'Some Other Name', d: 'A story. Alt title: Fire Force. Fun.'),
      ];
      expect(
        descriptionDuplicates(
          candidateId: 9,
          candidateTitle: 'Fire Force',
          entries: lib,
        ).map((x) => x.id),
        [1],
      );
    });

    test('titles shorter than kMinDescriptionMatchTitleLength never match', () {
      final lib = [e(1, 'Unrelated', d: 'a cat story about a cat')];
      expect(
        descriptionDuplicates(
          candidateId: 9,
          candidateTitle: 'cat',
          entries: lib,
        ),
        isEmpty,
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

    test(
      'disjoint title pairs produce two separate groups, sorted by header',
      () {
        final groups = findLibraryDuplicateGroups([
          e(1, 'Foo'),
          e(2, 'Foo'),
          e(3, 'Bar'),
          e(4, 'Bar'),
        ], checkDescriptions: false);
        expect(groups, hasLength(2));
        expect(groups[0].header, 'Bar');
        expect(groups[0].memberIds, [3, 4]);
        expect(groups[0].reasons, {DupReason.title});
        expect(groups[1].header, 'Foo');
        expect(groups[1].memberIds, [1, 2]);
        expect(groups[1].reasons, {DupReason.title});
      },
    );
  });

  group('findLibraryDuplicateGroupsChunked (web self-yielding path)', () {
    // DupGroup is a record whose `reasons` field is a Set — records compare
    // fields with `==`, and Set's `==` is identity, not value equality. So
    // list-of-record equality can't be asserted directly; compare field by
    // field instead (top-level Set-to-Set does work: `equals()` special-cases
    // bare Iterables, which is what the rest of this file already relies on).
    void expectSameGroups(List<DupGroup> actual, List<DupGroup> expected) {
      expect(actual, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i].header, expected[i].header, reason: 'group $i header');
        expect(
          actual[i].memberIds,
          expected[i].memberIds,
          reason: 'group $i memberIds',
        );
        expect(
          actual[i].reasons,
          expected[i].reasons,
          reason: 'group $i reasons',
        );
      }
    }

    test('matches the sync scan on a small mixed-reason case', () async {
      const pair = (trackerId: 5, remoteId: '900', remoteTitle: 'x');
      final entries = [
        e(1, 'Solo Leveling'),
        e(2, 'Solo Leveling', tp: [pair]),
        e(3, 'Something Else', tp: [pair]),
        e(4, 'Rare Title Example'),
        e(5, 'Something Different', d: 'mentions Rare Title Example here'),
      ];
      final sync = findLibraryDuplicateGroups(entries, checkDescriptions: true);
      final chunked = await findLibraryDuplicateGroupsChunked(
        entries,
        checkDescriptions: true,
      );
      expectSameGroups(chunked, sync);
    });

    test(
      'yields across a chunk boundary and still matches sync on a >200-entry library',
      () async {
        // 210 unrelated singles plus one description-matched pair spanning
        // the boundary — exercises the `chunkSize`-th slice's delay and
        // proves the yield doesn't skip or duplicate a pairing.
        final entries = [
          for (var i = 0; i < 210; i++) e(i, 'Solo Title $i'),
          e(300, 'Boundary Marker'),
          e(301, 'Other', d: 'mentions Boundary Marker here'),
        ];
        final sync = findLibraryDuplicateGroups(
          entries,
          checkDescriptions: true,
        );
        final chunked = await findLibraryDuplicateGroupsChunked(
          entries,
          checkDescriptions: true,
          chunkSize: 50,
        );
        expectSameGroups(chunked, sync);
        expect(sync, hasLength(1));
        expect(sync.single.memberIds, [300, 301]);
      },
    );
  });
}
