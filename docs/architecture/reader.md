# Reader

The reader is central (Tsumiru is webtoon/manhwa-first). It renders pages from the server, supports eight reading modes, pinch-to-zoom, gesture navigation, page-progress tracking, and seamless multi-chapter loading in webtoon/infinity mode.

## Key files

| Path | Responsibility |
|---|---|
| `.../reader/reader_screen.dart` | Entry; resolves `ReaderMode`, dispatches to continuous or single-page mode |
| `.../reader/controller/reader_controller.dart` | `chapterProvider`, `chapterPagesProvider` |
| `.../reader/widgets/reader_wrapper.dart` | Scaffold: hosts the viewer + `ReaderChrome`, keyboard/volume listeners, magnifier, gesture bridge, `_PageViewEnhancer`, `ReaderView`. Owns chrome `visibility` `useState` + the live `readerPadding`/`magnifierSize` notifiers |
| `.../reader/widgets/chrome/reader_chrome.dart` | Stack host layering overlays + the three chrome bars over the viewer; one 200 ms `AnimationController` drives show/hide + OS-bar sync |
| `.../reader/widgets/chrome/{reader_top_bar,mihon_bottom_controls,reader_side_seekbar}.dart` | The three chrome bars (extracted from the old AppBar/bottom-sheet) |
| `.../reader/widgets/chrome/chrome_extents.dart` | `chromeExtentsNotifierProvider` — measured top/bottom bar insets that position the side seekbar |
| `.../reader/widgets/chrome/{reader_color_overlays,reader_flash_overlay}.dart` | Custom-filter tint overlays + page-change flash (chrome-layer leaves) |
| `.../reader/widgets/chrome/reader_settings_dialog.dart` | `showReaderSettingsSheet` custom modal route + 3-tab `ReaderSettingsDialog` (replaced the endDrawer) |
| `.../reader/widgets/chrome/tabs/{reading_mode_tab,general_tab,custom_filter_tab}.dart` | The three settings tabs |
| `.../reader/controller/reader_settings_model.dart` | `ReaderSettingsModel(mangaId)` — resolved settings + all setters (per-series meta patch / global write) |
| `.../reader/controller/reader_setting.dart` | `ReaderSetting<T>` descriptor: scope + per-series key + global provider + fallback |
| `.../reader/controller/reader_mode_adapter.dart` | `ReaderModeAdapter` — maps the frozen 8-value `ReaderMode` ↔ Mihon-parity chips |
| `.../reader/controller/reader_preview_channel.dart` | Ephemeral `ValueNotifier` draft channels for live filter preview |
| `.../reader_mode/continuous_reader_mode.dart` | Non-infinity continuous (webtoon, continuousVertical, continuousHorizontal*) via `ScrollablePositionedList` |
| `.../reader_mode/single_page_reader_mode.dart` | Paged reader host: resolves effective settings, builds spread mapping, prefetches ±2 |
| `.../reader_mode/paged_reader_viewport.dart` | Custom paged viewport: pointer input, page snapping, per-display zoom/pan, tap zones, boundary chapter navigation |
| `.../reader_mode/{paged_spread_mapping,double_page_view}.dart` | Raw-page ↔ display-entry mapping plus single/double/split-wide rendering |
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
| `single*` | `SinglePageReaderMode` | Custom `PagedReaderViewport` |

**Continuous scroll:** `ScrollablePositionedList.separated`; `initialScrollIndex = chapter.lastPageRead`; `minCacheExtent = viewport*2`; position listener with an 800ms debounce to suppress programmatic jumps; "most visible" page picked by greatest visible fraction > 0.4; special case forces last page when its trailing edge ≤ 1.0 (fixes mark-as-read for short final images).

