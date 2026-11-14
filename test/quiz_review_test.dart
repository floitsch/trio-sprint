// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/quiz_review.dart';

void main() {
  for (final size in [const Size(320, 480), const Size(740, 360)]) {
    testWidgets(
      'review preserves trios, shows corrections and filters mistakes at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final entries = [
          QuizReviewTrio(cards: [0, 40, 80], answer: true),
          QuizReviewTrio(cards: [0, 40, 79], answer: true),
          QuizReviewTrio(cards: [0, 1, 2]),
        ];
        await tester.pumpWidget(
          MaterialApp(home: QuizReviewScreen(trios: entries)),
        );
        for (var i = 0; i < entries.length; i++) {
          final views = tester.widgetList<CardView>(find.byType(CardView));
          expect(views.map((v) => v.card.id), entries[i].cards);
          expect(views.every((v) => v.onTap == null), isTrue);
          expect(find.text('Trio ${i + 1} of 3'), findsOneWidget);
          expect(find.text(entries[i].status), findsOneWidget);
          expect(
            find.text(explainTrio(entries[i].cards.map(SetCard.new).toList())),
            findsOneWidget,
          );
          if (i < entries.length - 1) {
            await tester.tap(find.byTooltip('Next trio'));
            await tester.pump();
          }
        }
        await tester.tap(find.text('Wrong only'));
        await tester.pumpAndSettle();
        expect(find.text('Trio 2 of 3'), findsOneWidget);
        expect(find.text('Wrong'), findsOneWidget);
        expect(find.text('Your answer: Yes'), findsOneWidget);
        expect(
          find.text('Correct answer: No — this is not a set.'),
          findsOneWidget,
        );
        expect(find.text('1 / 1'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Next trio',
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Wrong only'));
        await tester.pumpAndSettle();
        expect(find.text('Trio 1 of 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'wrong-only filter handles a clean run without changing the answers',
    (tester) async {
      final cards = [0, 40, 80];
      final entry = QuizReviewTrio(cards: cards, answer: true);
      cards[0] = 1;
      expect(entry.cards, [0, 40, 80]);
      await tester.pumpWidget(
        MaterialApp(home: QuizReviewScreen(trios: [entry])),
      );
      await tester.tap(find.text('Wrong only'));
      await tester.pump();
      expect(find.text('No wrong answers.'), findsOneWidget);
      expect(find.text('0 / 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
