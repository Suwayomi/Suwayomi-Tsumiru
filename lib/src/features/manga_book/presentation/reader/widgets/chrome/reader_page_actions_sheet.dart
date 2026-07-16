// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../../constants/endpoints.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../global_providers/global_providers.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/launch_url_in_web.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../auth/data/auth_credentials_store.dart';
import '../../../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import 'image_clipboard.dart';

/// "Show actions on long tap": long-pressing a reader page opens this
/// page-actions bar instead of the magnifier — a compact horizontal row of
/// icon buttons docked at the bottom. On mobile it's a single-page set:
/// Copy (the image itself, to the clipboard), Share image, Save to gallery.
/// "Set as cover" is omitted — Suwayomi exposes no cover mutation
/// (schema `UpdateMangaPatchInput` is `inLibrary`-only). "Open in web" is shown
/// only on desktop/web, where native image actions can't run, so it's the
/// one universally-working fallback there.
Future<void> showReaderPageActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterPagesDto chapterPages,
  required int pageIndex,
  int? secondaryPageIndex,
  List<int>? spreadPageIndexes,
}) {
  final pages = chapterPages.pages;
  bool isValidPage(int index) => index >= 0 && index < pages.length;
  bool canResolvePage(int index) {
    if (!isValidPage(index)) return false;
    final relative = pages[index];
    if (relative.startsWith('file:')) return true;
    return _buildPageUrl(ref, chapterPages, index, withToken: false) != null &&
        _buildPageUrl(ref, chapterPages, index, withToken: true) != null;
  }

  if (!canResolvePage(pageIndex)) {
    ref.read(toastProvider)?.showError(
          context.l10n.errorSomethingWentWrong,
          instantShow: true,
        );
    return Future<void>.value();
  }

  List<int> actionPageIndexes() {
    final spreadIndexes = spreadPageIndexes;
    if (spreadIndexes != null &&
        spreadIndexes.length == 2 &&
        spreadIndexes[0] != spreadIndexes[1] &&
        spreadIndexes.every(canResolvePage)) {
      return spreadIndexes;
    }
    if (secondaryPageIndex != null &&
        secondaryPageIndex != pageIndex &&
        canResolvePage(secondaryPageIndex)) {
      return [pageIndex, secondaryPageIndex];
    }
    return [pageIndex];
  }

  final pageActionIndexes = actionPageIndexes();
  final firstPageIndex = pageActionIndexes.first;
  final extraPageIndex =
      pageActionIndexes.length == 2 ? pageActionIndexes.last : null;

  String? localPathFor(int index) {
    final relative = pages[index];
    return relative.startsWith('file:')
        ? Uri.parse(relative).toFilePath()
        : null;
  }

  Future<File> resolvePageFile(int index) async {
    final localPath = localPathFor(index);
    if (localPath != null) return File(localPath);
    final shareUrl = _buildPageUrl(ref, chapterPages, index, withToken: false)!;
    final openUrl = _buildPageUrl(ref, chapterPages, index, withToken: true)!;
    return DefaultCacheManager().getSingleFile(
      openUrl,
      key: shareUrl,
      headers: _buildHttpHeaders(ref) ?? const {},
    );
  }

  Future<File> resolveSpreadFile() async => _combineSpreadImages(
        await resolvePageFile(firstPageIndex),
        await resolvePageFile(extraPageIndex!),
      );

  // gal is mobile-only, so both extra actions are gated to real Android/iOS.
  // defaultTargetPlatform (not dart:io Platform) so widget tests can drive the
  // mobile path without faking the production gate.
  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final openUrl =
      _buildPageUrl(ref, chapterPages, firstPageIndex, withToken: true);

  return showModalBottomSheet<void>(
    context: context,
    // Reader overrides bottomSheetTheme to transparent; the Material below
    // supplies its own surface + rounded top.
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheetContext) {
      VoidCallback? copyAction(Future<File> Function() resolve) {
        if (!imageClipboardSupported) return null;
        return () async {
          final toast = ref.read(toastProvider);
          final copiedMsg = context.l10n.copiedImage;
          final errorMsg = context.l10n.errorSomethingWentWrong;
          Navigator.pop(sheetContext);
          try {
            final file = await resolve();
            if (await copyImageToClipboard(file.path)) {
              toast?.show(copiedMsg, instantShow: true);
            } else {
              toast?.showError(errorMsg, instantShow: true);
            }
          } catch (_) {
            toast?.showError(errorMsg, instantShow: true);
          }
        };
      }

      VoidCallback? shareAction(Future<File> Function() resolve) {
        if (!isMobile) return null;
        return () async {
          final toast = ref.read(toastProvider);
          final errorMsg = context.l10n.errorSomethingWentWrong;
          Navigator.pop(sheetContext);
          try {
            final file = await resolve();
            await SharePlus.instance
                .share(ShareParams(files: [XFile(file.path)]));
          } catch (_) {
            toast?.showError(errorMsg, instantShow: true);
          }
        };
      }

      VoidCallback? saveAction(Future<File> Function() resolve) {
        if (!isMobile) return null;
        return () async {
          final toast = ref.read(toastProvider);
          final savedMsg = context.l10n.savedToGallery;
          final errorMsg = context.l10n.errorSomethingWentWrong;
          Navigator.pop(sheetContext);
          try {
            final file = await resolve();
            if (!await Gal.requestAccess()) {
              toast?.showError(errorMsg, instantShow: true);
              return;
            }
            await Gal.putImage(file.path);
            toast?.show(savedMsg, instantShow: true);
          } catch (_) {
            toast?.showError(errorMsg, instantShow: true);
          }
        };
      }

      final hasSpread = extraPageIndex != null;
      final rows = <List<_PageAction>>[];

      void addMobileRow({
        required String copyLabel,
        required String shareLabel,
        required String saveLabel,
        required Key copyKey,
        required Key shareKey,
        required Key saveKey,
        required Future<File> Function() resolve,
      }) {
        final actions = [
          _PageAction(
            key: copyKey,
            icon: Icons.content_copy_rounded,
            label: copyLabel,
            onTap: copyAction(resolve),
          ),
          _PageAction(
            key: shareKey,
            icon: Icons.share_rounded,
            label: shareLabel,
            onTap: shareAction(resolve),
          ),
          _PageAction(
            key: saveKey,
            icon: Icons.save_alt_rounded,
            label: saveLabel,
            onTap: saveAction(resolve),
          ),
        ].where((action) => action.onTap != null).toList();
        if (actions.isNotEmpty) rows.add(actions);
      }

      if (isMobile || imageClipboardSupported) {
        addMobileRow(
          copyLabel: hasSpread
              ? context.l10n.copyFirstPage
              : context.l10n.copyImageToClipboard,
          shareLabel:
              hasSpread ? context.l10n.shareFirstPage : context.l10n.shareImage,
          saveLabel: hasSpread
              ? context.l10n.saveFirstPage
              : context.l10n.saveToGallery,
          copyKey: const ValueKey('reader-page-action-copy-image'),
          shareKey: const ValueKey('reader-page-action-share'),
          saveKey: const ValueKey('reader-page-action-save'),
          resolve: () => resolvePageFile(firstPageIndex),
        );
        if (hasSpread) {
          addMobileRow(
            copyLabel: context.l10n.copySecondPage,
            shareLabel: context.l10n.shareSecondPage,
            saveLabel: context.l10n.saveSecondPage,
            copyKey: const ValueKey('reader-page-action-copy-image-second'),
            shareKey: const ValueKey('reader-page-action-share-second'),
            saveKey: const ValueKey('reader-page-action-save-second'),
            resolve: () => resolvePageFile(extraPageIndex),
          );
          addMobileRow(
            copyLabel: context.l10n.copySpread,
            shareLabel: context.l10n.shareSpread,
            saveLabel: context.l10n.saveSpread,
            copyKey: const ValueKey('reader-page-action-copy-spread'),
            shareKey: const ValueKey('reader-page-action-share-spread'),
            saveKey: const ValueKey('reader-page-action-save-spread'),
            resolve: resolveSpreadFile,
          );
        }
      }

      if (!isMobile && openUrl != null) {
        rows.add([
          _PageAction(
            key: const ValueKey('reader-page-action-open-web'),
            icon: Icons.public_rounded,
            label: context.l10n.openInWeb,
            onTap: () {
              Navigator.pop(sheetContext);
              launchUrlInWeb(context, openUrl, ref.read(toastProvider));
            },
          ),
        ]);
      }

      return _PageActionsSheet(rows: rows);
    },
  );
}

