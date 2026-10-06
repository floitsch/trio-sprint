// Copyright (C) 2026 Toit contributors.
export function isSet(cards) {
  return Array.isArray(cards) && cards.length === 3 && new Set(cards).size === 3 &&
    cards.every(c => Number.isInteger(c) && c >= 0 && c < 81) &&
    [1, 3, 9, 27].every(place => cards.reduce((sum, c) => sum + Math.floor(c / place) % 3, 0) % 3 === 0);
}
export function findSet(board) {
  for (let a = 0; a < board.length - 2; a++)
    for (let b = a + 1; b < board.length - 1; b++)
      for (let c = b + 1; c < board.length; c++)
        if (isSet([board[a], board[b], board[c]])) return [board[a], board[b], board[c]];
  return null;
}
export function validSeed(seed) { return typeof seed === 'string' && /^(s[12]|[13]m)-[0-9a-f]{8}$/.test(seed); }
// Timed seeds count sets until their limit. Keep in sync with RunMode in lib/game.dart.
const limits = {'1m': 60000, '3m': 180000};
export function timeLimit(seed) { return limits[seed.slice(0, 2)] ?? null; }
// Timed seeds deal like s2 from a different starting state; see seedState in lib/game.dart.
function seedState(seed) {
  const digits = parseInt(seed.slice(3), 16);
  const salt = {'1m': 0x9e3779b9, '3m': 0x7f4a7c15}[seed.slice(0, 2)] ?? 0;
  return (digits ^ salt) >>> 0;
}
export function seededBoards(seed) {
  if (!validSeed(seed) || !seed.startsWith('s1-')) throw new Error('Only legacy s1 seeds have independent boards');
  let state = parseInt(seed.slice(3), 16);
  const shuffle = values => {
    for (let i = values.length - 1; i > 0; i--) {
      state = (1664525 * state + 1013904223) % 4294967296;
      const j = state % (i + 1);
      [values[i], values[j]] = [values[j], values[i]];
    }
    return values;
  };
  return Array.from({ length: 5 }, () => {
    for (let attempt = 0; attempt < 100; attempt++) {
      const board = shuffle(Array.from({ length: 81 }, (_, i) => i)).slice(0, 12);
      if (findSet(board)) return board;
    }
    return shuffle([0, 1, 2, ...shuffle(Array.from({ length: 78 }, (_, i) => i + 3)).slice(0, 9)]);
  });
}
export function validPlayer(value) { return typeof value === 'string' && /^[a-f0-9]{48}$/.test(value); }
export function validName(value) { return typeof value === 'string' && value.trim().length > 0 && value.length <= 24 && !/[\x00-\x1f]/.test(value); }
// For timed seeds, milliseconds is the time of the last found set.
export function validateScore(body) {
  if (!body || !validPlayer(body.player) || !validName(body.name) || !validSeed(body.seed) ||
      !Number.isInteger(body.milliseconds) || body.milliseconds < 1 ||
      body.milliseconds > (timeLimit(body.seed) ?? 86400000) ||
      !Number.isInteger(body.mistakes) || body.mistakes < 0 || body.mistakes > 100000 ||
      !Array.isArray(body.solutions)) return false;
  const sets = body.solutions.length;
  if (timeLimit(body.seed) ? sets < 1 || sets > 500 : sets !== 5) return false;
  const run = new SeededRun(body.seed);
  return body.solutions.every(solution => run.pick(solution));
}


// s2 seeds an entire deck. Found cards are replaced in board-position order,
// independent of the order in which the player clicked them. Keep in sync with
// SetGame in lib/game.dart; changes to these rules require a new seed version.
export class SeededRun {
  constructor(seed) {
    if (!validSeed(seed)) throw new Error('Invalid seed');
    this.progress = 0;
    this.target = timeLimit(seed) ? Infinity : 5;
    this.state = seedState(seed);
    if (seed.startsWith('s1-')) {
      this.rounds = seededBoards(seed);
      this.board = [...this.rounds[0]];
    } else {
      this.deck = this.shuffle(Array.from({length: 81}, (_, i) => i));
      this.board = Array.from({length: 12}, () => this.deck.pop());
      this.ensureSet([9, 10, 11]);
    }
  }
  shuffle(values) {
    for (let i = values.length - 1; i > 0; i--) {
      this.state = (1664525 * this.state + 1013904223) % 4294967296;
      const j = this.state % (i + 1);
      [values[i], values[j]] = [values[j], values[i]];
    }
    return values;
  }
  refreshDeck() {
    this.deck = this.shuffle(Array.from({length: 81}, (_, i) => i).filter(c => !this.board.includes(c)));
  }
  ensureSet(positions) {
    let attempts = 0;
    while (!findSet(this.board)) {
      if (attempts++ === 100) {
        const kept = this.board.filter((_, i) => !positions.includes(i));
        const third = [1, 3, 9, 27].reduce((id, place) => id +
          ((6 - Math.floor(kept[0] / place) % 3 - Math.floor(kept[1] / place) % 3) % 3) * place, 0);
        this.board[positions[0]] = third;
        this.deck = this.deck.filter(c => c !== third);
        return;
      }
      if (this.deck.length < 3) this.refreshDeck();
      for (const position of positions) this.board[position] = this.deck.pop();
    }
  }
  pick(cards) {
    if (this.progress === this.target || !isSet(cards) || !cards.every(c => this.board.includes(c))) return false;
    this.progress++;
    if (this.progress === this.target) return true;
    if (this.rounds) {
      this.board = [...this.rounds[this.progress]];
      return true;
    }
    if (this.deck.length < 3) this.refreshDeck();
    const positions = [];
    for (let i = 0; i < this.board.length; i++) {
      if (cards.includes(this.board[i])) {
        this.board[i] = this.deck.pop();
        positions.push(i);
      }
    }
    this.ensureSet(positions);
    return true;
  }
}
