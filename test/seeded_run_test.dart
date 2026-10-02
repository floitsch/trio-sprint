import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('s2 entire runs match server fixtures and ignore tap order', () {
    final fixtures =
        jsonDecode(File('test/run_fixtures.json').readAsStringSync()) as List;
    for (final fixture in fixtures) {
      final game = SetGame(seed: fixture['seed'] as String);
      for (var pass = 0; pass < 2; pass++) {
        for (var round = 0; round < 5; round++) {
          expect(game.board.map((c) => c.id), fixture['boards'][round]);
          final solution = (fixture['solutions'][round] as List).cast<int>();
          for (final id in pass == 0 ? solution : solution.reversed) {
            game.pick(id);
          }
          expect(game.streak, round + 1);
        }
        expect(game.finished, isTrue);
        game.restart();
      }
    }
  });

  test('500 s2 runs preserve nine cards and reproduce the full path', () {
    for (var seed = 0; seed < 500; seed++) {
      final value = 's2-${seed.toRadixString(16).padLeft(8, '0')}';
      final game = SetGame(seed: value);
      final replay = SetGame(seed: value);
      for (var round = 0; round < 5; round++) {
        final before = game.board.map((c) => c.id).toList();
        final solution = findSet(
          seed.isEven ? game.board : game.board.reversed.toList(),
        )!;
        for (final card in solution) {
          game.pick(card.id);
        }
        for (final card in solution.reversed) {
          replay.pick(card.id);
        }
        expect(game.board.map((c) => c.id), replay.board.map((c) => c.id));
        expect(game.board.map((c) => c.id).toSet().length, 12);
        final removed = solution.map((c) => c.id).toSet();
        for (var i = 0; i < 12; i++) {
          if (!removed.contains(before[i]) || round == 4) {
            expect(game.board[i].id, before[i]);
          }
        }
        expect(findSet(game.board), isNotNull);
      }
    }
  });

  test('different set choices may branch a seeded run', () {
    final first = SetGame(seed: 's2-00000000');
    final second = SetGame(seed: 's2-00000000');
    final a = findSet(first.board)!;
    final b = findSet(second.board.reversed.toList())!;
    expect(a.map((c) => c.id).toSet(), isNot(b.map((c) => c.id).toSet()));
    for (final c in a) {
      first.pick(c.id);
    }
    for (final c in b) {
      second.pick(c.id);
    }
    expect(first.board.map((c) => c.id), isNot(second.board.map((c) => c.id)));
  });

  test('new and legacy runs have separate personal bests', () async {
    SharedPreferences.setMockInitialValues({'best': 1000});
    final player = await PlayerData.load();
    expect(player.best, isNull);
    await player.saveBest(10000, seed: 's2-1234abcd');
    expect(player.best, 10000);
    expect(player.bestForSeed('s1-1234abcd'), 1000);
    await player.saveBest(500, seed: 's1-1234abcd');
    expect(player.best, 10000);
    expect(player.bestForSeed('s1-1234abcd'), 500);
  });

  testWidgets(
    'restart uses a fresh seed while replay keeps the completed seed',
    (tester) async {
      await tester.pumpWidget(const TrioSprintApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      String shownSeed() => tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .singleWhere((text) => text.startsWith('First attempt · '))
          .split(' · ')
          .last;
      final original = shownSeed();
      await tester.tap(find.byTooltip('Restart run'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      final fresh = shownSeed();
      expect(fresh, isNot(original));
      for (var round = 0; round < 5; round++) {
        final cards = tester
            .widgetList<CardView>(find.byType(CardView))
            .map((view) => view.card)
            .toList();
        for (final card in findSet(cards)!) {
          await tester.tap(find.byKey(ValueKey('card-${card.id}')));
          await tester.pump();
        }
      }
      // Random seeds are new by construction; without a nickname (or API)
      // nothing uploads automatically, so the button remains.
      expect(find.text('First time on this seed?'), findsNothing);
      expect(
        find.text('First attempt. It can enter the high scores.'),
        findsOneWidget,
      );
      expect(find.text('Submit high score'), findsOneWidget);
      await tester.ensureVisible(find.text('Replay seed (practice)'));
      await tester.tap(find.text('Replay seed (practice)'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Practice replay · $fresh'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final duringCountdown in [true, false]) {
    testWidgets(
      'abandon cancels the run and preserves first-attempt status; countdown=$duringCountdown',
      (tester) async {
        await tester.pumpWidget(const TrioSprintApp());
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Run a seed'));
        await tester.tap(find.text('Run a seed'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 's2-1234abcd');
        await tester.tap(find.text('Run seed'));
        await tester.pumpAndSettle();
        expect(find.text('First time on this seed?'), findsOneWidget);
        await tester.tap(find.text('First time'));
        await tester.pump();
        await tester.pump();
        expect(find.text('2'), findsOneWidget);
        if (!duringCountdown) {
          await tester.pump(const Duration(seconds: 2));
          final board = tester
              .widgetList<CardView>(find.byType(CardView))
              .map((v) => v.card)
              .toList();
          final wrong = [
            board[0],
            board[1],
            board.skip(2).firstWhere((c) => !isSet([board[0], board[1], c])),
          ];
          for (final card in wrong) {
            await tester.tap(find.byKey(ValueKey('card-${card.id}')));
            await tester.pump();
          }
        }
        await tester.tap(find.text('Abandon'));
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('Start run'), findsOneWidget);
        expect(find.byKey(const ValueKey('countdown')), findsNothing);
        expect(find.byKey(const ValueKey('timer')), findsNothing);
        final player = await PlayerData.load();
        expect(await player.claimSeed('s2-1234abcd'), isFalse);
        if (!duringCountdown) expect(player.practiceHistory.single.mistakes, 1);
        await tester.ensureVisible(find.text('Run a seed'));
        await tester.tap(find.text('Run a seed'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 's2-1234abcd');
        await tester.tap(find.text('Run seed'));
        await tester.pumpAndSettle();
        // This device already knows the seed, so there is nothing to ask.
        expect(find.text('First time on this seed?'), findsNothing);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Practice replay · s2-1234abcd'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  Future<void> typeSeed(WidgetTester tester, String seed) async {
    await tester.ensureVisible(find.text('Run a seed'));
    await tester.tap(find.text('Run a seed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), seed);
    await tester.tap(find.text('Run seed'));
    await tester.pumpAndSettle();
  }

  testWidgets('typed seeds that were played elsewhere become practice', (
    tester,
  ) async {
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await typeSeed(tester, 's2-0000abcd');
    await tester.tap(find.text('Played before'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Practice replay · s2-0000abcd'), findsOneWidget);
    final player = await PlayerData.load();
    expect(await player.hasAttempted('s2-0000abcd'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelling the first-attempt question does not use the seed', (
    tester,
  ) async {
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await typeSeed(tester, 's2-0000abcd');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Start run'), findsOneWidget);
    final player = await PlayerData.load();
    expect(await player.hasAttempted('s2-0000abcd'), isFalse);
    await typeSeed(tester, 's2-0000abcd');
    expect(find.text('First time on this seed?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
