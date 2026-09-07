import 'dart:convert';

import '../../offline/data/account_storage_paths.dart';

class AccountBinding {
  const AccountBinding({
    required this.address,
    this.userId,
    required this.username,
    required this.catalogId,
  });

  final String address;
  final int? userId;
  final String username;
  final String catalogId;

  String encode({required String accessToken, required String refreshToken}) =>
      jsonEncode({
        'address': address,
        'userId': userId,
        'username': username,
        'catalogId': catalogId,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      });

  static AccountBinding? decode(
    String? value, {
    required String? accessToken,
    required String? refreshToken,
  }) {
    if (value == null ||
        accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      return null;
    }
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      if (data['accessToken'] != accessToken ||
          data['refreshToken'] != refreshToken) {
        return null;
      }
      final address = data['address'] as String;
      final username = data['username'] as String;
      final catalogId = data['catalogId'] as String;
      final userId = data['userId'] as int?;
      if (address.isEmpty ||
          username.isEmpty ||
          (userId != null && userId <= 0)) {
        return null;
      }
      accountStoragePath('', catalogId);
      return AccountBinding(
        address: address,
        userId: userId,
        username: username,
        catalogId: catalogId,
      );
    } on Object {
      return null;
    }
  }
}
