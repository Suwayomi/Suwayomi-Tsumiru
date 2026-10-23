// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../library/presentation/library/controller/library_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../migration/domain/migration_models.dart';
import '../../../offline/data/server_reachability.dart';
import '../../../offline/presentation/server_unreachable_banner.dart';
import '../../../settings/presentation/appearance/widgets/show_recommendations/show_recommendations_tile.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/manga/manga_model.dart';
import '../../widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import 'controller/manga_details_controller.dart';
import 'server_web_url.dart';
import 'widgets/big_screen_manga_details.dart';
import 'widgets/edit_manga_category_dialog.dart';
import 'widgets/manga_chapter_organizer.dart';
import 'widgets/manga_description.dart';
import 'widgets/series_header.dart';
import 'widgets/series_info_column.dart';
import 'widgets/small_screen_manga_details.dart';

class MangaDetailsScreen extends HookConsumerWidget {
  const MangaDetailsScreen({super.key, required this.mangaId, this.categoryId});
  final int mangaId;
  final int? categoryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaProvider = mangaWithIdProvider(mangaId: mangaId);
    final chapterListProvider = mangaChapterListProvider(mangaId: mangaId);
    final chapterListFilteredProvider = mangaChapterListWithFilterProvider(
      mangaId: mangaId,
    );
    final chapterListEntriesProvider = mangaChapterListEntriesProvider(
      mangaId: mangaId,
    );

    final manga = ref.watch(mangaProvider);
    final filteredChapterList = ref.watch(chapterListFilteredProvider);
    final chapterListEntries = ref.watch(chapterListEntriesProvider);
    final firstUnreadChapter = ref.watch(
      firstUnreadInFilteredChapterListProvider(mangaId: mangaId),
    );

    final infoExpansion = useMemoized(SeriesInfoExpansion.new, [mangaId]);
    useEffect(() => infoExpansion.dispose, [infoExpansion]);

    final selectedChapters = useState<Map<int, ChapterDto>>({});
    final selecting = selectedChapters.value.isNotEmpty;
    final offline = ref.watch(serverUnreachableProvider);
    // The series page switches from the phone layout to the two-column one at
    // Material's expanded class (840), all in one step.
    final twoColumn = context.windowSizeClass >= WindowSizeClass.expanded;

