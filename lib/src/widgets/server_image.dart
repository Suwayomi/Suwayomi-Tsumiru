// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../constants/app_sizes.dart';
import '../constants/endpoints.dart';
import '../constants/enum.dart';
import '../features/auth/data/auth_coordinator.dart';
import '../features/auth/data/auth_credentials_store.dart';
import '../features/auth/data/custom_headers_store.dart';
import '../features/manga_book/presentation/reader/crop/cropped_image_provider.dart';
import '../features/offline/data/offline_image_provider.dart';
import '../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../global_providers/global_providers.dart';
import '../utils/extensions/custom_extensions.dart';
import '../utils/hooks/debounced_hook.dart';
import '../utils/misc/app_utils.dart';
import '../utils/motion/reduce_motion.dart';
import 'cover_cache/cover_cache.dart';
import 'custom_circular_progress_indicator.dart';

Future<bool> reloadServerImage({
  required Iterable<String> cacheKeys,
  required bool Function() isCurrentSession,
  required Future<void> Function(String) evict,
  required Future<void> Function() refresh,
}) async {
  for (final key in cacheKeys) {
    if (!isCurrentSession()) return false;
    try {
      await evict(key);
    } catch (_) {}
  }
  if (!isCurrentSession()) return false;
  try {
    await refresh();
  } catch (_) {}
  return isCurrentSession();
}

final failedReaderPageReloadsProvider = Provider<Set<Future<void> Function()>>(
  (ref) => {},
);

Future<void> retryFailedReaderPages(WidgetRef ref) async {
  await Future.wait([
    for (final reload in {...ref.read(failedReaderPageReloadsProvider)})
      reload(),
  ]);
}

final _trailingSlashes = RegExp(r'/+$');
final _leadingSlashes = RegExp(r'^/+');

/// Join server-relative paths without duplicating /api/v1; blank paths return '' and must not be fetched.
String serverFileUrl({
  required String path,
  required String? baseUrl,
  required int? port,
  required bool addPort,
  required bool appendApiToUrl,
}) {
  if (path.isEmpty) return '';
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('file://')) {
    return path;
  }

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

/// Web uses URL tokens to avoid CORS preflights; native uses headers to keep tokens out of logs/cache keys.
const bool kImageTokenInUrl = kIsWeb;

/// Add Authorization unless this platform carries tokens in image URLs.
Map<String, String>? withUiLoginImageAuth(
  Map<String, String>? headers,
  String? token,
) {
  if (kImageTokenInUrl || token == null || token.isEmpty) return headers;
  return {...?headers, 'Authorization': 'Bearer $token'};
}

String uiLoginImageUrl(String url, String? token) =>
    kImageTokenInUrl ? appendUiLoginToken(url, token) : url;

/// External browsers require URL tokens; the token remains in history until expiry.
String serverImageBrowserUrl(WidgetRef ref, String fetchUrl) {
  if (kImageTokenInUrl ||
      ref.read(authTypeKeyProvider) != AuthType.uiLogin) {
    return fetchUrl;
  }
  return appendUiLoginTokenToWebUrl(
    fetchUrl,
    ref.read(authCredentialsStoreProvider).value?.uiAccessToken,
  );
}

/// Only web addresses may receive tokens; file URLs must never pass credentials to an OS opener.
String appendUiLoginTokenToWebUrl(String url, String? token) {
  final scheme = Uri.tryParse(url)?.scheme;
  return scheme == 'http' || scheme == 'https'
      ? appendUiLoginToken(url, token)
      : url;
}

/// Add the token query parameter accepted by Suwayomi when clients cannot send headers.
String appendUiLoginToken(String url, String? token) {
  if (url.isEmpty || token == null || token.isEmpty) return url;
  final hasQuery = Uri.tryParse(url)?.hasQuery ?? url.contains('?');
  final separator = hasQuery ? '&' : '?';
  return '$url${separator}token=${Uri.encodeQueryComponent(token)}';
}

