// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Regression guard for the "Cannot use the Ref of categoryControllerProvider
// after it has been disposed" crash: opening a manga and adding it to the
// library reads categoryControllerProvider.future, which starts an async build
// that the auto-dispose then tears down mid-flight. If build() touches ref
// after its await, Riverpod throws. This exercises the REAL build() (not an
// overridden stub) with a disposal in the middle.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// getCategoryList() completes only when the test says so, holding
/// CategoryController.build() suspended at its await.
class _PendingCategoryRepo extends CategoryRepository {
  _PendingCategoryRepo(this.completer) : super(_dummyClient());
  final Completer<List<CategoryDto>?> completer;
  @override
  Future<List<CategoryDto>?> getCategoryList() => completer.future;
}

void main() {
  test('build() disposed mid-fetch does not use ref after disposal', () async {
    final fetch = Completer<List<CategoryDto>?>();
    final errors = <Object>[];

    // The disposed-ref crash surfaces through Flutter's error handler (the red
    // overlay), not as an uncaught async error — capture both to be safe.
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = prevOnError);

    await runZonedGuarded(() async {
      final container = ProviderContainer(overrides: [
        categoryRepositoryProvider
            .overrideWithValue(_PendingCategoryRepo(fetch)),
        offlineReadDatabaseProvider.overrideWithValue(null),
        offlineSyncProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);

      // Mirror add-to-library: read .future with NO retained listener, so this
      // auto-dispose provider can be torn down while its build is still pending.
      final future = container.read(categoryControllerProvider.future);
      await Future<void>.delayed(Duration.zero);
      // Fully dispose the pending build (no listener → no rebuild).
      container.invalidate(categoryControllerProvider);

      // Resume the disposed build past its await. On the buggy version this is
      // where ref.read(offlineSyncProvider) hits a dead ref and throws.
      fetch.complete(const <CategoryDto>[]);
      try {
        await future;
      } catch (e) {
        errors.add(e);
      }
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => errors.add(error));

    final disposedRefUse =
        errors.where((e) => e.toString().contains('after it has been disposed'));
    expect(disposedRefUse, isEmpty,
        reason: 'build() used ref after the provider was disposed: $errors');
  });
}
