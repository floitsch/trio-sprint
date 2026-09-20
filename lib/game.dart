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
  SetGame({Random? random}) : _random = random ?? Random() {
    restart();
  }

  final Random _random;
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
