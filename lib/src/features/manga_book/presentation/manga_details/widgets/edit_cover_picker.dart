// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../browse_center/presentation/global_search/controller/source_quick_search_controller.dart';
import '../../../data/cover_search/cover_site_search.dart';
import '../../../domain/manga/manga_model.dart';
import '../controller/manga_details_controller.dart';

final _visibleSites = [
  for (final site in CoverSite.values)
    if (coverSiteVisible(site)) site,
];

/// Grid of candidate covers from installed sources and cover sites, plus a pasted link.
Future<void> showEditCoverPicker(
  BuildContext context,
  WidgetRef ref,
  MangaDto manga,
) {
  if (context.windowSizeClass == WindowSizeClass.compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: context.motionStyle,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final height =
            media.size.height - media.viewPadding.top - media.viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            top: media.viewPadding.top,
            bottom: media.viewInsets.bottom,
          ),
          child: SizedBox(
            height: height <= 0 ? 0 : height,
            child: _EditCoverPicker(manga: manga),
          ),
        );
      },
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
      ),
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: _EditCoverPicker(manga: manga),
        ),
      ),
    ),
  );
}

typedef _PickerCover = ({
  String imageUrl,
  String title,
  String originLabel,
  String saveValue,
  String? coverVersion,
});

typedef _PickerOrigin = ({
  String key,
  String label,
  List<_PickerCover> covers,
  bool answered,
  bool failed,
  VoidCallback retry,
});

class _EditCoverPicker extends HookConsumerWidget {
  const _EditCoverPicker({required this.manga});

  final MangaDto manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController(text: manga.title);
    final linkController = useTextEditingController();
    final query = useState(manga.title);
    final selected = useState<String?>(null);
    final arrivalOrder = useState<List<String>>([]);
    // The grid reuses the user's Global Search scope; it is read-only here.
    ref.watch(globalSearchScopeProvider);
    final submitted = query.value.trim();

    final siteValues = <CoverSite, AsyncValue<List<CoverCandidate>>>{};
    for (final site in _visibleSites) {
      siteValues[site] = ref.watch(
        coverSiteResultsProvider(site, query: submitted),
      );
    }
    final quickSearch = ref.watch(quickSearchResultsProvider(query: submitted));
    final pairs = quickSearch.value ?? const <QuickSearchResults>[];

    final origins = <_PickerOrigin>[
      for (final site in _visibleSites)
        (
          key: 'site:${site.name}',
          label: site.label,
          covers: [
            for (final candidate
                in siteValues[site]!.value ?? const <CoverCandidate>[])
              (
                imageUrl: candidate.coverUrl,
                title: candidate.title,
                originLabel: site.label,
                saveValue: candidate.coverUrl,
                coverVersion: null,
              ),
          ],
          answered: siteValues[site]!.hasValue || siteValues[site]!.hasError,
          failed: siteValues[site]!.hasError,
          retry: () =>
              ref.invalidate(coverSiteResultsProvider(site, query: submitted)),
        ),
      for (final pair in pairs)
        (
          key: 'source:${pair.source.id}',
          label: pair.source.displayName,
          covers: [
            for (final result in pair.mangaList.value ?? const <MangaDto>[])
              (
                imageUrl: result.thumbnailUrl ?? '',
                title: result.title,
                originLabel: pair.source.displayName,
                saveValue: result.thumbnailUrl ?? '',
                coverVersion: result.coverVersion,
              ),
          ],
          answered: pair.mangaList.hasValue || pair.mangaList.hasError,
          failed: pair.mangaList.hasError,
          retry: () => ref.invalidate(
            sourceQuickSearchMangaListProvider(
              pair.source.id,
              query: submitted,
            ),
          ),
        ),
    ];

    // Origins keep their arrival order so covers already shown never move.
    final signature = origins
        .map((origin) => '${origin.key}:${origin.answered ? '1' : '0'}')
        .join('|');
    useEffect(() {
      final next = arrivalOrder.value.toList();
      var changed = false;
      for (final origin in origins) {
        if (origin.answered && !next.contains(origin.key)) {
          next.add(origin.key);
          changed = true;
        }
      }
      if (changed) arrivalOrder.value = next;
      return null;
    }, [signature]);

