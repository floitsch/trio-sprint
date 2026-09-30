import 'dart:math';

/// The 81 unique combinations of four attributes with three values each.
class SetCard {
  const SetCard(this.id);

  final int id;
  int get count => id % 3 + 1;
  int get shape => id ~/ 3 % 3;
  int get color => id ~/ 9 % 3;
  int get fill => id ~/ 27 % 3;

  List<int> get attributes => [count - 1, shape, color, fill];

  String get description =>
      '$count ${['red', 'green', 'purple'][color]} '
      '${['solid', 'striped', 'outlined'][fill]} '
      '${['oval', 'diamond', 'squiggle'][shape]}${count == 1 ? '' : 's'}';
}

bool isSet(List<SetCard> cards) {
  if (cards.length != 3 || cards.map((c) => c.id).toSet().length != 3) {
    return false;
  }
  for (var attribute = 0; attribute < 4; attribute++) {
    if (cards.fold(0, (sum, c) => sum + c.attributes[attribute]) % 3 != 0) {
      return false;
    }
  }
  return true;
}

List<SetCard>? findSet(List<SetCard> cards) {
  for (var a = 0; a < cards.length - 2; a++) {
    for (var b = a + 1; b < cards.length - 1; b++) {
      for (var c = b + 1; c < cards.length; c++) {
        final candidate = [cards[a], cards[b], cards[c]];
        if (isSet(candidate)) return candidate;
      }
    }
  }
  return null;
}

enum PickResult { selected, deselected, wrong, correct, finished }

class SetGame {
  SetGame({Random? random, this.seed}) : _random = random ?? Random() {
    restart();
  }

  final Random _random;
  final String? seed;
  List<List<SetCard>>? _rounds;
  final List<SetCard> board = [];
  final List<SetCard> _deck = [];
  final Set<int> selected = {};
  int streak = 0;
  int mistakes = 0;
  bool get finished => streak == 5;

  void restart() {
    streak = 0;
    mistakes = 0;
    selected.clear();
    board.clear();
    if (seed != null) {
      _rounds = seededBoards(seed!);
      board.addAll(_rounds!.first);
      return;
    }
    _deck
      ..clear()
      ..addAll(List.generate(81, SetCard.new)..shuffle(_random));
    _deal(12);
    _ensureSet(const [9, 10, 11]);
  }

  PickResult pick(int id) {
    if (finished || !board.any((card) => card.id == id)) {
      return PickResult.selected;
    }
    if (selected.remove(id)) return PickResult.deselected;
    selected.add(id);
    if (selected.length < 3) return PickResult.selected;
    final chosen = board.where((card) => selected.contains(card.id)).toList();
    if (!isSet(chosen)) {
      selected.clear();
      mistakes++;
      return PickResult.wrong;
    }
    streak++;
    if (finished) {
      selected.clear();
      return PickResult.finished;
    }
    if (_rounds != null) {
      board
        ..clear()
        ..addAll(_rounds![streak]);
      selected.clear();
      return PickResult.correct;
    }
    if (_deck.length < 3) _refreshDeck();
    final lastDealtPositions = <int>[];
    for (var i = 0; i < board.length; i++) {
      if (selected.contains(board[i].id)) {
        board[i] = _deck.removeLast();
        lastDealtPositions.add(i);
      }
    }
    selected.clear();
    _ensureSet(lastDealtPositions);
    return PickResult.correct;
  }

  void _deal(int count) {
    for (var i = 0; i < count && _deck.isNotEmpty; i++) {
      board.add(_deck.removeLast());
    }
  }

  void _ensureSet(List<int> lastDealtPositions) {
    while (findSet(board) == null) {
      if (_deck.length < 3) _refreshDeck();
      for (final position in lastDealtPositions) {
        board[position] = _deck.removeLast();
      }
    }
  }

  void _refreshDeck() {
    final boardIds = board.map((card) => card.id).toSet();
    _deck
      ..clear()
      ..addAll(
        List.generate(
          81,
          SetCard.new,
        ).where((card) => !boardIds.contains(card.id)),
      )
      ..shuffle(_random);
  }
}

