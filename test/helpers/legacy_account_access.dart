import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';

final legacyAccountAccess = AccountAccess(
  capability: AccountCapability.unsupported,
);
final legacyAccountPermissions = AccountPermissionGuard(
  () => legacyAccountAccess,
);
