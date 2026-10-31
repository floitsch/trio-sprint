// Copyright (C) 2026 Florian Loitsch.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'data.dart';
import 'sync_platform_stub.dart'
    if (dart.library.js_interop) 'sync_platform_web.dart'
    as platform;

/// An outbox is persisted before any request. Retrying a lost response is safe.
/// Timers run only while the app is alive; resume/startup also drain the outbox.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService(this.player, {OnlineApi? api}) : api = api ?? OnlineApi();
  final PlayerData player;
  final OnlineApi api;
  Timer? _timer;
  Future<void>? _running;
  bool _disposed = false;
  bool _started = false;
  String? error;
  bool probablyOffline = false;
  bool get offlineReady => platform.offlineReady();
  bool get busy => _running != null;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    player.onRecordsChanged = changed;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
    platform.onOnline(() => unawaited(sync()));
    unawaited(sync());
  }

  void changed() {
    if (_disposed) return;
    notifyListeners();
    unawaited(sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  Future<void> sync() {
    if (_disposed) return Future.value();
    if (_running != null) return _running!;
    // Defer execution so listeners always see an accurate busy flag.
    final work = Future<void>.microtask(() async {
      if (_disposed) return;
      error = null;
      try {
        if (!api.configured) return;
        // Re-read the outbox after every request. A run can finish while a
        // board upload is in flight, and should not wait for the next timer.
        while (!_disposed) {
          final scores = player.savedScores.where(
            (score) =>
                score['status'] == 'pending' &&
                ((score['name'] as String).isNotEmpty ||
                    player.nickname.isNotEmpty),
          );
          if (scores.isNotEmpty) {
            final score = Map<String, dynamic>.from(scores.first);
            if ((score['name'] as String).isEmpty) {
              if (player.nickname.isEmpty) continue;
              score['name'] = player.nickname;
              // Freeze the submitted nickname before the first network attempt.
              await player.updateSavedScore(score);
            }
            final body = Map<String, dynamic>.from(score)
              ..remove('status')
              ..remove('error');
            try {
              await api.request('/scores', body: body);
              probablyOffline = false;
              score['status'] = 'synced';
              await player.updateSavedScore(score);
            } on ApiException catch (failure) {
              probablyOffline = false;
              if (failure.status != 400 && failure.status != 409) rethrow;
              // Keep rejected scores for inspection; never retry them forever
              // or let one conflict prevent other offline runs from uploading.
              score['status'] = 'rejected';
              score['error'] = failure.message;
              await player.updateSavedScore(score);
            }
            continue;
          }
          if (player.pendingAttempts == 0) {
            if (!player.nicknameNeedsSync) break;
            final name = player.nickname;
            await api.request(
              '/players/name',
              body: {'player': player.player, 'name': name},
            );
            probablyOffline = false;
            await player.acknowledgeNickname(name);
            continue;
          }
          final batch = player.attemptBatch();
          final next = player.syncedHistory + batch.length;
          await api.request(
            '/attempts',
            body: {'player': player.player, 'attempts': batch},
          );
          probablyOffline = false;
          await player.acknowledgeAttempts(next);
        }
      } catch (failure) {
        probablyOffline = failure is! ApiException;
        error = 'Saved on this device. Sync will retry: $failure';
      }
    });
    _running = work;
    if (!_disposed) notifyListeners();
    return work.whenComplete(() {
      _running = null;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    platform.onOnline(null);
    player.onRecordsChanged = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
