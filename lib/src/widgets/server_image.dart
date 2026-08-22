// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../features/manga_book/presentation/reader/crop/cropped_image_provider.dart';
import '../features/offline/data/offline_image_provider.dart';
import '../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../global_providers/global_providers.dart';
import '../utils/extensions/custom_extensions.dart';
import '../utils/hooks/debounced_hook.dart';
import '../utils/misc/app_utils.dart';
import 'cover_cache/cover_cache.dart';
import 'custom_circular_progress_indicator.dart';

final _trailingSlashes = RegExp(r'/+$');
final _leadingSlashes = RegExp(r'^/+');

/// Absolute URL for a server-relative image or page [path].
///
/// Suwayomi hands these out root-relative and already carrying the `/api/v1`
/// prefix, so [appendApiToUrl] only applies when the path has none. A doubled
/// prefix or slash misses the route and falls through to the WebUI SPA, which
/// answers 200 with index.html — a bad join shows up as a broken image rather
/// than an HTTP error.
///
/// Returns `''` for a blank [path]; callers must skip the request instead of
/// passing the result on.
String serverFileUrl({
  required String path,
  required String? baseUrl,
  required int? port,
  required bool addPort,
  required bool appendApiToUrl,
}) {
  if (path.isEmpty) return '';
  // Already absolute: a downloaded page (`file://`) or a fully-qualified URL.
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('file://')) {
    return path;
  }

  // Only let the caller's `appendApiToUrl` add the prefix when the server did
  // not already put one on the path.
  final hasApiPrefix = path.startsWith('/api/') || path.startsWith('api/');
  final origin = Endpoints.baseApi(
    baseUrl: baseUrl,
    port: port,
    addPort: addPort,
    appendApiToUrl: appendApiToUrl && !hasApiPrefix,
  );

  final root = origin.replaceAll(_trailingSlashes, '');
  final relative = path.replaceAll(_leadingSlashes, '');
  return '$root/$relative';
}

