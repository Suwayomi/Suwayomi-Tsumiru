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

    test('rejects a host with a query', () {
      expect(
        normaliseSyncYomiHost('https://syncyomi.example.com/?token=x'),
        isNull,
      );
    });

    test('rejects a host with a fragment', () {
      expect(normaliseSyncYomiHost('https://h/#x'), isNull);
    });

    test('keeps a host with a path', () {
      expect(normaliseSyncYomiHost('https://h/syncyomi'), 'https://h/syncyomi');
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
        describeSyncYomiInterval('PT30M').label,
        SyncYomiIntervalLabel.every30Minutes,
      );
      expect(
        describeSyncYomiInterval('PT1H').label,
        SyncYomiIntervalLabel.everyHour,
      );
      expect(
        describeSyncYomiInterval('PT3H').label,
        SyncYomiIntervalLabel.every3Hours,
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
        SyncYomiIntervalLabel.daily,
      );
      expect(
        describeSyncYomiInterval('PT168H').label,
        SyncYomiIntervalLabel.weekly,
      );
    });

    test('another spelling of an offered interval matches it', () {
      expect(
        describeSyncYomiInterval('P1D').label,
        SyncYomiIntervalLabel.daily,
      );
      expect(
        describeSyncYomiInterval('PT60M').label,
        SyncYomiIntervalLabel.everyHour,
      );
    });

    test('an hour multiple the picker does not offer reads out in hours', () {
      final twoHours = describeSyncYomiInterval('PT2H');
      expect(twoHours.label, SyncYomiIntervalLabel.everyNHours);
      expect(twoHours.count, 2);
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

  group('syncYomiIntervalOption', () {
    test('matches an offered interval by its length, not its spelling', () {
      expect(syncYomiIntervalOption('PT24H'), 'PT24H');
      expect(syncYomiIntervalOption('P1D'), 'PT24H');
      expect(syncYomiIntervalOption('PT168H'), 'PT168H');
      expect(syncYomiIntervalOption('PT0S'), kSyncYomiIntervalManual);
      expect(syncYomiIntervalOption('PT60M'), 'PT1H');
    });

    test('an interval the picker does not offer has no match', () {
      expect(syncYomiIntervalOption('PT2H'), isNull);
      expect(syncYomiIntervalOption('PT90M'), isNull);
      expect(syncYomiIntervalOption('weekly'), isNull);
    });
  });

  group('syncYomiStep', () {
    test('names each step the server reports', () {
      expect(syncYomiStep('STARTED'), SyncYomiStep.starting);
      expect(syncYomiStep('CREATING_BACKUP'), SyncYomiStep.creatingBackup);
      expect(syncYomiStep('DOWNLOADING'), SyncYomiStep.downloading);
      expect(syncYomiStep('MERGING'), SyncYomiStep.merging);
      expect(syncYomiStep('UPLOADING'), SyncYomiStep.uploading);
      expect(syncYomiStep('RESTORING'), SyncYomiStep.restoring);
    });

    test('a state this build does not know is unknown', () {
      expect(syncYomiStep('COMPRESSING'), SyncYomiStep.unknown);
      expect(syncYomiStep(null), SyncYomiStep.unknown);
    });
  });

  group('enabledSyncYomiData', () {
    test('lists the kinds that are on, in dialog order', () {
      expect(
        enabledSyncYomiData(
          manga: true,
          chapters: false,
          categories: true,
          history: false,
          tracking: true,
        ),
        [
          SyncYomiDataKind.manga,
          SyncYomiDataKind.categories,
          SyncYomiDataKind.tracking,
        ],
      );
    });

    test('nothing on is an empty list', () {
      expect(
        enabledSyncYomiData(
          manga: false,
          chapters: false,
          categories: false,
          history: false,
          tracking: false,
        ),
        isEmpty,
      );
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
