# Reader

The reader is central (Tsumiru is webtoon/manhwa-first). It renders pages from the server, supports seven reading modes, pinch-to-zoom, gesture navigation, page-progress tracking, and seamless multi-chapter loading in webtoon/infinity mode.

## Key files

| Path | Responsibility |
|---|---|
| `.../reader/reader_screen.dart` | Entry; resolves `ReaderMode`, dispatches to continuous or single-page mode |
| `.../reader/controller/reader_controller.dart` | `chapterProvider`, `chapterPagesProvider` |
| `.../reader/widgets/reader_wrapper.dart` | Scaffold: AppBar, bottom sheet (slider + chapter nav + settings drawer), keyboard/volume listeners, magnifier, gesture handlers; `_PageViewEnhancer`, `ReaderView` |
| `.../reader_mode/continuous_reader_mode.dart` | Non-infinity continuous (webtoon, continuousVertical, continuousHorizontal*) via `ScrollablePositionedList` |
| `.../reader_mode/single_page_reader_mode.dart` | Paged reader via `PageView` (prefetch ±2) |
| `.../reader_mode/infinity_continuous_reader_mode.dart` | Router: infinity+vertical → `MultiChapterContinuousReaderMode`; else single-chapter SPL fallback |
| `.../infinity_continuous/multichapter_continuous_reader_mode.dart` | The real webtoon-infinity reader: dynamic adjacent-chapter loading, page-height measurement, prepend re-anchor |
| `.../infinity_continuous/measure_size.dart` | `MeasureSize` — reports rendered size to cache true page heights (prevents scroll-snap) |
| `.../infinity_continuous/infinity_continuous_{config,utils,navigation,feedback}.dart` | Constants, helpers, navigation, chapter-load snackbars + separator |
| `.../reader/widgets/directional_swipe_gesture_handler.dart` | Swipe-to-chapter-nav / simple boundary-swipe recognizers |
| `.../reader/widgets/reader_navigation_layout/` | Tap-zone layouts: edge, kindlish, lShaped, rightAndLeft, disabled |
| `lib/src/widgets/zoom/scroll_offset_to_scroll_controller.dart` | Adapts SPL's `ScrollOffsetController` to a `ScrollController` for `zoom_view` |

## Reader modes

`ReaderMode` (`constants/enum.dart`): `defaultReader`, `continuousVertical`, `singleHorizontalLTR`, `singleHorizontalRTL`, `continuousHorizontalLTR`, `continuousHorizontalRTL`, `singleVertical`, `webtoon`. **Default: `webtoon`.**

`ReaderScreen` switches on `manga.metaData.readerMode ?? globalDefault` (per-manga override via `MangaMetaKeys`):

| Mode | Widget | Mechanism |
|---|---|---|
| `webtoon` | `ContinuousReaderMode` (no separator) → may delegate to `MultiChapterContinuousReaderMode` | SPL vertical, no gaps |
| `continuousVertical` | `ContinuousReaderMode` (separator, never infinity) | SPL, 16px gaps |
| `continuousHorizontal*` | `ContinuousReaderMode` (horizontal ± reverse) | SPL horizontal |
| `single*` | `SinglePageReaderMode` | `PageView` |

**Continuous scroll:** `ScrollablePositionedList.separated`; `initialScrollIndex = chapter.lastPageRead`; `minCacheExtent = viewport*2`; position listener with an 800ms debounce to suppress programmatic jumps; "most visible" page picked by greatest visible fraction > 0.4; special case forces last page when its trailing edge ≤ 1.0 (fixes mark-as-read for short final images).

**Page-height caching (infinity):** each image wrapped in `MeasureSize`; first rendered height cached per image URL; re-entry uses the cached height to prevent strip collapse + backward snap.

## Pinch-to-zoom

`zoom_view` package. Continuous modes wrap the SPL in `ZoomView` with a `ScrollOffsetToScrollController` adapter; `maxScale 5.0`, `doubleTapDrag`, **`forceHoldOnPointerDown: true`** (so the scale recognizer wins the arena vs SPL/PageView drag — closes #256). Paged mode wraps `PageView` directly. Mobile-only (`!kIsWeb && (Android||iOS)`). Setting: `pinchToZoomProvider` (`DBKeys.pinchToZoom`, default `true`), read via `ref.read` (mid-session change needs reload).

## Reader settings / overlay

Overlay visibility is `useState` in `ReaderWrapper` (initial from `readerInitialOverlayProvider`), toggled by tap. Settings drawer: mode, nav layout, padding, magnifier size — written back per-manga via `patchMangaMeta`.

Reader DBKeys: `readerMode` (webtoon), `readerPadding` (0.0), `readerMagnifierSize` (1.0), `readerNavigationLayout` (disabled), `swipeToggle` (true), `lastPageSwipeEnabled` (false), `infinityScrollingMode` (false), `readerOverlay` (true), `pinchToZoom` (true), `readerIgnoreSafeArea` (false). Per-manga overrides via `MangaMetaKeys` take precedence.

Page-progress: `onPageChanged` debounces 2s then `putChapter` (`lastPageRead`); final page fires immediately with `isRead: true, lastPageRead: 0`. Uses actual loaded page count, not metadata.

## Gotchas / tech debt

- **Three near-identical continuous implementations** (`ContinuousReaderMode`, the infinity-off fallback, `MultiChapterContinuousReaderMode`) — scroll fixes must be applied to all or they diverge again.
- **800ms `programmaticNavigationDelay`** blocks programmatic nav (incl. slider) while scrolling; slider uses `forceNavigation: true` + a 300ms reset that can race.
- **Prepend re-anchor is one-frame deferred** — on a slow device SPL may not register the new `itemCount` in that frame → viewport snaps to wrong content.
- **`_PageViewEnhancer._checkBoundarySwipe` is dead code** (`return;`).
- **Overscroll chapter nav can fire on momentum** (300ms window can expire before animation settles).
- **`infinityScrollingMode` toggle only shows when the global default is `webtoon`** — hidden if global is `continuousVertical` but per-manga is `webtoon`.
- **`minVisibleAreaThreshold = 0.4` is duplicated** in `_ScrollConfig` and `InfinityContinuousConfig` (not shared).
- **Requires the pinned `scrollable_positioned_list` fork** (exposes `ScrollOffsetController.position`) — won't compile against pub.dev.
