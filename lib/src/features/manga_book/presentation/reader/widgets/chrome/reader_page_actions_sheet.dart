// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

/// Komikku "Show actions on long tap": long-pressing a reader page opens this
/// page-actions bar instead of the magnifier — a compact horizontal row of
/// icon buttons docked at the bottom (Komikku `ReaderPageActionsDialog` /
/// `ActionButton`). On mobile it mirrors Komikku's single-page set exactly:
/// Copy (the image itself, to the clipboard), Share image, Save to gallery.
/// Komikku's "Set as cover" is omitted — Suwayomi exposes no cover mutation
/// (schema `UpdateMangaPatchInput` is `inLibrary`-only). "Open in web" is shown
/// only on desktop/web, where Komikku's image actions can't run, so it's the
/// one universally-working fallback there.
Future<void> showReaderPageActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterPagesDto chapterPages,
  required int pageIndex,
}) {
  final pages = chapterPages.pages;
  if (pageIndex < 0 || pageIndex >= pages.length) {
    ref.read(toastProvider)?.showError(
          context.l10n.errorSomethingWentWrong,
          instantShow: true,
        );
    return Future<void>.value();
  }

  final relative = pages[pageIndex];
  // Downloaded/offline pages are served as `file://` URIs — there's no server
  // URL to copy or open, but the local file can still be shared/saved.
  final localPath =
      relative.startsWith('file:') ? Uri.parse(relative).toFilePath() : null;

  // Token-less URL is copied (avoids leaking the ui_login token into whatever
  // the user pastes into); token-appended URL is opened/fetched locally so it
  // works. Both null for offline pages (handled via [localPath]).
  final shareUrl = _buildPageUrl(ref, chapterPages, pageIndex, withToken: false);
  final openUrl = _buildPageUrl(ref, chapterPages, pageIndex, withToken: true);

  // A server page with no derivable URL is an unexpected state — bail loudly.
  if (localPath == null && (shareUrl == null || openUrl == null)) {
    ref.read(toastProvider)?.showError(
          context.l10n.errorSomethingWentWrong,
          instantShow: true,
        );
    return Future<void>.value();
  }

  // Resolves the on-disk image file for the current page: straight off disk for
  // offline pages, otherwise via the shared image cache (same cacheKey + auth
  // headers ServerImage uses, so it reuses the already-decoded page).
  Future<File> resolvePageFile() async {
    if (localPath != null) return File(localPath);
    return DefaultCacheManager().getSingleFile(
      openUrl!,
      key: shareUrl!,
      headers: _buildHttpHeaders(ref) ?? const {},
    );
  }

  // gal is mobile-only, so both extra actions are gated to real Android/iOS.
  // defaultTargetPlatform (not dart:io Platform) so widget tests can drive the
  // mobile path without faking the production gate.
  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  return showModalBottomSheet<void>(
    context: context,
    // Reader overrides bottomSheetTheme to transparent; the Material below
    // supplies its own surface + rounded top.
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheetContext) => _PageActionsSheet(
      // Komikku's "Copy to clipboard" copies the image itself, not a link.
      // Native ClipData.newUri path is Android-only.
      onCopyImage: !imageClipboardSupported
          ? null
          : () async {
              final toast = ref.read(toastProvider);
              final copiedMsg = context.l10n.copiedImage;
              final errorMsg = context.l10n.errorSomethingWentWrong;
              Navigator.pop(sheetContext);
              try {
                final file = await resolvePageFile();
                if (await copyImageToClipboard(file.path)) {
                  toast?.show(copiedMsg, instantShow: true);
                } else {
                  toast?.showError(errorMsg, instantShow: true);
                }
              } catch (_) {
                toast?.showError(errorMsg, instantShow: true);
              }
            },
      // Not a Komikku action — only surfaced on desktop/web, where the
      // image-copy/share/save actions can't run, so the menu isn't empty.
      onOpenInWeb: (isMobile || openUrl == null)
          ? null
          : () {
              Navigator.pop(sheetContext);
              launchUrlInWeb(context, openUrl, ref.read(toastProvider));
            },
      onShare: !isMobile
          ? null
          : () async {
              final toast = ref.read(toastProvider);
              final errorMsg = context.l10n.errorSomethingWentWrong;
              Navigator.pop(sheetContext);
              try {
                final file = await resolvePageFile();
                await SharePlus.instance
                    .share(ShareParams(files: [XFile(file.path)]));
              } catch (_) {
                toast?.showError(errorMsg, instantShow: true);
              }
            },
      onSave: !isMobile
          ? null
          : () async {
              final toast = ref.read(toastProvider);
              final savedMsg = context.l10n.savedToGallery;
              final errorMsg = context.l10n.errorSomethingWentWrong;
              Navigator.pop(sheetContext);
              try {
                final file = await resolvePageFile();
                if (!await Gal.requestAccess()) {
                  toast?.showError(errorMsg, instantShow: true);
                  return;
                }
                await Gal.putImage(file.path);
                toast?.show(savedMsg, instantShow: true);
              } catch (_) {
                toast?.showError(errorMsg, instantShow: true);
              }
            },
    ),
  );
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
        ref.read(authCredentialsStoreProvider).valueOrNull?.uiAccessToken;
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
    final basicToken = ref.read(credentialsProvider).valueOrNull;
    if (basicToken != null) return {"Authorization": basicToken};
  } else if (authType == AuthType.simpleLogin) {
    return ref
        .read(authCredentialsStoreProvider)
        .valueOrNull
        ?.simpleLoginCookieHeader;
  }
  return null;
}

class _PageActionsSheet extends StatelessWidget {
  const _PageActionsSheet({
    required this.onCopyImage,
    required this.onOpenInWeb,
    required this.onShare,
    required this.onSave,
  });

  final VoidCallback? onCopyImage;
  final VoidCallback? onOpenInWeb;
  final VoidCallback? onShare;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    // Komikku layout: a compact horizontal row of equal-weight icon buttons
    // (icon above a centred, ≤2-line label) docked at the bottom.
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onCopyImage != null)
                _ActionButton(
                  actionKey: const ValueKey('reader-page-action-copy-image'),
                  icon: Icons.content_copy_rounded,
                  label: context.l10n.copyImageToClipboard,
                  onTap: onCopyImage!,
                ),
              if (onOpenInWeb != null)
                _ActionButton(
                  actionKey: const ValueKey('reader-page-action-open-web'),
                  icon: Icons.public_rounded,
                  label: context.l10n.openInWeb,
                  onTap: onOpenInWeb!,
                ),
              if (onShare != null)
                _ActionButton(
                  actionKey: const ValueKey('reader-page-action-share'),
                  icon: Icons.share_rounded,
                  label: context.l10n.shareImage,
                  onTap: onShare!,
                ),
              if (onSave != null)
                _ActionButton(
                  actionKey: const ValueKey('reader-page-action-save'),
                  icon: Icons.save_alt_rounded,
                  label: context.l10n.saveToGallery,
                  onTap: onSave!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One Komikku-style page action: a full-height [TextButton] with the icon
/// stacked above a centred label, taking an equal share of the row.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton(
        key: actionKey,
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
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
