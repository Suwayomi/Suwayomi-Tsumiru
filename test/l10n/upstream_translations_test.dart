import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_ar.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_de.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_ja.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_ru.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_zh.dart';

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

  test('German pilot preserves zero meanings and legacy select keys', () {
    final locale = AppLocalizationsDe();
    expect(counts.map(locale.nChapters), [
      'Keine',
      '1 Kapitel',
      '2 Kapitel',
      '3 Kapitel',
      '11 Kapitel',
      '21 Kapitel',
    ]);
    expect(locale.nDays('01'), '01 Tag');
    expect(locale.nDays('1'), '1 Tage');
    expect(locale.nDays('0'), '0 Tage');
    expect(locale.nDays('21'), '21 Tage');
    expect(locale.backupCleanupDescription('0'), 'Nie');
    expect(
      locale.backupCleanupDescription('01'),
      'Sicherungen löschen, die älter als 1 Tag sind',
    );
    expect(
      locale.backupCleanupDescription('21'),
      'Sicherungen löschen, die älter als 21 Tage sind',
    );
  });

  test('German pilot dates and migration counts retain their quantities', () {
    final locale = AppLocalizationsDe();
    expect(counts.map(locale.daysAgo), [
      'Vor 0 Tagen',
      'Vor 1 Tag',
      'Vor 2 Tagen',
      'Vor 3 Tagen',
      'Vor 11 Tagen',
      'Vor 21 Tagen',
    ]);
    expect(locale.inNDays(1), 'In 1 Tag');
    expect(locale.inNDays(21), 'In 21 Tagen');
    expect(locale.minutesAgo(1), 'Vor 1 Minute');
    expect(locale.minutesAgo(21), 'Vor 21 Minuten');
    expect(locale.hoursAgo(1), 'Vor 1 Stunde');
    expect(locale.hoursAgo(21), 'Vor 21 Stunden');
    expect(locale.nHours(1), '1 Stunde');
    expect(locale.nHours(21), '21 Stunden');
    expect(locale.nRepo(1), '1 Depot');
    expect(locale.nRepo(21), '21 Depots');
    expect(locale.migrationSourceSeriesCount(1), '1 Serie');
    expect(locale.migrationSourceSeriesCount(21), '21 Serien');
    expect(
      locale.migrationTrackerCollisionSummary(1),
      startsWith('1 Serie hat'),
    );
    expect(
      locale.migrationTrackerCollisionSummary(21),
      startsWith('21 Serien haben'),
    );
    expect(
      locale.duplicatesRemoveConfirm(1),
      startsWith('1 Eintrag aus deiner Bibliothek entfernen?'),
    );
    expect(
      locale.duplicatesRemoveConfirm(21),
      startsWith('21 Einträge aus deiner Bibliothek entfernen?'),
    );
  });

  test('German pilot interpolates account and download details', () {
    final locale = AppLocalizationsDe();
    expect(
      locale.accountCatalogueRemoveConfirm('Anna', 'example.org'),
      'Die heruntergeladenen Kapitel und die Offline-Bibliothek für Anna '
      'auf example.org von diesem Gerät entfernen? '
      'Die Daten auf dem Server bleiben unverändert.',
    );
    expect(locale.accountPermissionsSummary(2, 9), '2 von 9 erlaubt');
    expect(locale.downloadPagesProgress(2, 9), '2/9 Seiten');
    expect(
      locale.updatingLibraryProgress(25, 1, 4),
      'Bibliothek wird aktualisiert (25% · 1/4)',
    );
    expect(
      locale.trackRemoveConfirmBody('AniList'),
      'Die Verknüpfung mit AniList wird entfernt.',
    );
    expect(locale.searchTipsBody, contains('status:ongoing'));
    expect(locale.searchTipsBody, contains('tag:"slice of life"'));
    expect(locale.searchTipsBody, contains('-tag:dropped'));
  });

  test('Chinese completion retains quantities and script-specific wording', () {
    final simplified = AppLocalizationsZhHans();
    final traditional = AppLocalizationsZhHant();
    final generic = AppLocalizationsZh();
    for (final count in counts) {
      expect(simplified.offlineRecoveryCompleted(count), '已恢复 $count 张图片');
      expect(traditional.offlineRecoveryCompleted(count), '已復原 $count 張圖片');
      expect(
        generic.offlineRecoveryCompleted(count),
        simplified.offlineRecoveryCompleted(count),
      );
    }
    expect(simplified.accountPermissionsSummary(2, 9), '已允许 2 项，共 9 项');
    expect(traditional.accountPermissionsSummary(2, 9), '已允許 2 項，共 9 項');
    expect(simplified.accountCodeExpires('2026-09-22'), '到期时间：2026-09-22');
    expect(traditional.accountCodeExpires('2026-09-22'), '到期時間：2026-09-22');
    expect(traditional.accountSignOut, '登出');
    expect(simplified.accountSignOut, '退出登录');
    expect(generic.accountSignOut, simplified.accountSignOut);
  });

  test(
    'Chinese account removal keeps account and server arguments distinct',
    () {
      final simplified = AppLocalizationsZhHans();
      final traditional = AppLocalizationsZhHant();
      expect(
        simplified.accountCatalogueRemoveConfirm('Alice', 'example.org'),
        '从此设备移除 example.org 上 Alice 的已下载章节和离线书架？服务器数据将保持不变。',
      );
      expect(
        traditional.accountCatalogueRemoveConfirm('Alice', 'example.org'),
        '從此裝置移除 example.org 上 Alice 的已下載章節和離線書架？伺服器資料將保持不變。',
      );
      expect(
        simplified.accountCatalogueRemoveConfirm(
          simplified.accountCatalogueOwner('7'),
          'example.org',
        ),
        '从此设备移除 example.org 上 账户 7 的已下载章节和离线书架？服务器数据将保持不变。',
      );
      expect(
        traditional.accountCatalogueRemoveConfirm(
          traditional.accountCatalogueWithoutLogin,
          'example.org',
        ),
        '從此裝置移除 example.org 上 未登入帳戶時的下載 的已下載章節和離線書架？伺服器資料將保持不變。',
      );
      expect(traditional.offlineRecoveryCurrent, '使用目前進度');
      expect(traditional.offlineRecoveryOriginal, '使用原始進度');
      expect(traditional.offlineRecoveryPendingSync('書籤'), '待同步：書籤');
      expect(simplified.offlineRecoveryPendingSync('书签'), '待同步：书签');
      expect(traditional.offlineRecoveryLastRead('12:34'), '上次閱讀：12:34');
    },
  );

  test('Japanese completion retains counts without English plural grammar', () {
    final locale = AppLocalizationsJa();
    for (final count in counts) {
      expect(locale.minutesAgo(count), '$count分前');
      expect(locale.hoursAgo(count), '$count時間前');
      expect(locale.inNDays(count), '$count日後');
      expect(locale.migrationSourceSeriesCount(count), '$count作品');
      expect(
        locale.migrationTrackerCollisionSummary(count),
        startsWith('$count作品は'),
      );
      expect(
        locale.duplicatesRemoveConfirm(count),
        startsWith('ライブラリから$count件を削除しますか？'),
      );
      expect(locale.offlineRecoveryCompleted(count), '画像を$count枚復元しました');
    }
    expect(locale.nChapters(0), 'なし');
    expect(locale.nDays('01'), '1日');
    expect(locale.backupCleanupDescription('0'), 'Never');
  });

  test('Japanese completion keeps account labels and tracker links distinct', () {
    final locale = AppLocalizationsJa();
    expect(locale.accountPermissionsSummary(2, 9), '9項目中2項目を許可');
    expect(
      locale.accountCatalogueRemoveConfirm(
        locale.accountCatalogueOwner('7'),
        'example.org',
      ),
      'example.org の「アカウント 7」に属するダウンロード済みの章とオフラインライブラリを、この端末から削除しますか？サーバーのデータは変更されません。',
    );
    expect(
      locale.accountCatalogueRemoveConfirm(
        locale.accountCatalogueWithoutLogin,
        'example.org',
      ),
      contains('「未ログイン時のダウンロード」'),
    );
    expect(locale.trackRemoveConfirmBody('AniList'), 'AniList との連携を解除します。');
    expect(locale.offlineRecoveryPendingSync('ブックマーク'), '同期待ち：ブックマーク');
    for (final syntax in [
      'tag:seinen',
      'genre:action',
      'author:oda',
      'status:ongoing',
      'completed',
      'hiatus',
      'cancelled',
      'source:mangadex',
      'tracked:true',
      'tracked:anilist',
      'rating:>=4',
      'unread:true',
      'downloaded:true',
      'tag:"slice of life"',
      '-tag:dropped',
    ]) {
      expect(locale.searchTipsBody, contains(syntax));
    }
  });

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
