// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

typedef RefreshResult = ({String access, String refresh});

class BackgroundTokenRecord {
  const BackgroundTokenRecord({
    required this.gen,
    required this.authType,
    this.accessToken,
    this.refreshToken,
    this.password,
    this.basicCredential,
    this.simpleCookie,
  });

  final int gen;
  final String authType; // basic | simpleLogin | uiLogin | none
  final String? accessToken, refreshToken, password, basicCredential, simpleCookie;

  BackgroundTokenRecord copyWith({int? gen, String? accessToken, String? refreshToken}) =>
      BackgroundTokenRecord(
        gen: gen ?? this.gen,
        authType: authType,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        password: password,
        basicCredential: basicCredential,
        simpleCookie: simpleCookie,
      );

  Map<String, Object?> toJson() => {
        'gen': gen, 'authType': authType, 'accessToken': accessToken,
        'refreshToken': refreshToken, 'password': password,
        'basicCredential': basicCredential, 'simpleCookie': simpleCookie,
      };

  factory BackgroundTokenRecord.fromJson(Map<String, Object?> j) =>
      BackgroundTokenRecord(
        gen: j['gen'] as int,
        authType: j['authType'] as String,
        accessToken: j['accessToken'] as String?,
        refreshToken: j['refreshToken'] as String?,
        password: j['password'] as String?,
        basicCredential: j['basicCredential'] as String?,
        simpleCookie: j['simpleCookie'] as String?,
      );
}

/// Coordinates token refresh across the main and worker isolates against ONE
/// gen-versioned record, so a rotating refresh token is never lost-updated by two
/// holders. Pure logic: storage + the actual refresh network call are injected.
class TokenBroker {
  TokenBroker({required this.read, required this.write, required this.refreshFn});
  final Future<BackgroundTokenRecord> Function() read;
  final Future<void> Function(BackgroundTokenRecord) write;
  final Future<RefreshResult?> Function(String refreshToken) refreshFn;

  /// Returns a usable access token to retry with, or null if auth is dead.
  Future<String?> resolveAfter401(String tokenThat401d) async {
    final current = await read();
    // Someone already refreshed to a different access token — use it, no refresh.
    if (current.accessToken != null && current.accessToken != tokenThat401d) {
      return current.accessToken;
    }
    final rt = current.refreshToken;
    if (rt == null) return null;
    final res = await refreshFn(rt);
    if (res == null) return null;
    await write(current.copyWith(
        gen: current.gen + 1, accessToken: res.access, refreshToken: res.refresh));
    return res.access;
  }
}
