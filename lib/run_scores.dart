// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/foundation.dart';

import 'data.dart';
import 'sync.dart';

/// Persists a completed run before the UI allows another attempt.
class RunScoreSubmission extends ChangeNotifier {
  bool busy = false;
  Object? error;
  bool _disposed = false;

  void reset() {
    if (busy) return;
    error = null;
    notifyListeners();
  }

  Future<bool> save(Future<void> Function() persist) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await persist();
      return true;
    } catch (failure) {
      error = failure;
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String runScoreSyncStatus({
  required Map<String, dynamic> saved,
  required PlayerData player,
  SyncService? sync,
}) {
  if (saved['status'] == 'synced') {
    return 'Score submitted as ${saved['name']}.';
  }
  if (saved['status'] == 'rejected') {
    return 'Score not accepted: ${saved['error']}';
  }
  if ((saved['name'] as String? ?? '').isEmpty && player.nickname.isEmpty) {
    return 'Saved on this device. Add a nickname to publish your score.';
  }
  if (sync != null && !sync.api.configured) {
    return 'Saved on this device. Online scores are not configured in this build.';
  }
  if (sync?.busy == true) return 'Uploading score…';
  if (sync?.error != null) {
    return 'Upload pending. Saved on this device; retrying automatically.';
  }
  return 'Saved on this device. Upload pending.';
}
