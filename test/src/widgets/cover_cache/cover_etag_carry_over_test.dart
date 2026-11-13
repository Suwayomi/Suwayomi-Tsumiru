// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache_manager_io.dart';

class _Dir implements FileSystem {
  _Dir(this.path);
  final String path;
  @override
  Future<File> createFile(String name) async =>
      const LocalFileSystem().directory(path).childFile(name);
}

class _Response implements FileServiceResponse {
  _Response(this.statusCode, {this.eTag, List<int> body = const []})
    : content = Stream.value(body);
  @override
  final int statusCode;
  @override
  final String? eTag;
  @override
  final Stream<List<int>> content;
  @override
  int? get contentLength => null;
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 7));
  @override
  String get fileExtension => '.jpg';
}

class _Service extends FileService {
  _Service(this.answer);
  final Future<FileServiceResponse> Function() answer;
  final requests = <Map<String, String>>[];
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) {
    requests.add({...?headers});
    return answer();
  }
}

const _url = 'http://server/api/v1/manga/1/thumbnail';
const _account = 'tsumiru-image:account:a/$_url';

void main() {
  late io.Directory dir;
  setUp(() async {
    dir = await io.Directory.systemTemp.createTemp('cover-etag-');
  });
  tearDown(() => dir.delete(recursive: true));

  CacheManager cache(_Service service) => CacheManager(
    Config(
      'covers-test',
      repo: JsonCacheInfoRepository.withFile(io.File('${dir.path}/db.json')),
      fileSystem: _Dir(dir.path),
      fileService: service,
    ),
  );

  Future<FileInfo?> carry(CacheManager c, String base, String version) =>
      carryOverCoverVersion(
        cache: c,
        url: _url,
        key: '$base#cover-$version',
        unversionedKey: base,
        headers: {'Authorization': 'Bearer t'},
      );

  test('304 keeps the previous file under the new version, once', () async {
    final service = _Service(() async => _Response(304, eTag: '"a"'));
    final c = cache(service);
    await c.putFile(
      _url,
      Uint8List.fromList([1, 2, 3]),
      key: '$_account#cover-1',
      eTag: '"a"',
      fileExtension: 'jpg',
    );

    final info = await carry(c, _account, '2');

    expect(await info!.file.readAsBytes(), [1, 2, 3]);
    expect(service.requests.single, {
      'Authorization': 'Bearer t',
      io.HttpHeaders.ifNoneMatchHeader: '"a"',
    });
    expect(await c.getFileFromCache('$_account#cover-1'), isNull);
    final moved = await c.store.retrieveCacheData('$_account#cover-2');
    expect(moved!.eTag, '"a"');
  });

  test('200 stores the new body and drops the previous version', () async {
    final service = _Service(
      () async => _Response(200, eTag: '"b"', body: [9, 9]),
    );
    final c = cache(service);
    await c.putFile(
      _url,
      Uint8List.fromList([1]),
      key: '$_account#cover-1',
      eTag: '"a"',
    );

    final info = await carry(c, _account, '2');

    expect(await info!.file.readAsBytes(), [9, 9]);
    expect(await c.getFileFromCache('$_account#cover-1'), isNull);
    final stored = await c.store.retrieveCacheData('$_account#cover-2');
    expect(stored!.eTag, '"b"');
  });

  test('no request without a previous version of the same account with an '
      'ETag', () async {
    final service = _Service(() async => _Response(304));
    final c = cache(service);
    await c.putFile(
      _url,
      Uint8List.fromList([1]),
      key: 'tsumiru-image:account:b/$_url#cover-1',
      eTag: '"a"',
    );
    await c.putFile(_url, Uint8List.fromList([1]), key: '$_url#cover-1');

    expect(await carry(c, _account, '2'), isNull);
    expect(await carry(c, _url, '2'), isNull);
    expect(service.requests, isEmpty);
  });

  test('a legacy unversioned entry is revalidated too', () async {
    final service = _Service(() async => _Response(304));
    final c = cache(service);
    await c.putFile(
      _url,
      Uint8List.fromList([4]),
      key: _account,
      eTag: '"legacy"',
    );

    final info = await carry(c, _account, '2');

    expect(await info!.file.readAsBytes(), [4]);
    expect(
      service.requests.single[io.HttpHeaders.ifNoneMatchHeader],
      '"legacy"',
    );
    expect(await c.getFileFromCache(_account), isNull);
  });

  test('a network failure is reported instead of retried', () async {
    final service = _Service(
      () async => throw const io.SocketException('offline'),
    );
    final c = cache(service);
    await c.putFile(
      _url,
      Uint8List.fromList([1]),
      key: '$_account#cover-1',
      eTag: '"a"',
    );

    await expectLater(
      carry(c, _account, '2'),
      throwsA(isA<io.SocketException>()),
    );
    expect(await c.getFileFromCache('$_account#cover-1'), isNotNull);
  });
}
