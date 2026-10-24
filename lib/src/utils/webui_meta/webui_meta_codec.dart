String webUiKey(String key) => 'webUI_$key';

String? readWebUiValue(Map<String, String> metas, String key) {
  final fullKey = webUiKey(key);
  if (metas.containsKey(fullKey)) return metas[fullKey];
  final count = _webUiNumber(metas['${fullKey}_length']) ?? 0;
  if (count <= 0) return null;
  if (!count.isFinite || count != count.truncateToDouble()) {
    throw RangeError('Invalid WebUI chunk count: $count');
  }
  final value = StringBuffer();
  for (var index = 0; index < count; index++) {
    final chunk = metas['${fullKey}_$index'];
    if (chunk == null) return null;
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

  var staleChunkCount = _webUiNumber(existingMetas[lengthKey]) ?? 0;
  while (existingMetas.containsKey(
    '${fullKey}_${_numberString(staleChunkCount)}',
  )) {
    staleChunkCount++;
  }
  if (newChunkCount > 0 && existingMetas.containsKey(fullKey)) {
    delete.add(fullKey);
  }
  if (newChunkCount == 0 && existingMetas.containsKey(lengthKey)) {
    delete.add(lengthKey);
  }
  for (var index = newChunkCount; index < staleChunkCount; index++) {
    delete.add('${fullKey}_$index');
  }
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
  for (final (prefix, radix) in [('0x', 16), ('0b', 2), ('0o', 8)]) {
    if (trimmed.toLowerCase().startsWith(prefix)) {
      return int.tryParse(trimmed.substring(2), radix: radix);
    }
  }
  final number = num.tryParse(trimmed);
  return number == null || number.isNaN ? null : number;
}

String _numberString(num value) =>
    value.isFinite && value == value.truncateToDouble()
    ? '${value.toInt()}'
    : '$value';
