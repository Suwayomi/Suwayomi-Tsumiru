// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/auth/data/jwt_utils.dart';

/// Builds a JWT with the given payload. The signature segment is a fixed
/// placeholder — these tests don't verify, so any non-empty string works.
String _jwt(Map<String, dynamic> payload, {String? rawPayload}) {
  String b64Url(String s) {
    final encoded = base64Url.encode(utf8.encode(s));
    // Strip padding like the JWT spec does.
    return encoded.replaceAll('=', '');
  }

  const header = '{"alg":"HS256","typ":"JWT"}';
  final body = rawPayload ?? jsonEncode(payload);
  return '${b64Url(header)}.${b64Url(body)}.signature';
}

void main() {
  group('decodeJwtExp', () {
    test('returns UTC DateTime for valid integer exp', () {
      const ts = 1730000000;
      final jwt = _jwt({'exp': ts, 'sub': 'user'});
      final result = decodeJwtExp(jwt);
      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result.millisecondsSinceEpoch, ts * 1000);
    });

    test('accepts float exp per RFC 7519 NumericDate (floors to int)', () {
      // R2-5: NumericDate may be non-integer. Must NOT reject.
      const ts = 1730000000.5;
      final jwt = _jwt({'exp': ts});
      final result = decodeJwtExp(jwt);
      expect(result, isNotNull);
      // 1730000000.5 floors to 1730000000.
      expect(result!.millisecondsSinceEpoch, 1730000000 * 1000);
    });

    test('decodes payload that needed padding restoration', () {
      // base64url length 22 needs 2 padding chars to be a multiple of 4.
      // Construct a payload that produces such a segment.
      final jwt = _jwt({'exp': 1700000000});
      // Sanity: the payload segment of our _jwt builder strips padding,
      // so this exercises the padding-restoration code path.
      final segs = jwt.split('.');
      expect(segs[1].endsWith('='), isFalse); // pad really was stripped
      expect(decodeJwtExp(jwt), isNotNull);

      // Malformed payloads all decode to null rather than throwing.
      final notJson = base64Url
          .encode(utf8.encode('not json'))
          .replaceAll('=', '');
      final arrayBody = base64Url
          .encode(utf8.encode('[1,2,3]'))
          .replaceAll('=', '');
      final malformed = [
        'abc',
        'a.b',
        'a.b.c.d',
        'header.!!!invalid_base64!!!.sig',
        'header.$notJson.sig',
        'header.$arrayBody.sig',
        _jwt({'sub': 'user'}),
        _jwt({'exp': '1730000000'}),
        _jwt({'exp': null}),
        _jwt({}, rawPayload: '{"exp": NaN}'),
        '',
        '   ',
      ];
      for (final token in malformed) {
        expect(decodeJwtExp(token), isNull, reason: token);
      }
    });
  });
}
