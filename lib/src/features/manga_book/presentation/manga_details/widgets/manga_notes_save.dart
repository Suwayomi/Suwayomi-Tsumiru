import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/webui_meta/webui_meta_repository.dart';
import '../controller/manga_details_controller.dart';

Future<bool> persistMangaNotes({
  required GraphQLClient client,
  required int mangaId,
  required String rawText,
  required Map<String, String> existingMetas,
  required void Function() onSaved,
}) async {
  final trimmed = rawText.trimRight();
  try {
    await WebUiMetaRepository(client).writeMangaValue(
      mangaId,
      'notes',
      trimmed.isEmpty ? null : trimmed,
      existingMetas,
    );
  } catch (_) {
    return false;
  }
  onSaved();
  return true;
}

void refreshMangaAfterNotes(WidgetRef ref, int mangaId) {
  ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
}
