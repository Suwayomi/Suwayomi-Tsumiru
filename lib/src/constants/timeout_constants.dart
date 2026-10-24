/// Timeout values are in milliseconds.
class TimeoutConstants {
  // Give each retry the full timeout: client aborts do not stop server-side fetches.
  static const int requestTimeoutDefaultMs = 30000;
  static const int requestTimeoutMinMs = 1000;
  static const int requestTimeoutMaxMs = 120000;

  // Retries after the initial attempt.
  static const int autoRefreshMaxRetries = 2;

  static const int autoRefreshRetryDelayDefaultMs = 1000;
  static const int autoRefreshRetryDelayMinMs = 1000;
  static const int autoRefreshRetryDelayMaxMs = 10000;

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
