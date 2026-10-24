import 'package:graphql/client.dart';

import '../../graphql/__generated__/schema.graphql.dart';
import '../extensions/custom_extensions.dart';
import '__generated__/webui_meta.graphql.dart';
import 'webui_meta_codec.dart';

class WebUiMetaRepository {
  const WebUiMetaRepository(this.client);

  final GraphQLClient client;

  Future<void> writeMangaValue(
    int mangaId,
    String key,
    String? value,
    Map<String, String> existingMetas,
  ) async {
    final plan = planWebUiWrite(existingMetas, key, value);
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
    }
    if (plan.delete.isNotEmpty) {
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
  }

  Future<void> writeSourceValue(
    String sourceId,
    String key,
    String? value,
    Map<String, String> existingMetas,
  ) async {
    final plan = planWebUiWrite(existingMetas, key, value);
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
  }

  Future<void> writeGlobalValue(
    String key,
    String? value,
    Map<String, String> existingMetas,
  ) async {
    final plan = planWebUiWrite(existingMetas, key, value);
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
  }
}
