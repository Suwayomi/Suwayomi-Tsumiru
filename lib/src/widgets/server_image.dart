// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../constants/app_sizes.dart';
import '../constants/endpoints.dart';
import '../constants/enum.dart';
import '../features/auth/data/auth_coordinator.dart';
import '../features/auth/data/auth_credentials_store.dart';
import '../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../global_providers/global_providers.dart';
import '../utils/extensions/custom_extensions.dart';
import '../utils/misc/app_utils.dart';
import 'custom_circular_progress_indicator.dart';

class ServerImage extends HookConsumerWidget {
  const ServerImage({
    super.key,
    required this.imageUrl,
    this.size,
    this.fit,
    this.appendApiToUrl = false,
    this.progressIndicatorBuilder,
    this.imageBuilder,
    this.wrapper,
    this.showReloadButton = false,
  });

  final String imageUrl;
  final Size? size;
  final BoxFit? fit;
  final bool appendApiToUrl;
  final Widget Function(BuildContext, String, DownloadProgress)?
      progressIndicatorBuilder;
  // Wraps the decoded image. Only invoked once the image has loaded (never for
  // the placeholder), so callers can measure the real rendered page here.
  final Widget Function(BuildContext, ImageProvider)? imageBuilder;
  final Widget Function(Widget child)? wrapper;
  final bool showReloadButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = useState(UniqueKey());
    // Providers
    final authType = ref.watch(authTypeKeyProvider);
    final basicToken = ref.watch(credentialsProvider).valueOrNull;

    // Watch ONLY the simple-login cookie via `select` — never the
    // uiAccessToken. Watching the whole credentials state caused a
    // rebuild storm in webtoon mode every time the proactive refresh
    // rotated the access token (every ~4 min), and the wave of
    // simultaneous ServerImage rebuilds re-anchored the
    // ScrollablePositionedList and yanked the user backward several
    // pages mid-chapter. The access token is read via `ref.read` at
    // build time only — for cached images the URL value is irrelevant
    // because the lookup hits via the stable cacheKey (baseApi).
    final simpleCookieHeader = ref.watch(
      authCredentialsStoreProvider.select(
        (async) => async.valueOrNull?.simpleLoginCookieHeader,
      ),
    );
    final uiAccessTokenSnapshot = ref
        .read(authCredentialsStoreProvider)
        .valueOrNull
        ?.uiAccessToken;

