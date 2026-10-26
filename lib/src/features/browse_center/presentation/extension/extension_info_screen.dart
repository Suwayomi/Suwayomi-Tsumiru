import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/server_image.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../domain/content_rating.dart';
import '../../domain/extension/extension_model.dart';
import '../../domain/source/source_model.dart';
import '../source/controller/source_controller.dart';
import 'controller/extension_controller.dart';
import 'widgets/extension_list_tile.dart';

class ExtensionInfoScreen extends HookConsumerWidget {
  const ExtensionInfoScreen({super.key, required this.pkgName});
  final String pkgName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref.watch(extensionProvider);
    final sources = ref.watch(sourceListProvider);
    final running = useState<String?>(null);
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.extensionInfo);
    final body = extensions.showUiWhenData(context, (data) {
      final extension = data?.where((e) => e.pkgName == pkgName).firstOrNull;
      if (extension == null) return const SizedBox.shrink();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: ServerImageWithCpi(
              isLoading: false,
              url: extension.iconUrl,
              outerSize: const Size.square(48),
              innerSize: const Size.square(24),
            ),
            title: Text(extension.name, style: context.textTheme.titleLarge),
          ),
          ListTile(
            title: Text(context.l10n.extensionVersion),
            trailing: Text(extension.versionName),
          ),
          ListTile(
            title: Text(context.l10n.extensionLanguage),
            trailing: Text(extension.language?.displayName ?? extension.lang),
          ),
          if (isNsfwFromWarning(extension.contentWarning))
            ListTile(title: Text(context.l10n.nsfw18)),
          if (extension.extensionStore != null ||
              extension.storeIndexUrl.isNotBlank)
            ListTile(
              title: Text(context.l10n.extensionStore),
              subtitle: Text(
                extension.extensionStore?.name ?? extension.storeIndexUrl!,
              ),
            ),
          if (extension.extensionLib.isNotBlank)
            ListTile(
              title: Text(context.l10n.extensionLibrary),
              trailing: Text(extension.extensionLib!),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: ExtensionListTileTailing(
              extension: extension,
              runningAction: running,
              ref: ref,
            ),
          ),
          const Divider(),
          sources.showUiWhenData(
            context,
            (items) => Column(
              children: [
                for (final source in items ?? [])
                  if (source.$extension.pkgName == pkgName)
                    ListTile(
                      leading: ServerImageWithCpi(
                        isLoading: false,
                        url: source.iconUrl,
                        outerSize: const Size.square(48),
                        innerSize: const Size.square(24),
                      ),
                      title: Text(source.displayName),
                      onTap: () => SourceTypeRoute(
                        sourceId: source.id,
                        sourceType: SourceType.POPULAR,
                      ).push(context),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (source.supportsLatest)
                            TextButton(
                              onPressed: () => SourceTypeRoute(
                                sourceId: source.id,
                                sourceType: SourceType.LATEST,
                              ).push(context),
                              child: Text(context.l10n.latest),
                            ),
                          if (source.isConfigurable)
                            IconButton(
                              tooltip: context.l10n.settings,
                              icon: const Icon(FluentIcons.settings_24_regular),
                              onPressed: () => SourcePreferenceRoute(
                                sourceId: source.id,
                              ).push(context),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
            refresh: () => ref.invalidate(sourceListProvider),
          ),
        ],
      );
    }, refresh: () => ref.invalidate(extensionProvider));
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(leading: detailNavigationBackButton(context), title: title),
      body: body,
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}
