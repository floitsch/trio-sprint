// Copyright (C) 2026 Florian Loitsch.
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { SeededRun, findSet } from '../src/game.js';

const base = process.env.TEST_API_URL || 'http://127.0.0.1:8787';
const playerId = () => randomBytes(24).toString('hex');
async function post(path, body, status = 200) {
  const response = await fetch(base + path, {
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
  });
  assert.equal(response.status, status, await response.text());
}
async function total(name) {
  const response = await fetch(base + '/scores/total-sets');
  assert.equal(response.status, 200);
  return (await response.json()).scores.filter(row => row.name === name);
}
function attempt(id, outcome, source = 's2', assisted = false) {
  const run = new SeededRun('s2-1234abcd');
  return {id: String(id), board: {
    cards: run.board, anchors: [], differences: null, milliseconds: 2000,
    mistakes: 0, assisted, outcome, source, seed: 's2-1234abcd',
    recordedAt: Date.now(), solutionCards: outcome === 'solved' ? findSet(run.board) : [],
  }};
}

test('total-sets API counts solved history once, combines devices, and updates names without a run score', async () => {
  const a = playerId(), b = playerId();
  const name = 'Total ' + randomBytes(5).toString('hex');
  await post('/players/name', {player: 'bad', name}, 400);
  await post('/players/name', {player: a, name: ''}, 400);
  await post('/players/name', {player: a, name: 'Bad\nname'}, 400);
  const batch = {player: a, attempts: [
    attempt(0, 'solved'), attempt(1, 'solved', 'replay', true),
    ...['timedOut', 'restarted', 'interrupted', 'skipped'].map((o, i) => attempt(i + 2, o)),
  ]};
  await post('/attempts', batch);
  await post('/attempts', batch);
  await post('/players/name', {player: a, name});
  assert.deepEqual(await total(name), [{name, sets: 2}]);
  await post('/attempts', {player: b, attempts: [
    attempt(0, 'solved', 'training'), attempt(1, 'solved', 'race'),
  ]});
  await post('/players/code', {player: a});
  await post('/players/merge', {player: b, target: a});
  assert.deepEqual(await total(name), [{name, sets: 4}]);
  const renamed = name + ' new';
  await post('/players/name', {player: a, name: renamed});
  assert.deepEqual(await total(renamed), [{name: renamed, sets: 4}]);
  assert.deepEqual(await total(name), []);
});
