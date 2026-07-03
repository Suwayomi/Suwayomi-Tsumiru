/// TimeoutSettings constant values
/// Values are stored in milliseconds.
class TimeoutConstants {
  // Server request timeout. 30s default matches Komikku's source read
  // timeout; the 120s ceiling matches its whole-call cap. Each retry attempt
  // gets the FULL timeout: short rapid-fire attempts abort client-side while
  // the server keeps fetching, and stacked aborted fetches have been observed
  // to drive a Suwayomi server to 2GB RAM / 70% CPU (Discord, 2026-07-03).
  static const int requestTimeoutDefaultMs = 30000;
  static const int requestTimeoutMinMs = 1000;
  static const int requestTimeoutMaxMs = 120000;

  // Full-length attempts, at most this many retries after the first try.
  static const int autoRefreshMaxRetries = 2;

  // Auto-refresh retry delay
  static const int autoRefreshRetryDelayDefaultMs = 1000;
  static const int autoRefreshRetryDelayMinMs = 1000;
  static const int autoRefreshRetryDelayMaxMs = 10000;

  // Helper getters in seconds
  static int get requestTimeoutDefaultSeconds =>
      requestTimeoutDefaultMs ~/ 1000;
  static int get requestTimeoutMinSeconds => requestTimeoutMinMs ~/ 1000;
  static int get requestTimeoutMaxSeconds => requestTimeoutMaxMs ~/ 1000;

  static int get autoRefreshRetryDelayDefaultSeconds =>
      autoRefreshRetryDelayDefaultMs ~/ 1000;
  static int get autoRefreshRetryDelayMinSeconds =>
      autoRefreshRetryDelayMinMs ~/ 1000;
  static int get autoRefreshRetryDelayMaxSeconds =>
      autoRefreshRetryDelayMaxMs ~/ 1000;
}
