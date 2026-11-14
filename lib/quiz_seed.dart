// Copyright (C) 2026 Florian Loitsch.
import 'dart:math';

import 'game.dart';

/// Versioned recognition seeds fix the duration, difficulty and entire sequence.
/// Changing q1 or SetQuizExercise requires a new seed prefix.
class QuizSeed {
  const QuizSeed._(this.value, this.seconds, this.difficult, this.state);
  final String value;
  final int seconds;
  final bool difficult;
  final int state;

  static QuizSeed? parse(String input) {
    final text = input.trim();
    final uri = Uri.tryParse(text);
    final value =
        (uri?.queryParameters['quiz'] ?? uri?.queryParameters['seed'] ?? text)
            .toLowerCase();
    final match = RegExp(r'^q1-(30|60|180)-(n|h)-([0-9a-f]{8})$')
        .firstMatch(value);
    if (match == null) return null;
    return QuizSeed._(
      value,
      int.parse(match[1]!),
      match[2] == 'h',
      int.parse(match[3]!, radix: 16),
    );
  }

  static QuizSeed create(int seconds, bool difficult) {
    final digits = Random.secure()
        .nextInt(0x100000000)
        .toRadixString(16)
        .padLeft(8, '0');
    return parse('q1-$seconds-${difficult ? 'h' : 'n'}-$digits')!;
  }

  Random random() => _QuizRandom(state);
}

/// Keep q1's integer arithmetic permanent so web and native replays agree.
class _QuizRandom implements Random {
  _QuizRandom(int state) : source = SeedRandom(state);
  final SeedRandom source;

  @override
  int nextInt(int max) {
    if (max <= 0 || max > 0x100000000) throw ArgumentError.value(max);
    return source.nextInt(0x100000000) % max;
  }

  @override
  bool nextBool() => source.nextInt(0x100000000) >= 0x80000000;

  @override
  double nextDouble() => source.nextInt(0x100000000) / 0x100000000;
}
