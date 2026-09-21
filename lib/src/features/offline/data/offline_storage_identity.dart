import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';
import 'account_storage_paths.dart';

String offlineCatalogServerIdKey(SharedPreferences preferences) =>
    preferences.getBool(offlineNonAccountScopedKey) == true
    ? offlineNonAccountCatalogServerIdKey
    : DBKeys.offlineCatalogServerId.name;

String offlineLastServerIdKey(SharedPreferences preferences) =>
    preferences.getBool(offlineNonAccountScopedKey) == true
    ? offlineNonAccountLastServerIdKey
    : DBKeys.offlineLastServerId.name;

String offlineLastServerAddressKey(SharedPreferences preferences) =>
    preferences.getBool(offlineNonAccountScopedKey) == true
    ? offlineNonAccountLastServerAddressKey
    : DBKeys.offlineLastServerAddress.name;
