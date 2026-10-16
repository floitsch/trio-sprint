// Copyright (C) 2026 Toit contributors.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/practice.dart';
import 'package:trio_sprint/sync.dart';
import 'package:trio_sprint/sync_screen.dart';

class FakeApi extends OnlineApi {
  bool offline = false;
  bool loseResponse = false;
  final uploadedScores = <String, Map<String, dynamic>>{};
  final attempts = <String, Map<String, dynamic>>{};
  final rejected = <String>{};
  final calls = <String>[];
  Completer<void>? gate;
  String? gatePath;
  @override
  bool get configured => true;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add(path);
    if (offline) throw Exception('No connection');
    if (gate != null && (gatePath == null || gatePath == path)) {
      await gate!.future;
    }
    if (path == '/scores') {
      if (rejected.contains(body!['seed'])) {
        throw const ApiException(409, 'Seed already submitted');
      }
      uploadedScores.putIfAbsent(body['seed'] as String, () => body);
    } else if (path == '/attempts') {
      for (final attempt in body!['attempts'] as List) {
        attempts.putIfAbsent(
          '${body['player']}/${attempt['id']}',
          () => attempt as Map<String, dynamic>,
        );
      }
    } else {
      throw StateError('Unexpected request: $path');
    }
    if (loseResponse) throw TimeoutException('Response lost after saving');
    return {'ok': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> saveRun(PlayerData player, String seed) async {
    final game = SetGame(seed: seed);
    final solutions = <List<int>>[];
    for (var i = 0; i < 5; i++) {
      final solution = findSet(game.board)!;
      solutions.add(solution.map((c) => c.id).toList());
      await player.recordPractice(
        PracticeBoard(
          cards: game.board.map((c) => c.id).toList(),
          milliseconds: 2000,
          source: 's2',
          seed: seed,
          solutionCards: solutions.last,
        ),
      );
      for (final card in solution) {
        game.pick(card.id);
      }
    }
    await player.queueScore(
      seed: seed,
      milliseconds: 10000,
      mistakes: 0,
      solutions: solutions,
    );
  }

  test(
    'offline runs survive reopen and upload once with their original nickname',
    () async {
      final player = await PlayerData.load();
      await player.setNickname('Before flight');
      await saveRun(player, 's2-1234abcd');
      final api = FakeApi()..offline = true;
      final first = SyncService(player, api: api);
      await first.sync();
      expect(player.pendingScores, 1);
      expect(player.pendingAttempts, 5);
      expect(first.error, contains('Saved on this device'));
      expect(first.probablyOffline, isTrue);
      first.dispose();

      final restored = await PlayerData.load();
      await restored.setNickname('After flight');
      final second = SyncService(restored, api: api);
      api.offline = false;
      await second.sync();
      expect(restored.pendingScores, 0);
      expect(restored.pendingAttempts, 0);
      expect(second.probablyOffline, isFalse);
      expect(api.uploadedScores.values.single['name'], 'Before flight');
      expect(api.attempts.length, 5);
      expect(restored.attemptsHistory.length, 5);
      final requests = api.calls.length;
      await second.sync();
      expect(api.calls.length, requests);
      second.dispose();
    },
  );

  test('lost acknowledgements retry idempotently after restart', () async {
    final player = await PlayerData.load();
    await player.setNickname('Pilot');
    await saveRun(player, 's2-1234abcd');
    final api = FakeApi()..loseResponse = true;
    final first = SyncService(player, api: api);
    await first.sync();
    expect(api.uploadedScores.length, 1);
    expect(player.pendingScores, 1);
    first.dispose();
    api.loseResponse = false;
    final restored = await PlayerData.load();
    final second = SyncService(restored, api: api);
    await second.sync();
    expect(api.uploadedScores.length, 1);
    expect(restored.pendingScores, 0);
    expect(restored.pendingAttempts, 0);
    second.dispose();
  });

  test('unnamed scores wait while board history syncs; conflicts do not block later runs', () async {
    final player = await PlayerData.load();
    await saveRun(player, 's2-1234abcd');
    await saveRun(player, 's2-abcdef12');
    final api = FakeApi();
    final sync = SyncService(player, api: api);
    await sync.sync();
    expect(api.uploadedScores, isEmpty);
    expect(api.attempts.length, 10);
    expect(player.pendingScores, 2);
    await player.setNickname('Traveller');
    api.rejected.add('s2-1234abcd');
    await sync.sync();
    expect(player.pendingScores, 0);
    expect(player.rejectedScores, 1);
    expect(
      player.savedScore('s2-1234abcd')!['error'],
      'Seed already submitted',
    );
    expect(api.uploadedScores.keys, ['s2-abcdef12']);
    // A later replay can never replace the saved first attempt.
    await player.queueScore(
      seed: 's2-abcdef12',
      milliseconds: 10,
      mistakes: 0,
      solutions: [],
    );
    expect(player.savedScore('s2-abcdef12')!['milliseconds'], 10000);
    sync.dispose();
  });

  test('concurrent sync requests and new records during an upload do not lose data', () async {
    final player = await PlayerData.load();
    await player.setNickname('Traveller');
    await saveRun(player, 's2-1234abcd');
    final api = FakeApi()
      ..gate = Completer<void>()
      ..gatePath = '/attempts';
    final sync = SyncService(player, api: api);
    final first = sync.sync();
    final second = sync.sync();
    await Future<void>.delayed(Duration.zero);
    await saveRun(player, 's2-abcdef12');
    api.gate!.complete();
    await Future.wait([first, second]);
    expect(api.attempts.length, 10);
    expect(player.pendingAttempts, 0);
    expect(player.pendingScores, 0);
    expect(api.uploadedScores.keys, ['s2-1234abcd', 's2-abcdef12']);
    expect(api.calls.where((path) => path == '/attempts').length, 2);
    sync.dispose();
  });

  testWidgets(
    'offline status clears after automatic sync without a retry button',
    (tester) async {
      final player = await PlayerData.load();
      await player.setNickname('Traveller');
      await saveRun(player, 's2-1234abcd');
      final api = FakeApi()..offline = true;
      final sync = SyncService(player, api: api);
      await sync.sync();
      await tester.pumpWidget(MaterialApp(home: SyncScreen(sync: sync)));
      expect(find.textContaining('You may be offline.'), findsOneWidget);
      expect(find.textContaining('Sync now'), findsNothing);
      api.offline = false;
      await sync.sync();
      await tester.pump();
      expect(find.textContaining('You may be offline.'), findsNothing);
      expect(find.text('Nothing waiting to upload.'), findsOneWidget);
      expect(player.pendingScores, 0);
      await tester.pumpWidget(const SizedBox());
      sync.dispose();
    },
  );

  test(
    'history uploads retain interruptions, skips and training constraints',
    () async {
      final player = await PlayerData.load();
      final exercise = TrainingExercise(differences: 2, completePair: true);
      for (final outcome in AttemptOutcome.values) {
        await player.recordPractice(
          PracticeBoard(
            cards: exercise.board.map((c) => c.id).toList(),
            anchors: exercise.solution.take(2).map((c) => c.id).toList(),
            differences: 2,
            milliseconds: 120000,
            source: 'training',
            outcome: outcome,
          ),
        );
      }
      final api = FakeApi()..loseResponse = true;
      final sync = SyncService(player, api: api);
      await sync.sync();
      expect(player.pendingAttempts, 5);
      api.loseResponse = false;
      await sync.sync();
      expect(api.attempts.length, 5);
      expect(
        api.attempts.values.map((a) => (a['board'] as Map)['outcome']).toSet(),
        AttemptOutcome.values.map((o) => o.name).toSet(),
      );
      expect(player.pendingAttempts, 0);
      sync.dispose();
    },
  );
}
