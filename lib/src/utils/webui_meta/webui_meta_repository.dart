import 'package:graphql/client.dart';

import '../../features/offline/data/offline_database.dart';
import '../../graphql/__generated__/schema.graphql.dart';
import '../extensions/custom_extensions.dart';
import '__generated__/webui_meta.graphql.dart';
import 'webui_meta_codec.dart';

class WebUiMetaRepository {
  const WebUiMetaRepository(this.client, {this.readOfflineDb});

  final GraphQLClient client;
  final OfflineDatabase? Function()? readOfflineDb;

  Future<void> writeMangaValue(
    int mangaId,
    String key,
    String? value, [
    Map<String, String>? existingMetas,
  ]) async {
    final nodes = await client
        .query$GetWebUiMangaMetas(
          Options$Query$GetWebUiMangaMetas(
            variables: Variables$Query$GetWebUiMangaMetas(id: mangaId),
            fetchPolicy: FetchPolicy.noCache,
          ),
        )
        .getData((data) => data.manga.meta);
    if (nodes == null) throw StateError('Could not read manga metadata');
    final plan = planWebUiWrite(
      {for (final node in nodes) node.key: node.value},
      key,
      value,
    );
    if (plan.set.isNotEmpty) {
      await client
          .mutate$SetWebUiMangaMetas(
            Options$Mutation$SetWebUiMangaMetas(
              variables: Variables$Mutation$SetWebUiMangaMetas(
                input: Input$SetMangaMetasInput(
                  items: [
                    Input$SetMangaMetasItemInput(
                      mangaIds: [mangaId],
                      metas: plan.set.entries
                          .map(
                            (entry) => Input$MetaInput(
                              key: entry.key,
                              value: entry.value,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          )
          .getData((data) => data.setMangaMetas);
      for (final entry in plan.set.entries) {
        await mirrorMangaMeta(readOfflineDb, mangaId, entry.key, entry.value);
      }
    }
    if (plan.delete.isNotEmpty) {
      Future<void> cleanup() async {
      await client
          .mutate$DeleteWebUiMangaMetas(
            Options$Mutation$DeleteWebUiMangaMetas(
              variables: Variables$Mutation$DeleteWebUiMangaMetas(
                input: Input$DeleteMangaMetasInput(
                  items: [
                    Input$DeleteMangaMetasItemInput(
                      mangaIds: [mangaId],
                      keys: plan.delete,
                    ),
                  ],
                ),
              ),
            ),
          )
          .getData((data) => data.deleteMangaMetas);
    }

      try {
        await cleanup();
      } catch (_) {
        await cleanup();
      }
      for (final key in plan.delete) {
        await mirrorMangaMeta(readOfflineDb, mangaId, key);
      }
    }
  }

  Future<Map<String, String>> readSourceMetas(String sourceId) async {
    final nodes = await client
        .query$GetWebUiSourceMetas(
          Options$Query$GetWebUiSourceMetas(
            variables: Variables$Query$GetWebUiSourceMetas(id: sourceId),
            fetchPolicy: FetchPolicy.noCache,
          ),
        )
        .getData((data) => data.source.meta);
    if (nodes == null) throw StateError('Could not read source metadata');
    return {for (final node in nodes) node.key: node.value};
  }

  Future<void> writeSourceValue(
    String sourceId,
    String key,
    String? value, [
    Map<String, String>? existingMetas,
  ]) async {
    final plan = planWebUiWrite(
      await readSourceMetas(sourceId),
      key,
      value,
    );
    if (plan.set.isNotEmpty) {
      await client
          .mutate$SetWebUiSourceMetas(
            Options$Mutation$SetWebUiSourceMetas(
              variables: Variables$Mutation$SetWebUiSourceMetas(
                input: Input$SetSourceMetasInput(
                  items: [
                    Input$SetSourceMetasItemInput(
                      sourceIds: [sourceId],
                      metas: plan.set.entries
                          .map(
                            (entry) => Input$MetaInput(
                              key: entry.key,
                              value: entry.value,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          )
          .getData((data) => data.setSourceMetas);
    }
    if (plan.delete.isNotEmpty) {
      Future<void> cleanup() async {
      await client
          .mutate$DeleteWebUiSourceMetas(
            Options$Mutation$DeleteWebUiSourceMetas(
              variables: Variables$Mutation$DeleteWebUiSourceMetas(
                input: Input$DeleteSourceMetasInput(
                  items: [
                    Input$DeleteSourceMetasItemInput(
                      sourceIds: [sourceId],
                      keys: plan.delete,
                    ),
                  ],
                ),
              ),
            ),
          )
          .getData((data) => data.deleteSourceMetas);
    }

      try {
        await cleanup();
      } catch (_) {
        await cleanup();
      }
    }
  }

  Future<Map<String, String>> readGlobalMetas() async {
    final nodes =
        await client
            .query$GetWebUiGlobalMetas(
              Options$Query$GetWebUiGlobalMetas(
                fetchPolicy: FetchPolicy.noCache,
              ),
            )
            .getData((data) => data.metas.nodes);
    if (nodes == null) throw StateError('Could not read global metadata');
    return {for (final node in nodes) node.key: node.value};
  }

  Future<void> writeGlobalValue(
    String key,
    String? value, [
    Map<String, String>? existingMetas,
  ]) async {
    final plan = planWebUiWrite(await readGlobalMetas(), key, value);
    if (plan.set.isNotEmpty) {
      await client
          .mutate$SetWebUiGlobalMetas(
            Options$Mutation$SetWebUiGlobalMetas(
              variables: Variables$Mutation$SetWebUiGlobalMetas(
                input: Input$SetGlobalMetasInput(
                  metas: plan.set.entries
                      .map(
                        (entry) =>
                            Input$MetaInput(key: entry.key, value: entry.value),
                      )
                      .toList(),
                ),
              ),
            ),
          )
          .getData((data) => data.setGlobalMetas);
    }
    if (plan.delete.isNotEmpty) {
      Future<void> cleanup() async {
      await client
          .mutate$DeleteWebUiGlobalMetas(
            Options$Mutation$DeleteWebUiGlobalMetas(
              variables: Variables$Mutation$DeleteWebUiGlobalMetas(
                input: Input$DeleteGlobalMetasInput(keys: plan.delete),
              ),
            ),
          )
          .getData((data) => data.deleteGlobalMetas);
    }

      try {
        await cleanup();
      } catch (_) {
        await cleanup();
      }
    }
  }
}

// Offline-first screens read the mirror, so reflect confirmed server writes there.
Future<void> mirrorMangaMeta(
  OfflineDatabase? Function()? readOfflineDb,
  int mangaId,
  String key, [
  String? value,
]) async {
  try {
    await readOfflineDb?.call()?.updateMangaMetaValue(
      mangaId: mangaId,
      key: key,
      value: value,
    );
  } catch (_) {}
}
