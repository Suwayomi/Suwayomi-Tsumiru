import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../account/data/account_providers.dart';
import '../../account/data/graphql/__generated__/account.graphql.dart';
import '../../account/domain/account_access.dart';
import 'user_settings.dart';

Future<T?> accountOrLegacySettings<T>(
  Ref ref, {
  required T? Function(Fragment$AccountSettingsDto? user) fromUser,
  required Future<T?> Function() legacy,
}) async {
  switch (ref.watch(
    settledAccountAccessProvider.select((access) => access.capability),
  )) {
    case AccountCapability.supported:
      return fromUser(await ref.watch(userSettingsProvider.future));
    case AccountCapability.unsupported:
      return legacy();
    case AccountCapability.unknown:
      throw StateError('Account settings unavailable');
  }
}
