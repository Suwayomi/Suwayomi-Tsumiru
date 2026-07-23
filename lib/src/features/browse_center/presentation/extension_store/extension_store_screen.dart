// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/popup_widgets/pop_button.dart';
import '../../data/extension_store_repository/extension_store_repository.dart';
import '../../domain/extension_store/extension_store_model.dart';
import 'widgets/add_store_dialog.dart';

/// Guide page ships in a later task; linked from the empty-state Help button.
const kStoreHelpUrl = 'https://tsumiru.app/docs/guides/adding-sources';

class ExtensionStoreScreen extends ConsumerWidget {
  const ExtensionStoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeData = ref.watch(extensionStoreListProvider);
    refresh() => ref.refresh(extensionStoreListProvider.future);

    Future<void> removeStore(ExtensionStore store) => AppUtils.guard(
          () async {
            await ref
                .read(extensionStoreRepositoryProvider)
                .removeStore(store.indexUrl);
            // ignore: unused_result
            ref.refresh(extensionStoreListProvider.future);
          },
          ref.read(toastProvider),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.extensionStores),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => AddStoreDialog(
            existingUrls: {
              ...?storeData.value?.stores.map((store) => store.indexUrl),
            },
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: storeData.showUiWhenData(
        context,
        (data) {
          final stores = data?.stores ?? const <ExtensionStore>[];
          if (stores.isEmpty) {
            return Emoticons(
              title: context.l10n.extensionStoresEmpty,
              button: TextButton.icon(
                onPressed: () => launchUrlInWeb(
                  context,
                  kStoreHelpUrl,
                  ref.read(toastProvider),
                ),
                icon: const Icon(Icons.help_outline_rounded),
                label: Text(context.l10n.help),
              ),
            );
          }
          return ListView.builder(
            padding: KEdgeInsets.a8.size,
            itemCount: stores.length,
            itemBuilder: (context, index) {
              final store = stores[index];
              return Card(
                margin: KEdgeInsets.h16v4.size,
                child: ListTile(
                  leading: const Icon(Icons.extension_rounded, size: 48),
                  title: Text(store.name),
                  subtitle: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (store.contactWebsite.isNotBlank)
                        IconButton(
                          icon: const Icon(Icons.public_rounded),
                          onPressed: () => launchUrlInWeb(
                            context,
                            store.contactWebsite,
                            ref.read(toastProvider),
                          ),
                        ),
                      if (store.contactDiscord != null)
                        IconButton(
                          icon: const Icon(Icons.discord_rounded),
                          onPressed: () => launchUrlInWeb(
                            context,
                            store.contactDiscord!,
                            ref.read(toastProvider),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: store.indexUrl),
                          );
                          if (context.mounted) {
                            ref.read(toastProvider)?.show(context.l10n.copied);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(context.l10n.removeExtensionStore),
                            content: Text(
                              context.l10n.removeExtensionStoreBody(
                                store.name,
                                store.indexUrl,
                              ),
                            ),
                            actions: [
                              const PopButton(),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  removeStore(store);
                                },
                                child: Text(context.l10n.ok),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        refresh: refresh,
      ),
    );
  }
}
