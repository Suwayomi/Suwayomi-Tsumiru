// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../widgets/emoticons.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../library/presentation/library/controller/library_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../migration/domain/migration_models.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import 'controller/manga_details_controller.dart';
import 'server_web_url.dart';
import 'widgets/big_screen_manga_details.dart';
import 'widgets/chapter_download_presets_button.dart';
import 'widgets/edit_manga_category_dialog.dart';
import 'widgets/manga_chapter_organizer.dart';
import 'widgets/small_screen_manga_details.dart';

class MangaDetailsScreen extends HookConsumerWidget {
  const MangaDetailsScreen({super.key, required this.mangaId, this.categoryId});
  final int mangaId;
  final int? categoryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaProvider = mangaWithIdProvider(mangaId: mangaId);
    final chapterListProvider = mangaChapterListProvider(mangaId: mangaId);
    final chapterListFilteredProvider =
        mangaChapterListWithFilterProvider(mangaId: mangaId);

    final manga = ref.watch(mangaProvider);
    final filteredChapterList = ref.watch(chapterListFilteredProvider);
    final bulkActionsChapterList = ref.watch(
      mangaChapterListForBulkActionsProvider(mangaId: mangaId),
    );
    final firstUnreadChapter = ref.watch(
      firstUnreadInFilteredChapterListProvider(mangaId: mangaId),
    );

    final selectedChapters = useState<Map<int, ChapterDto>>({});

    // Drives the immersive app bar: transparent over the hero, fading to the
    // surface color as the user scrolls past it. Updated from a
    // NotificationListener on the body so only the app bar rebuilds on scroll —
    // never the chapter list.
    final scrollPx = useMemoized(() => ValueNotifier<double>(0.0));
    useEffect(() => scrollPx.dispose, const []);
    final surface = context.theme.scaffoldBackgroundColor;

    // Container (not the widget ref) so deferred invalidations below survive
    // this screen being disposed mid-flight.
    final providerContainer = ProviderScope.containerOf(context, listen: false);

