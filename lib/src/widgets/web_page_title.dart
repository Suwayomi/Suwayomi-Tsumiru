// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../features/manga_book/presentation/reader/controller/reader_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/extensions/custom_extensions.dart';

String webRouteTitle(
  AppLocalizations l10n,
  Uri uri, {
  String? mangaTitle,
  String? chapterName,
}) {
  final appTitle = l10n.appTitle;
  String titled(String label) => '$label - $appTitle';
  final segments = uri.pathSegments;
  if (segments.length >= 4 &&
      segments.first == 'manga' &&
      segments[2] == 'chapter') {
    if (mangaTitle == null) return appTitle;
    final chapter = chapterName;
    return chapter == null
        ? titled(mangaTitle)
        : '$mangaTitle: $chapter - $appTitle';
  }
  if (segments.length >= 2 && segments.first == 'manga') {
    final title = mangaTitle;
    return title == null ? appTitle : titled(title);
  }
  final screen = switch (segments) {
    ['library', ...] => l10n.library,
    ['updates'] => l10n.updates,
    ['history'] || ['more', 'history'] => l10n.history,
    ['downloads'] => l10n.downloads,
    ['upcoming'] => l10n.upcoming,
    ['source', ...] => l10n.sources,
    ['extension'] => l10n.extensions,
    ['migrate'] || ['migration', ...] => l10n.migrate,
    ['global-search'] => l10n.globalSearch,
    ['library-duplicates'] => l10n.duplicatedEntries,
    ['library-update-errors'] => l10n.libraryUpdateErrors,
    ['source-filter'] => l10n.browse,
    ['recommends', ...] => l10n.recommendations,
    ['more'] => l10n.more,
    ['more', 'about'] => l10n.about,
    ['more', 'connection'] => l10n.connection,
    ['more', 'account', ...] => l10n.accountTitle,
    ['more', 'settings'] => l10n.settings,
    ['more', 'settings', 'library', 'edit-categories'] => l10n.categories,
    ['more', 'settings', 'library'] => l10n.library,
    ['more', 'settings', 'browse', 'extension-store'] => l10n.extensionStores,
    ['more', 'settings', 'browse'] => l10n.browse,
    ['more', 'settings', 'reader'] => l10n.reader,
    ['more', 'settings', 'appearance'] => l10n.appearance,
    ['more', 'settings', 'general'] => l10n.general,
    ['more', 'settings', 'backup'] => l10n.backup,
    ['more', 'settings', 'server'] => l10n.server,
    ['more', 'settings', 'downloads'] => l10n.downloads,
    ['more', 'settings', 'offline'] => l10n.onDeviceDownloads,
    ['more', 'settings', 'notifications'] => l10n.notifications,
    ['more', 'settings', 'tracking'] => l10n.tracking,
    ['more', 'settings', 'syncyomi'] => l10n.syncyomi,
    ['more', 'settings', 'koreader-sync'] => l10n.koreaderSync,
    ['more', 'settings', 'hotkeys'] => l10n.keyboardShortcuts,
    _ => null,
  };
  return screen == null ? appTitle : titled(screen);
}

class WebPageTitle extends ConsumerWidget {
  const WebPageTitle({super.key, required this.uri, required this.child});

  final Uri uri;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb) return child;
    final segments = uri.pathSegments;
    String? mangaTitle;
    String? chapterName;
    if (segments.length >= 2 && segments.first == 'manga') {
      final mangaId = int.tryParse(segments[1]);
      final manga = mangaId == null
          ? null
          : ref.watch(mangaWithIdProvider(mangaId: mangaId)).value;
      mangaTitle = manga?.title;
      if (segments.length >= 4 && segments[2] == 'chapter') {
        final chapterId = int.tryParse(segments[3]);
        chapterName = chapterId == null
            ? null
            : ref.watch(chapterProvider(chapterId: chapterId)).value?.name;
      }
    }
    return Title(
      title: webRouteTitle(
        context.l10n,
        uri,
        mangaTitle: mangaTitle,
        chapterName: chapterName,
      ),
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}
