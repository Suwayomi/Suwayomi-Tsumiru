import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../routes/router_config.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../widgets/cover_cache/cover_cache.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../../account/domain/account_access.dart';
import '../../../../search/settings_search_registry.dart';
import '../../../../widgets/settings_group_card/settings_group_card.dart';
import 'data/images_repository.dart';

class ImagesSection extends HookConsumerWidget {
  const ImagesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(settledAccountAccessProvider);
    final canManage = access.allows(Enum$UserPermission.MANAGE_SETTINGS);
    final showAdminRows =
        access.capability != AccountCapability.supported || canManage;
    final repository = ref.watch(imagesRepositoryProvider);
    final download = ref.watch(imagesDownloadSettingsProvider);
    final serve = ref.watch(serveConversionsProvider);
    final clearSupport = ref.watch(clearCachedImagesSupportProvider);
    final clearing = useState(false);
    if (download.hasError || serve.hasError) {
      return const SizedBox.shrink();
    }
    final downloadData = download.value;
    final serveData = serve.value;
    final canClear = clearSupport.value ?? false;
    if (downloadData == null && serveData == null && !canClear) {
      return const SizedBox.shrink();
    }
    final showProcessingCard =
        (showAdminRows && downloadData != null) || serveData != null;
    final showClearCard = showAdminRows && canClear;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (showProcessingCard)
          SettingsGroupCard(
            children: [
              if (showAdminRows && downloadData != null)
                SettingsHighlightTarget(
                  id: 'imageDownloadProcessing',
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: ListTile(
                      title: Text(context.l10n.imageDownloadProcessing),
                      onTap: () => const ImageProcessingRoute(
                        type: 'download',
                      ).push(context),
                    ),
                  ),
                ),
              if (serveData != null)
                SettingsHighlightTarget(
                  id: 'imageServeProcessing',
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: ListTile(
                      title: Text(context.l10n.imageServeProcessing),
                      onTap: () => const ImageProcessingRoute(
                        type: 'serve',
                      ).push(context),
                    ),
                  ),
                ),
            ],
          ),
        if (showProcessingCard && showClearCard) const SizedBox(height: 16),
        if (showClearCard)
          SettingsGroupCard(
            children: [
              SettingsHighlightTarget(
                id: 'imagesClearCache',
                // Explicit boundary: without it the engine folds this tappable
                // row into a neighbouring switch row (same guard as the OPDS,
                // WebView and Misc rows).
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: ListTile(
                    title: Text(context.l10n.imageProcessingClearCache),
                    onTap: canManage && !clearing.value
                        ? () async {
                            clearing.value = true;
                            try {
                              await repository.clearCachedImages();
                              await DefaultCacheManager().emptyCache();
                              await ref
                                  .read(coverCacheManagerProvider)
                                  .emptyCache();
                              if (context.mounted) {
                                ref
                                    .read(toastProvider)
                                    ?.show(
                                      context.l10n.imageProcessingClearedCache,
                                    );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ref
                                    .read(toastProvider)
                                    ?.show(
                                      context
                                          .l10n
                                          .imageProcessingCouldNotClearCache,
                                    );
                              }
                            } finally {
                              if (context.mounted) clearing.value = false;
                            }
                          }
                        : null,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