/// Appends the ui_login access token to [url] as a query parameter.
///
/// `cached_network_image` cannot reliably inject an `Authorization` header
/// across platforms, and the server accepts `?token=` as a fallback. The
/// delimiter comes from the parsed URI, since page URLs can already carry a
/// query string.
String appendUiLoginToken(String url, String? token) {
  if (url.isEmpty || token == null || token.isEmpty) return url;
  final hasQuery = Uri.tryParse(url)?.hasQuery ?? url.contains('?');
  final separator = hasQuery ? '&' : '?';
  return '$url${separator}token=${Uri.encodeQueryComponent(token)}';
}

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
    this.localFilePath,
    this.cropBorders = false,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  /// When set, the page is rendered straight off disk (downloaded chapter,
  /// offline reading) instead of fetched from the server. The network path is
  /// left untouched when this is null.
  final String? localFilePath;

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

  /// Trim solid page borders before display. Routes the
  /// page through [CroppedImageProvider] so crop composes with rotate/split/
  /// double via the existing [imageBuilder]. No-op on web.
  final bool cropBorders;

  /// Decode the image at this pixel size instead of the source's native
  /// resolution. Long-strip webtoon pages are ~800×15000 source; decoding at
  /// the actual on-screen width shrinks the GPU texture the compositor samples
  /// every frame (the #196 high-GPU-while-scrolling cost). Aspect is preserved
  /// when only one dimension is given. Callers pass display-px = logical × DPR.
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// Wrap [base] so it decodes at [memCacheWidth]/[memCacheHeight] (display px)
  /// instead of the source's native resolution. Returns [base] unchanged when
  /// no cap is set. Used for the offline/crop provider paths; the network path
  /// takes memCache* directly on [CachedNetworkImage].
  ImageProvider _capDecode(ImageProvider base, int? width, int? height) =>
      (width == null && height == null)
          ? base
          : ResizeImage(base, width: width, height: height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = useState(UniqueKey());
    // Debounce the decode resolution. Reader modes tie memCache* to the window
    // size; a desktop window resize changes it every frame, which would evict
    // and re-decode the page each frame — flashing its placeholder ("black")
    // until the drag stops. Holding the last decode size lets the current bitmap
    // stretch smoothly, then re-decodes once when the size settles. Static
    // memCache* (thumbnails/covers) never changes, so this is a no-op there.
    final int? cacheWidth =
        useSettled(memCacheWidth, const Duration(milliseconds: 250));
    final int? cacheHeight =
        useSettled(memCacheHeight, const Duration(milliseconds: 250));

    // Renders a crop provider through the same imageBuilder/wrapper contract as
    // the normal paths (imageBuilder fires immediately with the provider, like
    // the offline branch; consumers show the frame once it decodes).
    //
    // No `_capDecode`/`ResizeImage` wrap here, unlike the other paths below:
    // `CroppedImageProvider` takes the decode cap directly (targetWidth/
    // targetHeight passed in at the call sites) and applies it itself, since
    // wrapping it in `ResizeImage` would silently do nothing for the cropped
    // branch (see the provider's own doc comment).
    Widget renderCrop(ImageProvider provider) {
      if (imageBuilder != null) {
        return AppUtils.wrapOn(wrapper, imageBuilder!(context, provider));
      }
      return AppUtils.wrapOn(
        wrapper,
        Image(
          image: provider,
          width: size?.width,
          height: size?.height,
          fit: fit ?? BoxFit.cover,
          frameBuilder: (ctx, child, frame, wasSync) =>
              frame != null ? child : const CenterSorayomiShimmerIndicator(),
          errorBuilder: (ctx, error, stack) => AppUtils.wrapOn(
            wrapper,
            const Icon(Icons.broken_image_rounded, color: Colors.grey),
          ),
        ),
      );
    }

    final wantCrop = cropBorders && !kIsWeb;

    // Offline: render the downloaded page from disk. Triggered either by an
    // explicit localFilePath or by a `file://` imageUrl (the offline reader
    // serves downloaded chapters as file URIs). Returned BEFORE any auth /
    // server provider reads, so local pages never subscribe to token rotation
    // (no rebuild storms) and need no network. Both inputs are immutable per
    // widget instance, so this branch is consistent across rebuilds.
    final localPath = localFilePath ??
        (imageUrl.startsWith('file:') ? Uri.parse(imageUrl).toFilePath() : null);
    if (localPath != null) {
      if (wantCrop) {
        return renderCrop(CroppedImageProvider(
          fetchUrl: imageUrl,
          cacheKey: localPath,
          localPath: localPath,
          targetWidth: cacheWidth,
          targetHeight: cacheHeight,
        ));
      }
      final ImageProvider provider =
          _capDecode(offlineImageProvider(localPath), cacheWidth, cacheHeight);
      if (imageBuilder != null) {
        return AppUtils.wrapOn(wrapper, imageBuilder!(context, provider));
      }
      return AppUtils.wrapOn(
        wrapper,
        Image(
          image: provider,
          height: size?.height,
          width: size?.width,
          fit: fit ?? BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => AppUtils.wrapOn(
            wrapper,
            const Icon(Icons.broken_image_rounded, color: Colors.grey),
          ),
        ),
      );
    }

    // Callers pass "" for entries with no image (a source restored from the
    // offline catalog, a null thumbnailUrl). Fetching it would hit the bare
    // origin, which answers with the WebUI's index.html.
    if (imageUrl.isEmpty) {
      return AppUtils.wrapOn(
        wrapper,
        const Icon(Icons.broken_image_rounded, color: Colors.grey),
      );
    }

    // Providers
    final authType = ref.watch(authTypeKeyProvider);
    final basicToken = ref.watch(credentialsProvider).value;

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
        (async) => async.value?.simpleLoginCookieHeader,
      ),
    );
    final uiAccessTokenSnapshot = ref
        .read(authCredentialsStoreProvider)
        .value
        ?.uiAccessToken;

    final baseApi = serverFileUrl(
      path: imageUrl,
      baseUrl: ref.watch(serverUrlProvider),
      port: ref.watch(serverPortProvider),
      addPort: ref.watch(serverPortToggleProvider).ifNull(),
      appendApiToUrl: appendApiToUrl,
    );

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
    final fetchUrl = appendUiLoginToken(
      baseApi,
      authType == AuthType.uiLogin ? uiAccessTokenSnapshot : null,
    );

    // Covers/icons go to the durable cover store; pages stay on the default
    // temp-dir manager. Offline library covers render from this cache, so it
    // must not share the page ring buffer's 200-object cap.
    final cacheManager = isCoverImagePath(imageUrl)
        ? ref.watch(coverCacheManagerProvider)
        : DefaultCacheManager();

    final ImageRenderMethodForWeb renderMethod;
    if (httpHeaders != null) {
      renderMethod = ImageRenderMethodForWeb.HttpGet;
    } else {
      renderMethod = ImageRenderMethodForWeb.HtmlImage;
    }

    // Covers re-decode from disk within a few frames after any cache clear
    // (tab switch under pressure, background trim). Delaying the shimmer
    // hides those near-instant reloads while real network loads still show one.
    final defaultIndicator = isCoverImagePath(imageUrl)
        ? const DelayedShimmer()
        : const CenterSorayomiShimmerIndicator();
    finalProgressIndicatorBuilder(
            BuildContext context, String url, DownloadProgress progress) =>
        AppUtils.wrapOn(
          wrapper,
          progressIndicatorBuilder?.call(context, url, progress) ??
              defaultIndicator,
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
                          await cacheManager.removeFile(keyToEvict);
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

    if (wantCrop) {
      return renderCrop(CroppedImageProvider(
        fetchUrl: fetchUrl,
        cacheKey: baseApi,
        headers: httpHeaders,
        targetWidth: cacheWidth,
        targetHeight: cacheHeight,
      ));
    }

    // cached_network_image hands `imageBuilder` the RAW provider, so its
    // memCache* is ignored whenever an imageBuilder is set (multichapter /
    // infinity / paged all set one). Inject the decode cap into the caller's
    // builder instead, and only pass memCache* to the plain-render path.
    final imageBuilderCapped = imageBuilder == null
        ? null
        : (BuildContext ctx, ImageProvider provider) =>
            imageBuilder!(ctx, _capDecode(provider, cacheWidth, cacheHeight));

    return CachedNetworkImage(
      key: key.value,
      imageUrl: fetchUrl,
      cacheKey: baseApi,
      height: size?.height,
      cacheManager: cacheManager,
      httpHeaders: httpHeaders,
      width: size?.width,
      fit: fit ?? BoxFit.cover,
      // Package defaults linger the placeholder a full second after the image
      // is ready.
      fadeOutDuration: const Duration(milliseconds: 150),
      fadeInDuration: const Duration(milliseconds: 150),
      memCacheWidth: imageBuilder == null ? cacheWidth : null,
      memCacheHeight: imageBuilder == null ? cacheHeight : null,
      imageRenderMethodForWeb: renderMethod,
      progressIndicatorBuilder: finalProgressIndicatorBuilder,
      imageBuilder: imageBuilderCapped,
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

/// The fetch URL, cache key and auth headers [ServerImage] would use for
/// [imageUrl] — so a caller that needs the raw bytes (e.g. the crop-borders
/// path) hits the SAME cache entry with the SAME auth instead of re-deriving.
/// [localPath] is set for offline/`file://` pages (bytes come from disk).
({String fetchUrl, String cacheKey, Map<String, String>? headers, String? localPath})
    serverImageRequest(
  WidgetRef ref,
  String imageUrl, {
  bool appendApiToUrl = false,
}) {
  final localPath =
      imageUrl.startsWith('file:') ? Uri.parse(imageUrl).toFilePath() : null;
  if (localPath != null) {
    return (fetchUrl: imageUrl, cacheKey: imageUrl, headers: null, localPath: localPath);
  }

  final authType = ref.read(authTypeKeyProvider);
  final basicToken = ref.read(credentialsProvider).value;
  final creds = ref.read(authCredentialsStoreProvider).value;

  final cacheKey = serverFileUrl(
    path: imageUrl,
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
    appendApiToUrl: appendApiToUrl,
  );

  Map<String, String>? headers;
  if (authType == AuthType.basic && basicToken != null) {
    headers = {"Authorization": basicToken};
  } else if (authType == AuthType.simpleLogin) {
    headers = creds?.simpleLoginCookieHeader;
  }

  final fetchUrl = appendUiLoginToken(
    cacheKey,
    authType == AuthType.uiLogin ? creds?.uiAccessToken : null,
  );
  return (fetchUrl: fetchUrl, cacheKey: cacheKey, headers: headers, localPath: null);
}

/// The [ImageProvider] matching what [ServerImage] renders for [imageUrl] —
/// same URL, cacheKey and auth, but WITHOUT the widget's memCache* decode cap,
/// so a prefetch through this decodes native-res into its own cache entry.
/// Callers use it to learn page dimensions (and warm the network cache) ahead
/// of the viewport; mirrors the provider selection in [ServerImage.build];
/// reads creds non-reactively (ref.read).
ImageProvider serverPageImageProvider(
  WidgetRef ref,
  String imageUrl, {
  bool appendApiToUrl = false,
}) {
  final localPath =
      imageUrl.startsWith('file:') ? Uri.parse(imageUrl).toFilePath() : null;
  if (localPath != null) return offlineImageProvider(localPath);

  final authType = ref.read(authTypeKeyProvider);
  final basicToken = ref.read(credentialsProvider).value;
  final creds = ref.read(authCredentialsStoreProvider).value;

  final baseApi = serverFileUrl(
    path: imageUrl,
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
    appendApiToUrl: appendApiToUrl,
  );

  Map<String, String>? httpHeaders;
  if (authType == AuthType.basic && basicToken != null) {
    httpHeaders = {"Authorization": basicToken};
  } else if (authType == AuthType.simpleLogin) {
    httpHeaders = creds?.simpleLoginCookieHeader;
  }

  final fetchUrl = appendUiLoginToken(
    baseApi,
    authType == AuthType.uiLogin ? creds?.uiAccessToken : null,
  );

  return CachedNetworkImageProvider(
    fetchUrl,
    cacheKey: baseApi,
    cacheManager: isCoverImagePath(imageUrl)
        ? ref.read(coverCacheManagerProvider)
        : DefaultCacheManager(),
    headers: httpHeaders,
  );
}
