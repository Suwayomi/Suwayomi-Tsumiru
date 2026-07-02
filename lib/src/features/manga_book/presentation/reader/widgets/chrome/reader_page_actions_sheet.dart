// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/endpoints.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../global_providers/global_providers.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/launch_url_in_web.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../auth/data/auth_credentials_store.dart';
import '../../../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';

/// Komikku "Show actions on long tap": long-pressing a reader page opens this
/// page-actions sheet instead of the magnifier. Only offers what the
/// server-client model supports without a new pub dependency:
///   • Copy page link   (clean, token-less resource URL)
///   • Open page in web  (token-appended so it opens immediately)
///
/// Komikku's other long-tap actions (Share image, Save to gallery, Set as
/// cover) need image bytes + platform plugins the app doesn't ship (share_plus,
/// gal) or a server mutation Suwayomi doesn't expose — see the module notes.
Future<void> showReaderPageActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterPagesDto chapterPages,
  required int pageIndex,
}) {
  // Token-less URL is copied (avoids leaking the ui_login token into whatever
  // the user pastes into); token-appended URL is opened locally so it works.
  final shareUrl = _buildPageUrl(ref, chapterPages, pageIndex, withToken: false);
  final openUrl = _buildPageUrl(ref, chapterPages, pageIndex, withToken: true);

  if (shareUrl == null || openUrl == null) {
    ref.read(toastProvider)?.showError(
          context.l10n.errorSomethingWentWrong,
          instantShow: true,
        );
    return Future<void>.value();
  }

  final pageLabel = context.l10n.page(pageIndex + 1);

  return showModalBottomSheet<void>(
    context: context,
    // Reader overrides bottomSheetTheme to transparent; the Material below
    // supplies its own surface + rounded top.
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheetContext) => _PageActionsSheet(
      pageLabel: pageLabel,
      onCopyLink: () {
        Clipboard.setData(ClipboardData(text: shareUrl));
        Navigator.pop(sheetContext);
        ref
            .read(toastProvider)
            ?.show(sheetContext.l10n.copied, instantShow: true);
      },
      onOpenInWeb: () {
        Navigator.pop(sheetContext);
        launchUrlInWeb(context, openUrl, ref.read(toastProvider));
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

class _PageActionsSheet extends StatelessWidget {
  const _PageActionsSheet({
    required this.pageLabel,
    required this.onCopyLink,
    required this.onOpenInWeb,
  });

  final String pageLabel;
  final VoidCallback onCopyLink;
  final VoidCallback onOpenInWeb;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: context.theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  pageLabel,
                  style: context.textTheme.titleSmall
                      ?.copyWith(color: context.theme.colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              key: const ValueKey('reader-page-action-copy-link'),
              leading: const Icon(Icons.link_rounded),
              // No dedicated l10n key for "copy link" exists and the arb is out
              // of scope here; label is plain text (flagged for the controller).
              title: const Text('Copy page link'),
              onTap: onCopyLink,
            ),
            ListTile(
              key: const ValueKey('reader-page-action-open-web'),
              leading: const Icon(Icons.open_in_browser_rounded),
              title: Text(context.l10n.openInWeb),
              onTap: onOpenInWeb,
            ),
          ],
        ),
      ),
    );
  }
}