/// Absolute http(s) URL hosted anywhere but the configured server; those load
/// with no server credentials, so an unparsable server matches nothing.
bool isExternalImageUrl({
  required String imageUrl,
  required String? baseUrl,
  required int? port,
  required bool addPort,
}) {
  final uri = Uri.tryParse(imageUrl);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return false;
  }
  final server = Uri.tryParse(
    Endpoints.baseApi(
      baseUrl: baseUrl,
      port: port,
      addPort: addPort,
      appendApiToUrl: false,
    ),
  );
  if (server == null ||
      (server.scheme != 'http' && server.scheme != 'https') ||
      server.host.isEmpty) {
    return true;
  }
  return uri.origin != server.origin;
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
    this.fallbackImageUrl,
    this.coverVersion,
    this.fallbackCoverVersion,
  });

  final String? localFilePath;

  final String imageUrl;

  final String? fallbackImageUrl;
  final String? coverVersion;

  /// Version for [fallbackImageUrl]; the primary [coverVersion] is null for custom covers.
  final String? fallbackCoverVersion;
  final Size? size;
  final BoxFit? fit;
  final bool appendApiToUrl;
  final Widget Function(BuildContext, String, DownloadProgress)?
  progressIndicatorBuilder;
  // Invoked only after loading, so callers can measure the rendered image.
  final Widget Function(BuildContext, ImageProvider)? imageBuilder;
  final Widget Function(Widget child)? wrapper;
  final bool showReloadButton;

  /// Crop before the imageBuilder transform; no-op on web.
  final bool cropBorders;

  /// Display-pixel decode size (logical × DPR); one dimension preserves aspect ratio.
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// Cap offline/crop decode size; no cap returns base unchanged.
  ImageProvider _capDecode(ImageProvider base, int? width, int? height) =>
      (width == null && height == null)
      ? base
      : ResizeImage(base, width: width, height: height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = useState(UniqueKey());
    final failed = useRef(false);
    final reload = useRef<Future<void> Function()?>(null);
    final reloads =
        showReloadButton &&
            imageUrl.isNotEmpty &&
            localFilePath == null &&
            !imageUrl.startsWith('file:')
        ? ref.watch(failedReaderPageReloadsProvider)
        : null;
    useEffect(() {
      Future<void> retry() async {
        if (failed.value) await reload.value?.call();
      }

      reloads?.add(retry);
      return () => reloads?.remove(retry);
    }, [reloads, showReloadButton]);
    // Debounce window-driven decode sizes to avoid eviction/re-decoding on every resize frame.
    final int? cacheWidth = useSettled(
      memCacheWidth,
      const Duration(milliseconds: 250),
    );
    final int? cacheHeight = useSettled(
      memCacheHeight,
      const Duration(milliseconds: 250),
    );

    // CroppedImageProvider applies its own decode cap; wrapping it in ResizeImage has no effect.
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
            Icon(
              FluentIcons.image_off_24_regular,
              color: ctx.theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final wantCrop = cropBorders && !kIsWeb;

    // Resolve local pages before auth/provider reads so offline images need no network or token subscriptions.
    final localPath =
        localFilePath ??
        (imageUrl.startsWith('file:')
            ? Uri.parse(imageUrl).toFilePath()
            : null);
    if (localPath != null) {
      if (wantCrop) {
        return renderCrop(
          CroppedImageProvider(
            fetchUrl: imageUrl,
            cacheKey: localPath,
            localPath: localPath,
            targetWidth: cacheWidth,
            targetHeight: cacheHeight,
          ),
        );
      }
      final ImageProvider provider = _capDecode(
        offlineImageProvider(localPath),
        cacheWidth,
        cacheHeight,
      );
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
            Icon(
              FluentIcons.image_off_24_regular,
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // An empty image path hits the origin's WebUI HTML instead of an image.
    if (imageUrl.isEmpty) {
      return AppUtils.wrapOn(
        wrapper,
        Icon(
          FluentIcons.image_off_24_regular,
          color: context.theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final authType = ref.watch(authTypeKeyProvider);
    final basicToken = ref.watch(credentialsProvider).value;

    // Token refresh must not rebuild cached reader images.
    final simpleCookieHeader = ref.watch(
      authCredentialsStoreProvider.select(
        (async) => async.value?.simpleLoginCookieHeader,
      ),
    );
    ref.watch(
      authCredentialsStoreProvider.select(
        (value) => (
          value.value?.accountBinding?.catalogId,
          value.value?.sessionEpoch,
          value.value?.sessionChanging,
        ),
      ),
    );
    final credentials = ref.read(authCredentialsStoreProvider).value;
    final uiAccessTokenSnapshot = credentials?.uiAccessToken;

    final serverUrl = ref.watch(serverUrlProvider);
    final serverPort = ref.watch(serverPortProvider);
    final serverAddPort = ref.watch(serverPortToggleProvider).ifNull();
    final external = isExternalImageUrl(
      imageUrl: imageUrl,
      baseUrl: serverUrl,
      port: serverPort,
      addPort: serverAddPort,
    );

    final baseApi = serverFileUrl(
      path: imageUrl,
      baseUrl: serverUrl,
      port: serverPort,
      addPort: serverAddPort,
      appendApiToUrl: appendApiToUrl,
    );

    // External covers cache under their own URL and carry no server credentials.
    final serverCacheKey = accountImageCacheKey(
      baseApi,
      authType: authType,
      store: ref.read(authCredentialsStoreProvider.notifier),
      credentials: credentials,
      coverVersion: coverVersion,
    );
    final cacheKey = external ? baseApi : serverCacheKey;

    Map<String, String>? httpHeaders;
    final requestAuthType = external ? null : authType;
    if (requestAuthType == AuthType.basic && basicToken != null) {
      httpHeaders = {"Authorization": basicToken};
    } else if (requestAuthType == AuthType.simpleLogin) {
      httpHeaders = simpleCookieHeader;
    }
    final customHeaders =
        ref.watch(customHttpHeadersProvider).value ?? const {};
    if (!external && customHeaders.isNotEmpty) {
      httpHeaders = applyCustomHeaders(
        Map<String, String>.from(httpHeaders ?? const {}),
        customHeaders,
      );
    }

    final uiToken = !external && authType == AuthType.uiLogin
        ? uiAccessTokenSnapshot
        : null;
    httpHeaders = withUiLoginImageAuth(httpHeaders, uiToken);
    final fetchUrl = uiLoginImageUrl(baseApi, uiToken);

    final cover = isCoverImagePath(imageUrl) || external;
    final cacheManager = cover
        ? ref.watch(coverCacheManagerProvider)
        : ref.watch(serverPageCacheManagerProvider);

    // Delay shimmer so quick cache re-decodes do not flash a placeholder.
    final defaultIndicator = cover
        ? const DelayedShimmer()
        : const CenterSorayomiShimmerIndicator();
    finalProgressIndicatorBuilder(
      BuildContext context,
      String url,
      DownloadProgress progress,
    ) => AppUtils.wrapOn(
      wrapper,
      progressIndicatorBuilder?.call(context, url, progress) ??
          defaultIndicator,
    );

    final reloadStore = ref.read(authCredentialsStoreProvider.notifier);
    final reloadEpoch = reloadStore.sessionEpoch;
    bool canReload() =>
        context.mounted &&
        !reloadStore.sessionChanging &&
        reloadStore.sessionEpoch == reloadEpoch;

    reload.value = () async {
      final ready = await reloadServerImage(
        cacheKeys: {cacheKey},
        isCurrentSession: canReload,
        evict: cacheManager.removeFile,
        refresh: () async {
          await ref
              .read(authCoordinatorProvider.notifier)
              .refreshUiAccessTokenIfDue(
                gqlClient: ref.read(unauthenticatedGraphQlClientProvider),
                trigger: 'image-reload',
              );
        },
      );
      if (ready && canReload()) {
        failed.value = false;
        key.value = UniqueKey();
      }
    };

    Widget errorWidget(BuildContext context, String error, stackTrace) {
      failed.value = true;
      // Covers warmed before versioned keys existed sit under the unversioned
      // key, so a failed versioned fetch draws that entry instead of an error.
      if (coverVersion != null && !external) {
        return AppUtils.wrapOn(
          wrapper,
          ServerImage(
            imageUrl: imageUrl,
            size: size,
            fit: fit,
            memCacheWidth: cacheWidth,
            memCacheHeight: cacheHeight,
          ),
        );
      }
      final fallback = fallbackImageUrl;
      if (fallback != null && fallback.isNotEmpty && fallback != imageUrl) {
        return AppUtils.wrapOn(
          wrapper,
          ServerImage(
            imageUrl: fallback,
            size: size,
            fit: fit,
            memCacheWidth: cacheWidth,
            memCacheHeight: cacheHeight,
            coverVersion: fallbackCoverVersion ?? coverVersion,
          ),
        );
      }
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
                  Icon(
                    FluentIcons.image_off_24_regular,
                    color: context.theme.colorScheme.onSurfaceVariant,
                  ),
                  const Gap(32),
                  TextButton(
                    onPressed: () => reload.value?.call(),
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
          Icon(
            FluentIcons.image_off_24_regular,
            color: context.theme.colorScheme.onSurfaceVariant,
          ),
        );
      }
    }

    // Some cover hosts send no CORS headers, so byte fetches fail on web.
    if (external && kIsWeb) {
      if (imageBuilder != null) {
        return AppUtils.wrapOn(
          wrapper,
          imageBuilder!(
            context,
            NetworkImage(
              fetchUrl,
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
            ),
          ),
        );
      }
      return AppUtils.wrapOn(
        wrapper,
        Image.network(
          fetchUrl,
          key: key.value,
          width: size?.width,
          height: size?.height,
          fit: fit ?? BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          frameBuilder: (ctx, child, frame, wasSync) =>
              frame != null ? child : defaultIndicator,
          errorBuilder: (ctx, error, stack) => errorWidget(ctx, '', stack),
        ),
      );
    }

    if (wantCrop) {
      return renderCrop(
        CroppedImageProvider(
          fetchUrl: fetchUrl,
          cacheKey: cacheKey,
          cacheManager: cacheManager,
          headers: httpHeaders,
          targetWidth: cacheWidth,
          targetHeight: cacheHeight,
        ),
      );
    }

    // cached_network_image passes imageBuilder a raw provider, so inject its decode cap here.
    final imageBuilderCapped = imageBuilder == null
        ? null
        : (BuildContext ctx, ImageProvider provider) =>
              imageBuilder!(ctx, _capDecode(provider, cacheWidth, cacheHeight));

    final fadeDuration = context.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 150);
    // Changing managers must invalidate the widget load even if the cache key is unchanged.
    return KeyedSubtree(
      key: ValueKey(cacheManager),
      child: CachedNetworkImage(
        key: key.value,
        imageUrl: fetchUrl,
        cacheKey: cacheKey,
        height: size?.height,
        cacheManager: cacheManager,
        httpHeaders: httpHeaders,
        width: size?.width,
        fit: fit ?? BoxFit.cover,
        // Zero bypasses the package's extra second of placeholder after decoding.
        fadeOutDuration: fadeDuration,
        fadeInDuration: fadeDuration,
        memCacheWidth: imageBuilder == null ? cacheWidth : null,
        memCacheHeight: imageBuilder == null ? cacheHeight : null,
        imageRenderMethodForWeb: external && kIsWeb
            ? ImageRenderMethodForWeb.HtmlImage
            : ImageRenderMethodForWeb.HttpGet,
        progressIndicatorBuilder: finalProgressIndicatorBuilder,
        imageBuilder: imageBuilderCapped,
        errorWidget: errorWidget,
      ),
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
            ),
          ],
        ),
      );
    } else {
      return ServerImage(imageUrl: url, size: outerSize);
    }
  }
}

