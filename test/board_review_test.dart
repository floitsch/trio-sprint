// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trio_sprint/card_view.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/practice.dart';
import 'package:trio_sprint/statistics.dart';

void main() {
  final board = PracticeBoard(cards: List.generate(12, (i) => i));
  const expected = [
    [0, 1, 2],
    [0, 3, 6],
    [0, 4, 8],
    [0, 5, 7],
    [1, 3, 8],
    [1, 4, 7],
    [1, 5, 6],
    [2, 3, 7],
    [2, 4, 6],
    [2, 5, 8],
    [3, 4, 5],
    [6, 7, 8],
    [9, 10, 11],
  ];

  test('enumerates every solution exactly once and respects constraints', () {
    expect(
      board.solutions.map((trio) => trio.map((c) => c.id).toList()),
      expected,
    );
    final constrained = PracticeBoard(cards: board.cards, differences: 2);
    expect(
      constrained.solutions.map((trio) => trio.map((c) => c.id).toList()),
      [
        for (final trio in expected)
          if (differentAttributes(trio.map(SetCard.new).toList()) == 2) trio,
      ],
    );
    final pair = PracticeBoard(cards: [2, 3, 4, 5, 6, 7], anchors: [0, 1]);
    expect(pair.solutions.map((trio) => trio.map((c) => c.id)), [
      [0, 1, 2],
    ]);
  });

  testWidgets(
    'review can reveal and browse all 13 sets without changing cards',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BoardReviewScreen(board: board, title: 'Last unsolved board'),
        ),
      );
      Iterable<int> highlighted() => tester
          .widgetList<CardView>(find.byType(CardView))
          .where((c) => c.selected)
          .map((c) => c.card.id);
      expect(highlighted(), isEmpty);
      await tester.tap(find.text('Show solution'));
      await tester.pump();
      for (var i = 0; i < expected.length; i++) {
        expect(find.text('Solution ${i + 1} of 13'), findsOneWidget);
        expect(highlighted(), expected[i]);
        expect(
          tester
              .widgetList<CardView>(find.byType(CardView))
              .map((c) => c.card.id),
          board.cards,
        );
        await tester.tap(find.byTooltip('Next solution'));
        await tester.pump();
      }
      expect(highlighted(), expected.first);
      await tester.tap(find.byTooltip('Previous solution'));
      await tester.pump();
      expect(highlighted(), expected.last);
      await tester.tap(find.text('Hide solution'));
      await tester.pump();
      expect(highlighted(), isEmpty);
    },
  );

  testWidgets(
    'solved board starts with the actual solution and offers alternatives',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BoardReviewScreen(
            board: PracticeBoard(
              cards: board.cards,
              solutionCards: expected.last,
            ),
            title: 'Solved board',
          ),
        ),
      );
      await tester.tap(find.text('Show solution'));
      await tester.pump();
      expect(find.text('Solution 13 of 13'), findsOneWidget);
    },
  );
}