String formatTime(Duration duration) {
  final hundredths = duration.inMilliseconds ~/ 10;
  final seconds = hundredths ~/ 100;
  final fraction = (hundredths % 100).toString().padLeft(2, '0');
  if (seconds < 60) return '$seconds.$fraction';
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}.$fraction';
}

/// s1 uses an explicitly specified PRNG and shuffle, shared with the server.
/// Never change this algorithm without introducing a new seed version.
class SeedRandom {
  SeedRandom(this.state);
  int state;
  int nextInt(int maximum) {
    state = (1664525 * state + 1013904223) % 4294967296;
    return state % maximum;
  }

  void shuffle<T>(List<T> values) {
    for (var i = values.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final temporary = values[i];
      values[i] = values[j];
      values[j] = temporary;
    }
  }
}

String? normalizeSeed(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  final seed = (uri?.queryParameters['seed'] ?? trimmed).toLowerCase();
  return RegExp(r'^s1-[0-9a-f]{8}$').hasMatch(seed) ? seed : null;
}

String newSeed() =>
    's1-${Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0')}';

List<List<SetCard>> seededBoards(String seed) {
  if (normalizeSeed(seed) != seed) throw ArgumentError('Invalid seed');
  final random = SeedRandom(int.parse(seed.substring(3), radix: 16));
  return List.generate(5, (_) {
    for (var attempt = 0; attempt < 100; attempt++) {
      final deck = List.generate(81, SetCard.new);
      random.shuffle(deck);
      final board = deck.take(12).toList();
      if (findSet(board) != null) return board;
    }
    // Bounded fallback with a guaranteed set.
    final rest = List.generate(78, (i) => SetCard(i + 3));
    random.shuffle(rest);
    final board = [
      const SetCard(0),
      const SetCard(1),
      const SetCard(2),
      ...rest.take(9),
    ];
    random.shuffle(board);
    return board;
  });
}

int differentAttributes(List<SetCard> cards) => List.generate(
  4,
  (i) => i,
).where((i) => cards.map((c) => c.attributes[i]).toSet().length == 3).length;

String explainTrio(List<SetCard> cards) {
  const names = ['Number', 'Shape', 'Color', 'Fill'];
  return List.generate(4, (i) {
    final count = cards.map((c) => c.attributes[i]).toSet().length;
    return '${names[i]}: ${count == 1
        ? 'all same'
        : count == 3
        ? 'all different'
        : 'two same, one different ✗'}';
  }).join(' · ');
}

class TrainingExercise {
  TrainingExercise({
    required this.differences,
    required this.completePair,
    Random? random,
  }) {
    final rng = random ?? Random();
    final candidates = <List<SetCard>>[];
    // Each pair determines exactly one third card.
    for (var a = 0; a < 81; a++) {
      for (var b = a + 1; b < 81; b++) {
        final aa = SetCard(a).attributes;
        final bb = SetCard(b).attributes;
        var c = 0;
        var place = 1;
        for (var i = 0; i < 4; i++) {
          c += ((6 - aa[i] - bb[i]) % 3) * place;
          place *= 3;
        }
        if (c <= b) continue;
        final trio = [SetCard(a), SetCard(b), SetCard(c)];
        if (differentAttributes(trio) == differences) candidates.add(trio);
      }
    }
    solution = [...candidates[rng.nextInt(candidates.length)]]..shuffle(rng);
    final excluded = solution.map((c) => c.id).toSet();
    final distractors = List.generate(
      81,
      SetCard.new,
    ).where((c) => !excluded.contains(c.id)).toList()..shuffle(rng);
    board = completePair
        ? [solution[2], ...distractors.take(5)]
        : [...solution, ...distractors.take(9)];
    board.shuffle(rng);
  }
  final int differences;
  final bool completePair;
  late final List<SetCard> solution;
  late final List<SetCard> board;
  bool accepts(List<SetCard> cards) =>
      isSet(cards) && differentAttributes(cards) == differences;
}
