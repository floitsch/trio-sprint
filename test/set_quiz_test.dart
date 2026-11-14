// Copyright (C) 2026 Florian Loitsch.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/main.dart';
import 'package:trio_sprint/data.dart';
import 'package:trio_sprint/quiz_leaderboard.dart';
import 'package:trio_sprint/set_quiz.dart';
import 'package:trio_sprint/sync.dart';
import 'package:trio_sprint/practice.dart';
import 'package:trio_sprint/quiz_seed.dart';
import 'package:trio_sprint/quiz_review.dart';

void main() {
  for (final difficult in [false, true]) {
    test(
      'balanced, distinct trios with correct answers, difficult=$difficult',
      () {
        final random = Random(4711);
        var valid = 0;
        final seen = <String>{};
        for (var i = 0; i < 4000; i++) {
          final exercise = SetQuizExercise(
            difficultOnly: difficult,
            random: random,
          );
          expect(exercise.cards.map((c) => c.id).toSet(), hasLength(3));
          expect(exercise.cards.every((c) => c.id >= 0 && c.id < 81), isTrue);
          expect(isSet(exercise.cards), exercise.answer);
          if (exercise.answer) valid++;
          seen.add(exercise.cards.map((c) => c.id).join(','));
          if (difficult) {
            final same = List.generate(4, (i) => i)
                .where(
                  (i) =>
                      exercise.cards
                          .map((c) => c.attributes[i])
                          .toSet()
                          .length ==
                      1,
                )
                .length;
            expect(same, lessThanOrEqualTo(1));
          }
        }
        expect(valid, inInclusiveRange(1800, 2200));
        expect(seen.length, greaterThan(1000));
      },
    );
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> startRace(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Start race'), 120);
    await tester.tap(find.text('Start race'));
    await tester.pump();
    expect(find.byType(CardView), findsNothing);
    expect(find.text('Yes'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CardView), findsNWidgets(3));
  }

  List<SetCard> cards(WidgetTester tester) => tester
      .widgetList<CardView>(find.byType(CardView))
      .map((view) => view.card)
      .toList();

  testWidgets('start screen opens the recognition race', (tester) async {
    await tester.pumpWidget(const TrioSprintApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Yes / No'));
    await tester.tap(find.text('Yes / No'));
    await tester.pumpAndSettle();
    expect(find.text('Difficult only'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
    expect(find.text('1 min'), findsNWidgets(2));
    expect(find.text('3 min'), findsNWidgets(2));
    await tester.ensureVisible(find.text('Start run'));
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz-countdown')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'results change from uploading to submitted as soon as this score is acknowledged',
    (tester) async {
      final player = await PlayerData.load();
      await player.setNickname('Flo');
      final api = QuizSyncTestApi();
      final sync = SyncService(player, api: api)..start();
      await tester.pumpWidget(
        MaterialApp(
          home: SetQuizScreen(player: player, sync: sync),
        ),
      );
      await startRace(tester);
      await tester.tap(find.text(isSet(cards(tester)) ? 'Yes' : 'No'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(find.text('Uploading score…'), findsOneWidget);
      expect(find.textContaining('Score submitted as'), findsNothing);
      // Keep an unrelated history upload pending after the score is accepted.
      await player.recordPractice(
        PracticeBoard(cards: List.generate(12, (i) => i), source: 'training'),
      );
      api.scoreGate.complete();
      await tester.pump();
      await tester.pump();
      expect(sync.busy, isTrue);
      expect(find.text('Score submitted as Flo.'), findsOneWidget);
      expect(find.text('Uploading score…'), findsNothing);
      expect(
        find.text(
          'Saved on this device. Scores sync automatically when online.',
        ),
        findsNothing,
      );
      api.historyGate.complete();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      sync.dispose();
    },
  );

  for (final rejected in [false, true]) {
    testWidgets(
      'results display ${rejected ? 'rejection' : 'pending upload and successful retry'}',
      (tester) async {
        final player = await PlayerData.load();
        await player.setNickname('Flo');
        final api = QuizSyncTestApi()
          ..failure = rejected
              ? const ApiException(400, 'Invalid answers')
              : Exception('Network unavailable');
        api.scoreGate.complete();
        final sync = SyncService(player, api: api)..start();
        await tester.pumpWidget(
          MaterialApp(
            home: SetQuizScreen(player: player, sync: sync),
          ),
        );
        await startRace(tester);
        await tester.tap(find.text(isSet(cards(tester)) ? 'Yes' : 'No'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 30));
        await tester.pump();
        if (rejected) {
          expect(
            find.text('Score not accepted: Invalid answers'),
            findsOneWidget,
          );
        } else {
          expect(
            find.text(
              'Upload pending. Saved on this device; retrying automatically.',
            ),
            findsOneWidget,
          );
          api.failure = null;
          await sync.sync();
          await tester.pump();
          expect(find.text('Score submitted as Flo.'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        sync.dispose();
      },
    );
  }

  testWidgets('unnamed score explains the nickname requirement while online', (
    tester,
  ) async {
    final player = await PlayerData.load();
    final api = QuizSyncTestApi();
    final sync = SyncService(player, api: api)..start();
    await tester.pumpWidget(
      MaterialApp(
        home: SetQuizScreen(player: player, sync: sync),
      ),
    );
    await startRace(tester);
    await tester.tap(find.text(isSet(cards(tester)) ? 'Yes' : 'No'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(
      find.text('Saved on this device. Add a nickname to publish your score.'),
      findsOneWidget,
    );
    expect(find.text('Set nickname'), findsOneWidget);
    expect(api.scoreGate.isCompleted, isFalse);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets(
    'results show a reproducible seed and review without changing scores',
    (tester) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final player = await PlayerData.load();
      await tester.pumpWidget(MaterialApp(home: SetQuizScreen(player: player)));
      await startRace(tester);
      final seen = <List<int>>[];
      for (var i = 0; i < 2; i++) {
        final current = cards(tester);
        seen.add(current.map((c) => c.id).toList());
        await tester.tap(find.text(isSet(current) == i.isEven ? 'Yes' : 'No'));
        await tester.pump();
      }
      final unanswered = cards(tester).map((c) => c.id).toList();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      final label = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      final seed = QuizSeed.parse(label.substring('Seed: '.length))!;
      expect(seed.seconds, 30);
      final original = player.savedQuizScores;
      expect(original, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await tester.scrollUntilVisible(
        find.text('Copy seed link'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy seed link'));
      await tester.pump();
      expect(QuizSeed.parse(copiedText!)!.value, seed.value);
      await tester.scrollUntilVisible(
        find.text('Review trios'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review trios'));
      await tester.pumpAndSettle();
      final review = tester.widget<QuizReviewScreen>(
        find.byType(QuizReviewScreen),
      );
      expect(review.trios.map((t) => t.cards), [...seen, unanswered]);
      expect(review.trios.map((t) => t.status), [
        'Correct',
        'Wrong',
        'Unanswered',
      ]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(player.savedQuizScores, original);
      await tester.scrollUntilVisible(
        find.text('Replay seed (practice)'),
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replay seed (practice)'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(cards(tester).map((c) => c.id), seen.first);
      await tester.tap(find.text(isSet(cards(tester)) ? 'No' : 'Yes'));
      await tester.pump();
      expect(cards(tester).map((c) => c.id), seen[1]);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(
        find.text(
          'Practice replay. Personal best and high scores are unchanged.',
        ),
        findsOneWidget,
      );
      expect(player.savedQuizScores, original);
      expect(player.quizBest(30, false), 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('recognition setup accepts its own seed entry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SetQuizScreen()));
    await tester.ensureVisible(find.text('Run a seed'));
    await tester.tap(find.text('Run a seed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'q1-30-n-1234abcd');
    await tester.tap(find.text('Run seed'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(cards(tester).map((c) => c.id), [42, 27, 48]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'shared seed settings and cards are honored by the main seed dialog',
    (tester) async {
      await tester.pumpWidget(const TrioSprintApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Run a seed'));
      await tester.tap(find.text('Run a seed'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/?quiz=q1-180-h-ffffffff',
      );
      await tester.tap(find.text('Run seed'));
      await tester.pumpAndSettle();
      expect(find.text('Seed: q1-180-h-ffffffff · Practice'), findsOneWidget);
      await startRace(tester);
      expect(cards(tester).map((c) => c.id), [28, 72, 20]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(320, 480), const Size(740, 360)]) {
    testWidgets('integrated Yes / No selector and leaderboard fit at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const TrioSprintApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Yes / No'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes / No'));
      await tester.pumpAndSettle();
      expect(find.text('30 s'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(home: QuizLeaderboardScreen(api: QuizTestApi())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'a completed 30-second race persists its personal best and upload payload',
    (tester) async {
      final player = await PlayerData.load();
      await tester.pumpWidget(MaterialApp(home: SetQuizScreen(player: player)));
      await startRace(tester);
      final current = cards(tester);
      await tester.tap(find.text(isSet(current) ? 'Yes' : 'No'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      final restored = await PlayerData.load();
      expect(restored.quizBest(30, false), 1);
      expect(restored.pendingScores, 1);
      expect(restored.savedQuizScores.single['answers'], [
        [...current.map((c) => c.id), isSet(current)],
      ]);
      expect(find.text('New personal best!'), findsOneWidget);
      expect(find.text('30 s'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(320, 480), const Size(740, 360)]) {
    testWidgets('race advances immediately with distinct haptics at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SetQuizScreen()));
      await tester.scrollUntilVisible(find.byType(Checkbox), 120);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await startRace(tester);
      for (var round = 0; round < 4; round++) {
        final current = cards(tester);
        final same = List.generate(4, (i) => i)
            .where(
              (i) => current.map((c) => c.attributes[i]).toSet().length == 1,
            )
            .length;
        expect(same, lessThanOrEqualTo(1));
        final chooseCorrect = round.isEven;
        final yes = isSet(current) == chooseCorrect;
        final button = yes
            ? find.widgetWithText(FilledButton, 'Yes')
            : find.widgetWithText(OutlinedButton, 'No');
        final target = tester.getRect(button);
        expect(target.height, greaterThanOrEqualTo(80));
        expect(target.bottom, lessThanOrEqualTo(size.height - 32));
        await tester.tapAt(Offset(target.center.dx, target.top + 8));
        await tester.pump();
        expect(
          haptics.last,
          chooseCorrect
              ? 'HapticFeedbackType.selectionClick'
              : 'HapticFeedbackType.heavyImpact',
        );
        expect(haptics, hasLength(round + 1));
        expect(find.text('Score: ${chooseCorrect ? 1 : 0}'), findsOneWidget);
        expect(find.text('Yes').hitTestable(), findsOneWidget);
        expect(find.text('No').hitTestable(), findsOneWidget);
        expect(find.text('Next trio'), findsNothing);
        expect(find.text(explainTrio(current)), findsNothing);
        for (final element in find.byType(CardView).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.width, greaterThan(0));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(56));
          expect(
            rect.bottom,
            lessThanOrEqualTo(tester.getTopLeft(find.text('Yes')).dy),
          );
        }
        expect(tester.takeException(), isNull);
      }
      final lateAnswer = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Yes'))
          .onPressed!;
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Time’s up.'), findsOneWidget);
      expect(find.text('2 correct · 2 wrong'), findsOneWidget);
      expect(find.byType(CardView), findsNothing);
      lateAnswer();
      await tester.pump();
      expect(haptics, hasLength(4));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'High scores'))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.scrollUntilVisible(
        find.text('Race again'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Race again'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Score: 0'), findsOneWidget);
      expect(find.byType(CardView), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'three-minute race runs in the background and allows settings changes',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SetQuizScreen()));
      await tester.tap(find.text('3 min'));
      await tester.pump();
      await startRace(tester);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Time’s up.'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Time’s up.'), findsOneWidget);
      expect(find.text('0 correct · 0 wrong'), findsOneWidget);
      expect(find.text('3 min'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Change settings'));
      await tester.pumpAndSettle();
      expect(find.text('Difficult only'), findsOneWidget);
      expect(find.text('Start race'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'recognition leaderboard loads and filters duration, difficulty and player best',
    (tester) async {
      final api = QuizTestApi();
      await tester.pumpWidget(
        MaterialApp(home: QuizLeaderboardScreen(api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(api.queries.last, {
        'seconds': '30',
        'difficult': 'false',
        'unique': 'true',
      });
      await tester.tap(find.text('3 min'));
      await tester.pumpAndSettle();
      expect(api.queries.last['seconds'], '180');
      await tester.tap(find.text('Difficult only'));
      await tester.pumpAndSettle();
      expect(api.queries.last['difficult'], 'true');
      await tester.tap(find.text('Only each player’s best'));
      await tester.pumpAndSettle();
      expect(api.queries.last['unique'], 'false');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('leaving during countdown cancels pending timers', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SetQuizScreen()));
    await tester.tap(find.text('Start race'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 4));
    expect(tester.takeException(), isNull);
  });
}

class QuizTestApi extends OnlineApi {
  final queries = <Map<String, String>>[];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path != '/quiz-scores') throw StateError(path);
    queries.add(query!);
    return {
      'scores': [
        {'name': 'Alice', 'score': 7, 'correct': 9, 'mistakes': 2},
      ],
    };
  }
}

class QuizSyncTestApi extends OnlineApi {
  final scoreGate = Completer<void>();
  final historyGate = Completer<void>();
  Object? failure;

  @override
  bool get configured => true;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/quiz-scores') {
      await scoreGate.future;
      if (failure != null) throw failure!;
    } else if (path == '/attempts') {
      await historyGate.future;
    }
    return {'ok': true};
  }
}
