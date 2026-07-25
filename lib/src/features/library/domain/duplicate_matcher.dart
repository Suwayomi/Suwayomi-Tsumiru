/// Library-identity duplicate matching (#117/#118) — pure Dart, no Flutter.
/// Ports Suwayomi-WebUI's enhancedCleanup semantics; deliberately stricter
/// than Komikku's substring LIKE (design 2026-07-24, decision 1).
library;

import 'dart:async';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String normalizeTitle(String raw) =>
    unorm.nfkc(raw).toLowerCase().replaceAll(_nonAlnum, ' ').trim();

typedef TrackerPair = ({int trackerId, String remoteId, String remoteTitle});
typedef DupEntry = ({
  int id,
  String title,
  String? description,
  List<TrackerPair> trackerPairs,
});

List<DupEntry> titleDuplicates({
  required int candidateId,
  required String candidateTitle,
  required List<DupEntry> entries,
}) {
  final normalizedCandidate = normalizeTitle(candidateTitle);
  if (normalizedCandidate.isEmpty) return [];
  return entries
      .where(
        (entry) =>
            entry.id != candidateId &&
            normalizeTitle(entry.title) == normalizedCandidate,
      )
      .toList();
}

/// Below this normalized length, titles are too generic to trust as a
/// description substring match (e.g. "cat" would hit half the library).
const int kMinDescriptionMatchTitleLength = 4;

/// Both sides padded with spaces so containment respects word boundaries
/// ("fire" must not hit inside "bonfire"). [findLibraryDuplicateGroups]
/// precomputes this per entry to keep its pairwise pass off the
/// normalization cost.
String? _paddedNormalizedDescription(String? description) {
  if (description == null || description.isEmpty) return null;
  final normalized = normalizeTitle(description);
  return normalized.isEmpty ? null : ' $normalized ';
}

List<DupEntry> descriptionDuplicates({
  required int candidateId,
  required String candidateTitle,
  required List<DupEntry> entries,
}) {
  final normalizedCandidate = normalizeTitle(candidateTitle);
  if (normalizedCandidate.length < kMinDescriptionMatchTitleLength) return [];
  final paddedCandidate = ' $normalizedCandidate ';
  return entries.where((entry) {
    if (entry.id == candidateId) return false;
    final padded = _paddedNormalizedDescription(entry.description);
    return padded != null && padded.contains(paddedCandidate);
  }).toList();
}

List<DupEntry> trackerDuplicates({
  required int candidateId,
  required List<TrackerPair> candidatePairs,
  required List<DupEntry> entries,
}) => entries
    .where(
      (entry) =>
          entry.id != candidateId &&
          entry.trackerPairs.any(
            (entryPair) => candidatePairs.any(
              (candidatePair) =>
                  candidatePair.trackerId == entryPair.trackerId &&
                  candidatePair.remoteId == entryPair.remoteId,
            ),
          ),
    )
    .toList();

enum DupReason { title, tracker, description }

typedef DupGroup = ({
  String header,
  List<int> memberIds,
  Set<DupReason> reasons,
});

class _UnionFind {
  _UnionFind(int size) : _parent = List.generate(size, (i) => i);

  final List<int> _parent;

  int find(int x) {
    while (_parent[x] != x) {
      _parent[x] = _parent[_parent[x]];
      x = _parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) _parent[rootA] = rootB;
  }
}

String _trackerKey(TrackerPair pair) => '${pair.trackerId}|${pair.remoteId}';

/// Tracker keys held by two or more distinct members — the bindings that
/// actually tie the cluster together, as opposed to a stray binding one
/// member happens to carry.
Set<String> _sharedTrackerKeys(List<DupEntry> members) {
  final holders = <String, Set<int>>{};
  for (final member in members) {
    for (final pair in member.trackerPairs) {
      holders.putIfAbsent(_trackerKey(pair), () => {}).add(member.id);
    }
  }
  return {
    for (final entry in holders.entries)
      if (entry.value.length >= 2) entry.key,
  };
}

