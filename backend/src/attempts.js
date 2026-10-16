// Copyright (C) 2026 Toit contributors.
import { isSet, validSeed, validPlayer } from './game.js';

export function validAttempts(body) {
  if (!body || !validPlayer(body.player) || !Array.isArray(body.attempts) ||
      body.attempts.length < 1 || body.attempts.length > 10) return false;
  return body.attempts.every(a => {
    if (!a || typeof a.id !== 'string' || !/^(0|[1-9][0-9]{0,11})$/.test(a.id)) return false;
    const b = a.board;
    if (!b || !Array.isArray(b.cards) || !Array.isArray(b.anchors) ||
        b.cards.length !== (b.anchors.length === 0 ? 12 : 6) ||
        ![0, 2].includes(b.anchors.length)) return false;
    const all = [...b.cards, ...b.anchors];
    if (all.some(id => !Number.isInteger(id) || id < 0 || id > 80) ||
        new Set(all).size !== all.length ||
        (b.differences != null && (!Number.isInteger(b.differences) || b.differences < 1 || b.differences > 4)) ||
        !Number.isSafeInteger(b.milliseconds) || b.milliseconds < 0 ||
        !Number.isSafeInteger(b.mistakes) || b.mistakes < 0 ||
        typeof b.assisted !== 'boolean' ||
        !['solved', 'timedOut', 'restarted', 'interrupted', 'skipped'].includes(b.outcome) ||
        !['s1', 's2', '1m', '3m', 'race', 'training', 'review', 'replay'].includes(b.source) ||
        (b.seed != null && !validSeed(b.seed)) ||
        (b.recordedAt != null && (!Number.isSafeInteger(b.recordedAt) || b.recordedAt < 0)) ||
        !Array.isArray(b.solutionCards)) return false;
    return b.solutionCards.length === 0 || (isSet(b.solutionCards) &&
      b.solutionCards.every(id => all.includes(id)));
  }) && new Set(body.attempts.map(a => a.id)).size === body.attempts.length;
}

export async function saveAttempts(db, body) {
  // Immutable first write wins. A repeated batch acknowledges existing IDs.
  await db.batch(body.attempts.map(a => db.prepare(
    'INSERT OR IGNORE INTO attempts (player, attempt_id, board) VALUES (?, ?, ?)'
  ).bind(body.player, a.id, JSON.stringify(a.board))));
}
