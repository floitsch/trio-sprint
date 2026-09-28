import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trio_sprint/game.dart';

void main() {
  test('all 81 cards are unique and there are exactly 1080 sets', () {
    final cards = List.generate(81, SetCard.new);
    expect(cards.map((c) => c.attributes.join()).toSet().length, 81);
    var sets = 0;
    for (var a = 0; a < 79; a++) {
      for (var b = a + 1; b < 80; b++) {
        for (var c = b + 1; c < 81; c++) {
          if (isSet([cards[a], cards[b], cards[c]])) sets++;
        }
      }
    }
    expect(sets, 1080);
    expect(isSet([cards[0], cards[0], cards[0]]), isFalse);
    expect(isSet([cards[0], cards[1]]), isFalse);
  });

  test('500 seeded games stay solvable and finish on the fifth set', () {
    for (var seed = 0; seed < 500; seed++) {
      final game = SetGame(random: Random(seed));
      for (var streak = 1; streak <= 5; streak++) {
        expect(game.board.length, 12);
        expect(game.board.map((c) => c.id).toSet().length, game.board.length);
        final previousIds = game.board.map((card) => card.id).toList();
        final solution = findSet(game.board);
        expect(solution, isNotNull);
        final dealtPositions = solution!
            .map((card) => game.board.indexWhere((item) => item.id == card.id))
            .toSet();
        game.pick(solution[0].id);
        game.pick(solution[1].id);
        expect(
          game.pick(solution[2].id),
          streak == 5 ? PickResult.finished : PickResult.correct,
        );
        expect(game.streak, streak);
        expect(game.board.length, 12);
        if (streak < 5) {
          for (var position = 0; position < game.board.length; position++) {
            if (!dealtPositions.contains(position)) {
              expect(game.board[position].id, previousIds[position]);
            }
          }
        }
      }
      expect(game.finished, isTrue);
      game.restart();
      expect(game.streak, 0);
      expect(game.mistakes, 0);
      expect(game.selected, isEmpty);
      expect(game.finished, isFalse);
    }
  });

  test('wrong trios preserve the streak; tapping again deselects', () {
    final game = SetGame(random: Random(3));
    final solution = findSet(game.board)!;
    for (final card in solution) {
      game.pick(card.id);
    }
    expect(game.streak, 1);
    final first = game.board.first.id;
    expect(game.pick(first), PickResult.selected);
    expect(game.pick(first), PickResult.deselected);
    expect(game.selected, isEmpty);
    final wrong = wrongTrio(game.board);
    game.pick(wrong[0].id);
    game.pick(wrong[1].id);
    expect(game.pick(wrong[2].id), PickResult.wrong);
    expect(game.streak, 1);
    expect(game.mistakes, 1);
    expect(game.selected, isEmpty);
  });

  test('mistakes accumulate without changing the streak', () {
    final game = SetGame(random: Random(23));
    for (var completed = 0; completed < 5; completed++) {
      for (final card in wrongTrio(game.board)) {
        game.pick(card.id);
      }
      expect(game.streak, completed);
      expect(game.mistakes, completed + 1);
      for (final card in findSet(game.board)!) {
        game.pick(card.id);
      }
      expect(findSet(game.board), isNotNull);
      expect(game.streak, completed + 1);
    }
    expect(game.finished, isTrue);
  });

  test('time formatting includes hundredths and minutes', () {
    expect(formatTime(const Duration(milliseconds: 1234)), '1.23');
    expect(formatTime(const Duration(milliseconds: 61567)), '1:01.56');
  });
}

List<SetCard> wrongTrio(List<SetCard> board) {
  for (var i = 2; i < board.length; i++) {
    final cards = [board[0], board[1], board[i]];
    if (!isSet(cards)) return cards;
  }
  throw StateError('No wrong trio found');
}
