import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../account/data/account_providers.dart';
import '../../account/domain/account_access.dart';
import '../../offline/data/offline_repository.dart';
import '../../offline/data/server_reachability.dart';
import 'category_repository.dart';

final defaultCategoryIdProvider = FutureProvider<int?>((ref) async {
  if (ref.watch(authTypeKeyProvider) != AuthType.uiLogin) return 0;
  final offline =
      ref.watch(viewOfflineNowProvider) || ref.watch(serverUnreachableProvider);
  final db = ref.watch(offlineReadDatabaseProvider);
  if (offline && db != null) {
    final categories = await db.allOfflineCategories();
    final defaults = categories.where((category) => category.isDefaultCategory);
    return defaults.length == 1 ? defaults.single.id : null;
  }
  final accessFuture = ref.watch(accountAccessProvider.future);
  final repository = ref.watch(categoryRepositoryProvider);
  final access = await accessFuture;
  return switch (access.capability) {
    AccountCapability.unsupported => 0,
    AccountCapability.supported => repository.getDefaultCategoryId(),
    _ => null,
  };
});

final settledDefaultCategoryIdProvider = Provider<int?>((ref) {
  final value = ref.watch(defaultCategoryIdProvider);
  return value.isLoading || value.hasError ? null : value.value;
});
