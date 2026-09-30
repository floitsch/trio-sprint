// Copyright (C) 2026 Toit contributors.
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { SeededRun, findSet } from '../src/game.js';

const base = process.env.TEST_API_URL || 'http://127.0.0.1:8787';
const player = () => randomBytes(24).toString('hex');
const seed = () => 's2-' + randomBytes(4).toString('hex');
async function post(path, body, status = 200) {
  const response = await fetch(base + path, {
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
  });
  const result = await response.json();
  assert.equal(response.status, status, JSON.stringify(result));
  return result;
}
const code = player => post('/players/code', {player});
const pairing = player => post('/players/pairing', {player});
const merge = (player, target) => post('/players/merge', {player, target});
async function scores(query) {
  const response = await fetch(base + '/scores?' + new URLSearchParams(query));
  assert.equal(response.status, 200);
  return (await response.json()).scores;
}
function score(player, seed, name, milliseconds) {
  const run = new SeededRun(seed);
  const solutions = [];
  for (let i = 0; i < 5; i++) {
    const solution = findSet(run.board);
    solutions.push(solution);
    run.pick(solution);
  }
  return {player, seed, name, milliseconds, mistakes: 0, solutions};
}

test('codes are stable, validated, and must come from an existing device', async () => {
  const a = player();
  assert.deepEqual(await code(a), {code: a, devices: 1});
  assert.deepEqual(await code(a), {code: a, devices: 1});
  await post('/players/code', {player: 'bad'}, 400);
  await post('/players/merge', {player: a, target: 'bad'}, 400);
  await post('/players/merge', {player: a, target: player()}, 404);
  assert.deepEqual(await merge(a, a), {ok: true, devices: 1});
});

test('short codes are unique, stable during concurrent requests, and survive group merges', async () => {
  const [a, b, c] = Array.from({length: 3}, player);
  const responses = await Promise.all(Array.from({length: 8}, () => pairing(a)));
  const short = responses[0].code;
  assert.match(short, /^[A-HJ-NP-Z2-9]{6}$/);
  for (const response of responses) assert.deepEqual(response, {code: short, devices: 1});
  const bCode = (await pairing(b)).code;
  assert.notEqual(short, bCode);
  const formatted = short.slice(0, 3).toLowerCase() + ' - ' + short.slice(3).toLowerCase();
  assert.deepEqual(await merge(b, formatted), {ok: true, devices: 2});
  assert.deepEqual(await pairing(a), {code: short, devices: 2});
  assert.deepEqual(await pairing(b), {code: bCode, devices: 2});
  assert.deepEqual(await merge(c, bCode), {ok: true, devices: 3});
  assert.equal((await code(a)).devices, 3);
  await post('/players/pairing', {player: 'bad'}, 400);
  await post('/players/merge', {player: a, target: 'ABC01I'}, 400);
  // Find a valid unused code without assuming any particular database contents.
  const missing = 'ZZZ' + randomBytes(2).toString('hex').slice(0, 3).replace(/[01]/g, 'Z').toUpperCase();
  await post('/players/merge', {player: a, target: missing}, 404);
});

test('linking combines existing and future scores and keeps the earliest seed submission', async () => {
  const a = player(), b = player(), shared = seed(), separate = seed();
  const name = 'Link ' + randomBytes(5).toString('hex');
  const original = score(a, shared, name, 4);
  await post('/scores', original);
  await post('/scores', score(b, shared, name, 1));
  await post('/scores', score(b, separate, name, 3));
  assert.equal((await scores({seed: shared})).length, 2);
  const short = (await pairing(a)).code;
  // The source need not have opened Link devices beforehand.
  assert.deepEqual(await merge(b, short), {ok: true, devices: 2});
  for (const unique of ['true', 'false']) {
    const rows = await scores({seed: shared, unique});
    assert.equal(rows.length, 1);
    assert.equal(rows[0].milliseconds, 4);
  }
  const all = (await scores({unique: 'false'})).filter(row => row.name === name);
  assert.deepEqual(all.map(row => row.seed), [separate, shared]);
  const best = (await scores({unique: 'true'})).filter(row => row.name === name);
  assert.deepEqual(best.map(row => row.seed), [separate]);
  await post('/scores', original); // Original submissions remain retryable.
  await post('/scores', score(b, shared, name, 2), 409);
  const future = seed();
  await post('/scores', score(b, future, name, 2));
  await post('/scores', score(a, future, name, 3), 409);
  assert.deepEqual(await merge(a, b), {ok: true, devices: 2});
  assert.equal((await scores({seed: future})).length, 1);
  assert.equal((await scores({seed: separate})).length, 1);
  assert.deepEqual(await code(a), {code: a, devices: 2});
  assert.deepEqual(await code(b), {code: b, devices: 2});
});

test('merging groups and reusing old codes keeps every member linked', async () => {
  const [a, b, c, d, e] = Array.from({length: 5}, player);
  await Promise.all([a, b, c, d, e].map(code));
  await merge(a, b);
  await merge(c, d);
  assert.equal((await merge(a, c)).devices, 4);
  assert.equal((await merge(e, b)).devices, 5);
  for (const id of [a, b, c, d, e]) assert.equal((await code(id)).devices, 5);
});

test('simultaneous merges converge and linked devices cannot submit the same seed twice', async () => {
  const [a, b, c] = Array.from({length: 3}, player);
  await Promise.all([a, b, c].map(code));
  await Promise.all([merge(a, b), merge(a, c), merge(c, b)]);
  for (const id of [a, b, c]) assert.equal((await code(id)).devices, 3);
  const shared = seed();
  const responses = await Promise.all([a, b, c].map((id, i) => fetch(base + '/scores', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(score(id, shared, 'Concurrent link', 100 + i)),
  })));
  assert.deepEqual(responses.map(r => r.status).sort(), [200, 409, 409]);
  assert.equal((await scores({seed: shared, unique: 'false'})).length, 1);
});
