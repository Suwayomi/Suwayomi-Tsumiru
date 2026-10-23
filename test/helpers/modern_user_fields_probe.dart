Map<String, Object?>? modernUserFieldsProbeData(String query) {
  if (!RegExp(r'__type\s*\(\s*name:\s*"ChapterType"\s*\)').hasMatch(query)) {
    return null;
  }
  return {
    '__type': {
      'fields': [
        {'name': 'id'},
        {'name': 'user'},
      ],
    },
  };
}
