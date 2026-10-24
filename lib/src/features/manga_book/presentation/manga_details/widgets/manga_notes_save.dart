import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/webui_meta/webui_meta_repository.dart';
import '../controller/manga_details_controller.dart';

/// Writes series notes through WebUI's chunked meta codec (the repository
/// handles chunking and stale-chunk cleanup). Trims trailing whitespace like
/// WebUI's `trimEnd()`; an empty result deletes the key. Refreshes the series
/// afterwards so the notes display above the description updates. Returns
/// false when the write failed — callers keep their text and show the error
/// toast pattern.
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

/// Invalidates the same provider the details screen watches.
void refreshMangaAfterNotes(WidgetRef ref, int mangaId) {
  ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
}
