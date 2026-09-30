import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { SeededRun, findSet } from '../src/game.js';

const base = process.env.TEST_API_URL || 'http://127.0.0.1:8787';
const player = () => randomBytes(24).toString('hex');
async function post(path, body) {
  return fetch(base + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
}
const seedFor = i => 's2-' + i.toString(16).padStart(8, '0');
const score = (id, seed, milliseconds = 50000) => {
  const run = new SeededRun(seed);
  const solutions = [];
  for (let i = 0; i < 5; i++) {
    const solution = findSet(run.board);
    solutions.push(solution);
    run.pick(solution);
  }
  return {player: id, name: 'Test friend', seed, milliseconds, mistakes: 0, solutions};
};

test('scores: more than five, per-player filter, seed filter, immutable/idempotent submissions', async () => {
  const id = player();
  const seed = 's2-' + randomBytes(4).toString('hex');
  const body = score(id, seed, 12345);
  assert.equal((await post('/scores', body)).status, 200);
  assert.equal((await post('/scores', body)).status, 200);
  assert.equal((await post('/scores', {...body, milliseconds: 1234})).status, 409);
  assert.equal((await post('/scores', {...body, player: player(), solutions: []})).status, 400);
  const perSeed = await (await fetch(base + '/scores?seed=' + seed)).json();
  assert.equal(perSeed.scores.length, 1);
  assert.equal(perSeed.scores[0].milliseconds, 12345);
  for (let i = 0; i < 12; i++) assert.equal((await post('/scores', score(id, seedFor(i), 10 + i))).status, 200);
  const all = await (await fetch(base + '/scores?unique=false')).json();
  const unique = await (await fetch(base + '/scores?unique=true')).json();
  assert.ok(all.scores.length >= 13);
  assert.ok(unique.scores.length < all.scores.length);
  assert.equal((await fetch(base + '/scores?seed=nope')).status, 400);
  const legacySeed = seed.replace('s2-', 's1-');
  assert.equal((await post('/scores', score(id, legacySeed, 1))).status, 200);
  const legacy = await (await fetch(base + '/scores?seed=' + legacySeed)).json();
  assert.equal(legacy.scores.length, 1);
  const current = await (await fetch(base + '/scores?unique=false')).json();
  assert.ok(current.scores.every(row => row.seed.startsWith('s2-')));
});

class Client {
  constructor(room, id, name) {
    this.messages = [];
    this.ws = new WebSocket(base.replace('http', 'ws') + `/rooms/${room}?player=${id}&name=${name}`);
    this.ws.addEventListener('message', event => {
      const data = JSON.parse(event.data);
      this.messages.push(data);
      if (data.type === 'state') this.state = data;
    });
  }
  async wait(predicate) {
    const until = Date.now() + 10000;
    while (Date.now() < until) {
      if (this.state && predicate(this.state)) return this.state;
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    throw new Error('Timed out waiting for race state: ' + JSON.stringify(this.state));
  }
  send(data) { this.ws.send(JSON.stringify(data)); }
  close() { this.ws.close(); }
}

test('two-player race: countdown, identical boards, validation, reconnect and winner', async () => {
  const {room} = await (await post('/rooms', {})).json();
  const id = player();
  const first = new Client(room, id, 'Alice');
  const second = new Client(room, player(), 'Bob');
  let reconnect;
  try {
    await first.wait(s => s.players.length === 2);
    await second.wait(s => s.players.length === 2);
    assert.deepEqual(first.state.board, []);
    first.send({type: 'ready'});
    second.send({type: 'ready'});
    await first.wait(s => s.startAt !== null);
    assert.deepEqual(first.state.board, []);
    await first.wait(s => s.board.length === 12);
    await second.wait(s => s.board.length === 12);
    assert.deepEqual(first.state.board, second.state.board);
    first.send({type: 'pick', round: 0, cards: [0, 0, 0]});
    await first.wait(s => s.players[s.you].mistakes === 1);
    assert.equal(first.state.players[first.state.you].progress, 0);
    assert.match(first.state.seed, /^s2-/);
    const starting = [...first.state.board];
    const solution = findSet(starting);
    first.send({type: 'pick', round: 0, cards: solution});
    await first.wait(s => s.players[s.you].progress === 1);
    const nextBoard = [...first.state.board];
    for (let i = 0; i < 12; i++) {
      if (!solution.includes(starting[i])) assert.equal(nextBoard[i], starting[i]);
    }
    assert.deepEqual(second.state.board, starting);
    first.close();
    await second.wait(s => s.players.some(p => p.name === 'Alice' && !p.connected));
    reconnect = new Client(room, id, 'Alice');
    await reconnect.wait(s => s.players[s.you].progress === 1);
    assert.deepEqual(reconnect.state.board, nextBoard);
    reconnect.send({type: 'pick', round: 0, cards: findSet(reconnect.state.board)});
    await new Promise(resolve => setTimeout(resolve, 100));
    assert.equal(reconnect.state.players[reconnect.state.you].progress, 1);
    for (let round = 1; round < 5; round++) {
      reconnect.send({type: 'pick', round, cards: findSet(reconnect.state.board)});
      await reconnect.wait(s => s.players[s.you].progress === round + 1);
    }
    await second.wait(s => s.ended);
    assert.equal(reconnect.state.winner, reconnect.state.you);
    assert.equal(second.state.winner, reconnect.state.winner);
  } finally { first.close(); second.close(); reconnect?.close(); }
});

test('leaving a started race forfeits it', async () => {
  const {room} = await (await post('/rooms', {})).json();
  const first = new Client(room, player(), 'Alice');
  const second = new Client(room, player(), 'Bob');
  try {
    await first.wait(s => s.players.length === 2);
    await second.wait(s => s.players.length === 2);
    first.send({type: 'ready'});
    second.send({type: 'ready'});
    await first.wait(s => s.startAt !== null);
    first.send({type: 'leave'});
    await second.wait(s => s.ended);
    assert.equal(second.state.winner, second.state.you);
  } finally { first.close(); second.close(); }
});
