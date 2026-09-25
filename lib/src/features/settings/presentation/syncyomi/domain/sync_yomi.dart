/// SyncYomi keeps its interval as an ISO-8601 duration string, shared with
/// Suwayomi-WebUI. PT0S means "only when the user asks".
const kSyncYomiIntervalManual = 'PT0S';

const kSyncYomiIntervalOptions = <String>[
  kSyncYomiIntervalManual,
  'PT1H',
  'PT6H',
  'PT12H',
  'PT24H',
];

final _httpScheme = RegExp(r'^https?://', caseSensitive: false);
final _trailingSlashes = RegExp(r'/+$');
final _isoDuration = RegExp(
  r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
);

/// The bare origin the server appends `/api/sync/...` to, or null when [raw]
/// is not an http(s) URL with a host.
String? normaliseSyncYomiHost(String raw) {
  final trimmed = raw.trim();
  if (!_httpScheme.hasMatch(trimmed)) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return null;
  return trimmed.replaceFirst(_trailingSlashes, '');
}

/// Hours/minutes of an ISO-8601 duration, or null when it does not parse.
Duration? parseIsoDuration(String? value) {
  if (value == null) return null;
  final match = _isoDuration.firstMatch(value.trim());
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 4; i++) match.group(i)];
  if (parts.every((part) => part == null)) return null;
  int part(int index) => int.tryParse(parts[index] ?? '') ?? 0;
  return Duration(
    days: part(0),
    hours: part(1),
    minutes: part(2),
    seconds: part(3),
  );
}

/// The server sends epoch milliseconds as a string.
DateTime? parseEpochMillis(String? value) {
  final millis = int.tryParse(value?.trim() ?? '');
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}

enum SyncYomiStatusKind { never, syncing, synced, failed }

class SyncYomiStatusView {
  const SyncYomiStatusView({required this.kind, this.endDate, this.error});

  final SyncYomiStatusKind kind;
  final DateTime? endDate;
  final String? error;
}

/// Which line the status row should show. Every state other than SUCCESS and
/// ERROR counts as still running, including ones this build doesn't know.
SyncYomiStatusView syncYomiStatusView({
  String? state,
  String? endDate,
  String? errorMessage,
}) {
  if (state == null) {
    return const SyncYomiStatusView(kind: SyncYomiStatusKind.never);
  }
  return switch (state) {
    'SUCCESS' => SyncYomiStatusView(
      kind: SyncYomiStatusKind.synced,
      endDate: parseEpochMillis(endDate),
    ),
    'ERROR' => SyncYomiStatusView(
      kind: SyncYomiStatusKind.failed,
      error: errorMessage,
    ),
    _ => const SyncYomiStatusView(kind: SyncYomiStatusKind.syncing),
  };
}

enum SyncYomiIntervalLabel {
  manualOnly,
  everyHour,
  every6Hours,
  every12Hours,
  everyDay,
  everyNHours,
  everyNMinutes,
  verbatim,
}

class SyncYomiIntervalDescription {
  const SyncYomiIntervalDescription(this.label, {this.count = 0, this.raw});

  final SyncYomiIntervalLabel label;
  final int count;
  final String? raw;
}

/// How to word a stored interval. A value the picker doesn't offer came from
/// another client, so it is read out in whole hours or whole minutes.
SyncYomiIntervalDescription describeSyncYomiInterval(String value) {
  switch (value) {
    case 'PT0S':
      return const SyncYomiIntervalDescription(
        SyncYomiIntervalLabel.manualOnly,
      );
    case 'PT1H':
      return const SyncYomiIntervalDescription(SyncYomiIntervalLabel.everyHour);
    case 'PT6H':
      return const SyncYomiIntervalDescription(
        SyncYomiIntervalLabel.every6Hours,
      );
    case 'PT12H':
      return const SyncYomiIntervalDescription(
        SyncYomiIntervalLabel.every12Hours,
      );
    case 'PT24H':
      return const SyncYomiIntervalDescription(SyncYomiIntervalLabel.everyDay);
  }
  final duration = parseIsoDuration(value);
  if (duration == null) {
    return SyncYomiIntervalDescription(
      SyncYomiIntervalLabel.verbatim,
      raw: value,
    );
  }
  if (duration.inMinutes == 0) {
    return const SyncYomiIntervalDescription(SyncYomiIntervalLabel.manualOnly);
  }
  return duration.inMinutes % 60 == 0
      ? SyncYomiIntervalDescription(
          SyncYomiIntervalLabel.everyNHours,
          count: duration.inHours,
        )
      : SyncYomiIntervalDescription(
          SyncYomiIntervalLabel.everyNMinutes,
          count: duration.inMinutes,
        );
}