    // Esc belongs to the selection, not the global Back hotkey, whatever holds
    // focus on this page (list, selection header, app bar). Focusing the page
    // scope when a selection starts keeps Esc inside it.
    final pageScope = useMemoized(FocusScopeNode.new);
    useEffect(() => pageScope.dispose, [pageScope]);
    final wasSelecting = usePrevious(selecting);
    useEffect(() {
      if (selecting && wasSelecting == false) pageScope.requestFocus();
      return null;
    }, [selecting]);

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
      [chapterListProvider],
    );

    final refresh = useCallback(([onlineFetch = false]) async {
      // This can be invoked as a bulk chapter action's `afterOptionSelected`,
      // reached only after that action's own network round trip — the screen
      // may already be gone by then, and every ref use below assumes it isn't.
      if (!context.mounted) return;
      if (onlineFetch) {
        ref
            .read(toastProvider)
            ?.show(context.l10n.updating, withMicrotask: true);
      }
      await mangaRefresh(onlineFetch);
      // mangaRefresh can no-op on disposal partway through without throwing
      // (it checks context.mounted internally) — but chapterListRefresh has
      // no such guard, so this screen going away during mangaRefresh must be
      // caught here before falling into it.
      if (!context.mounted) return;
      await chapterListRefresh(onlineFetch);
      if (onlineFetch) {
        // mangaRefresh only invalidates; await the actual refetch and report ITS
        // result. Reading the captured `manga` (stale) or the provider right
        // after invalidation (still loading) would announce "Updated" even when
        // the fetch ultimately failed.
        final result = await AsyncValue.guard(
          () => ref.read(mangaProvider.future),
        );
        if (!context.mounted) return;
        if (result.hasError) {
          ref
              .read(toastProvider)
              ?.showError(context.l10n.errorSomethingWentWrong);
        } else {
          ref
              .read(toastProvider)
              ?.show(context.l10n.updateCompleted, withMicrotask: true);
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

    // Leaving this route at the root of the detail shell pops the shell page,
    // which disposes this screen without popping its own route, so PopScope
    // alone would miss it. Mirror the latest data and run the same library
    // bookkeeping on dispose; the flag keeps it to one run per exit.
    final latestManga = useRef(manga);
    latestManga.value = manga;
    final libraryChecked = useRef(false);
    void refreshLibraryAfterExit() {
      if (libraryChecked.value || categoryId == null) return;
      libraryChecked.value = true;
      final id = categoryId!;
      final current = latestManga.value;
      // Every action re-fetches the series; mid-refetch, assume it changed.
      final fresh = current.isLoading ? null : current.value;
      // Defer off the pop's build phase (Riverpod-3 modify-during-build).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!providerContainer.exists(libraryMangaListProvider)) return;
        final listed = providerContainer
            .read(libraryMangaListProvider)
            .value
            ?.where((m) => m.id == mangaId)
            .firstOrNull;
        if (!libraryEntryOutdated(listed, fresh)) return;
        providerContainer.invalidate(libraryMangaListProvider);
        providerContainer.invalidate(categoryMangaListProvider(id));
      });
    }

    useEffect(() => refreshLibraryAfterExit, const []);

    // Native desktop draws the back button and title in the shell bar
    // instead of an app bar. Phone selection swaps the app bar; desktop
    // selection lives in the chapter-column header, so the slot never swaps.
    final topBar = showsMergedTopBar(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) refreshLibraryAfterExit();
      },
      child: manga.showUiWhenData(
        context,
        (data) {
          // The phone AppBar's toolbars, shared with the merged desktop bar so
          // both show the same controls. Medium windows keep the phone body but
          // suppress the AppBar, so the bar must carry these instead.
          final selectionActions = [
            IconButton(
              onPressed: () {
                final chapterList = [...?filteredChapterList.value];
                selectedChapters.value = ({
                  for (ChapterDto i in chapterList) i.id: i,
                });
              },
              icon: const Icon(Icons.select_all_rounded),
            ),
            IconButton(
              onPressed: () {
                final chapterList = [...?filteredChapterList.value];
                selectedChapters.value = ({
                  for (ChapterDto i in chapterList)
                    if (!selectedChapters.value.containsKey(i.id)) i.id: i,
                });
              },
              icon: const Icon(Icons.flip_to_back_rounded),
            ),
            MultiSelectPopupButton(
              filteredChapterList: filteredChapterList,
              selectedChapters: selectedChapters,
            ),
          ];
          final pageActions = [
            if (!twoColumn && data != null)
              IconButton(
                tooltip: context.l10n.webView,
                icon: const Icon(Icons.public_rounded),
                onPressed: () =>
                    MangaDescription.openInBrowser(context, ref, data),
              ),
            if (!twoColumn)
              IconButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    shape: RoundedRectangleBorder(
                      borderRadius: KBorderRadius.rT16.radius,
                    ),
                    clipBehavior: Clip.hardEdge,
                    builder: (_) => MangaChapterOrganizer(mangaId: mangaId),
                    sheetAnimationStyle: context.motionStyle,
                  );
                },
                icon: const Icon(Icons.filter_list_rounded),
              ),
            if (!twoColumn)
              PopupMenuButton(
                shape: RoundedRectangleBorder(
                  borderRadius: KBorderRadius.r16.radius,
                ),
                icon: const Icon(Icons.more_vert_rounded),
                itemBuilder: (context) => [
                  if (ref.watch(showRecommendationsProvider).ifNull(true) &&
                      ref.watch(recommendsInOverflowProvider).ifNull(false))
                    PopupMenuItem(
                      onTap: () => RecommendsRoute(
                        mangaId: mangaId,
                        mangaTitle: data?.title,
                      ).push(context),
                      child: Text(context.l10n.seeRecommendations),
                    ),
                  PopupMenuItem(
                    onTap: () => Future.microtask(() {
                      if (!context.mounted) return null;
                      return showDialog(
                        context: context,
                        builder: (context) =>
                            EditMangaCategoryDialog(mangaId: mangaId),
                        animationStyle: context.motionStyle,
                      );
                    }),
                    child: Text(context.l10n.editCategory),
                  ),
                  PopupMenuItem(
                    onTap: () => startMigration(context, mangaId, data),
                    child: Text(context.l10n.migrate),
                  ),
                  PopupMenuItem(
                    onTap: () => refresh(true),
                    child: Text(context.l10n.refresh),
                  ),
                  if (data?.realUrl != null)
                    PopupMenuItem(
                      onTap: () => openInBrowser(data!.realUrl!),
                      child: Text(context.l10n.openSourceInBrowser),
                    ),
                  PopupMenuItem(
                    onTap: openOnServer,
                    child: Text(context.l10n.openOnServer),
                  ),
                ],
                popUpAnimationStyle: context.motionStyle,
              ),
          ];
          final scaffold = FocusScope(
            node: pageScope,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape &&
                  selectedChapters.value.isNotEmpty) {
                selectedChapters.value = {};
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              extendBodyBehindAppBar:
                  !twoColumn && selectedChapters.value.isEmpty && !offline,
              // Tablet/desktop selection lives in the chapter-column header;
              // only phones get the selection app bar.
              appBar: topBar
                  ? null
                  : selectedChapters.value.isNotEmpty && !twoColumn
                  ? AppBar(
                      leading: IconButton(
                        onPressed: () => selectedChapters.value = ({}),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      title: Text(
                        context.l10n.numSelected(selectedChapters.value.length),
                      ),
                      actions: selectionActions,
                    )
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(kToolbarHeight),
                      child: ValueListenableBuilder<double>(
                        valueListenable: scrollPx,
                        builder: (context, px, _) {
                          final t = (px / 160).clamp(0.0, 1.0);
                          return AppBar(
                            leading: detailNavigationBackButton(context),
                            backgroundColor: twoColumn
                                ? surface
                                : Color.lerp(Colors.transparent, surface, t),
                            elevation: 0,
                            scrolledUnderElevation: 0,
                            // Scrim under the icons while the bar is transparent
                            // (hero showing); fades out as the bar turns opaque.
                            flexibleSpace: twoColumn || t >= 1
                                ? null
                                : DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(
                                            alpha: 0.45 * (1 - t),
                                          ),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                            // Tablets show the title beside the cover, so a
                            // second one in the bar would duplicate it.
                            title: twoColumn
                                ? SeriesAppBarTitle(
                                    title: data?.title ?? context.l10n.manga,
                                  )
                                : Opacity(
                                    opacity: t,
                                    child: Text(
                                      data?.title ?? context.l10n.manga,
                                    ),
                                  ),
                            actions: pageActions,
                          );
                        },
                      ),
                    ),
              endDrawerEnableOpenDragGesture: false,
              floatingActionButton:
                  !twoColumn &&
                      firstUnreadChapter != null &&
                      selectedChapters.value.isEmpty
                  ? BrandFab(
                      label: Text(
                        data?.user.lastReadChapter?.hasReadingProgress == true
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
              // Banner above the content, not over it: the hero owns the whole top
              // of this screen and a floating banner cuts the cover in half.
              body: Column(
                children: [
                  ServerUnreachableBanner(onRetry: refresh),
                  Expanded(
                    child: Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.axis == Axis.vertical) {
                              scrollPx.value = n.metrics.pixels;
                            }
                            return false;
                          },
                          child: data != null
                              ? twoColumn
                                    ? BigScreenMangaDetails(
                                        expansion: infoExpansion,
                                        chapterList: chapterListEntries,
                                        manga: data,
                                        mangaId: mangaId,
                                        onRefresh: refresh,
                                        onDescriptionRefresh: mangaRefresh,
                                        onListRefresh: chapterListRefresh,
                                        selectedChapters: selectedChapters,
                                      )
                                    : SmallScreenMangaDetails(
                                        chapterList: chapterListEntries,
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
                        if (selectedChapters.value.isNotEmpty && !twoColumn)
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
                ],
              ),
            ),
          );
          // Single-column with the merged bar: the phone body has no bar of
          // its own, so the page's own toolbar moves to the shell bar. The
          // selection toolbar swaps in the phone AppBar's selection actions.
          if (topBar && !twoColumn && selectedChapters.value.isNotEmpty) {
            return TopBarSlot(
              slotKey: 'selection',
              content: DesktopTitleSlot(
                leading: IconButton(
                  onPressed: () => selectedChapters.value = ({}),
                  icon: const Icon(Icons.close_rounded),
                ),
                title: Text(
                  context.l10n.numSelected(selectedChapters.value.length),
                ),
                actions: selectionActions,
              ),
              minWidth: titleTopBarSlotMinWidth(selectionActions.length),
              child: scaffold,
            );
          }
          return titleTopBarSlot(
            topBar: topBar,
            leading: detailNavigationBackButton(context),
            title: twoColumn
                ? SeriesAppBarTitle(title: data?.title ?? context.l10n.manga)
                : Text(data?.title ?? context.l10n.manga),
            actions: pageActions,
            child: scaffold,
          );
        },
        refresh: refresh,
        wrapper: (body) {
          final topBar = showsMergedTopBar(context);
          final title = Text(context.l10n.manga);
          final scaffold = Scaffold(
            appBar: topBar ? null : AppBar(title: title),
            body: body,
          );
          return titleTopBarSlot(
            topBar: topBar,
            leading: detailNavigationBackButton(context),
            title: title,
            child: scaffold,
          );
        },
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
      shape: RoundedRectangleBorder(borderRadius: KBorderRadius.r16.radius),
      icon: const Icon(Icons.more_vert_rounded),
      itemBuilder: (context) => [
        PopupMenuItem(
          onTap: () {
            List<ChapterDto> chapterList = [...?filteredChapterList.value];
            final lastId = selectedChapters.value.keys.last;
            final lastIndex = chapterList.lastIndexWhere(
              (chapter) => chapter.id == lastId,
            );
            final maxIndex = min(chapterList.length, lastIndex + 10);
            selectedChapters.value = ({
              ...selectedChapters.value,
              for (int i = lastIndex + 1; i < maxIndex; i++)
                chapterList[i].id: chapterList[i],
            });
          },
          child: Text(context.l10n.selectNext10),
        ),
        PopupMenuItem(
          onTap: () {
            final chapterList = [...?filteredChapterList.value];

            selectedChapters.value = ({
              for (ChapterDto i in chapterList)
                if (!i.user.isRead.ifNull()) i.id: i,
            });
          },
          child: Text(context.l10n.selectUnread),
        ),
        PopupMenuItem(
          onTap: () {
            final chapterList = [...?filteredChapterList.value];
            final selectedChapterIds = selectedChapters.value.keys.toList(
              growable: false,
            );
            final firstSelectedIndex = chapterList.indexWhere(
              (chapter) => chapter.id == selectedChapterIds.firstOrNull,
            );
            final lastSelectedIndex = chapterList.indexWhere(
              (chapter) => chapter.id == selectedChapterIds.lastOrNull,
            );
            final firstIndex = min(firstSelectedIndex, lastSelectedIndex);
            final lastIndex = max(firstSelectedIndex, lastSelectedIndex);

            selectedChapters.value = ({
              for (int i = firstIndex; i <= lastIndex; i++)
                chapterList[i].id: chapterList[i],
            });
          },
          child: Text(context.l10n.selectInBetween),
        ),
        PopupMenuItem(
          onTap: () {
            final chapterList = [...?filteredChapterList.value];
            final selectedIds = selectedChapters.value.keys.toSet();
            final anchorIndex = chapterList.indexWhere(
              (c) => selectedIds.contains(c.id),
            );
            if (anchorIndex < 0) return;
            selectedChapters.value = {
              ...selectedChapters.value,
              for (int i = anchorIndex + 1; i < chapterList.length; i++)
                chapterList[i].id: chapterList[i],
            };
          },
          child: Text(context.l10n.selectBelow),
        ),
      ],
      popUpAnimationStyle: context.motionStyle,
    );
  }
}