/// Share ServerImage URL/cache key/auth; localPath marks offline or file-URI bytes.
({
  String fetchUrl,
  String cacheKey,
  Map<String, String>? headers,
  String? localPath,
})
serverImageRequest(
  WidgetRef ref,
  String imageUrl, {
  bool appendApiToUrl = false,
  String? coverVersion,
}) {
  final localPath = imageUrl.startsWith('file:')
      ? Uri.parse(imageUrl).toFilePath()
      : null;
  if (localPath != null) {
    return (
      fetchUrl: imageUrl,
      cacheKey: imageUrl,
      headers: null,
      localPath: localPath,
    );
  }

  final authType = ref.read(authTypeKeyProvider);
  final basicToken = ref.read(credentialsProvider).value;
  final creds = ref.read(authCredentialsStoreProvider).value;

  final serverUrl = ref.read(serverUrlProvider);
  final serverPort = ref.read(serverPortProvider);
  final serverAddPort = ref.read(serverPortToggleProvider).ifNull();

  final rawUrl = serverFileUrl(
    path: imageUrl,
    baseUrl: serverUrl,
    port: serverPort,
    addPort: serverAddPort,
    appendApiToUrl: appendApiToUrl,
  );

  if (isExternalImageUrl(
    imageUrl: imageUrl,
    baseUrl: serverUrl,
    port: serverPort,
    addPort: serverAddPort,
  )) {
    return (
      fetchUrl: rawUrl,
      cacheKey: rawUrl,
      headers: null,
      localPath: null,
    );
  }

  Map<String, String>? headers;
  if (authType == AuthType.basic && basicToken != null) {
    headers = {"Authorization": basicToken};
  } else if (authType == AuthType.simpleLogin) {
    headers = creds?.simpleLoginCookieHeader;
  }
  final customHeaders = ref.read(customHttpHeadersProvider).value ?? const {};
  if (customHeaders.isNotEmpty) {
    headers = applyCustomHeaders(
      Map<String, String>.from(headers ?? const {}),
      customHeaders,
    );
  }

  final uiToken = authType == AuthType.uiLogin ? creds?.uiAccessToken : null;
  headers = withUiLoginImageAuth(headers, uiToken);
  final fetchUrl = uiLoginImageUrl(rawUrl, uiToken);
  final cacheKey = accountImageCacheKey(
    rawUrl,
    authType: authType,
    store: ref.read(authCredentialsStoreProvider.notifier),
    credentials: creds,
    coverVersion: coverVersion,
  );
  return (
    fetchUrl: fetchUrl,
    cacheKey: cacheKey,
    headers: headers,
    localPath: null,
  );
}

/// Matching provider without a decode cap; prefetches native resolution and reads credentials non-reactively.
ImageProvider serverPageImageProvider(
  WidgetRef ref,
  String imageUrl, {
  bool appendApiToUrl = false,
  String? coverVersion,
}) {
  final request = serverImageRequest(
    ref,
    imageUrl,
    appendApiToUrl: appendApiToUrl,
    coverVersion: coverVersion,
  );
  if (request.localPath != null) {
    return offlineImageProvider(request.localPath!);
  }
  final external = isExternalImageUrl(
    imageUrl: imageUrl,
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
  );
  if (external && kIsWeb) {
    return NetworkImage(
      request.fetchUrl,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
    );
  }
  return CachedNetworkImageProvider(
    request.fetchUrl,
    cacheKey: request.cacheKey,
    cacheManager: isCoverImagePath(imageUrl) || external
        ? ref.read(coverCacheManagerProvider)
        : ref.read(serverPageCacheManagerProvider),
    headers: request.headers,
    imageRenderMethodForWeb: external && kIsWeb
        ? ImageRenderMethodForWeb.HtmlImage
        : ImageRenderMethodForWeb.HttpGet,
  );
}
