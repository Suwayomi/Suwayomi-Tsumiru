import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../search/settings_search_registry.dart';
import '../../../../widgets/settings_group_card/settings_group_card.dart';
import 'data/database_repository.dart';
import 'graphql/__generated__/database.graphql.dart';

String _databaseTypeName(BuildContext context, Enum$DatabaseType type) =>
    switch (type) {
      Enum$DatabaseType.H2 => context.l10n.databaseTypeH2,
      Enum$DatabaseType.POSTGRESQL => context.l10n.databaseTypePostgresql,
      Enum$DatabaseType.$unknown => type.name,
    };

class DatabaseSection extends ConsumerWidget {
  const DatabaseSection({super.key});

  @override
  Widget build(context, ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(databaseSettingsRepositoryProvider);
    final settings = ref.watch(databaseSettingsProvider);
    if (settings.hasError) return const SizedBox.shrink();
    final data = settings.value;
    if (data == null) return const SizedBox.shrink();
    final preview = ref.watch(previewDatabaseSettingsProvider).value;
    final type = data.databaseType;
    final isH2 = type == Enum$DatabaseType.H2;
    Future<void> save(
      Future<Fragment$DatabaseSettingsDto?> Function() action,
    ) async {
      final result = await AppUtils.guard(action, ref.read(toastProvider));
      if (result != null && context.mounted) {
        ref.invalidate(databaseSettingsProvider);
        ref.invalidate(previewDatabaseSettingsProvider);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        SettingsGroupCard(
          children: [
            SettingsHighlightTarget(
              id: 'databaseType',
              // Same merge guard as the OPDS rows: without it the engine folds
              // this row into a neighbouring switch row.
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: ListTile(
                  title: Text(context.l10n.databaseType),
                  subtitle: Text(_databaseTypeName(context, type)),
                  onTap: canManage
                      ? () async {
                          final selected = await showDialog<Enum$DatabaseType>(
                            context: context,
                            builder: (dialogContext) =>
                                RadioListPopup<Enum$DatabaseType>(
                                  title: context.l10n.databaseType,
                                  value: type,
                                  optionList: const [
                                    Enum$DatabaseType.H2,
                                    Enum$DatabaseType.POSTGRESQL,
                                  ],
                                  getOptionTitle: (option) =>
                                      _databaseTypeName(context, option),
                                  onChange: (option) =>
                                      Navigator.pop(dialogContext, option),
                                ),
                            animationStyle: context.motionStyle,
                          );
                          if (selected != null &&
                              selected != type &&
                              context.mounted) {
                            await save(
                              () => repository.write(
                                Input$PartialSettingsTypeInput(
                                  databaseType: selected,
                                ),
                              ),
                            );
                          }
                        }
                      : null,
                ),
              ),
            ),
            SettingsHighlightTarget(
              id: 'databaseUrl',
              // Same merge guard as the OPDS rows: without it the engine folds
              // this row into a neighbouring switch row.
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: SettingsPropTile(
                  title: context.l10n.databaseUrl,
                  subtitle: data.databaseUrl,
                  type: SettingsPropType.textField(
                    hintText: context.l10n.databaseUrlHint,
                    value: data.databaseUrl,
                    onChanged: canManage && !isH2
                        ? (value) => save(
                            () => repository.write(
                              Input$PartialSettingsTypeInput(
                                databaseUrl: value,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            SettingsHighlightTarget(
              id: 'databaseUsername',
              // Same merge guard as the OPDS rows: without it the engine folds
              // this row into a neighbouring switch row.
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: SettingsPropTile(
                  title: context.l10n.databaseUsername,
                  subtitle: data.databaseUsername,
                  type: SettingsPropType.textField(
                    hintText: context.l10n.enterProp(
                      context.l10n.databaseUsername,
                    ),
                    value: data.databaseUsername,
                    onChanged: canManage && !isH2
                        ? (value) => save(
                            () => repository.write(
                              Input$PartialSettingsTypeInput(
                                databaseUsername: value,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            SettingsHighlightTarget(
              id: 'databasePassword',
              // Same merge guard as the OPDS rows: without it the engine folds
              // this row into a neighbouring switch row.
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: SettingsPropTile(
                  title: context.l10n.databasePassword,
                  type: SettingsPropType.textField(
                    canObscure: true,
                    hintText: context.l10n.enterProp(
                      context.l10n.databasePassword,
                    ),
                    value: data.databasePassword,
                    onChanged: canManage && !isH2
                        ? (value) => save(
                            () => repository.write(
                              Input$PartialSettingsTypeInput(
                                databasePassword: value,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            if (preview != null)
              SettingsHighlightTarget(
                id: 'databaseSchema',
                child: SettingsPropTile(
                  title: context.l10n.databaseSchema,
                  subtitle: preview.databaseSchema,
                  type: SettingsPropType.textField(
                    value: preview.databaseSchema,
                    hintText: context.l10n.databaseSchema,
                    onChanged: canManage && !isH2
                        ? (value) => save(
                            () => repository.write(
                              Input$PartialSettingsTypeInput(
                                databaseSchema: value,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            SettingsHighlightTarget(
              id: 'hikariConnectionPool',
              child: SettingsPropTile(
                title: context.l10n.hikariConnectionPool,
                description: context.l10n.hikariConnectionPoolDescription,
                type: SettingsPropType.switchTile(
                  value: data.useHikariConnectionPool,
                  onChanged: canManage
                      ? (value) => save(
                          () => repository.write(
                            Input$PartialSettingsTypeInput(
                              useHikariConnectionPool: value,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            if (preview != null)
              SettingsHighlightTarget(
                id: 'hikariMaxPoolSize',
                child: SettingsPropTile(
                  title: context.l10n.hikariMaxPoolSize,
                  subtitle: '${preview.hikariMaxPoolSize}',
                  type: SettingsPropType.numberPicker(
                    min: 1,
                    max: 10000000,
                    value: preview.hikariMaxPoolSize,
                    onChanged: canManage && data.useHikariConnectionPool
                        ? (value) => save(
                            () => repository.write(
                              Input$PartialSettingsTypeInput(
                                hikariMaxPoolSize: value,
                              ),
                            ),
                          )
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
