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

test('s2 golden runs match every board, including different paths and tap order', async () => {
  const {SeededRun} = await import('../src/game.js');
  const fixtures = JSON.parse(readFileSync(new URL('../../test/run_fixtures.json', import.meta.url)));
  for (const fixture of fixtures) {
    const run = new SeededRun(fixture.seed);
    for (let i = 0; i < 5; i++) {
      assert.deepEqual(run.board, fixture.boards[i]);
      assert.ok(run.pick([...fixture.solutions[i]].reverse()));
    }
    assert.equal(run.progress, 5);
    assert.equal(run.pick(fixture.solutions[4]), false);
    assert.ok(validateScore({player: 'a'.repeat(48), name: 'Flo', seed: fixture.seed,
      milliseconds: 12000, mistakes: 0, solutions: fixture.solutions}));
    assert.equal(validateScore({player: 'a'.repeat(48), name: 'Flo', seed: fixture.seed,
      milliseconds: 12000, mistakes: 0, solutions: fixture.solutions.map(() => fixture.solutions[0])}), false);
  }
});

test('1000 s2 runs keep unchosen cards in place and remain solvable', async () => {
  const {SeededRun} = await import('../src/game.js');
  for (let i = 0; i < 1000; i++) {
    const seed = 's2-' + i.toString(16).padStart(8, '0');
    const run = new SeededRun(seed);
    const replay = new SeededRun(seed);
    assert.equal(run.pick([0, 0, 0]), false);
    for (let round = 0; round < 5; round++) {
      const before = [...run.board];
      const solution = findSet(i % 2 ? before : [...before].reverse());
      assert.ok(solution);
      assert.ok(run.pick(solution));
      assert.ok(replay.pick([...solution].reverse()));
      assert.deepEqual(run.board, replay.board);
      assert.equal(new Set(run.board).size, 12);
      for (let position = 0; position < 12; position++) {
        if (!solution.includes(before[position]) || round === 4)
          assert.equal(run.board[position], before[position]);
      }
    }
    assert.equal(run.progress, 5);
  }
});
