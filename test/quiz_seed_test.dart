// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter_test/flutter_test.dart';
import 'package:trio_sprint/game.dart';
import 'package:trio_sprint/quiz_seed.dart';

void main() {
  test('recognition seeds encode settings and normalize shared links', () {
    final seed = QuizSeed.parse('https://example.com/?quiz=Q1-30-H-1234ABCD')!;
    expect(seed.value, 'q1-30-h-1234abcd');
    expect(seed.seconds, 30);
    expect(seed.difficult, isTrue);
    expect(
      QuizSeed.parse('https://example.com/?seed=q1-60-n-00000000')!.seconds,
      60,
    );
    for (final value in [
      'q1-45-n-1234abcd',
      'q2-30-n-1234abcd',
      'q1-30-x-1234abcd',
      's2-1234abcd',
      'q1-30-n-1234abc',
    ]) {
      expect(QuizSeed.parse(value), isNull);
    }
    for (final seconds in [30, 60, 180]) {
      for (final hard in [false, true]) {
        final generated = QuizSeed.create(seconds, hard);
        expect(generated.seconds, seconds);
        expect(generated.difficult, hard);
        expect(QuizSeed.parse(generated.value)!.value, generated.value);
      }
    }
  });

  test('q1 golden sequences remain permanent across replays', () {
    final fixtures = {
      'q1-30-n-1234abcd': [
        [42, 27, 48],
        [19, 25, 22],
        [29, 60, 4],
      ],
      'q1-180-h-ffffffff': [
        [28, 72, 20],
        [14, 27, 79],
        [2, 72, 74],
      ],
    };
    for (final item in fixtures.entries) {
      final seed = QuizSeed.parse(item.key)!;
      final first = seed.random();
      final replay = seed.random();
      for (final cards in item.value) {
        final exercise = SetQuizExercise(
          difficultOnly: seed.difficult,
          random: first,
        );
        final again = SetQuizExercise(
          difficultOnly: seed.difficult,
          random: replay,
        );
        expect(exercise.cards.map((c) => c.id), cards);
        expect(again.cards.map((c) => c.id), cards);
        expect(exercise.answer, isSet(exercise.cards));
      }
    }
  });
}
