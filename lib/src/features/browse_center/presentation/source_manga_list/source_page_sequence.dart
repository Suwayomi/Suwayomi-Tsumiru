import '../../../../utils/hooks/paging_controller_hook.dart';

class SourcePageSequence<T> {
  Map<int, int> _nextPages = {};

  void refresh() => _nextPages = {};

  Future<ServerPage<T>> fetch(
    int pageKey,
    Future<ServerPage<T>> Function(int sourcePage) fetchPage,
  ) async {
    final nextPages = _nextPages;
    var sourcePage = pageKey == 1 ? 1 : nextPages[pageKey] ?? pageKey;
    while (identical(nextPages, _nextPages)) {
      final page = await fetchPage(sourcePage);
      if (!identical(nextPages, _nextPages)) break;
      sourcePage++;
      nextPages[pageKey + 1] = sourcePage;
      if (page.items.isNotEmpty || !page.hasNextPage) return page;
    }
    return (items: <T>[], hasNextPage: false);
  }
}
