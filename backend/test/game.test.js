import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { seededBoards, findSet, isSet, validateScore } from '../src/game.js';

test('seed version matches shared golden boards', () => {
  const fixtures = JSON.parse(readFileSync(new URL('../../test/seed_fixtures.json', import.meta.url)));
  for (const [seed, boards] of Object.entries(fixtures)) assert.deepEqual(seededBoards(seed), boards);
});
test('1000 seeds have five unique, solvable boards', () => {
  for (let i = 0; i < 1000; i++) {
    const boards = seededBoards('s1-' + i.toString(16).padStart(8, '0'));
    assert.equal(boards.length, 5);
    for (const board of boards) {
      assert.equal(new Set(board).size, 12);
      assert.ok(isSet(findSet(board)));
    }
  }
});
test('scores require solutions to all five actual boards', () => {
  const seed = 's1-1234abcd';
  const score = { player: 'a'.repeat(48), name: 'Flo', seed, milliseconds: 12500,
    mistakes: 0, solutions: seededBoards(seed).map(findSet) };
  assert.ok(validateScore(score));
  assert.equal(validateScore({...score, milliseconds: -1}), false);
  assert.equal(validateScore({...score, solutions: [[0, 1, 2]]}), false);
  assert.equal(validateScore({...score, name: ''}), false);
  assert.equal(validateScore({...score, solutions: score.solutions.map(() => [0, 0, 0])}), false);
});
