import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/game.dart';

void main() {
  test('versioned seed boards match the server golden fixtures', () {
    final fixtures = jsonDecode(
      File('test/seed_fixtures.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final entry in fixtures.entries) {
      expect(
        seededBoards(entry.key)
            .map((b) => b.map((c) => c.id).toList())
            .toList(),
        entry.value,
      );
    }
    expect(
      normalizeSeed('https://example.com/?seed=S1-1234ABCD'),
      's1-1234abcd',
    );
    expect(normalizeSeed('s2-1234abcd'), 's2-1234abcd');
    expect(normalizeSeed('s3-1234abcd'), isNull);
  });
  test('legacy s1 seeds retain independent boards', () {
    final first = SetGame(seed: 's1-1234abcd');
    final second = SetGame(seed: 's1-1234abcd');
    final a = findSet(first.board)!;
    final b = findSet(second.board.reversed.toList())!;
    for (final card in a) {
      first.pick(card.id);
    }
    for (final card in b) {
      second.pick(card.id);
    }
    expect(first.board.map((c) => c.id), second.board.map((c) => c.id));
    for (var i = 1; i < 5; i++) {
      for (final card in findSet(first.board)!) {
        first.pick(card.id);
      }
    }
    expect(first.finished, isTrue);
  });
  test('all training targets are solvable and third-card exercises have one answer', () {
    for (var count = 1; count <= 4; count++) {
      for (final pair in [true, false]) {
        for (var seed = 0; seed < 30; seed++) {
          final exercise = TrainingExercise(
            differences: count,
            completePair: pair,
            random: Random(seed),
          );
          expect(exercise.accepts(exercise.solution), isTrue);
          expect(exercise.board.map((c) => c.id).toSet().length, pair ? 6 : 12);
          if (pair) {
            expect(
              exercise.board
                  .where(
                    (c) => exercise.accepts([...exercise.solution.take(2), c]),
                  )
                  .length,
              1,
            );
          } else {
            expect(
              exercise.solution.every((c) => exercise.board.contains(c)),
              isTrue,
            );
          }
        }
      }
    }
  });
  test(
    'starting, abandoning and reloading a seed cannot restore eligibility',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = await PlayerData.load();
      expect(await first.claimSeed('s1-00000001'), isTrue);
      expect(await first.claimSeed('s1-00000001'), isFalse);
      final reloaded = await PlayerData.load();
      expect(reloaded.player, first.player);
      expect(await reloaded.claimSeed('s1-00000001'), isFalse);
      expect(await reloaded.claimSeed('s1-00000002'), isTrue);
      await first.saveBest(12345);
      await first.saveBest(23456);
      expect(first.best, 12345);
    },
  );
}
