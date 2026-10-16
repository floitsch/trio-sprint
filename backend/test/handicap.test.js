// Copyright (C) 2026 Toit contributors.
import test from 'node:test';
import assert from 'node:assert/strict';
import { delayBoard, visibleBoard, validHandicap } from '../src/handicap.js';

test('handicap only withholds changed positions and survives persistence', () => {
  const player = { handicapMs: 1200 };
  delayBoard(player, [1, 2, 3, 4], [1, 5, 6, 4], 10000);
  const restored = JSON.parse(JSON.stringify(player));
  assert.deepEqual(visibleBoard([1, 5, 6, 4], restored, 11199), [1, null, null, 4]);
  assert.deepEqual(visibleBoard([1, 5, 6, 4], restored, 11200), [1, 5, 6, 4]);
  delayBoard(player, [], [1, 2, 3, 4], 20000);
  assert.deepEqual(visibleBoard([1, 2, 3, 4], player, 20000), [null, null, null, null]);
});
test('zero delay and tenth-second validation', () => {
  const player = {};
  delayBoard(player, [], [1, 2, 3], 100);
  assert.deepEqual(visibleBoard([1, 2, 3], player, 100), [1, 2, 3]);
  for (const value of [0, 100, 1200, 30000]) assert.ok(validHandicap(value));
  for (const value of [-100, 10, 100.1, 30100, null, '100', NaN]) assert.ok(!validHandicap(value));
});