/// Which edge kinds are actually present among a cluster's members — a
/// fresh scan rather than provenance-tracking during union, since any two
/// members sharing a title/tracker key are a real edge regardless of which
/// union operation happened to connect the cluster.
Set<DupReason> _reasonsWithinCluster(List<DupEntry> members) {
  final reasons = <DupReason>{};

  final titleCounts = <String, int>{};
  for (final member in members) {
    final norm = normalizeTitle(member.title);
    if (norm.isEmpty) continue;
    titleCounts[norm] = (titleCounts[norm] ?? 0) + 1;
  }
  if (titleCounts.values.any((count) => count >= 2)) {
    reasons.add(DupReason.title);
  }

  if (_sharedTrackerKeys(members).isNotEmpty) {
    reasons.add(DupReason.tracker);
  }

  return reasons;
}

/// Tracker-group header comes from a *shared* pair only — the lowest-id
/// member holding one, then its lowest-(trackerId, remoteId) shared pair.
/// A member that joined via title but carries an unrelated binding must not
/// donate that binding's title as the group header. Always well-defined
/// when the tracker reason is set: some pair is held by two members, and
/// stage-2 attachments only ever add members.
String _headerFor(List<DupEntry> members, Set<DupReason> reasons) {
  final byId = List.of(members)..sort((a, b) => a.id.compareTo(b.id));

  if (reasons.contains(DupReason.tracker)) {
    final shared = _sharedTrackerKeys(members);
    final holder = byId.firstWhere(
      (m) => m.trackerPairs.any((p) => shared.contains(_trackerKey(p))),
    );
    final sharedPairs =
        holder.trackerPairs
            .where((p) => shared.contains(_trackerKey(p)))
            .toList()
          ..sort((a, b) {
            final byTracker = a.trackerId.compareTo(b.trackerId);
            return byTracker != 0
                ? byTracker
                : a.remoteId.compareTo(b.remoteId);
          });
    return sharedPairs.first.remoteTitle;
  }
  return byId.first.title;
}

/// Library-wide duplicate grouping (#117).
///
/// Two-stage on purpose — see the Phase 1 design note this ports:
/// - **Stage 1** unions title + tracker edges via a parent-array
///   union-find. Both relations are true equivalences (normalized-title
///   equality; shared tracker binding), so chaining them transitively is
///   safe.
/// - **Stage 2** (description substring containment) is NOT transitive —
///   two unrelated titles can each appear inside one hub's description
///   without being duplicates of each other. So a description edge only
///   ever attaches a still-free entry to an existing stage-1 cluster, or
///   pairs two free entries into a brand-new 2-member group. Once an entry
///   is touched by stage 2 (attached or paired), it becomes a dead end —
///   it never sources or receives another description edge. This is what
///   stops a hub description from gluing two unrelated clusters together.
typedef _Stage1 = ({
  Map<int, List<int>> memberIndicesByRoot,
  Map<int, Set<DupReason>> reasonsByRoot,
  Map<int, int> rootByIndex,
});

/// Stage 1: union title + tracker edges (both true equivalences, so chaining
/// them transitively is safe). O(n) and never needs to yield, so it's shared
/// verbatim by the sync and chunked entry points below.
_Stage1 _unionStage1(List<DupEntry> entries) {
  final n = entries.length;
  final uf = _UnionFind(n);

  final byNormalizedTitle = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    final norm = normalizeTitle(entries[i].title);
    if (norm.isEmpty) continue;
    byNormalizedTitle.putIfAbsent(norm, () => []).add(i);
  }
  for (final group in byNormalizedTitle.values) {
    for (var k = 1; k < group.length; k++) {
      uf.union(group[0], group[k]);
    }
  }

  final byTrackerKey = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    for (final pair in entries[i].trackerPairs) {
      byTrackerKey.putIfAbsent(_trackerKey(pair), () => []).add(i);
    }
  }
  for (final group in byTrackerKey.values) {
    for (var k = 1; k < group.length; k++) {
      uf.union(group[0], group[k]);
    }
  }

  final clusterIndices = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    clusterIndices.putIfAbsent(uf.find(i), () => []).add(i);
  }

  // root -> mutable member-index list / reasons, real clusters (size >= 2)
  // only; free (still-singleton) indices never enter this map.
  final memberIndicesByRoot = <int, List<int>>{};
  final reasonsByRoot = <int, Set<DupReason>>{};
  final rootByIndex = <int, int>{};
  for (final entry in clusterIndices.entries) {
    if (entry.value.length < 2) continue;
    final root = entry.key;
    memberIndicesByRoot[root] = List.of(entry.value);
    reasonsByRoot[root] = _reasonsWithinCluster(
      entry.value.map((i) => entries[i]).toList(),
    );
    for (final idx in entry.value) {
      rootByIndex[idx] = root;
    }
  }

  return (
    memberIndicesByRoot: memberIndicesByRoot,
    reasonsByRoot: reasonsByRoot,
    rootByIndex: rootByIndex,
  );
}

