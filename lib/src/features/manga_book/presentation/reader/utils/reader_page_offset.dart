// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';

/// Chapter meta key holding the position inside the last read page.
///
/// The page index itself stays in `lastPageRead`, which is what Suwayomi,
/// KOReader sync and other clients read; this only refines it.
const readerPageOffsetMetaKey = 'tsumiru_pageOffset';

/// Where the top of the viewport was inside [page], as a share of the page's
/// height. Page-relative, so it lands on the same artwork on any screen.
@immutable
class ReaderPageOffset {
  const ReaderPageOffset({
    required this.page,
    required this.fraction,
    required this.updatedAt,
  });

  final int page;
  final double fraction;
  final DateTime updatedAt;

  String encode() =>
      '$page:${fraction.toStringAsFixed(4)}:${updatedAt.millisecondsSinceEpoch}';

  static ReaderPageOffset? decode(String? raw) {
    final parts = raw?.split(':');
    if (parts == null || parts.length != 3) return null;
    final page = int.tryParse(parts[0]);
    final fraction = double.tryParse(parts[1]);
    final millis = int.tryParse(parts[2]);
    if (page == null || page < 0 || fraction == null || millis == null) {
      return null;
    }
    if (fraction.isNaN || fraction < 0 || fraction > 1) return null;
    return ReaderPageOffset(
      page: page,
      fraction: fraction,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }

  /// Worth another server write after [previous]: a different page, or a move
  /// of at least 2% of the page.
  bool differsFrom(ReaderPageOffset? previous) =>
      previous == null ||
      previous.page != page ||
      (previous.fraction - fraction).abs() >= 0.02;

  @override
  bool operator ==(Object other) =>
      other is ReaderPageOffset &&
      other.page == page &&
      other.fraction == fraction &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(page, fraction, updatedAt);
}

ReaderPageOffset? readerPageOffsetFromMeta(ChapterDto chapter) =>
    ReaderPageOffset.decode(
      chapter.meta
          .firstWhereOrNull((m) => m.key == readerPageOffsetMetaKey)
          ?.value,
    );

/// Saved offset to resume at on open, or null to open the page at its top.
///
/// An offset only counts while it still points at the chapter's current
/// `lastPageRead`: once KOReader, the web UI or another device moved the
/// progress, the stored offset belongs to an older page and is dropped.
/// Between the local and the server copy, the most recent one wins.
ReaderPageOffset? resolveResumeOffset({
  required ChapterDto chapter,
  ReaderPageOffset? local,
}) {
  if (chapter.user.isRead.ifNull()) return null;
  final page = chapter.user.lastPageRead.getValueOnNullOrNegative();
  return [local, readerPageOffsetFromMeta(chapter)].nonNulls
      .where((o) => o.page == page && o.fraction > 0)
      .sorted((a, b) => b.updatedAt.compareTo(a.updatedAt))
      .firstOrNull;
}

/// Share of the resume page to scroll past on open; see [resolveResumeOffset].
double? resolveResumeFraction({
  required ChapterDto chapter,
  ReaderPageOffset? local,
}) => resolveResumeOffset(chapter: chapter, local: local)?.fraction;

/// Offset from a later server answer that should replace [current], the one
/// the reader resumed at (null when it opened at the page top).
///
/// A downloaded chapter opens from the device catalogue before the server
/// answers, so an offset saved on another device only shows up afterwards. It
/// applies only on the same page the reader opened at and only when it is
/// newer; a move back to the page top on the other device counts too.
ReaderPageOffset? newerServerResume({
  required ChapterDto server,
  required int page,
  ReaderPageOffset? current,
}) {
  if (server.user.isRead.ifNull()) return null;
  if (server.user.lastPageRead.getValueOnNullOrNegative() != page) return null;
  final remote = readerPageOffsetFromMeta(server);
  if (remote == null || remote.page != page) return null;
  if (current == null) return remote.fraction > 0 ? remote : null;
  if (!remote.updatedAt.isAfter(current.updatedAt)) return null;
  if (remote.page == current.page && remote.fraction == current.fraction) {
    return null;
  }
  return remote;
}

/// Device-local copy, so offline reads and an unreachable server still resume.
///
/// Keyed by the configured server, not the active address: moving between
/// the LAN and the external URL reaches the same server and must not lose the
/// offset. Entries written under one of its [aliases] are still read.
class ReaderPageOffsetStore {
  ReaderPageOffsetStore(
    this._preferences,
    this._server, {
    Iterable<String> aliases = const [],
  }) : _aliases = aliases.where((a) => a.isNotEmpty && a != _server).toSet();

