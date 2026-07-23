// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/language_list.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/server_image.dart';
import '../../data/source_repository/source_repository.dart';
import '../../domain/language/flag_emoji.dart';
import '../../domain/source/source_model.dart';
import 'controller/source_controller.dart';

/// 1:1 port of Komikku's SourcesFilterScreen: every language is a toggle
/// (enables/disables it in browse), each enabled language has an "All Sources"
/// toggle plus per-source checkboxes. Language state is [SourceLanguageFilter];
/// per-source hide state is the `tsumiru_isHidden` server meta.
class SourceFilterScreen extends HookConsumerWidget {
  const SourceFilterScreen({super.key});

  void _toggleLanguage(WidgetRef ref, String code, bool enable) {
    final notifier = ref.read(sourceLanguageFilterProvider.notifier);
    if (enable) {
      notifier.updateWithPreviousState((prev) => {...?prev, code}.toList());
    } else {
      notifier
          .updateWithPreviousState((prev) => [...?prev]..remove(code));
    }
  }

  Future<void> _setHidden(
    WidgetRef ref,
    BuildContext context,
    List<String> sourceIds, {
    required bool hidden,
  }) async {
    try {
      final repo = ref.read(sourceRepositoryProvider);
      await Future.wait(sourceIds.map((id) => repo.setSourceHidden(id, hidden)));
      ref.invalidate(sourceListProvider);
    } catch (e) {
      if (context.mounted) ref.read(toastProvider)?.showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceMapData = ref.watch(allSourcesByLanguageProvider);
    final enabledLangs = ref.watch(sourceLanguageFilterProvider);

    refresh() => ref.refresh(sourceListProvider.future);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.sources)),
      body: sourceMapData.showUiWhenData(
        context,
        (data) {
          final sourceMap = {...data};
          // The local source isn't listed on Komikku's filter screen (it's
          // always available); Browse surfaces it in its own bucket.
          sourceMap.remove('localsourcelang');
          // Komikku's GetLanguagesWithSources ordering: enabled languages
          // first, then alphabetical — so the languages you actually use float
          // to the top above the disabled ones.
          bool isEnabled(String c) => enabledLangs?.contains(c) ?? false;
          final languages = sourceMap.keys.toList()
            ..sort((a, b) {
              final ae = isEnabled(a), be = isEnabled(b);
              return ae == be ? a.compareTo(b) : (ae ? -1 : 1);
            });

          if (languages.isEmpty) {
            return Emoticons(
              title: context.l10n.noSourcesFound,
              button: TextButton(
                onPressed: refresh,
                child: Text(context.l10n.refresh),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: refresh,
            child: CustomScrollView(
              slivers: [
                for (final lang in languages) ...[
                  SliverToBoxAdapter(
                    child: _LanguageToggle(
                      langCode: lang,
                      enabled: enabledLangs?.contains(lang) ?? false,
                      onChanged: (value) => _toggleLanguage(ref, lang, value),
                    ),
                  ),
                  if (enabledLangs?.contains(lang) ?? false) ...[
                    SliverToBoxAdapter(
                      child: _AllSourcesToggle(
                        langCode: lang,
                        sources: sourceMap[lang]!,
                        onToggleAll: (hidden) => _setHidden(
                          ref,
                          context,
                          [for (final s in sourceMap[lang]!) s.id],
                          hidden: hidden,
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final source = sourceMap[lang]![index];
                          return _SourceCheckItem(
                            source: source,
                            onToggle: () => _setHidden(
                              ref,
                              context,
                              [source.id],
                              hidden: !source.isHidden,
                            ),
                          );
                        },
                        childCount: sourceMap[lang]!.length,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
        refresh: refresh,
      ),
    );
  }
}

/// Komikku's SourcesFilterHeader: `native (name flag)` with a switch that
/// enables/disables the whole language.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({
    required this.langCode,
    required this.enabled,
    required this.onChanged,
  });

  final String langCode;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final lang = languageMap[langCode];
    final native = lang?.nativeName ?? lang?.name ?? langCode;
    final name = lang?.name ?? langCode;
    final flag = flagEmojiForLang(langCode);
    final title = langCode == 'all' || langCode == 'other'
        ? '$native ($flag)'
        : '$native ($name $flag)';
    return SwitchListTile(
      value: enabled,
      onChanged: onChanged,
      title: Text(title),
    );
  }
}

/// Komikku's SourcesFilterToggle: `All Sources (flag)` — enables/disables
/// every source in the language at once. On when none are hidden.
class _AllSourcesToggle extends StatelessWidget {
  const _AllSourcesToggle({
    required this.langCode,
    required this.sources,
    required this.onToggleAll,
  });

  final String langCode;
  final List<SourceDto> sources;
  final ValueChanged<bool> onToggleAll;

  @override
  Widget build(BuildContext context) {
    final allShown = sources.every((s) => !s.isHidden);
    return SwitchListTile(
      value: allShown,
      // On -> hide all; off/partial -> show all.
      onChanged: (_) => onToggleAll(allShown),
      title: Text('${context.l10n.allSources} (${flagEmojiForLang(langCode)})'),
    );
  }
}

/// Komikku's SourcesFilterItem: source icon, name, `flag lang 18+` subtitle,
/// and a trailing checkbox (checked = shown).
class _SourceCheckItem extends StatelessWidget {
  const _SourceCheckItem({required this.source, required this.onToggle});

  final SourceDto source;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final langName = source.language?.name ?? source.language?.displayName;
    return ListTile(
      onTap: onToggle,
      leading: ClipRRect(
        borderRadius: KBorderRadius.r8.radius,
        child: ServerImage(
          imageUrl: source.iconUrl,
          size: const Size.square(40),
        ),
      ),
      title: Text(source.name),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              '${flagEmojiForLang(source.lang)} ${langName ?? source.lang}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // #138: legacy field, kept until a min server version is enforced.
          // ignore: deprecated_member_use_from_same_package
          if (source.isNsfw.ifNull()) ...[
            const SizedBox(width: 8),
            Text(
              context.l10n.nsfw18,
              style: TextStyle(color: context.theme.colorScheme.error),
            ),
          ],
        ],
      ),
      trailing: Checkbox(
        value: !source.isHidden,
        onChanged: (_) => onToggle(),
      ),
    );
  }
}