Future<File> _combineSpreadImages(File firstFile, File secondFile) async {
  final tempDir = await getTemporaryDirectory();
  // Sweep spread PNGs left by earlier shares/saves so they don't accumulate —
  // each call leaves at most the one file it's about to hand off.
  await _cleanStaleSpreadTemps(tempDir);
  final outputPath =
      '${tempDir.path}/tsumiru-spread-${DateTime.now().microsecondsSinceEpoch}.png';
  await compute(
    _combineSpreadImagesSync,
    [firstFile.path, secondFile.path, outputPath],
  );
  return File(outputPath);
}

Future<void> _cleanStaleSpreadTemps(Directory tempDir) async {
  try {
    await for (final entity in tempDir.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('tsumiru-spread-') &&
          entity.path.endsWith('.png')) {
        await entity.delete();
      }
    }
  } catch (_) {
    // Best-effort — cleanup must never break a share/save.
  }
}

void _combineSpreadImagesSync(List<String> paths) {
  final first = img.decodeImage(File(paths[0]).readAsBytesSync());
  final second = img.decodeImage(File(paths[1]).readAsBytesSync());
  if (first == null || second == null) {
    throw const FormatException('Could not decode spread image');
  }

  final height = math.max(first.height, second.height);
  final canvas = img.Image(
    width: first.width + second.width,
    height: height,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 255));
  img.compositeImage(
    canvas,
    first,
    dstX: 0,
    dstY: (height - first.height) ~/ 2,
    blend: img.BlendMode.direct,
  );
  img.compositeImage(
    canvas,
    second,
    dstX: first.width,
    dstY: (height - second.height) ~/ 2,
    blend: img.BlendMode.direct,
  );

  File(paths[2]).writeAsBytesSync(img.encodePng(canvas), flush: true);
}

