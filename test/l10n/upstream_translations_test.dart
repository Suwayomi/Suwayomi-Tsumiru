import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_ar.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_de.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_ru.dart';

void main() {
  const counts = [0, 1, 2, 3, 11, 21];

  test(
    'German imported counts interpolate and select singular only for one',
    () {
      final locale = AppLocalizationsDe();
      expect(counts.map(locale.nStores), [
        '0 Depots',
        '1 Depot',
        '2 Depots',
        '3 Depots',
        '11 Depots',
        '21 Depots',
      ]);
      expect(counts.map(locale.downloadNextChaptersN), [
        'Nächste 0 Kapitel',
        'Nächstes Kapitel',
        'Nächste 2 Kapitel',
        'Nächste 3 Kapitel',
        'Nächste 11 Kapitel',
        'Nächste 21 Kapitel',
      ]);
      expect(counts.map(locale.noOfChapters), [
        '0 Kapitel',
        '1 Kapitel',
        '2 Kapitel',
        '3 Kapitel',
        '11 Kapitel',
        '21 Kapitel',
      ]);
    },
  );

  test('Arabic preserves zero, one, two, few and many forms', () {
    final locale = AppLocalizationsAr();
    expect(counts.map(locale.flashEveryPages), [
      'بدون صفحات',
      'صفحة',
      'صفحتان',
      '3 صفحات',
      '11 صفحة',
      '21 صفحة',
    ]);
  });

  test('Russian one category retains the actual count at twenty-one', () {
    final locale = AppLocalizationsRu();
    expect(counts.map(locale.nStores), [
      '0 хранилищ',
      '1 хранилище',
      '2 хранилища',
      '3 хранилища',
      '11 хранилищ',
      '21 хранилище',
    ]);
  });

  test('Two-argument messages preserve names and numeric argument types', () {
    final locale = AppLocalizationsDe();
    expect(
      locale.removeExtensionStoreBody('Example', 'https://example.org'),
      'Möchtest du das Erweiterungsdepot "Example" (https://example.org) entfernen?',
    );
    expect(
      locale.notificationChapterSingleAndMore('12.5', 3),
      'Kapitel 12.5 und 3 mehr',
    );
  });
}
