// Copyright (C) 2026 Florian Loitsch.
import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readdirSync, readFileSync } from 'node:fs';
import { totalSetsQuery } from '../src/set_totals.js';

function database(t) {
  const db = new DatabaseSync(':memory:');
  t.after(() => db.close());
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of readdirSync(migrations).filter(f => f.endsWith('.sql')).sort()) {
    db.exec(readFileSync(new URL(file, migrations), 'utf8'));
  }
  return db;
}
const rows = db => db.prepare(totalSetsQuery).all().map(row => ({...row}));
const name = (db, player, value) => db.prepare('INSERT INTO player_names (player, name) VALUES (?, ?)')
  .run(player, value);
function attempt(db, player, id, outcome = 'solved', source = 's2', assisted = false) {
  db.prepare('INSERT OR IGNORE INTO attempts (player, attempt_id, board) VALUES (?, ?, ?)')
    .run(player, String(id), JSON.stringify({outcome, source, assisted}));
}

test('totals count repeated solved sets across modes, but never unfinished boards or upload retries', t => {
  const db = database(t);
  name(db, 'a', 'Alice');
  name(db, 'b', 'Bob');
  for (const [id, source] of ['s1', 's2', '1m', '3m', 'race', 'training', 'review', 'replay'].entries()) {
    attempt(db, 'a', id, 'solved', source, true);
    attempt(db, 'a', id, 'solved', source, true);
  }
  for (const [id, outcome] of ['timedOut', 'interrupted', 'restarted', 'skipped'].entries()) {
    attempt(db, 'a', id + 10, outcome);
  }
  attempt(db, 'b', 0);
  assert.deepEqual(rows(db), [{name: 'Alice', sets: 8}, {name: 'Bob', sets: 1}]);
});

test('linked devices share past and future solves, including identical local attempt IDs', t => {
  const db = database(t);
  name(db, 'a', 'Alice');
  name(db, 'c', 'Carol');
  attempt(db, 'a', 0);
  attempt(db, 'b', 0);
  attempt(db, 'c', 0);
  db.prepare('INSERT INTO player_links (player, identity) VALUES (?, ?)').run('a', 'a');
  db.prepare('INSERT INTO player_links (player, identity) VALUES (?, ?)').run('b', 'a');
  assert.deepEqual(rows(db), [{name: 'Alice', sets: 2}, {name: 'Carol', sets: 1}]);
  attempt(db, 'b', 1, 'solved', 'training');
  assert.equal(rows(db)[0].sets, 3);
});

test('nickname changes and old score names can identify existing solves without adding score counts', t => {
  const db = database(t);
  attempt(db, 'a', 0);
  assert.deepEqual(rows(db), []);
  db.prepare('INSERT INTO scores (player, name, seed, milliseconds, mistakes) VALUES (?, ?, ?, ?, ?)')
    .run('a', 'Old name', 's2-1234abcd', 10000, 0);
  assert.deepEqual(rows(db), [{name: 'Old name', sets: 1}]);
  name(db, 'a', 'New name');
  assert.deepEqual(rows(db), [{name: 'New name', sets: 1}]);
  db.prepare('UPDATE player_names SET name = ? WHERE player = ?').run('Latest name', 'a');
  assert.deepEqual(rows(db), [{name: 'Latest name', sets: 1}]);
});

test('totals list at most 100 named players with consistent ordering for ties', t => {
  const db = database(t);
  for (let i = 0; i < 105; i++) {
    const id = String(i).padStart(3, '0');
    name(db, id, `Player ${id}`);
    attempt(db, id, 0);
  }
  const scores = rows(db);
  assert.equal(scores.length, 100);
  assert.equal(scores[0].name, 'Player 000');
  assert.equal(scores[99].name, 'Player 099');
});