    final byKey = {for (final origin in origins) origin.key: origin};
    final orderedKeys = [
      for (final key in arrivalOrder.value)
        if (byKey.containsKey(key)) key,
    ];
    final activeKey =
        selected.value != null && byKey.containsKey(selected.value)
        ? selected.value!
        : null;
    final visibleOrigins = activeKey == null
        ? [for (final key in orderedKeys) byKey[key]!]
        : [byKey[activeKey]!];
    final covers = [for (final origin in visibleOrigins) ...origin.covers];
    final pending = [
      for (final origin in visibleOrigins)
        if (!origin.answered) origin,
    ];
    final failed = [
      for (final origin in visibleOrigins)
        if (origin.failed) origin,
    ];
    final showEmpty = covers.isEmpty && pending.isEmpty && failed.isEmpty;
    final currentCover = manga.displayCoverUrl;

    void submitSearch() {
      final next = searchController.text.trim();
      if (next.isEmpty) return;
      if (next == submitted) {
        ref.invalidate(quickSearchResultsProvider(query: submitted));
        for (final site in _visibleSites) {
          ref.invalidate(coverSiteResultsProvider(site, query: submitted));
        }
        return;
      }
      arrivalOrder.value = [];
      selected.value = null;
      query.value = next;
    }

    Future<void> openPreview({
      required String imageUrl,
      required String originLabel,
      required String? title,
      required String saveValue,
      String? coverVersion,
    }) async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _CoverPreviewDialog(
          mangaId: manga.id,
          imageUrl: imageUrl,
          originLabel: originLabel,
          title: title,
          saveValue: saveValue,
          coverVersion: coverVersion,
        ),
      );
      if (saved != true || !context.mounted) return;
      ref.read(toastProvider)?.show(context.l10n.coverUpdated);
      Navigator.of(context).pop();
    }

    Future<void> pasteLink() async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty || !context.mounted) return;
      linkController.text = text;
      linkController.selection = TextSelection.collapsed(offset: text.length);
    }

    final l10n = context.l10n;
    final chips = <Widget>[];
    void addChip({required String? key, required String label}) {
      if (chips.isNotEmpty) chips.add(const SizedBox(width: 8));
      chips.add(
        FilterChip(
          showCheckmark: false,
          label: Text(label),
          selected: activeKey == key,
          onSelected: (_) =>
              selected.value = selected.value == key ? null : key,
        ),
      );
    }

    addChip(key: null, label: l10n.all);
    for (final site in _visibleSites) {
      addChip(key: 'site:${site.name}', label: site.label);
    }
    for (final pair in pairs) {
      if ((pair.mangaList.value ?? const []).isNotEmpty) {
        addChip(
          key: 'source:${pair.source.id}',
          label: pair.source.displayName,
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.editCover,
                  style: context.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: l10n.close,
                icon: const Icon(FluentIcons.dismiss_24_regular),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => submitSearch(),
            decoration: InputDecoration(
              prefixIcon: const Icon(FluentIcons.search_24_regular),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: searchController,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: searchController.clear,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.customCoversTsumiruOnly,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: chips),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: mangaCoverGridDelegate(null),
              itemCount: covers.length + pending.length * 2,
              itemBuilder: (context, index) {
                if (index < covers.length) {
                  final cover = covers[index];
                  final current =
                      cover.saveValue.isNotEmpty &&
                      cover.saveValue == currentCover;
                  return _UrlCoverTile(
                    cover: cover,
                    current: current,
                    onTap: () => openPreview(
                      imageUrl: cover.imageUrl,
                      originLabel: cover.originLabel,
                      title: cover.title,
                      saveValue: cover.saveValue,
                      coverVersion: cover.coverVersion,
                    ),
                  );
                }
                final origin = pending[(index - covers.length) ~/ 2];
                return _PendingCoverTile(label: origin.label);
              },
            ),
          if (failed.isNotEmpty || showEmpty) ...[
            const SizedBox(height: 8),
            for (final origin in failed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.error_circle_24_regular,
                      size: 20,
                      color: context.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.couldntReachSource(origin.label),
                        style: TextStyle(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: origin.retry,
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            if (showEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.noResultFound),
                ),
              ),
          ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            left: false,
            right: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.thumbnailUrl, style: context.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: linkController,
                    builder: (context, value, _) {
                      final link = value.text.trim();
                      final valid = _isHttpUrl(link);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: linkController,
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(
                                  FluentIcons.link_24_regular,
                                ),
                                hintText: 'https://',
                                suffixIcon: link.isEmpty
                                    ? IconButton(
                                        tooltip: l10n.paste,
                                        icon: const Icon(
                                          FluentIcons
                                              .clipboard_paste_24_regular,
                                        ),
                                        onPressed: pasteLink,
                                      )
                                    : IconButton(
                                        icon: const Icon(
                                          FluentIcons.dismiss_24_regular,
                                        ),
                                        onPressed: linkController.clear,
                                      ),
                              ),
                            ),
                          ),
                          if (valid) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => openPreview(
                                imageUrl: link,
                                originLabel: l10n.thumbnailUrl,
                                title: null,
                                saveValue: link,
                              ),
                              child: SizedBox(
                                width: 48,
                                height: 72,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: ServerImage(imageUrl: link),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

class _UrlCoverTile extends StatelessWidget {
  const _UrlCoverTile({
    required this.cover,
    required this.current,
    required this.onTap,
  });

  final _PickerCover cover;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: KBorderRadius.r12.radius,
        side: current
            ? BorderSide(color: context.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => ServerImage(
                imageUrl: cover.imageUrl,
                coverVersion: cover.coverVersion,
                fit: BoxFit.cover,
                memCacheWidth: constraints.hasBoundedWidth
                    ? (constraints.maxWidth *
                              MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(1, 1 << 16)
                    : null,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(0, 1 / 3),
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, OnImage.scrim],
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  dense: true,
                  title: Text(
                    cover.title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: const TextStyle(
                      color: OnImage.text,
                      fontSize: 12,
                      height: 1.5,
                      shadows: [Shadow(color: OnImage.shadow, blurRadius: 4)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: OnImage.scrim,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cover.originLabel,
                  style: const TextStyle(color: OnImage.text, fontSize: 10),
                ),
              ),
            ),
            if (current)
              Positioned(
                top: 4,
                left: 4,
                child: Icon(
                  FluentIcons.checkmark_circle_24_filled,
                  color: context.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingCoverTile extends StatelessWidget {
  const _PendingCoverTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: KBorderRadius.r12.radius,
        side: BorderSide.none,
      ),
      child: Container(
        color: context.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverPreviewDialog extends HookConsumerWidget {
  const _CoverPreviewDialog({
    required this.mangaId,
    required this.imageUrl,
    required this.originLabel,
    required this.title,
    required this.saveValue,
    this.coverVersion,
  });

  final int mangaId;
  final String imageUrl;
  final String originLabel;
  final String? title;
  final String saveValue;
  final String? coverVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saving = useState(false);
    final loadFailed = useState(false);
    useEffect(() {
      loadFailed.value = false;
      var cancelled = false;
      final provider = serverPageImageProvider(
        ref,
        imageUrl,
        coverVersion: coverVersion,
      );
      precacheImage(provider, context).then(
        (_) {},
        onError: (_) {
          if (!cancelled) loadFailed.value = true;
        },
      );
      return () {
        cancelled = true;
      };
    }, [imageUrl, coverVersion]);

    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.editCover),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: KBorderRadius.r12.radius,
                child: ServerImage(
                  imageUrl: imageUrl,
                  coverVersion: coverVersion,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title == null ? originLabel : '$originLabel · $title',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: loadFailed.value || saving.value
              ? null
              : () async {
                  saving.value = true;
                  final saved = await ref
                      .read(mangaCustomCoverProvider(mangaId: mangaId).notifier)
                      .setCover(saveValue);
                  if (!context.mounted) return;
                  if (saved) {
                    Navigator.of(context).pop(true);
                  } else {
                    saving.value = false;
                    ref.read(toastProvider)?.showError(l10n.coverUpdateFailed);
                  }
                },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
