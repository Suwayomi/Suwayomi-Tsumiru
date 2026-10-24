String webUiKey(String key) => 'webUI_$key';

String? readWebUiValue(Map<String, String> metas, String key) {
  final fullKey = webUiKey(key);
  final count = _webUiNumber(metas['${fullKey}_length']) ?? 0;
  if (count <= 0 ||
      !count.isFinite ||
      count != count.truncateToDouble() ||
      count > metas.length) {
    return metas[fullKey];
  }
  final value = StringBuffer();
  for (var index = 0; index < count; index++) {
    final chunk = metas['${fullKey}_$index'];
    if (chunk == null) return metas[fullKey];
    value.write(chunk);
  }
  return value.toString();
}

({Map<String, String> set, List<String> delete}) planWebUiWrite(
  Map<String, String> existingMetas,
  String key,
  String? value,
) {
  final fullKey = webUiKey(key);
  final lengthKey = '${fullKey}_length';
  final set = <String, String>{};
  final delete = <String>[];
  if (value == null) {
    final chunkKey = RegExp('^${RegExp.escape(fullKey)}_[0-9]+\$');
    return (
      set: set,
      delete: {
        fullKey,
        if (existingMetas.containsKey(lengthKey)) lengthKey,
        ...existingMetas.keys.where(chunkKey.hasMatch),
      }.toList(),
    );
  }

  var newChunkCount = 0;
  if (value.length <= 4000) {
    set[fullKey] = value;
  } else {
    // Dart and JavaScript both index strings in UTF-16 code units.
    for (var offset = 0; offset < value.length; offset += 4000) {
      final end = offset + 4000;
      set['${fullKey}_${newChunkCount++}'] = value.substring(
        offset,
        end < value.length ? end : value.length,
      );
    }
    set[lengthKey] = '$newChunkCount';
  }

  final chunkKey = RegExp('^${RegExp.escape(fullKey)}_[0-9]+\$');
  delete.addAll(
    existingMetas.keys.where(
      (key) =>
          (key == fullKey || key == lengthKey || chunkKey.hasMatch(key)) &&
          !set.containsKey(key),
    ),
  );
  return (set: set, delete: delete);
}

String encodeWebUiBool(bool value) => value ? 'true' : 'false';

bool decodeWebUiBool(String value) => value == 'true';

String encodeWebUiInt(int value) => '$value';

int decodeWebUiInt(String value, {required int defaultValue}) {
  final number = _webUiNumber(value);
  return number == null ||
          !number.isFinite ||
          number != number.truncateToDouble()
      ? defaultValue
      : number.toInt();
}

num? _webUiNumber(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 0;
  if (!_decimalNumber.hasMatch(trimmed)) return null;
  final number = num.tryParse(trimmed);
  return number == null || number.isNaN ? null : number;
}

final _decimalNumber = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');