/// Turns root-clusters + free description pairs into the final sorted
/// [DupGroup] list. Shared by the sync and chunked entry points below.
List<DupGroup> _assembleGroups(
  List<DupEntry> entries,
  Map<int, List<int>> memberIndicesByRoot,
  Map<int, Set<DupReason>> reasonsByRoot,
  List<List<int>> pairGroups,
) {
  final result = <DupGroup>[];
  for (final rootEntry in memberIndicesByRoot.entries) {
    final members = rootEntry.value.map((i) => entries[i]).toList();
    final reasons = reasonsByRoot[rootEntry.key]!;
    result.add((
      header: _headerFor(members, reasons),
      memberIds: members.map((m) => m.id).toList()..sort(),
      reasons: reasons,
    ));
  }
  for (final pair in pairGroups) {
    final members = pair.map((i) => entries[i]).toList();
    const reasons = {DupReason.description};
    result.add((
      header: _headerFor(members, reasons),
      memberIds: members.map((m) => m.id).toList()..sort(),
      reasons: reasons,
    ));
  }

  // Header ties break on lowest member id — List.sort isn't stable.
  result.sort((a, b) {
    final byHeader = a.header.compareTo(b.header);
    return byHeader != 0
        ? byHeader
        : a.memberIds.first.compareTo(b.memberIds.first);
  });
  return result;
}

List<DupGroup> findLibraryDuplicateGroups(
  List<DupEntry> entries, {
  required bool checkDescriptions,
}) {
  final n = entries.length;
  if (n < 2) return [];

  final stage1 = _unionStage1(entries);
  final memberIndicesByRoot = stage1.memberIndicesByRoot;
  final reasonsByRoot = stage1.reasonsByRoot;
  final rootByIndex = stage1.rootByIndex;

  final pairGroups = <List<int>>[];

  if (checkDescriptions) {
    // Normalize once per entry — the pairwise loop below is O(n²) and must
    // not pay NFKC/regex cost per pair.
    final normTitle = List.generate(n, (i) => normalizeTitle(entries[i].title));
    final paddedDescription = List.generate(
      n,
      (i) => _paddedNormalizedDescription(entries[i].description),
    );
    bool titleHitsDescription(int candidateIdx, int targetIdx) {
      final title = normTitle[candidateIdx];
      if (title.length < kMinDescriptionMatchTitleLength) return false;
      final padded = paddedDescription[targetIdx];
      return padded != null && padded.contains(' $title ');
    }

    final orderedIndices = List.generate(n, (i) => i)
      ..sort((a, b) => entries[a].id.compareTo(entries[b].id));

    // Attached-or-paired free indices become dead ends; this is what
    // enforces "attachments never chain".
    final consumedFree = <int>{};

    for (var a = 0; a < orderedIndices.length; a++) {
      for (var b = a + 1; b < orderedIndices.length; b++) {
        final i = orderedIndices[a];
        final j = orderedIndices[b];
        if (!titleHitsDescription(i, j) && !titleHitsDescription(j, i)) {
          continue;
        }

        final rootI = rootByIndex[i];
        final rootJ = rootByIndex[j];
        final deadI = rootI == null && consumedFree.contains(i);
        final deadJ = rootJ == null && consumedFree.contains(j);
        if (deadI || deadJ) continue;

        if (rootI != null && rootJ != null) {
          if (rootI == rootJ) reasonsByRoot[rootI]!.add(DupReason.description);
          continue; // different real clusters — never merge, by design.
        }
        if (rootI != null) {
          memberIndicesByRoot[rootI]!.add(j);
          reasonsByRoot[rootI]!.add(DupReason.description);
          consumedFree.add(j);
          continue;
        }
        if (rootJ != null) {
          memberIndicesByRoot[rootJ]!.add(i);
          reasonsByRoot[rootJ]!.add(DupReason.description);
          consumedFree.add(i);
          continue;
        }
        pairGroups.add([i, j]);
        consumedFree
          ..add(i)
          ..add(j);
      }
    }
  }

  return _assembleGroups(
    entries,
    memberIndicesByRoot,
    reasonsByRoot,
    pairGroups,
  );
}

