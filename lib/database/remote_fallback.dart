import '../api/api_reachability.dart';
import '../config/api_config.dart';
import '../sync/pending_sync_service.dart';

/// Tries the remote API first when [ApiConfig.useRemoteApi] is true; on network
/// failure falls back to [local] without disabling future remote attempts.
Future<T> remoteFirst<T>({
  required Future<T> Function() remote,
  required Future<T> Function() local,
  PendingSyncEntry? queueIfLocal,
}) async {
  if (!ApiConfig.useRemoteApi) {
    return local();
  }
  try {
    final result = await remote();
    ApiReachability.instance.markOnline();
    ApiReachability.instance.onReconnectIfNeeded();
    return result;
  } catch (e) {
    if (!ApiReachability.isNetworkFailure(e)) {
      rethrow;
    }
    ApiReachability.instance.markOffline();
    final result = await local();
    if (queueIfLocal != null) {
      await PendingSyncService.instance.enqueue(queueIfLocal);
    }
    return result;
  }
}

Future<void> remoteFirstVoid({
  required Future<void> Function() remote,
  required Future<void> Function() local,
  PendingSyncEntry? queueIfLocal,
}) async {
  await remoteFirst<Object?>(
    remote: () async {
      await remote();
      return null;
    },
    local: () async {
      await local();
      return null;
    },
    queueIfLocal: queueIfLocal,
  );
}
