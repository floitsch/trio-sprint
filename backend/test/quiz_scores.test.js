// Copyright (C) 2026 Florian Loitsch.
import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readdirSync, readFileSync} from 'node:fs';
import {quizResult, quizScoreQuery, saveQuizScore} from '../src/quiz_scores.js';

const body = (overrides = {}) => ({player: 'a'.repeat(48), id: '1'.repeat(48), name: 'Alice', seconds: 30,
  difficult: false, answers: [[0, 40, 80, true], [0, 40, 79, false], [0, 40, 80, false]], ...overrides});
function database(t) {
  const raw = new DatabaseSync(':memory:');
  t.after(() => raw.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of readdirSync(migrations).filter(f => f.endsWith('.sql')).sort()) raw.exec(readFileSync(new URL(file, migrations), 'utf8'));
  const db = {prepare(sql) { return {bind(...args) { const statement = raw.prepare(sql); return {
    run: async () => statement.run(...args), first: async () => statement.get(...args),
  }; }}; }};
  return {raw, db};
}

test('server derives points from answers and rejects invalid modes, cards and difficulty', () => {
  assert.deepEqual(quizResult(body()), {correct: 2, mistakes: 1});
  assert.deepEqual(quizResult(body({correct: 9999, score: 9999, difficult: true})), {correct: 2, mistakes: 1});
  for (const update of [{seconds: 0}, {seconds: 45}, {seconds: '30'}, {difficult: 1}, {name: ''}, {id: 'bad'},
    {answers: []}, {answers: Array(3001).fill([0, 40, 80, true])}, {answers: [[0, 0, 0, true]]},
    {answers: [[0, 40, 81, false]]}, {answers: [[0, 40, 80, 1]]}, {answers: [[0, 1, 2, true]], difficult: true}]) {
    assert.equal(quizResult(body(update)), null, JSON.stringify(update).slice(0, 100));
  }
  for (const seconds of [30, 60, 180]) assert.ok(quizResult(body({seconds})));
});

test('retries are idempotent and cannot replace a submitted race', async t => {
  const {raw, db} = database(t);
  assert.deepEqual(await saveQuizScore(db, body()), {ok: true});
  assert.deepEqual(await saveQuizScore(db, body()), {ok: true});
  assert.equal(raw.prepare('SELECT COUNT(*) AS n FROM quiz_scores').get().n, 1);
  assert.equal((await saveQuizScore(db, body({answers: [[0, 40, 80, true]]}))).status, 409);
  assert.equal((await saveQuizScore(db, body({seconds: 60}))).status, 409);
  assert.equal((await saveQuizScore(db, body({answers: []}))).status, 400);
});

test('leaderboards separate duration/difficulty, rank negative scores and merge linked devices', async t => {
  const {raw, db} = database(t);
  await saveQuizScore(db, body());
  await saveQuizScore(db, body({player: 'b'.repeat(48), name: 'Bob', answers: [[0, 40, 80, true]]}));
  await saveQuizScore(db, body({id: '2'.repeat(48), answers: [[0, 40, 80, true], [0, 40, 80, true]]}));
  await saveQuizScore(db, body({player: 'c'.repeat(48), name: 'Carol', answers: [[0, 40, 80, false]]}));
  await saveQuizScore(db, body({id: '3'.repeat(48), seconds: 60}));
  await saveQuizScore(db, body({id: '4'.repeat(48), difficult: true}));
  const rows = (unique, seconds = 30, hard = 0) => raw.prepare(quizScoreQuery(unique)).all(seconds, hard).map(r => ({...r}));
  assert.deepEqual(rows(false).map(r => [r.name, r.score, r.mistakes]), [['Alice', 2, 0], ['Bob', 1, 0], ['Alice', 1, 1], ['Carol', -1, 1]]);
  assert.equal(rows(true).length, 3);
  raw.prepare('INSERT INTO player_links (player, identity) VALUES (?, ?)').run('b'.repeat(48), 'a'.repeat(48));
  assert.deepEqual(rows(true).map(r => r.name), ['Alice', 'Carol']);
  assert.equal(rows(false, 60).length, 1);
  assert.equal(rows(false, 30, 1).length, 1);
});
