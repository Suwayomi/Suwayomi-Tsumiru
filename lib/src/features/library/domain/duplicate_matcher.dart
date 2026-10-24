/// Library-identity duplicate matching (#117/#118) — pure Dart, no Flutter.
/// Ports Suwayomi-WebUI's enhancedCleanup semantics; deliberately stricter
/// than Komikku's substring LIKE (design 2026-07-24, decision 1).
library;

import 'dart:async';

import 'title_fold.dart';

final _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String normalizeTitle(String raw) =>
    foldTitleCompat(raw).toLowerCase().replaceAll(_nonAlnum, ' ').trim();

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

/// Shorter titles are too generic for description substring matching.
const int kMinDescriptionMatchTitleLength = 4;

/// Space padding prevents matching "fire" inside "bonfire".
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

/// Only bindings shared by distinct members connect the cluster.
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

/// Recompute all real edges; union provenance omits edges that did not join clusters.
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

/// Use the lowest-id member's lowest shared tracker pair; unrelated bindings cannot name the group.
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

// Title/tracker edges are transitive; description edges may only attach or pair free entries once.
typedef _Stage1 = ({
  Map<int, List<int>> memberIndicesByRoot,
  Map<int, Set<DupReason>> reasonsByRoot,
  Map<int, int> rootByIndex,
});

/// Title and tracker equivalence edges may chain transitively.
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

  // Singletons stay outside this map so description matching can still pair them.
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

  // Break header ties by member id because List.sort is unstable.
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
    // Normalize once per entry to keep NFKC/regex work out of the O(n²) loop.
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

    // Consumed free entries become dead ends so description attachments never chain.
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

/// Entries processed between cooperative yields on web.
const int kDuplicateScanWebChunkSize = 200;

/// Yields during the O(n²) pass because compute() runs on the main thread on web.
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

    // Consumed free entries become dead ends so description attachments never chain.
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

/// Top-level isolate entry point avoids capturing non-transferable closure state.
List<DupGroup> scanForDuplicates((List<DupEntry>, bool) args) {
  final (entries, checkDescriptions) = args;
  return findLibraryDuplicateGroups(
    entries,
    checkDescriptions: checkDescriptions,
  );
}

/// Uses cooperative yields because web has no worker isolates.
Future<List<DupGroup>> scanForDuplicatesChunkedWeb(
  List<DupEntry> entries,
  bool checkDescriptions,
) => findLibraryDuplicateGroupsChunked(
  entries,
  checkDescriptions: checkDescriptions,
);
