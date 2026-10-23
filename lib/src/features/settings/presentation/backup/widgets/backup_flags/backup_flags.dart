import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../domain/settings/settings.dart';

class BackupFlags {
  const BackupFlags({
    this.includeManga = true,
    this.includeCategories = true,
    this.includeChapters = true,
    this.includeTracking = true,
    this.includeHistory = true,
    this.includeClientData = true,
    this.includeServerSettings = true,
  });

  factory BackupFlags.fromAuto(AutoBackupFlagsDto dto) => BackupFlags(
    includeManga: dto.autoBackupIncludeManga,
    includeCategories: dto.autoBackupIncludeCategories,
    includeChapters: dto.autoBackupIncludeChapters,
    includeTracking: dto.autoBackupIncludeTracking,
    includeHistory: dto.autoBackupIncludeHistory,
    includeClientData: dto.autoBackupIncludeClientData,
    includeServerSettings: dto.autoBackupIncludeServerSettings,
  );

  final bool includeManga;
  final bool includeCategories;
  final bool includeChapters;
  final bool includeTracking;
  final bool includeHistory;
  final bool includeClientData;
  final bool includeServerSettings;

  BackupFlags copyWith({
    bool? includeManga,
    bool? includeCategories,
    bool? includeChapters,
    bool? includeTracking,
    bool? includeHistory,
    bool? includeClientData,
    bool? includeServerSettings,
  }) => BackupFlags(
    includeManga: includeManga ?? this.includeManga,
    includeCategories: includeCategories ?? this.includeCategories,
    includeChapters: includeChapters ?? this.includeChapters,
    includeTracking: includeTracking ?? this.includeTracking,
    includeHistory: includeHistory ?? this.includeHistory,
    includeClientData: includeClientData ?? this.includeClientData,
    includeServerSettings: includeServerSettings ?? this.includeServerSettings,
  );

  Input$PartialBackupFlagsInput toPartialInput() =>
      Input$PartialBackupFlagsInput(
        includeManga: includeManga,
        includeCategories: includeCategories,
        includeChapters: includeChapters,
        includeTracking: includeTracking,
        includeHistory: includeHistory,
        includeClientData: includeClientData,
        includeServerSettings: includeServerSettings,
      );

  Input$PartialSettingsTypeInput toAutoInput() =>
      Input$PartialSettingsTypeInput(
        autoBackupIncludeManga: includeManga,
        autoBackupIncludeCategories: includeCategories,
        autoBackupIncludeChapters: includeChapters,
        autoBackupIncludeTracking: includeTracking,
        autoBackupIncludeHistory: includeHistory,
        autoBackupIncludeClientData: includeClientData,
        autoBackupIncludeServerSettings: includeServerSettings,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BackupFlags &&
          includeManga == other.includeManga &&
          includeCategories == other.includeCategories &&
          includeChapters == other.includeChapters &&
          includeTracking == other.includeTracking &&
          includeHistory == other.includeHistory &&
          includeClientData == other.includeClientData &&
          includeServerSettings == other.includeServerSettings);

  @override
  int get hashCode => Object.hash(
    includeManga,
    includeCategories,
    includeChapters,
    includeTracking,
    includeHistory,
    includeClientData,
    includeServerSettings,
  );
}

({String include, String exclude}) summarizeBackupFlags({
  required List<(String, bool)> entries,
  required String all,
  required String none,
}) {
  String describe(Iterable<String> labels) {
    final list = labels.toList();
    if (list.isEmpty) return none;
    if (list.length == entries.length) return all;
    return list.join(', ');
  }

  return (
    include: describe([
      for (final entry in entries)
        if (entry.$2) entry.$1,
    ]),
    exclude: describe([
      for (final entry in entries)
        if (!entry.$2) entry.$1,
    ]),
  );
}
