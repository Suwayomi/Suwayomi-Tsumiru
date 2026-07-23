import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/app_sizes.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../widgets/emoticons.dart';
import '../../../../../../widgets/input_popup/widgets/text_field_dialog.dart';
import '../../../../controller/server_controller.dart';
import '../../data/browse_settings_repository.dart';

class ExtensionRepositoryScreen extends ConsumerWidget {
  const ExtensionRepositoryScreen({super.key});
  @override
  Widget build(context, ref) {
    final repository = ref.watch(browseSettingsRepositoryProvider);
    final serverSettings = ref.watch(settingsProvider);
    final List<String> repoList = [
      // #138: legacy field, kept until a min server version is enforced.
      // ignore: deprecated_member_use_from_same_package
      ...?serverSettings.value?.extensionRepos
    ];
    onRefresh() => ref.refresh(settingsProvider.future);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.extensionRepository)),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          String? newUrl = await showDialog<String?>(
            context: context,
            builder: (context) => TextFieldDialog(
              title: context.l10n.extensionRepository,
              hintText:
                  context.l10n.enterProp(context.l10n.extensionRepository),
            ),
          );
          if (newUrl.isNotBlank && newUrl.isUrl) {
            await AppUtils.guard(
              () async {
                await repository.updateExtensionRepos({...repoList, newUrl!});
                // ignore: unused_result
                ref.refresh(settingsProvider.future);
              },
              ref.read(toastProvider),
            );
          } else if (context.mounted) {
            ref.read(toastProvider)?.showError(
                context.l10n.invalidProp(context.l10n.extensionRepository));
          }
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: repoList.isNotBlank
            ? ListView.builder(
                itemCount: (repoList.length).ifNull(),
                itemBuilder: (context, index) {
                  final repo = repoList[index];
                  if (repo.isBlank) return const SizedBox.shrink();
                  return Card(
                    margin: KEdgeInsets.a8.size,
                    child: ListTile(
                      title: Text(
                        repo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: repo));
                              if (context.mounted) {
                                ref
                                    .read(toastProvider)
                                    ?.show(context.l10n.copied);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_rounded),
                            onPressed: () async {
                              final newList = {...repoList}..remove(repo);
                              await AppUtils.guard(
                                () async {
                                  await repository
                                      .updateExtensionRepos(newList);
                                  // ignore: unused_result
                                  ref.refresh(settingsProvider.future);
                                },
                                ref.read(toastProvider),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              )
            : Emoticons(
                title:
                    context.l10n.noPropFound(context.l10n.extensionRepository),
                subTitle: context.l10n.extensionRepositoryDescription,
                button: TextButton(
                  onPressed: onRefresh,
                  child: Text(context.l10n.refresh),
                ),
              ),
      ),
    );
  }
}
