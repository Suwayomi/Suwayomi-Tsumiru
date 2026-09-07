import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_background_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/offline_test_db.dart';

class _FailingOwnership extends BackgroundDownloadController {
  _FailingOwnership(
    super.ref, {
    required this.acquireFails,
    required this.events,
  });

  final bool acquireFails;
  final List<String> events;
  bool held = false;
  final failure = StateError('ownership publication failed');

  @override
  Future<T> withOwnership<T>(Future<T> Function() action) async {
    events.add('acquire');
    if (acquireFails) throw failure;
    held = true;
    try {
      await action();
      events.add('action completed');
      throw failure;
    } finally {
      held = false;
      events.add('released');
    }
  }
}

void main() {
  late OfflineDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = testOfflineDatabase();
    await db.upsertMangaMetadata(
      id: 1,
      title: 'Manga',
      updatedAt: DateTime(2026),
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final tmp = await Directory.systemTemp.createTemp('keep-rule-ownership-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tmp.path,
        );
  });

  tearDown(() => db.close());

  for (final acquireFails in [false, true]) {
    testWidgets(
      acquireFails
          ? 'failed ownership acquisition leaves the rule and starter untouched'
          : 'publication failure surfaces after rule change and still starts downloads',
      (tester) async {
        final events = <String>[];
        final starts = <bool>[];
        late WidgetRef captured;
        late _FailingOwnership ownership;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              offlineEnabledProvider.overrideWithValue(false),
              offlineActiveProvider.overrideWithValue(true),
              offlineDatabaseProvider.overrideWithValue(db),
              offlineDownloadManagerProvider.overrideWithValue(null),
              offlineDownloadCoordinatorProvider.overrideWithValue(null),
              backgroundDownloadControllerProvider.overrideWith(
                (ref) => ownership = _FailingOwnership(
                  ref,
                  acquireFails: acquireFails,
                  events: events,
                ),
              ),
              downloadStarterProvider.overrideWithValue(({
                bool userInitiated = false,
              }) async {
                expect(ownership.held, isFalse);
                starts.add(userInitiated);
                events.add('started');
              }),
            ],
            child: Consumer(
              builder: (_, ref, _) {
                captured = ref;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.runAsync(() async {
          final before = (await db.mangaById(1))!;
          final controller =
              captured.read(backgroundDownloadControllerProvider)
                  as _FailingOwnership;
          await expectLater(
            changeKeepRule(captured, 1, OfflineKeepRule.all, 5),
            throwsA(same(controller.failure)),
          );
          final after = (await db.mangaById(1))!;
          if (acquireFails) {
            expect(after.keepRule, before.keepRule);
            expect(after.keepUnreadCount, before.keepUnreadCount);
            expect(starts, isEmpty);
            expect(events, ['acquire']);
          } else {
            expect(after.keepRule, OfflineKeepRule.all);
            expect(after.keepUnreadCount, 5);
            expect(starts, [true]);
            expect(events, [
              'acquire',
              'action completed',
              'released',
              'started',
            ]);
          }
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