    final mangaRefresh = useCallback(([bool onlineFetch = false]) async {
      await ref.read(mangaProvider.notifier).refresh();
      // Screen may be disposed during the refresh → don't invalidate a dead ref.
      if (!context.mounted) return;
      // Defer past the current frame — this resumes after an await and may land
      // mid-build, which would trip the Riverpod-3 modify-during-build assert.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => providerContainer.invalidate(categoryControllerProvider),
      );
    }, [mangaProvider, providerContainer]);

    final chapterListRefresh = useCallback(
        ([bool onlineFetch = false]) async =>
            await ref.read(chapterListProvider.notifier).refresh(onlineFetch),
        [chapterListProvider]);

    final refresh = useCallback(([onlineFetch = false]) async {
      if (context.mounted && onlineFetch) {
        ref.read(toastProvider)?.show(
              context.l10n.updating,
              withMicrotask: true,
            );
      }
      await mangaRefresh(onlineFetch);
      await chapterListRefresh(onlineFetch);
      if (onlineFetch) {
        // mangaRefresh only invalidates; await the actual refetch and report ITS
        // result. Reading the captured `manga` (stale) or the provider right
        // after invalidation (still loading) would announce "Updated" even when
        // the fetch ultimately failed.
        final result =
            await AsyncValue.guard(() => ref.read(mangaProvider.future));
        if (!context.mounted) return;
        if (result.hasError) {
          ref.read(toastProvider)?.showError(
                context.l10n.errorSomethingWentWrong,
              );
        } else {
          ref.read(toastProvider)?.show(
                context.l10n.updateCompleted,
                withMicrotask: true,
              );
        }
      }
    }, [context, mangaRefresh, chapterListRefresh]);

    useEffect(() {
      // Effect bodies run during build; invalidating a provider there throws.
      if (filteredChapterList.isNotLoading && manga.isNotLoading) {
        Future.microtask(() {
          if (context.mounted) refresh();
        });
      }
      return;
    }, []);

    void startMigration(BuildContext context, int mangaId, dynamic manga) {
      if (manga == null) return;

      // Single-manga migration goes through the same bulk path as the library
      // multi-select — one consistent flow (source picker → list → migrate).
      MigrationBulkConfigRoute(
        $extra: MigrationBulkConfigData(mangaIds: [mangaId]),
      ).push(context);
    }

    void openInBrowser(String url) =>
        launchUrlInWeb(context, url, ref.read(toastProvider));

    // Open the manga's page in the Suwayomi server's own WebUI (vs the source
    // site's realUrl). No-ops if no server is configured.
    void openOnServer() {
      final url = serverMangaWebUrl(ref, mangaId);
      if (url != null) openInBrowser(url);
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && categoryId != null) {
          final id = categoryId!;
          // Defer off the pop's build phase (Riverpod-3 modify-during-build).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            providerContainer.invalidate(libraryMangaListProvider);
            providerContainer.invalidate(categoryMangaListProvider(id));
          });
        }
      },
      child: manga.showUiWhenData(
        context,
        (data) => Scaffold(
          // Immersive hero: the blurred cover backdrop (top of the body) shows
          // through behind a transparent app bar.
          extendBodyBehindAppBar: selectedChapters.value.isEmpty,
          appBar: selectedChapters.value.isNotEmpty
              ? AppBar(
                  leading: IconButton(
                    onPressed: () => selectedChapters.value = ({}),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  title: Text(
                    context.l10n.numSelected(selectedChapters.value.length),
                  ),
                  actions: [
                    IconButton(
                      onPressed: () {
                        final chapterList = [
                          ...?filteredChapterList.value
                        ];
                        selectedChapters.value =
                            ({for (ChapterDto i in chapterList) i.id: i});
                      },
                      icon: const Icon(Icons.select_all_rounded),
                    ),
                    IconButton(
                      onPressed: () {
                        final chapterList = [
                          ...?filteredChapterList.value
                        ];
                        selectedChapters.value = ({
                          for (ChapterDto i in chapterList)
                            if (!selectedChapters.value.containsKey(i.id))
                              i.id: i
                        });
                      },
                      icon: const Icon(Icons.flip_to_back_rounded),
                    ),
                    MultiSelectPopupButton(
                      filteredChapterList: filteredChapterList,
                      selectedChapters: selectedChapters,
                    ),
                  ],
                )
              : PreferredSize(
                  preferredSize: const Size.fromHeight(kToolbarHeight),
                  child: ValueListenableBuilder<double>(
                    valueListenable: scrollPx,
                    builder: (context, px, _) {
                      final t = (px / 160).clamp(0.0, 1.0);
                      return AppBar(
                        // Explicit back button: wrapping the AppBar in a
                        // builder defeats automaticallyImplyLeading.
                        leading: Navigator.of(context).canPop()
                            ? const BackButton()
                            : null,
                        backgroundColor:
                            Color.lerp(Colors.transparent, surface, t),
                        elevation: 0,
                        scrolledUnderElevation: 0,
                        // Scrim under the icons while the bar is transparent
                        // (hero showing); fades out as the bar turns opaque.
                        flexibleSpace: t >= 1
                            ? null
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black
                                          .withValues(alpha: 0.45 * (1 - t)),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                        // Title lives in the hero at the top; fade it into the
                        // bar only once collapsed (avoids a duplicate title).
                        title: Opacity(
                          opacity: t,
                          child: Text(data?.title ?? context.l10n.manga),
                        ),
                        actions: [
                          if (context.isTablet) ...[
                            IconButton(
                              onPressed: () => refresh(true),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                            IconButton(
                              onPressed: () => showDialog(
                                context: context,
                                builder: (context) =>
                                    EditMangaCategoryDialog(mangaId: mangaId),
                              ),
                              icon: const Icon(Icons.category_rounded),
                            ),
                            IconButton(
                              onPressed: () =>
                                  startMigration(context, mangaId, data),
                              icon: const Icon(Icons.swap_horiz_rounded),
                              tooltip: context.l10n.migrate,
                            ),
                            PopupMenuButton<void>(
                              icon: const Icon(Icons.open_in_new_rounded),
                              tooltip: context.l10n.openInWeb,
                              itemBuilder: (context) => [
                                if (data?.realUrl != null)
                                  PopupMenuItem(
                                    onTap: () => openInBrowser(data!.realUrl!),
                                    child:
                                        Text(context.l10n.openSourceInBrowser),
                                  ),
                                PopupMenuItem(
                                  onTap: openOnServer,
                                  child: Text(context.l10n.openOnServer),
                                ),
                              ],
                            )
                          ],
                          ChapterDownloadPresetsButton(
                            chapterList: bulkActionsChapterList,
                            refresh: refresh,
                          ),
                          Builder(
                            builder: (context) => IconButton(
                              onPressed: () {
                                if (context.isTablet) {
                                  Scaffold.of(context).openEndDrawer();
                                } else {
                                  showModalBottomSheet(
                                    context: context,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: KBorderRadius.rT16.radius,
                                    ),
                                    clipBehavior: Clip.hardEdge,
                                    builder: (_) =>
                                        MangaChapterOrganizer(mangaId: mangaId),
                                  );
                                }
                              },
                              icon: const Icon(Icons.filter_list_rounded),
                            ),
                          ),
                          if (!context.isTablet)
                            PopupMenuButton(
                              shape: RoundedRectangleBorder(
                                borderRadius: KBorderRadius.r16.radius,
                              ),
                              icon: const Icon(Icons.more_vert_rounded),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  onTap: () => Future.microtask(
                                    () {
                                      if (!context.mounted) return null;
                                      return showDialog(
                                        context: context,
                                        builder: (context) =>
                                            EditMangaCategoryDialog(
                                                mangaId: mangaId),
                                      );
                                    },
                                  ),
                                  child: Text(context.l10n.editCategory),
                                ),
                                PopupMenuItem(
                                  onTap: () =>
                                      startMigration(context, mangaId, data),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.swap_horiz_rounded),
                                      const SizedBox(width: 8),
                                      Text(context.l10n.migrate),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  onTap: () => refresh(true),
                                  child: Text(context.l10n.refresh),
                                ),
                                if (data?.realUrl != null)
                                  PopupMenuItem(
                                    onTap: () => openInBrowser(data!.realUrl!),
                                    child:
                                        Text(context.l10n.openSourceInBrowser),
                                  ),
                                PopupMenuItem(
                                  onTap: openOnServer,
                                  child: Text(context.l10n.openOnServer),
                                ),
                              ],
                            )
                        ],
                      );
                    },
                  ),
                ),
          endDrawer: Drawer(
            shape: const RoundedRectangleBorder(),
            width: kDrawerWidth,
            child: MangaChapterOrganizer(mangaId: mangaId),
          ),
          floatingActionButton:
              firstUnreadChapter != null && selectedChapters.value.isEmpty
                  ? BrandFab(
                      label: Text(
                        data?.lastReadChapter?.hasReadingProgress == true
                            ? context.l10n.resume
                            : context.l10n.start,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      onPressed: () {
                        ReaderRoute(
                          mangaId: firstUnreadChapter.mangaId,
                          chapterId: firstUnreadChapter.id,
                          showReaderLayoutAnimation: true,
                        ).push(context);
                      },
                    )
                  : null,
          body: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.axis == Axis.vertical) {
                    scrollPx.value = n.metrics.pixels;
                  }
                  return false;
                },
                child: data != null
                    ? context.isTablet
                        ? BigScreenMangaDetails(
                            chapterList: filteredChapterList,
                            manga: data,
                            mangaId: mangaId,
                            onRefresh: refresh,
                            onDescriptionRefresh: mangaRefresh,
                            onListRefresh: chapterListRefresh,
                            selectedChapters: selectedChapters,
                          )
                        : SmallScreenMangaDetails(
                            chapterList: filteredChapterList,
                            manga: data,
                            mangaId: mangaId,
                            onRefresh: refresh,
                            onDescriptionRefresh: mangaRefresh,
                            onListRefresh: chapterListRefresh,
                            selectedChapters: selectedChapters,
                          )
                    : Emoticons(
                        title: context.l10n.noMangaFound,
                        button: TextButton(
                          onPressed: refresh,
                          child: Text(context.l10n.refresh),
                        ),
                      ),
              ),
              if (selectedChapters.value.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MultiChaptersActionsBottomAppBar(
                    afterOptionSelected: chapterListRefresh,
                    selectedChapters: selectedChapters,
                    chapterList: filteredChapterList.value,
                  ),
                ),
            ],
          ),
        ),
        refresh: refresh,
        wrapper: (body) => Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.manga),
          ),
          body: body,
        ),
      ),
    );
  }
}