/// Builds the fully-qualified page image URL the reader would fetch, mirroring
/// [ServerImage]'s URL assembly (base + relative path, optional ui_login
/// `?token=`). Returns null for out-of-range or offline (`file://`) pages.
String? _buildPageUrl(
  WidgetRef ref,
  ChapterPagesDto chapterPages,
  int pageIndex, {
  required bool withToken,
}) {
  final pages = chapterPages.pages;
  if (pageIndex < 0 || pageIndex >= pages.length) return null;
  final relative = pages[pageIndex];
  if (relative.startsWith('file:')) return null; // downloaded page, no URL

  final base = Endpoints.baseApi(
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
    appendApiToUrl: false,
  );
  var url = "$base$relative";

  if (withToken && ref.read(authTypeKeyProvider) == AuthType.uiLogin) {
    final token =
        ref.read(authCredentialsStoreProvider).value?.uiAccessToken;
    if (token != null && token.isNotEmpty) {
      final sep = url.contains('?') ? '&' : '?';
      url = "$url${sep}token=${Uri.encodeQueryComponent(token)}";
    }
  }
  return url;
}

/// The auth headers [ServerImage] attaches when fetching a page: basic auth →
/// `Authorization`; simple-login → the session cookie; ui_login → none (the
/// token rides in the URL query instead). Mirrors [ServerImage.build].
Map<String, String>? _buildHttpHeaders(WidgetRef ref) {
  final authType = ref.read(authTypeKeyProvider);
  if (authType == AuthType.basic) {
    final basicToken = ref.read(credentialsProvider).value;
    if (basicToken != null) return {"Authorization": basicToken};
  } else if (authType == AuthType.simpleLogin) {
    return ref
        .read(authCredentialsStoreProvider)
        .value
        ?.simpleLoginCookieHeader;
  }
  return null;
}

class _PageActionsSheet extends StatelessWidget {
  const _PageActionsSheet({
    required this.rows,
  });

  final List<List<_PageAction>> rows;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final action in rows[rowIndex])
                        _ActionButton(action: action),
                    ],
                  ),
                  if (rowIndex != rows.length - 1) const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageAction {
  const _PageAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final _PageAction action;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton(
        key: action.key,
        onPressed: action.onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: 26),
            const SizedBox(height: 8),
            Text(
              action.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: context.textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}
