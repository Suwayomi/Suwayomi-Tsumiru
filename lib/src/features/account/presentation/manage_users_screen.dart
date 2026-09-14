import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../data/account_administration.dart';
import '../data/account_providers.dart';
import '../domain/account_access.dart';
import 'account_admin_dialogs.dart';
import 'account_codes_screen.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.accountPermissionManageUsers)),
      body: !access.canManageUsers
          ? Center(child: Text(context.l10n.accountSettingsUnavailable))
          : Column(
              children: [
                Padding(
                  padding: KEdgeInsets.a16.size,
                  child: TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: context.l10n.accountSearchUsers,
                      suffixIcon: IconButton(
                        tooltip: context.l10n.search,
                        icon: const Icon(Icons.search),
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
                ListTile(
                  leading: const Icon(Icons.person_add_rounded),
                  title: Text(context.l10n.accountCreateUser),
                  onTap: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => const CreateAccountDialog(),
                    );
                    if (context.mounted) ref.invalidate(accountUsersProvider);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.key_rounded),
                  title: Text(context.l10n.accountCodes),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const AccountCodesScreen(),
                    ),
                  ),
                ),
                Expanded(
                  child: users!.showUiWhenData(
                    context,
                    (data) => RefreshIndicator(
                      onRefresh: refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
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
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () async {
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) => EditAccountDialog(user: user),
                                );
                                if (context.mounted) {
                                  ref.invalidate(accountUsersProvider);
                                }
                              },
                            ),
                          if (data.nodes.isEmpty)
                            ListTile(title: Text(context.l10n.accountNoUsers)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton(
                                onPressed: cursors.value.length > 1
                                    ? () => cursors.value = cursors.value
                                          .sublist(0, cursors.value.length - 1)
                                    : null,
                                child: Text(context.l10n.accountPreviousPage),
                              ),
                              TextButton(
                                onPressed:
                                    data.pageInfo.hasNextPage &&
                                        data.pageInfo.endCursor != null
                                    ? () => cursors.value = [
                                        ...cursors.value,
                                        data.pageInfo.endCursor,
                                      ]
                                    : null,
                                child: Text(context.l10n.next),
                              ),
                            ],
                          ),
                          ListTile(
                            subtitle: Text(context.l10n.accountNoUserRemoval),
                          ),
                        ],
                      ),
                    ),
                    refresh: () => ref.invalidate(accountUsersProvider(page)),
                  ),
                ),
              ],
            ),
    );
  }
}