  static const _preferencesKey = 'readerPageOffsets';
  static const _maxEntries = 200;

  final SharedPreferences _preferences;
  final String _server;
  final Set<String> _aliases;

  String _key(int chapterId, [String? server]) =>
      '${server ?? _server}|$chapterId';

  Map<String, String> _all() {
    try {
      final raw = _preferences.getString(_preferencesKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );
    } catch (_) {
      return {};
    }
  }

  ReaderPageOffset? read(int chapterId) {
    final all = _all();
    return [_server, ..._aliases]
        .map((server) => ReaderPageOffset.decode(all[_key(chapterId, server)]))
        .nonNulls
        .sorted((a, b) => b.updatedAt.compareTo(a.updatedAt))
        .firstOrNull;
  }

  Future<void> write(int chapterId, ReaderPageOffset offset) async {
    final all = _all()..[_key(chapterId)] = offset.encode();
    // One entry per chapter: drop copies left under another address.
    for (final alias in _aliases) {
      all.remove(_key(chapterId, alias));
    }
    if (all.length > _maxEntries) {
      // Keep the most recently written chapters.
      final kept = all.entries
          .sortedBy<num>(
            (e) =>
                -(ReaderPageOffset.decode(
                      e.value,
                    )?.updatedAt.millisecondsSinceEpoch ??
                    0),
          )
          .take(_maxEntries);
      all
        ..clear()
        ..addEntries(kept);
    }
    await _preferences.setString(_preferencesKey, jsonEncode(all));
  }
}

final readerPageOffsetStoreProvider = Provider<ReaderPageOffsetStore>((ref) {
  final active = ref.watch(serverUrlProvider) ?? '';
  final external = ref.watch(serverExternalUrlProvider) ?? '';
  final lan = ref.watch(serverLanUrlProvider) ?? '';
  return ReaderPageOffsetStore(
    ref.watch(sharedPreferencesProvider),
    external.isNotEmpty ? external : active,
    aliases: [active, lan],
  );
});

/// Writes the offset locally every time and to the chapter meta when it moved
/// enough. Holds no `ref`, so it is safe to call from a widget teardown.
class ReaderPageOffsetSaver {
  ReaderPageOffsetSaver(this._store, this._repository);

  final ReaderPageOffsetStore _store;
  final MangaBookRepository _repository;
  final _pushed = <int, ReaderPageOffset>{};

  /// Seeds what the server already holds so reopening does not rewrite it.
  /// A later, fresher answer from the server replaces an older seed.
  void seed(ChapterDto chapter) {
    final remote = readerPageOffsetFromMeta(chapter);
    if (remote == null) return;
    final known = _pushed[chapter.id];
    if (known == null || remote.updatedAt.isAfter(known.updatedAt)) {
      _pushed[chapter.id] = remote;
    }
  }

  Future<void> save(int chapterId, ReaderPageOffset offset) async {
    try {
      await _store.write(chapterId, offset);
    } catch (_) {}
    if (!offset.differsFrom(_pushed[chapterId])) return;
    _pushed[chapterId] = offset;
    try {
      await _repository.setChapterMeta(
        chapterId: chapterId,
        key: readerPageOffsetMetaKey,
        value: offset.encode(),
      );
    } catch (_) {
      // Offline or server error: the local copy still resumes on this device.
      _pushed.remove(chapterId);
    }
  }
}
