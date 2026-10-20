import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_de.dart';

void main() {
  test('imported translations keep plurals and interpolation', () {
    final locale = AppLocalizationsDe();
    // A plural selects singular only for one, with "zero" preserved.
    expect([0, 1, 2, 21].map(locale.nStores), [
      '0 Depots',
      '1 Depot',
      '2 Depots',
      '21 Depots',
    ]);
    // Two-argument messages keep their names and numeric argument types.
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
