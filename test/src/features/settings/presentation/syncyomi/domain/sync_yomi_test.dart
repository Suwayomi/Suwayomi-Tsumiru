import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/domain/sync_yomi.dart';

void main() {
  group('normaliseSyncYomiHost', () {
    test('keeps a bare https origin', () {
      expect(
        normaliseSyncYomiHost('https://syncyomi.example.com'),
        'https://syncyomi.example.com',
      );
    });

    test('trims whitespace and trailing slashes', () {
      expect(
        normaliseSyncYomiHost('  https://syncyomi.example.com///  '),
        'https://syncyomi.example.com',
      );
    });

    test('keeps an http origin with a port and sub path', () {
      expect(
        normaliseSyncYomiHost('http://host:8080/syncyomi/'),
        'http://host:8080/syncyomi',
      );
    });

    test('rejects a host with no scheme', () {
      expect(normaliseSyncYomiHost('syncyomi.example.com'), isNull);
    });

    test('rejects any other scheme', () {
      expect(normaliseSyncYomiHost('ftp://syncyomi.example.com'), isNull);
    });

    test('rejects a scheme with no host', () {
      expect(normaliseSyncYomiHost('https://'), isNull);
    });

    test('rejects a blank entry', () {
      expect(normaliseSyncYomiHost('   '), isNull);
    });
  });

  group('parseIsoDuration', () {
    test('reads whole hours', () {
      expect(parseIsoDuration('PT0S'), Duration.zero);
      expect(parseIsoDuration('PT1H'), const Duration(hours: 1));
      expect(parseIsoDuration('PT12H'), const Duration(hours: 12));
      expect(parseIsoDuration('PT24H'), const Duration(hours: 24));
    });

    test('reads minutes and mixed parts', () {
      expect(parseIsoDuration('PT90M'), const Duration(minutes: 90));
      expect(
        parseIsoDuration('PT1H30M'),
        const Duration(hours: 1, minutes: 30),
      );
      expect(parseIsoDuration('P1DT2H'), const Duration(days: 1, hours: 2));
    });

    test('refuses what it cannot read', () {
      expect(parseIsoDuration(null), isNull);
      expect(parseIsoDuration('soon'), isNull);
      expect(parseIsoDuration('PT'), isNull);
    });
  });

  group('describeSyncYomiInterval', () {
    test('PT0S is manual only', () {
      expect(
        describeSyncYomiInterval('PT0S').label,
        SyncYomiIntervalLabel.manualOnly,
      );
    });

    test('values the picker offers keep their own wording', () {
      expect(
        describeSyncYomiInterval('PT1H').label,
        SyncYomiIntervalLabel.everyHour,
      );
      expect(
        describeSyncYomiInterval('PT6H').label,
        SyncYomiIntervalLabel.every6Hours,
      );
      expect(
        describeSyncYomiInterval('PT12H').label,
        SyncYomiIntervalLabel.every12Hours,
      );
      expect(
        describeSyncYomiInterval('PT24H').label,
        SyncYomiIntervalLabel.everyDay,
      );
    });

    test('an hour multiple the picker does not offer reads out in hours', () {
      final threeHours = describeSyncYomiInterval('PT3H');
      expect(threeHours.label, SyncYomiIntervalLabel.everyNHours);
      expect(threeHours.count, 3);
    });

    test('a part hour reads out in minutes', () {
      final ninetyMinutes = describeSyncYomiInterval('PT90M');
      expect(ninetyMinutes.label, SyncYomiIntervalLabel.everyNMinutes);
      expect(ninetyMinutes.count, 90);
    });

    test('a zero-length duration the picker does not offer is manual only', () {
      expect(
        describeSyncYomiInterval('PT0M').label,
        SyncYomiIntervalLabel.manualOnly,
      );
    });

    test('an unreadable value is passed through unchanged', () {
      final verbatim = describeSyncYomiInterval('weekly');
      expect(verbatim.label, SyncYomiIntervalLabel.verbatim);
      expect(verbatim.raw, 'weekly');
    });
  });

  group('syncYomiStatusView', () {
    test('no status yet is never synced', () {
      expect(syncYomiStatusView().kind, SyncYomiStatusKind.never);
    });

    test('SUCCESS carries the end time', () {
      final view = syncYomiStatusView(
        state: 'SUCCESS',
        endDate: '1700000000000',
      );
      expect(view.kind, SyncYomiStatusKind.synced);
      expect(view.endDate, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('SUCCESS without a readable end time still reads as synced', () {
      final view = syncYomiStatusView(state: 'SUCCESS', endDate: 'later');
      expect(view.kind, SyncYomiStatusKind.synced);
      expect(view.endDate, isNull);
    });

    test('ERROR carries its message', () {
      final view = syncYomiStatusView(
        state: 'ERROR',
        errorMessage: 'host unreachable',
      );
      expect(view.kind, SyncYomiStatusKind.failed);
      expect(view.error, 'host unreachable');
    });

    test('ERROR without a message leaves it to the caller', () {
      expect(syncYomiStatusView(state: 'ERROR').error, isNull);
    });

    test('work in progress counts as syncing', () {
      for (final state in [
        'STARTED',
        'CREATING_BACKUP',
        'DOWNLOADING',
        'MERGING',
        'UPLOADING',
        'RESTORING',
      ]) {
        expect(
          syncYomiStatusView(state: state).kind,
          SyncYomiStatusKind.syncing,
          reason: state,
        );
      }
    });

    test('a state this build does not know counts as syncing', () {
      expect(
        syncYomiStatusView(state: 'COMPRESSING').kind,
        SyncYomiStatusKind.syncing,
      );
    });
  });

  group('parseEpochMillis', () {
    test('reads the server string', () {
      expect(
        parseEpochMillis('1700000000000'),
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('refuses what it cannot read', () {
      expect(parseEpochMillis(null), isNull);
      expect(parseEpochMillis(''), isNull);
      expect(parseEpochMillis('yesterday'), isNull);
    });
  });
}
