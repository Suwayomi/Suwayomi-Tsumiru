import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OAuthTestStorage implements FlutterSecureStorage {
  final values = <String, String>{};
  final failWrites = <String>{};
  final failDeletes = <String>{};
  Future<void> Function(String key)? beforeWrite;
  Future<void> Function(String key)? beforeDelete;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes++;
    await beforeWrite?.call(key);
    if (failWrites.contains(key)) {
      throw PlatformException(code: 'write-refused');
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletes++;
    await beforeDelete?.call(key);
    if (failDeletes.contains(key)) {
      throw PlatformException(code: 'delete-refused');
    }
    values.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
