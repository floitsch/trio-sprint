// Copyright (C) 2026 Florian Loitsch.
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
const base = process.env.TEST_API_URL || 'http://127.0.0.1:8787';
const id = () => randomBytes(24).toString('hex');
const post = body => fetch(base + '/quiz-scores', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
test('recognition score API validates answers, accepts large runs, separates boards and retries safely', async () => {
  const body = {player: id(), id: id(), name: 'Recognition test', seconds: 30, difficult: true,
    answers: Array(600).fill([0, 40, 80, true])};
  assert.equal((await post(body)).status, 200);
  assert.equal((await post(body)).status, 200);
  assert.equal((await post({...body, seconds: 60})).status, 409);
  assert.equal((await post({...body, id: id(), answers: [[0, 1, 2, true]]})).status, 400);
  const response = await fetch(base + '/quiz-scores?seconds=30&difficult=true&unique=true');
  assert.equal(response.status, 200);
  const scores = (await response.json()).scores;
  assert.ok(scores.some(row => row.name === body.name && row.score === 600 && row.mistakes === 0));
  assert.equal((await fetch(base + '/quiz-scores?seconds=45&difficult=true')).status, 400);
  assert.equal((await fetch(base + '/quiz-scores?seconds=30&difficult=invalid')).status, 400);
});
