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
    test('fancy quotes/dashes are separators, CJK letters survive', () {
      expect(normalizeTitle('“Ａｂｃ”—ｄｅｆ'), 'abc def');
      expect(normalizeTitle('葬送のフリーレン'), '葬送のフリーレン');
    });
    test('empty and punctuation-only titles normalize to empty', () {
      expect(normalizeTitle(''), '');
      expect(normalizeTitle('***'), '');
    });
  });

  test('TrackerPair/DupEntry typedefs hold record literals', () {
    const TrackerPair pair = (
      trackerId: 1,
      remoteId: '42',
      remoteTitle: 'Solo Leveling',
    );
    const DupEntry entry = (
      id: 1,
      title: 'Solo Leveling',
      description: null,
      trackerPairs: [pair],
    );
    expect(entry.trackerPairs.single.remoteTitle, 'Solo Leveling');
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

    test('empty normalized candidate title short-circuits to no matches', () {
      final lib = [e(1, ''), e(2, '***')];
      expect(
        titleDuplicates(candidateId: 9, candidateTitle: '***', entries: lib),
        isEmpty,
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

    test('same remoteId on a different trackerId is not a match', () {
      const mine = (trackerId: 2, remoteId: '10087', remoteTitle: 'x');
      const other = (trackerId: 3, remoteId: '10087', remoteTitle: 'x');
      final lib = [
        e(1, 'A', tp: [other]),
      ];
      expect(
        trackerDuplicates(candidateId: 9, candidatePairs: [mine], entries: lib),
        isEmpty,
      );
    });

    test('remoteId compares as a string — "123" does not equal "0123"', () {
      const mine = (trackerId: 2, remoteId: '123', remoteTitle: 'x');
      const other = (trackerId: 2, remoteId: '0123', remoteTitle: 'x');
      final lib = [
        e(1, 'A', tp: [other]),
      ];
      expect(
        trackerDuplicates(candidateId: 9, candidatePairs: [mine], entries: lib),
        isEmpty,
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

    test('word-boundary guard: "fire" does not hit inside "bonfire"', () {
      final lib = [e(1, 'Unrelated', d: 'a bonfire story')];
      expect(
        descriptionDuplicates(
          candidateId: 9,
          candidateTitle: 'fire',
          entries: lib,
        ),
        isEmpty,
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

    test('null or empty descriptions never match', () {
      final lib = [e(1, 'A', d: null), e(2, 'B', d: '')];
      expect(
        descriptionDuplicates(
          candidateId: 9,
          candidateTitle: 'Solo Leveling',
          entries: lib,
        ),
        isEmpty,
      );
    });

    test('self-id is excluded even when its own description matches', () {
      final lib = [
        e(9, 'Me', d: 'Alt title: Solo Leveling'),
        e(1, 'Other', d: 'Alt title: Solo Leveling'),
      ];
      expect(
        descriptionDuplicates(
          candidateId: 9,
          candidateTitle: 'Solo Leveling',
          entries: lib,
        ).map((x) => x.id),
        [1],
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

    test('mega-cluster regression: a hub description must not transitively '
        'merge two unrelated titles it happens to mention', () {
      final a = e(1, 'Journey');
      final b = e(
        2,
        'Unrelated Middle',
        d: 'A story called Journey, later a Hero appears.',
      );
      final c = e(3, 'Hero');
      final groups = findLibraryDuplicateGroups([
        a,
        b,
        c,
      ], checkDescriptions: true);
      // Only one description edge may resolve into a real group — B is the
      // hub and can attach to at most one side; A and C must never both
      // land in the same group as a result.
      expect(groups, hasLength(1));
      expect(groups.single.memberIds, contains(2));
      final hasA = groups.single.memberIds.contains(1);
      final hasC = groups.single.memberIds.contains(3);
      expect(
        hasA && hasC,
        isFalse,
        reason: 'A and C must never share a group via a shared hub',
      );
    });

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

    test('checkDescriptions: false suppresses description edges entirely', () {
      final a = e(1, 'Rare Title Example');
      final b = e(2, 'Something Else', d: 'mentions Rare Title Example here');
      expect(
        findLibraryDuplicateGroups([a, b], checkDescriptions: false),
        isEmpty,
      );
      final withDescriptions = findLibraryDuplicateGroups([
        a,
        b,
      ], checkDescriptions: true);
      expect(withDescriptions, hasLength(1));
      expect(withDescriptions.single.memberIds, [1, 2]);
      expect(withDescriptions.single.reasons, {DupReason.description});
    });

    test('tracker-group header comes from the lowest-id member that actually '
        'carries the matched tracker pair, not just the lowest id overall', () {
      const pair = (trackerId: 2, remoteId: '100', remoteTitle: 'Foo Remote');
      // A (id 1, lowest) only joins via title — it carries no tracker pair.
      final a = e(1, 'Foo');
      final b = e(2, 'Foo', tp: [pair]);
      final c = e(3, 'Bar', tp: [pair]);
      final groups = findLibraryDuplicateGroups([
        a,
        b,
        c,
      ], checkDescriptions: false);
      expect(groups, hasLength(1));
      expect(groups.single.header, 'Foo Remote');

      // Order-independence: same input, shuffled, same result.
      final shuffled = findLibraryDuplicateGroups([
        c,
        a,
        b,
      ], checkDescriptions: false);
      expect(shuffled, hasLength(1));
      expect(shuffled.single.header, 'Foo Remote');
      expect(shuffled.single.memberIds, [1, 2, 3]);
    });

    test('tracker-group header ignores a tracker pair nobody else shares — '
        'it must come from the pair that actually links members', () {
      const shared = (trackerId: 2, remoteId: '100', remoteTitle: 'Shared');
      const lone = (trackerId: 1, remoteId: '7', remoteTitle: 'Unrelated');
      // A (lowest id) joins via title and carries only an UNSHARED pair.
      final a = e(1, 'Same Title', tp: [lone]);
      final b = e(5, 'Same Title', tp: [shared]);
      final c = e(6, 'Different Title', tp: [shared]);
      final groups = findLibraryDuplicateGroups([
        a,
        b,
        c,
      ], checkDescriptions: false);
      expect(groups, hasLength(1));
      expect(groups.single.header, 'Shared');
    });

    test('description edge inside an already-formed cluster adds the reason '
        'without erroring', () {
      final a = e(1, 'Twin Star Saga');
      final b = e(2, 'Twin Star Saga', d: 'Also known as Twin Star Saga.');
      final groups = findLibraryDuplicateGroups([
        a,
        b,
      ], checkDescriptions: true);
      expect(groups, hasLength(1));
      expect(groups.single.memberIds, [1, 2]);
      expect(groups.single.reasons, {DupReason.title, DupReason.description});
    });

    test('non-tracker group header is the raw (un-normalized) title of the '
        'lowest-id member', () {
      final a = e(5, 'zzz Zebra');
      final b = e(2, 'ZZZ zebra');
      final groups = findLibraryDuplicateGroups([
        a,
        b,
      ], checkDescriptions: false);
      expect(groups, hasLength(1));
      expect(groups.single.header, 'ZZZ zebra');
    });
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

    test('matches the sync scan with descriptions off', () async {
      final entries = [e(1, 'Foo'), e(2, 'Foo'), e(3, 'Bar'), e(4, 'Bar')];
      final sync = findLibraryDuplicateGroups(
        entries,
        checkDescriptions: false,
      );
      final chunked = await findLibraryDuplicateGroupsChunked(
        entries,
        checkDescriptions: false,
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

    test('scanForDuplicatesChunkedWeb delegates to the chunked scan', () async {
      final entries = [e(1, 'Same'), e(2, 'Same')];
      final result = await scanForDuplicatesChunkedWeb(entries, false);
      expectSameGroups(
        result,
        findLibraryDuplicateGroups(entries, checkDescriptions: false),
      );
    });

    test('scanForDuplicates (compute entry point) matches the sync scan', () {
      final entries = [e(1, 'Same'), e(2, 'Same')];
      final result = scanForDuplicates((entries, false));
      expectSameGroups(
        result,
        findLibraryDuplicateGroups(entries, checkDescriptions: false),
      );
    });
  });
}
