import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store.dart';

class OAuthTestPendingStore implements PendingTrackerOAuthStore {
  OAuthTestPendingStore(this.backing);
  final PendingTrackerOAuthStore backing;
  bool failRead = false;
  bool failReplace = false;
  bool failClaim = false;
  bool failCancel = false;
  Future<void> Function()? beforeReplace;
  Future<void> Function()? beforeClaim;
  Future<void> Function()? afterReplace;
  Future<void> Function()? afterClaim;
  Future<void> Function()? beforeCancel;
  int cancellations = 0;

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Pending store unavailable');
    return backing.read();
  }

  @override
  Future<bool> replace(String payload) async {
    await beforeReplace?.call();
    if (failReplace) return false;
    final result = await backing.replace(payload);
    await afterReplace?.call();
    return result;
  }

  @override
  Future<bool> claim(String expectedPayload) async {
    await beforeClaim?.call();
    if (failClaim) return false;
    final result = await backing.claim(expectedPayload);
    await afterClaim?.call();
    return result;
  }

  @override
  Future<bool> clearIfNonce(String nonce) => backing.clearIfNonce(nonce);
  @override
  Future<bool> cancel() async {
    cancellations++;
    await beforeCancel?.call();
    return !failCancel && await backing.cancel();
  }
}