    final baseApi = "${Endpoints.baseApi(
      baseUrl: ref.watch(serverUrlProvider),
      port: ref.watch(serverPortProvider),
      addPort: ref.watch(serverPortToggleProvider).ifNull(),
      appendApiToUrl: appendApiToUrl,
    )}"
        "$imageUrl";

    Map<String, String>? httpHeaders;
    if (authType == AuthType.basic && basicToken != null) {
      httpHeaders = {"Authorization": basicToken};
    } else if (authType == AuthType.simpleLogin) {
      httpHeaders = simpleCookieHeader;
    }

    // For ui_login, append ?token= since cached_network_image can't
    // reliably inject Authorization headers across platforms. Use the
    // un-tokened URL as cacheKey so token rotation doesn't bust cache.
    // Token value is read non-reactively above — if it rotates while
    // the widget exists, the widget won't rebuild and will keep using
    // the snapshot token. That's safe for cached images (cacheKey
    // hit, no HTTP). For uncached images the snapshot may be slightly
    // stale, but the proactive refresh schedules at exp-60s so the
    // snapshot is virtually always within the server's grace window;
    // worst case the request 401s once and the next widget rebuild
    // picks up the new token.
    var fetchUrl = baseApi;
    if (authType == AuthType.uiLogin &&
        uiAccessTokenSnapshot != null &&
        uiAccessTokenSnapshot.isNotEmpty) {
      final sep = fetchUrl.contains('?') ? '&' : '?';
      fetchUrl =
          '$fetchUrl${sep}token=${Uri.encodeQueryComponent(uiAccessTokenSnapshot)}';
    }

    final ImageRenderMethodForWeb renderMethod;
    if (httpHeaders != null) {
      renderMethod = ImageRenderMethodForWeb.HttpGet;
    } else {
      renderMethod = ImageRenderMethodForWeb.HtmlImage;
    }

    finalProgressIndicatorBuilder(
            BuildContext context, String url, DownloadProgress progress) =>
        AppUtils.wrapOn(
          wrapper,
          progressIndicatorBuilder?.call(context, url, progress) ??
              const CenterSorayomiShimmerIndicator(),
        );

    Widget errorWidget(BuildContext context, String error, stackTrace) {
      if (showReloadButton) {
        return AppUtils.wrapOn(
          wrapper,
          Padding(
            padding: KEdgeInsets.a8.size,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.grey,
                  ),
                  const Gap(32),
                  TextButton(
                    onPressed: () async {
                      // 1. Evict any cached entry. CachedNetworkImage
                      //    stores under our explicit cacheKey (baseApi),
                      //    but defensively evict fetchUrl too in case
                      //    the lib ever falls back to imageUrl. Idempotent
                      //    + cheap — non-existent entries are a no-op.
                      //    Wrapped in try/catch because removeFile
                      //    throws on missing entries on some platforms.
                      for (final keyToEvict in {baseApi, fetchUrl}) {
                        try {
                          await DefaultCacheManager().removeFile(keyToEvict);
                        } catch (_) {/* not in cache; ignore */}
                      }
                      // 2. Speculatively refresh if the ui_login access
                      //    token is within leadTime of expiry. Internally
                      //    gated on authType == uiLogin so this is a true
                      //    no-op for basic/simple — no GQL traffic.
                      try {
                        await ref
                            .read(authCoordinatorProvider.notifier)
                            .refreshUiAccessTokenIfDue(
                              gqlClient: ref.read(graphQlClientProvider),
                            );
                      } catch (_) {/* refresh failures degrade to retry */}
                      // 3. Remount. On RefreshSuccess the store was
                      //    updated synchronously, so the rebuild sees
                      //    fresh creds. On transient failure we remount
                      //    with stale creds and let the user retry —
                      //    correct behavior for non-auth errors.
                      key.value = (UniqueKey());
                    },
                    child: Text(context.l10n.reload),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        return AppUtils.wrapOn(
          wrapper,
          const Icon(
            Icons.broken_image_rounded,
            color: Colors.grey,
          ),
        );
      }
    }

    return CachedNetworkImage(
      key: key.value,
      imageUrl: fetchUrl,
      cacheKey: baseApi,
      height: size?.height,
      cacheManager: DefaultCacheManager(),
      httpHeaders: httpHeaders,
      width: size?.width,
      fit: fit ?? BoxFit.cover,
      imageRenderMethodForWeb: renderMethod,
      progressIndicatorBuilder: finalProgressIndicatorBuilder,
      imageBuilder: imageBuilder,
      errorWidget: errorWidget,
    );
  }
}

class ServerImageWithCpi extends StatelessWidget {
  const ServerImageWithCpi({
    super.key,
    required this.url,
    required this.outerSize,
    required this.innerSize,
    required this.isLoading,
  });
  final bool isLoading;
  final Size outerSize;
  final Size innerSize;
  final String url;
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox.fromSize(
        size: outerSize,
        child: Stack(
          alignment: AlignmentDirectional.center,
          children: [
            const Padding(
              padding: EdgeInsets.all(4.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            ServerImage(
              imageUrl: url,
              size: innerSize,
              progressIndicatorBuilder: (context, url, progress) =>
                  const CenterSorayomiShimmerIndicator(),
            )
          ],
        ),
      );
    } else {
      return ServerImage(imageUrl: url, size: outerSize);
    }
  }
}
