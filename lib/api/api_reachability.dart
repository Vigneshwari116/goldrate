import 'dart:async';

import 'package:flutter/foundation.dart';

import '../sync/offline_cache_sync.dart';
import '../sync/pending_sync_service.dart';
import 'api_client.dart';

/// Tracks whether the remote API is reachable for the current session.
/// A single failed request does not permanently disable the API; the next
/// operation tries the server again.
class ApiReachability {
  ApiReachability._();

  static final ApiReachability instance = ApiReachability._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  bool _wasOffline = false;

  void markOnline() {
    if (!isOnline.value) {
      isOnline.value = true;
      _wasOffline = true;
    }
  }

  void markOffline() {
    if (isOnline.value) {
      isOnline.value = false;
    }
  }

  /// After reconnect, run pending sync once.
  void onReconnectIfNeeded() {
    if (!_wasOffline) return;
    _wasOffline = false;
    unawaited(PendingSyncService.instance.flushPending());
    unawaited(OfflineCacheSync.instance.pullFromServerIfOnline());
  }

  static bool isNetworkFailure(Object error) {
    if (error is TimeoutException) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains('cannot reach server') ||
        msg.contains('timeout') ||
        msg.contains('timed out') ||
        msg.contains('socketexception') ||
        msg.contains('socket exception') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('clientexception');
  }

  /// Probes the server without throwing; used during bootstrap.
  Future<bool> probeHealth() async {
    try {
      final ok = await ApiClient.checkHealth();
      if (ok) {
        markOnline();
        onReconnectIfNeeded();
      } else {
        markOffline();
      }
      return ok;
    } catch (_) {
      markOffline();
      return false;
    }
  }
}
