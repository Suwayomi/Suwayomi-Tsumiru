import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/urls.dart';
import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/launch_url_in_web.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../controller/server_controller.dart';
import '../../../../domain/settings/settings.dart';
import '../../../../search/settings_search_registry.dart';
import '../../../../widgets/settings_group_card/settings_group_card.dart';
import '../../data/server_settings_repository.dart';

class CloudFlareSection extends ConsumerWidget {
  const CloudFlareSection({super.key, required this.cloudFlareDto});

  final CloudFlareBypassDto cloudFlareDto;
  @override
  Widget build(context, ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(serverSettingsRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupHeading(label: context.l10n.cloudflareBypass),
        SettingsGroupCard(
          children: [
            SettingsHighlightTarget(
              id: 'flareSolverr',
              child: SettingsPropTile(
                titleWidget: Row(
                  children: [
                    Text(context.l10n.flareSolverr),
                    IconButton(
                      iconSize: 18,
                      onPressed: () => launchUrlInWeb(
                        context,
                        AppUrls.flareSolverr.url,
                        ref.read(toastProvider),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded),
                    ),
                  ],
                ),
                type: SettingsPropType.switchTile(
                  value: cloudFlareDto.flareSolverrEnabled,
                  onChanged: canManage
                      ? (isEnabled) async {
                          final value = await AppUtils.guard(
                            () => repository.toggleFlareSolverr(isEnabled),
                            ref.read(toastProvider),
                          );
                          if (value != null && context.mounted) {
                            ref
                                .read(settingsProvider.notifier)
                                .updateState(value);
                          }
                        }
                      : null,
                ),
              ),
            ),
            if (cloudFlareDto.flareSolverrEnabled) ...[
              SettingsHighlightTarget(
                id: 'flareSolverrServerUrl',
                child: SettingsPropTile(
                  title: context.l10n.flareSolverrServerUrl,
                  type: SettingsPropType.textField(
                    hintText: context.l10n.enterProp(
                      context.l10n.flareSolverrServerUrl,
                    ),
                    value: cloudFlareDto.flareSolverrUrl,
                    onChanged: canManage
                        ? repository.updateFlareSolverrUrl
                        : null,
                  ),
                  subtitle: cloudFlareDto.flareSolverrUrl,
                ),
              ),
              SettingsHighlightTarget(
                id: 'flareSolverrRequestTimeout',
                child: SettingsPropTile(
                  title: context.l10n.flareSolverrRequestTimeout,
                  subtitle: context.l10n.nSeconds(
                    cloudFlareDto.flareSolverrTimeout,
                  ),
                  type: SettingsPropType.numberSlider(
                    min: 20,
                    max: 300,
                    value: cloudFlareDto.flareSolverrTimeout,
                    onChanged: canManage
                        ? repository.updateFlareSolverrTimeout
                        : null,
                  ),
                ),
              ),
              SettingsHighlightTarget(
                id: 'flareSolverrSessionName',
                child: SettingsPropTile(
                  title: context.l10n.flareSolverrSessionName,
                  type: SettingsPropType.textField(
                    hintText: context.l10n.enterProp(
                      context.l10n.flareSolverrSessionName,
                    ),
                    value: cloudFlareDto.flareSolverrSessionName,
                    onChanged: canManage
                        ? repository.updateFlareSolverrSessionName
                        : null,
                  ),
                  subtitle: cloudFlareDto.flareSolverrSessionName,
                ),
              ),
              SettingsHighlightTarget(
                id: 'flareSolverrSessionTTL',
                child: SettingsPropTile(
                  title: context.l10n.flareSolverrSessionTTL,
                  subtitle: context.l10n.nMinutes(
                    cloudFlareDto.flareSolverrSessionTtl,
                  ),
                  type: SettingsPropType.numberSlider(
                    min: 1,
                    max: 60,
                    value: cloudFlareDto.flareSolverrSessionTtl,
                    onChanged: canManage
                        ? repository.updateFlareSolverrSessionTtl
                        : null,
                  ),
                ),
              ),
              if (ref.watch(flareSolverrFallbackProvider).value != null)
                SettingsHighlightTarget(
                  id: 'flareSolverrResponseFallback',
                  child: SettingsPropTile(
                    title: context.l10n.responseFallback,
                    description: context.l10n.responseFallbackDescription,
                    type: SettingsPropType.switchTile(
                      value:
                          ref.watch(flareSolverrFallbackProvider).value ??
                          false,
                      onChanged: canManage
                          ? (isEnabled) async {
                              final value = await AppUtils.guard(
                                () => repository
                                    .toggleFlareSolverrAsResponseFallback(
                                      isEnabled,
                                    ),
                                ref.read(toastProvider),
                              );
                              if (value != null && context.mounted) {
                                ref.invalidate(flareSolverrFallbackProvider);
                              }
                            }
                          : null,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }
}
