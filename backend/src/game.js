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
export function validSeed(seed) { return typeof seed === 'string' && /^s1-[0-9a-f]{8}$/.test(seed); }
export function seededBoards(seed) {
  if (!validSeed(seed)) throw new Error('Invalid seed');
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
export function validateScore(body) {
  if (!body || !validPlayer(body.player) || !validName(body.name) || !validSeed(body.seed) ||
      !Number.isInteger(body.milliseconds) || body.milliseconds < 1 || body.milliseconds > 86400000 ||
      !Number.isInteger(body.mistakes) || body.mistakes < 0 || body.mistakes > 100000 ||
      !Array.isArray(body.solutions) || body.solutions.length !== 5) return false;
  const boards = seededBoards(body.seed);
  return body.solutions.every((solution, i) => isSet(solution) && solution.every(c => boards[i].includes(c)));
}
