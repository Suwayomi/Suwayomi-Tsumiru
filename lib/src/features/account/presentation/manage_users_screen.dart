import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/desktop/desktop_top_bar.dart';
import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../widgets/web_selection_area.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../data/account_administration.dart';
import '../data/account_providers.dart';
import '../domain/account_access.dart';
import 'account_admin_dialogs.dart';
import 'account_permission_labels.dart';

class ManageUsersScreen extends HookConsumerWidget {
  const ManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(settledAccountAccessProvider);
    final search = useTextEditingController();
    final query = useState('');
    final cursors = useState<List<int?>>([null]);
    final page = (search: query.value, after: cursors.value.last);
    final users = access.canManageUsers
        ? ref.watch(accountUsersProvider(page))
        : null;
    Future<void> refresh() async {
      ref.invalidate(accountUsersProvider);
      if (access.canManageUsers) {
        await ref.read(accountUsersProvider(page).future);
      }
    }

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.accountPermissionManageUsers);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(leading: detailNavigationBackButton(context), title: title),
      body: WebSelectionArea(
        child: !access.canManageUsers
            ? Center(child: Text(context.l10n.accountSettingsUnavailable))
            : Center(
                child: ConstrainedBox(
                  constraints: settingsPageConstraints(context),
                  child: Column(
                    children: [
                      Padding(
                        padding: settingsPagePadding(
                          context,
                          KEdgeInsets.a16.size,
                        )!,
                        child: TextField(
                          controller: search,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            labelText: context.l10n.accountSearchUsers,
                            suffixIcon: IconButton(
                              tooltip: context.l10n.search,
                              icon: const Icon(FluentIcons.search_24_regular),
                              onPressed: () {
                                cursors.value = [null];
                                query.value = search.text.trim();
                              },
                            ),
                          ),
                          onSubmitted: (value) {
                            cursors.value = [null];
                            query.value = value.trim();
                          },
                        ),
                      ),
                      Padding(
                        padding:
                            settingsPagePadding(context) ?? EdgeInsets.zero,
                        child: SettingsGroupCard(
                          children: [
                            SettingsGroupRow(
                              icon: FluentIcons.person_add_24_regular,
                              title: context.l10n.accountCreateUser,
                              onTap: () async {
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) => const CreateAccountDialog(),
                                  animationStyle: context.motionStyle,
                                );
                                if (context.mounted) {
                                  ref.invalidate(accountUsersProvider);
                                }
                              },
                            ),
                            SettingsGroupRow(
                              icon: FluentIcons.key_24_regular,
                              title: context.l10n.accountCodes,
                              onTap: () =>
                                  const AccountCodesRoute().push<void>(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: users!.showUiWhenData(
                          context,
                          (data) => RefreshIndicator(
                            onRefresh: refresh,
                            child: ListView(
                              padding: settingsPagePadding(context),
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SettingsGroupCard(
                                  children: [
                                    if (data.nodes.isEmpty)
                                      ListTile(
                                        title: Text(
                                          context.l10n.accountNoUsers,
                                        ),
                                      )
                                    else
                                      for (final user in data.nodes)
                                        ListTile(
                                          title: Text(user.username),
                                          subtitle: Text(
                                            '${user.roles.map((role) => switch (role) {
                                              Enum$UserRole.ADMIN => context.l10n.accountRoleAdmin,
                                              Enum$UserRole.USER => context.l10n.accountRoleUser,
                                              Enum$UserRole.VISITOR => context.l10n.accountRoleVisitor,
                                              Enum$UserRole.$unknown => context.l10n.accountRoleUnknown,
                                            }).join(', ')} · ${context.l10n.accountPermissionsSummary(accountPermissionLabels(context).keys.where(AccountAccess(capability: AccountCapability.supported, user: user).allows).length, accountPermissionLabels(context).length)}',
                                          ),
                                          trailing: IconButton(
                                            tooltip: context.l10n.delete,
                                            icon: const Icon(
                                              FluentIcons.delete_24_regular,
                                            ),
                                            onPressed: () => showDialog<void>(
                                              context: context,
                                              builder: (dialogContext) =>
                                                  AlertDialog(
                                                    title: Text(
                                                      context.l10n.delete,
                                                    ),
                                                    content: Text(
                                                      context
                                                          .l10n
                                                          .accountNoUserRemoval,
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              dialogContext,
                                                            ),
                                                        child: Text(
                                                          context.l10n.ok,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                              animationStyle:
                                                  context.motionStyle,
                                            ),
                                          ),
                                          onTap: () async {
                                            await showDialog<void>(
                                              context: context,
                                              builder: (_) =>
                                                  EditAccountDialog(user: user),
                                              animationStyle:
                                                  context.motionStyle,
                                            );
                                            if (context.mounted) {
                                              ref.invalidate(
                                                accountUsersProvider,
                                              );
                                            }
                                          },
                                        ),
                                  ],
                                ),
                                if (cursors.value.length > 1 ||
                                    (data.pageInfo.hasNextPage &&
                                        data.pageInfo.endCursor != null))
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      if (cursors.value.length > 1)
                                        TextButton(
                                          onPressed: () => cursors.value =
                                              cursors.value.sublist(
                                                0,
                                                cursors.value.length - 1,
                                              ),
                                          child: Text(
                                            context.l10n.accountPreviousPage,
                                          ),
                                        ),
                                      if (data.pageInfo.hasNextPage &&
                                          data.pageInfo.endCursor != null)
                                        TextButton(
                                          onPressed: () => cursors.value = [
                                            ...cursors.value,
                                            data.pageInfo.endCursor,
                                          ],
                                          child: Text(context.l10n.next),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          refresh: () =>
                              ref.invalidate(accountUsersProvider(page)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}
