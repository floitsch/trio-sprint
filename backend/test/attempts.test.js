// Copyright (C) 2026 Toit contributors.
import test from 'node:test';
import assert from 'node:assert/strict';
import { validAttempts } from '../src/attempts.js';
const record = () => ({player: 'a'.repeat(48), attempts: [{id: '0', board: {
  cards: Array.from({length: 12}, (_, i) => i), anchors: [], differences: null,
  milliseconds: 1234, mistakes: 1, assisted: false, outcome: 'solved', source: 's2',
  solutionCards: [0, 1, 2], seed: 's2-1234abcd', recordedAt: 1800000000000,
}}]});
test('accepts offline solved and unfinished history but rejects malformed uploads', () => {
  assert.ok(validAttempts(record()));
  for (const outcome of ['timedOut', 'restarted', 'interrupted', 'skipped']) {
    const body = record();
    body.attempts[0].board.outcome = outcome;
    body.attempts[0].board.solutionCards = [];
    assert.ok(validAttempts(body));
  }
  for (const mutate of [
    b => b.player = 'invalid', b => b.attempts = [],
    b => b.attempts.push(b.attempts[0]), b => b.attempts[0].id = '-1',
    b => b.attempts[0].board.cards[0] = 99,
    b => b.attempts[0].board.solutionCards = [0, 1, 4],
    b => b.attempts[0].board.milliseconds = -1,
    b => b.attempts[0].board.outcome = 'bogus',
  ]) {
    const body = record(); mutate(body); assert.equal(validAttempts(body), false);
  }
});
