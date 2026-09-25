import '../../../../../graphql/__generated__/schema.graphql.dart';

/// Anything at or below zero is stored as this, the server's smallest value.
const double koreaderSyncMinimumTolerance = 1e-15;

const List<Enum$KoreaderSyncConflictStrategy> koreaderSyncConflictStrategies = [
  Enum$KoreaderSyncConflictStrategy.PROMPT,
  Enum$KoreaderSyncConflictStrategy.KEEP_LOCAL,
  Enum$KoreaderSyncConflictStrategy.KEEP_REMOTE,
  Enum$KoreaderSyncConflictStrategy.DISABLED,
];

const List<Enum$KoreaderSyncChecksumMethod> koreaderSyncChecksumMethods = [
  Enum$KoreaderSyncChecksumMethod.BINARY,
  Enum$KoreaderSyncChecksumMethod.FILENAME,
];

double? parsePercentageTolerance(String raw) {
  final parsed = double.tryParse(raw.trim());
  if (parsed == null || !parsed.isFinite || parsed > 1) return null;
  return parsed <= 0 ? koreaderSyncMinimumTolerance : parsed;
}

String formatPercentageTolerance(double value) {
  if (value < 0.005) return '0';
  final text = value.toStringAsFixed(2);
  if (text.endsWith('.00')) return text.substring(0, text.length - 3);
  if (text.endsWith('0')) return text.substring(0, text.length - 1);
  return text;
}

String formatPercentageToleranceInput(double value) =>
    value <= koreaderSyncMinimumTolerance ? '0' : value.toString();

typedef KoreaderSyncSettings = ({
  Enum$KoreaderSyncConflictStrategy strategyForward,
  Enum$KoreaderSyncConflictStrategy strategyBackward,
  Enum$KoreaderSyncChecksumMethod checksumMethod,
  double percentageTolerance,
});

class KoSyncStatus {
  const KoSyncStatus({
    required this.isLoggedIn,
    this.serverAddress,
    this.username,
  });

  final bool isLoggedIn;
  final String? serverAddress;
  final String? username;
}