/// WebUI's chunk-size constant for cooperative-yield loops.
const int kDuplicateScanWebChunkSize = 200;

/// Web has no isolates — `compute()` runs its callback on the same thread —
/// so the O(n²) description pass must yield cooperatively itself, or it
/// freezes the tab for the duration of the scan. Stage 1 (title/tracker)
/// stays the same tight synchronous loop as [findLibraryDuplicateGroups]
/// (it's only O(n)); only the description pass chunks its outer loop at
/// [chunkSize] entries with a zero-duration delay between slices.
Future<List<DupGroup>> findLibraryDuplicateGroupsChunked(
  List<DupEntry> entries, {
  required bool checkDescriptions,
  int chunkSize = kDuplicateScanWebChunkSize,
}) async {
  final n = entries.length;
  if (n < 2) return [];

  final stage1 = _unionStage1(entries);
  final memberIndicesByRoot = stage1.memberIndicesByRoot;
  final reasonsByRoot = stage1.reasonsByRoot;
  final rootByIndex = stage1.rootByIndex;

  final pairGroups = <List<int>>[];

  if (checkDescriptions) {
    final normTitle = List.generate(n, (i) => normalizeTitle(entries[i].title));
    final paddedDescription = List.generate(
      n,
      (i) => _paddedNormalizedDescription(entries[i].description),
    );
    bool titleHitsDescription(int candidateIdx, int targetIdx) {
      final title = normTitle[candidateIdx];
      if (title.length < kMinDescriptionMatchTitleLength) return false;
      final padded = paddedDescription[targetIdx];
      return padded != null && padded.contains(' $title ');
    }

    final orderedIndices = List.generate(n, (i) => i)
      ..sort((a, b) => entries[a].id.compareTo(entries[b].id));

    // Attached-or-paired free indices become dead ends; this is what
    // enforces "attachments never chain". Kept in lockstep with the sync
    // version's stage 2 above — the only difference is the yield below.
    final consumedFree = <int>{};

    for (var a = 0; a < orderedIndices.length; a++) {
      if (a > 0 && a % chunkSize == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      for (var b = a + 1; b < orderedIndices.length; b++) {
        final i = orderedIndices[a];
        final j = orderedIndices[b];
        if (!titleHitsDescription(i, j) && !titleHitsDescription(j, i)) {
          continue;
        }

        final rootI = rootByIndex[i];
        final rootJ = rootByIndex[j];
        final deadI = rootI == null && consumedFree.contains(i);
        final deadJ = rootJ == null && consumedFree.contains(j);
        if (deadI || deadJ) continue;

        if (rootI != null && rootJ != null) {
          if (rootI == rootJ) reasonsByRoot[rootI]!.add(DupReason.description);
          continue; // different real clusters — never merge, by design.
        }
        if (rootI != null) {
          memberIndicesByRoot[rootI]!.add(j);
          reasonsByRoot[rootI]!.add(DupReason.description);
          consumedFree.add(j);
          continue;
        }
        if (rootJ != null) {
          memberIndicesByRoot[rootJ]!.add(i);
          reasonsByRoot[rootJ]!.add(DupReason.description);
          consumedFree.add(i);
          continue;
        }
        pairGroups.add([i, j]);
        consumedFree
          ..add(i)
          ..add(j);
      }
    }
  }

  return _assembleGroups(
    entries,
    memberIndicesByRoot,
    reasonsByRoot,
    pairGroups,
  );
}

/// Top-level so `compute()` can spawn it in a new isolate — a closure would
/// capture non-transferable state and fail across the isolate boundary.
List<DupGroup> scanForDuplicates((List<DupEntry>, bool) args) {
  final (entries, checkDescriptions) = args;
  return findLibraryDuplicateGroups(
    entries,
    checkDescriptions: checkDescriptions,
  );
}

/// Web entry point: no isolates, so route through the self-yielding chunked
/// scan instead of the plain sync one `compute()` uses natively.
Future<List<DupGroup>> scanForDuplicatesChunkedWeb(
  List<DupEntry> entries,
  bool checkDescriptions,
) => findLibraryDuplicateGroupsChunked(
  entries,
  checkDescriptions: checkDescriptions,
);