**Paged reader:** `PagedReaderViewport` is a custom `Listener` + `Stack`, not `PageView`. It keeps the current/previous/next display entries mounted, translates them by an `AnimationController`, and reports raw page indexes back through `SpreadMapping` so read tracking and the seekbar still address chapter pages. It renders entries through `DoublePageView`, so single page, double-page spread, split-wide halves, rotate-wide, center margin, and crop borders all share the same `ServerImage` path. `ReaderWrapper` passes tap/long-press/chapter-boundary callbacks through `ReaderInputScope`; when the viewport owns gestures, the overlay tap-zone widget is skipped.

**Page-height caching (infinity):** each image wrapped in `MeasureSize`; first rendered height cached per image URL; re-entry uses the cached height to prevent strip collapse + backward snap.

## Pinch-to-zoom

Continuous modes wrap the SPL in `ZoomView` with a `ScrollOffsetToScrollController` adapter; `maxScale 5.0`, `doubleTapDrag`, **`forceHoldOnPointerDown: true`** (so the scale recognizer wins the arena vs SPL drag — closes #256). Paged mode does not use `zoom_view`: `PagedReaderViewport` owns pointer input and keeps a `_PageZoomController` per display entry. Paged pinch, double-tap zoom, disable zoom-in/out, automatic landscape zoom, zoom-start, and navigate-to-pan are read from `ReaderSettingsModel` and apply live while the reader is mounted.

## Reader chrome

`ReaderChrome` (`chrome/reader_chrome.dart`) is a `Stack`-based host layered, bottom→top: **viewer** (passed as content) < **`ReaderColorOverlays`** (custom-filter tints — only the page beneath) < **`ReaderFlashOverlay`** (page-change flash) < **top bar / side seekbar / bottom controls**. The overlays are leaf siblings of the viewer and never touch the frozen reader engines.

All three bars are **always mounted**. A single **200 ms `AnimationController`** drives show/hide: `SlideTransition` + `FadeTransition` on top/bottom, `FadeTransition` only on the side seekbar. Slide runs the full 200 ms on `Curves.fastOutSlowIn`; fade completes in ~150 ms (an `Interval(0, 0.75)`) for a snappier feel. `IgnorePointer` when dismissed so hidden bars don't eat taps. `visibility` (a `useState` owned by `ReaderWrapper`) is the single source of truth; the controller is a pure render concern driven from it.

**OS system-bar sync (C1):** an `AnimationStatus` listener slaves the OS bars to the animation — `forward` → `edgeToEdge` (status bar appears *with* the sliding top bar); `dismissed` → `hiddenChromeUiMode(fullscreen)` (hides *after* the slide-out). The old `visibility→SystemUiMode` effect in `reader_wrapper.dart` was removed; this listener is the sole driver.

**A16 edge-to-edge:** targetSdk 36 forces edge-to-edge and ignores `statusBar`/`navBar` colors, so we don't set them — the bars paint their own surface *behind* the system bars (nav-inset padding lives INSIDE `MihonBottomControls`, so it slides as one rigid unit). Kept: icon brightness + `contrastEnforced: false` (kills the 3-button-nav scrim). All chrome surfaces use the uniform `readerNavSurface(cs)` token (`utils/theme/brand.dart`: surface @0.9 dark / 0.95 light, Komikku values).

**Side-seekbar positioning:** `chromeExtentsNotifierProvider` holds the measured `topInset` (status-bar inset + top-bar height) and `bottomInset` (nav inset + bottom-bar height, baked in). The seekbar `Positioned` derives `top`/`bottom` from these + 8 dp, so it never overlaps a bar. Hidden when `forceHorizontalSeekbar` is on (the horizontal bottom seekbar then serves all modes). `leftHandedVerticalSeekbar` flips it to the left edge.

## Reader settings sheet

`showReaderSettingsSheet` opens a **custom `_ReaderSettingsSheetRoute`** (a `ModalBottomSheetRoute` subclass) — needed because `showModalBottomSheet` can't do a **mutable `barrierColor`**. The route exposes a `barrierColor` setter that calls `changedInternalState()`; `readerSettingsPreviewProvider` (driven by the `TabController` listener) remaps the scrim live: the Custom-filter tab (index 2) goes transparent + hides the chrome (Komikku `onHideMenus`) so the page shows through. The barrier stays a real gesture-blocking barrier on every tab (C2), so drags never leak to the viewer.

Three tabs: **Reading mode**, **General**, **Custom filter**. The sheet is a `DraggableScrollableSheet`; its scroll controller is deliberately attached to nothing — each tab owns its own `primary: false` scroll view (I7: sharing it crashes with "attached to multiple scroll views").

**Dismiss/commit contract (C3):** `showReaderSettingsSheet` owns one idempotent `dismiss()` run via `Future.whenComplete` on every close path — closes the preview subscription, flushes any interrupted slider draft to the model, clears the draft channels, restores `visibility` to its pre-open value, and invalidates the preview provider.

## Settings model

`ReaderSetting<T>` (`reader_setting.dart`) declares each setting once: `scope` (global / perSeries), optional `perSeriesKey` (a `MangaMetaKeys`), optional `global` provider, and a `fallback`. Resolution is **`perSeries ?? global ?? fallback`** (`resolveWith(ref, perSeries)` watches the live global). `global` is null for the two **sentinel-backed** settings (mode / nav-layout) where "no override" is itself a stored state the engine resolves — keeps "Default" representable (§2.5).

`ReaderSettingsModel(mangaId)` (`@riverpod`, family `readerSettingsModelProvider` / alias `readerEffectiveSettingsProvider`) seeds from `mangaWithIdProvider` meta and exposes every setter. Per-series-capable setters take `{bool perSeries = true}`: **ON** patches manga meta (`_patchMeta` → await, then invalidate, `keepAlive` across the write); **OFF** ("For this series" toggle off) is the global path — `deleteMangaMeta` (a GraphQL mutation added this branch) removes the per-series override, then writes the global provider via a build-captured notifier (the ref-safety order). A Default chip + OFF only deletes the override (the global sentinel is never written).

## Reading-mode reconciliation

The stored `ReaderMode` enum stays **frozen at 8 values** (byte-for-byte). `ReaderModeAdapter` (`reader_mode_adapter.dart`) is pure presentation: it maps 6 of the 8 modes to Mihon-parity `ReadingModeChip`s (Default / Paged LTR / Paged RTL / Paged vertical / Long strip / Long strip + gaps). The two `continuousHorizontal*` modes are **orphans** with no parity chip — the sheet surfaces them as a dedicated **"legacy" chip** (`isLegacyOrphan`); tapping any parity chip is the only path *off* a legacy mode (`fromChip` never emits an orphan).

**Auto Webtoon** (`controller/auto_webtoon.dart`): when the resolved mode is `defaultReader`, `detectsWebtoon({genres, sourceName})` (a pure port of Mihon `MangaType.kt`) may override the reader to webtoon for that **session only** — the meta is never written (gate mirrors `ReaderActivity.kt`).

## Preview isolation

Slider drags in the Custom-filter tab must not rebuild the viewer or the tab. `reader_preview_channel.dart` holds two ephemeral `ValueNotifier<int?>` draft channels (brightness −75..100, packed-ARGB color filter). `onChanged` writes **only** the notifier; the filter overlays listen to `draft ?? committed`, so just that leaf subtree repaints. `onChangeEnd` (or sheet dismiss) commits to the provider and clears the draft.

`ReaderColorOverlays` uses **`BackdropFilter(ColorFilter)`** (not a leaf `ColorFiltered`) — a leaf only filters its own child, never the viewer pixels beneath it. Grayscale/invert compose as 4×5 color matrices (Komikku `getCombinedPaint`, grayscale-first); the blended color rect uses `ColorFilter.mode(color, blendMode)`; negative brightness is a black `ColoredBox` at `abs(value)/100`.

Reader DBKeys: `readerMode` (webtoon), `readerPadding` (0.0), `readerMagnifierSize` (1.0), `readerNavigationLayout` (disabled), `swipeToggle` (true), `lastPageSwipeEnabled` (false), `infinityScrollingMode` (false), `readerOverlay` (true), `pinchToZoom` (true), `readerIgnoreSafeArea` (false). Per-manga overrides via `MangaMetaKeys` take precedence. Many more zoom/filter/general keys added this branch (see below); most are settings-complete but engine-inert.

## Settings wiring status

Nearly every reader-experience setting is now consumed by the viewers. The few
that aren't are **hidden from the settings UI** (not shipped as dead toggles) —
each with a concrete architectural blocker below.

**Hidden — engine/architecture blocked** (removed from `reading_mode_tab.dart`):

| Setting(s) | Blocker |
|---|---|
| `dualPageSplitWebtoon` (+`Invert`) | Splitting one strip page into two entries needs a page-list remap (1→2) inside the **frozen** webtoon scroll/index math. |
| `smoothAutoScroll` | No auto-scroll driver exists yet (a webtoon auto-advance feature); the toggle has nothing to modify. |

**Still shown but inert (niche):** `cropBordersGaps` — appears only in the
non-default "Long strip with gaps" mode; its own key isn't read by an engine
(the wired crop uses `cropBorders` / `cropBordersWebtoon`).

**Wired this branch:** custom paged viewport · image scale type · double-page / wide-split / true-dual-spread / center-margin (paged) · paged zoom-start / automatic landscape zoom / navigate-to-pan · webtoon smart-scale (non-infinity) · **auto-crop borders** (decoder-level `CroppedImageProvider` → pure-Dart isolate edge-scan, applied across single/double/split/webtoon engines) · always-show-chapter-transition · smaller tap zones · page-number indicator · animate page transitions · positive custom brightness (`screen_brightness`) · **long-tap page actions** (copy link / open in web / share image / save to gallery) · **draw-under-cutout** (native `MethodChannel` → `layoutInDisplayCutoutMode`) · plus the earlier zoom toggles (double-tap / pinch / disable zoom-out→min 0.5 / disable zoom-in) · rotate-wide (+invert) · background color · seekbar chain + landscape/left-handed · fullscreen · page-change flash · keep-screen-on · auto-webtoon · orientation · tap-invert (4-value) · tap-zone layouts · all custom-filter overlays (grayscale / invert / negative brightness / blended color).

**Crop-borders render path:** `ServerImage(cropBorders: true)` swaps in `CroppedImageProvider` (`reader/crop/`), which fetches the page's encoded bytes through the SAME cache entry (shared `cacheKey` + auth headers via `serverImageRequest`), runs `findContentRect` in a `compute()` isolate (`image` pkg decode → per-edge threshold scan, corner-reference, ≥10%-area guard), and yields the cropped frame via `ui.decodeImageFromPixels`. Because it's an `ImageProvider`, crop composes with rotate/split/double through the existing `imageBuilder`. In the multichapter engine the crop frame decodes under the imageBuilder's own `frameBuilder`, so the reserved-height / `MeasureSize` scroll-anchor contract is untouched.

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
- **FROZEN reader-engine boundary (narrowed):** only the **scroll / position / index math** in `multichapter_continuous_reader_mode.dart` + `reader_chapter_logic.dart` is frozen. Render-only, parametric changes to `ServerImage` in the viewers are allowed (precedent: the multichapter zoom `minScale`/`doubleTapDrag` args, and this branch's `cropBorders:` arg — a render-only decode swap that the imageBuilder's own `frameBuilder` absorbs, leaving the height-reservation math untouched). Anything needing a **webtoon page-list remap** still stays out — see "Settings wiring status".
- **`reader_screen` hook effects must not read inherited widgets inside the effect body** — a `useEffect` that called `context.l10n` fired during hook-init and threw `_debugIsInitHook` (crashed the reader for webtoon series). Resolve l10n/theme/media in `build` and capture the value; only use the captured value inside the effect.