class MultiSelectPopupButton extends StatelessWidget {
  const MultiSelectPopupButton({
    super.key,
    required this.filteredChapterList,
    required this.selectedChapters,
  });

  final AsyncValue<List<ChapterDto>?> filteredChapterList;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      shape: RoundedRectangleBorder(
        borderRadius: KBorderRadius.r16.radius,
      ),
      icon: const Icon(Icons.more_vert_rounded),
      itemBuilder: (context) => [
        PopupMenuItem(
          onTap: () {
            List<ChapterDto> chapterList = [
              ...?filteredChapterList.value
            ];
            final lastId = selectedChapters.value.keys.last;
            final lastIndex =
                chapterList.lastIndexWhere((chapter) => chapter.id == lastId);
            final maxIndex = min(chapterList.length, lastIndex + 10);
            selectedChapters.value = ({
              ...selectedChapters.value,
              for (int i = lastIndex + 1; i < maxIndex; i++)
                chapterList[i].id: chapterList[i]
            });
          },
          child: Text(context.l10n.selectNext10),
        ),
        PopupMenuItem(
          onTap: () {
            final chapterList = [...?filteredChapterList.value];

            selectedChapters.value = ({
              for (ChapterDto i in chapterList)
                if (!i.isRead.ifNull()) i.id: i
            });
          },
          child: Text(context.l10n.selectUnread),
        ),
        PopupMenuItem(
          onTap: () {
            final chapterList = [...?filteredChapterList.value];
            final selectedChapterIds =
                selectedChapters.value.keys.toList(growable: false);
            final firstSelectedIndex = chapterList.indexWhere(
                (chapter) => chapter.id == selectedChapterIds.firstOrNull);
            final lastSelectedIndex = chapterList.indexWhere(
                (chapter) => chapter.id == selectedChapterIds.lastOrNull);
            final firstIndex = min(firstSelectedIndex, lastSelectedIndex);
            final lastIndex = max(firstSelectedIndex, lastSelectedIndex);

            selectedChapters.value = ({
              for (int i = firstIndex; i <= lastIndex; i++)
                chapterList[i].id: chapterList[i]
            });
          },
          child: Text(context.l10n.selectInBetween),
        ),
      ],
    );
  }
}
