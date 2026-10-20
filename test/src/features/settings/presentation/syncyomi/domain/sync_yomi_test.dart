import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/domain/sync_yomi.dart';

void main() {
  group('normaliseSyncYomiHost', () {
    test('keeps valid origins, trimming whitespace and trailing slashes', () {
      expect(
        normaliseSyncYomiHost('https://syncyomi.example.com'),
        'https://syncyomi.example.com',
      );
      expect(
        normaliseSyncYomiHost('  https://syncyomi.example.com///  '),
        'https://syncyomi.example.com',
      );
      expect(
        normaliseSyncYomiHost('http://host:8080/syncyomi/'),
        'http://host:8080/syncyomi',
      );
      expect(normaliseSyncYomiHost('https://h/syncyomi'), 'https://h/syncyomi');

      // Rejects anything that is not a plain http(s) origin or path.
      for (final bad in [
        'syncyomi.example.com',
        'ftp://syncyomi.example.com',
        'https://',
        'https://syncyomi.example.com/?token=x',
        'https://h/#x',
        '   ',
      ]) {
        expect(normaliseSyncYomiHost(bad), isNull, reason: bad);
      }
    });
  });

  group('parseIsoDuration', () {
    test('reads hours, minutes, days and refuses the rest', () {
      expect(parseIsoDuration('PT0S'), Duration.zero);
      expect(parseIsoDuration('PT1H'), const Duration(hours: 1));
      expect(parseIsoDuration('PT12H'), const Duration(hours: 12));
      expect(parseIsoDuration('PT24H'), const Duration(hours: 24));
      expect(parseIsoDuration('PT90M'), const Duration(minutes: 90));
      expect(
        parseIsoDuration('PT1H30M'),
        const Duration(hours: 1, minutes: 30),
      );
      expect(parseIsoDuration('P1DT2H'), const Duration(days: 1, hours: 2));
      expect(parseIsoDuration(null), isNull);
      expect(parseIsoDuration('soon'), isNull);
      expect(parseIsoDuration('PT'), isNull);
    });
  });

  group('describeSyncYomiInterval', () {
    test('names offered intervals, other multiples and unreadable values', () {
      expect(
        describeSyncYomiInterval('PT0S').label,
        SyncYomiIntervalLabel.manualOnly,
      );
      // Values the picker offers keep their own wording.
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
      // Another spelling of an offered interval matches it.
      expect(
        describeSyncYomiInterval('P1D').label,
        SyncYomiIntervalLabel.daily,
      );
      expect(
        describeSyncYomiInterval('PT60M').label,
        SyncYomiIntervalLabel.everyHour,
      );
      // An hour multiple the picker does not offer reads out in hours.
      final twoHours = describeSyncYomiInterval('PT2H');
      expect(twoHours.label, SyncYomiIntervalLabel.everyNHours);
      expect(twoHours.count, 2);
      // A part hour reads out in minutes.
      final ninetyMinutes = describeSyncYomiInterval('PT90M');
      expect(ninetyMinutes.label, SyncYomiIntervalLabel.everyNMinutes);
      expect(ninetyMinutes.count, 90);
      // A zero-length duration the picker does not offer is manual only.
      expect(
        describeSyncYomiInterval('PT0M').label,
        SyncYomiIntervalLabel.manualOnly,
      );
      // An unreadable value is passed through unchanged.
      final verbatim = describeSyncYomiInterval('weekly');
      expect(verbatim.label, SyncYomiIntervalLabel.verbatim);
      expect(verbatim.raw, 'weekly');
    });
  });

  group('syncYomiIntervalOption', () {
    test('matches offered intervals by length, and nothing else', () {
      expect(syncYomiIntervalOption('PT24H'), 'PT24H');
      expect(syncYomiIntervalOption('P1D'), 'PT24H');
      expect(syncYomiIntervalOption('PT168H'), 'PT168H');
      expect(syncYomiIntervalOption('PT0S'), kSyncYomiIntervalManual);
      expect(syncYomiIntervalOption('PT60M'), 'PT1H');

      expect(syncYomiIntervalOption('PT2H'), isNull);
      expect(syncYomiIntervalOption('PT90M'), isNull);
      expect(syncYomiIntervalOption('weekly'), isNull);
    });
  });

  group('syncYomiStep', () {
    test('names each step and treats an unknown state as unknown', () {
      expect(syncYomiStep('STARTED'), SyncYomiStep.starting);
      expect(syncYomiStep('CREATING_BACKUP'), SyncYomiStep.creatingBackup);
      expect(syncYomiStep('DOWNLOADING'), SyncYomiStep.downloading);
      expect(syncYomiStep('MERGING'), SyncYomiStep.merging);
      expect(syncYomiStep('UPLOADING'), SyncYomiStep.uploading);
      expect(syncYomiStep('RESTORING'), SyncYomiStep.restoring);
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
    test('maps never, synced, failed and syncing states', () {
      expect(syncYomiStatusView().kind, SyncYomiStatusKind.never);

      final synced = syncYomiStatusView(
        state: 'SUCCESS',
        endDate: '1700000000000',
      );
      expect(synced.kind, SyncYomiStatusKind.synced);
      expect(
        synced.endDate,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      // An unreadable end time still reads as synced.
      final unreadable = syncYomiStatusView(state: 'SUCCESS', endDate: 'later');
      expect(unreadable.kind, SyncYomiStatusKind.synced);
      expect(unreadable.endDate, isNull);

      expect(
        syncYomiStatusView(
          state: 'ERROR',
          errorMessage: 'host unreachable',
        ).error,
        'host unreachable',
      );
      expect(syncYomiStatusView(state: 'ERROR').error, isNull);

      for (final state in [
        'STARTED',
        'CREATING_BACKUP',
        'DOWNLOADING',
        'MERGING',
        'UPLOADING',
        'RESTORING',
        // A state this build does not know counts as syncing.
        'COMPRESSING',
      ]) {
        expect(
          syncYomiStatusView(state: state).kind,
          SyncYomiStatusKind.syncing,
          reason: state,
        );
      }
    });
  });

  group('parseEpochMillis', () {
    test('reads the server string and refuses what it cannot read', () {
      expect(
        parseEpochMillis('1700000000000'),
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(parseEpochMillis(null), isNull);
      expect(parseEpochMillis(''), isNull);
      expect(parseEpochMillis('yesterday'), isNull);
    });
  });
}
