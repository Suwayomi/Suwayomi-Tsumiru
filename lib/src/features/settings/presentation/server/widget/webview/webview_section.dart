import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../search/settings_search_registry.dart';
import '../../../../widgets/settings_group_card/settings_group_card.dart';
import 'data/webview_repository.dart';

class WebViewSection extends HookConsumerWidget {
  const WebViewSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(webViewRepositoryProvider);
    final settings = ref.watch(webViewSettingsProvider);
    final clearSupport = ref.watch(clearCookiesAndCacheSupportProvider);
    final clearing = useState(false);
    final data = settings.value;
    final canClear = clearSupport.value ?? false;
    if (data == null && !canClear) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupHeading(label: context.l10n.kcefWebView),
        SettingsGroupCard(
          children: [
            if (data != null)
              SettingsHighlightTarget(
                id: 'webview',
                child: SwitchListTile(
                  title: Text(context.l10n.kcefWebView),
                  subtitle: Text(context.l10n.kcefWebViewDescription),
                  value: data.kcefEnabled,
                  onChanged: canManage
                      ? (isEnabled) async {
                          final value = await AppUtils.guard(
                            () => repository.write(
                              Input$PartialSettingsTypeInput(
                                kcefEnabled: isEnabled,
                              ),
                            ),
                            ref.read(toastProvider),
                          );
                          if (value != null && context.mounted) {
                            ref.invalidate(webViewSettingsProvider);
                          }
                        }
                      : null,
                ),
              ),
            if (canClear)
              SettingsHighlightTarget(
                id: 'clearWebViewCache',
                // Explicit boundary: without it the web engine folds this row
                // into the switch row above, exposing the whole section as one
                // button with a nested switch instead of two controls.
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: ListTile(
                    title: Text(context.l10n.clearCookiesAndCache),
                    onTap: canManage && !clearing.value
                        ? () async {
                            clearing.value = true;
                            try {
                              await repository.clearCookiesAndCache();
                              if (context.mounted) {
                                ref
                                    .read(toastProvider)
                                    ?.show(
                                      context
                                          .l10n
                                          .clearedWebViewCookiesAndCache,
                                    );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ref
                                    .read(toastProvider)
                                    ?.show(
                                      context
                                          .l10n
                                          .couldNotClearWebViewCookiesAndCache,
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
