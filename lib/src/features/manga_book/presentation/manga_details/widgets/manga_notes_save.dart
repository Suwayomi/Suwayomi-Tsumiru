import 'package:graphql/client.dart';
import '../../../../../utils/webui_meta/webui_meta_repository.dart';

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
