// Copyright (C) 2026 Toit contributors.
import { validPlayer } from './game.js';

export async function registerDevice(db, player) {
  await db.prepare('INSERT OR IGNORE INTO player_links (player, identity) VALUES (?, ?)')
    .bind(player, player).run();
}

export async function deviceCount(db, player) {
  const row = await db.prepare(`SELECT COUNT(*) AS count FROM player_links
    WHERE identity = (SELECT identity FROM player_links WHERE player = ?)`)
    .bind(player).first();
  return row.count;
}

export async function pairingCode(db, player) {
  await registerDevice(db, player);
  const find = () => db.prepare('SELECT code FROM pairing_codes WHERE player = ?').bind(player).first();
  const existing = await find();
  if (existing) return existing.code;
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = Array.from(crypto.getRandomValues(new Uint8Array(6)), b => alphabet[b % alphabet.length]).join('');
    // Both unique constraints matter: retry a code collision, but reuse a code
    // created concurrently for this same device.
    await db.prepare('INSERT OR IGNORE INTO pairing_codes (player, code) VALUES (?, ?)')
      .bind(player, code).run();
    const created = await find();
    if (created) return created.code;
  }
  throw new Error('Could not allocate pairing code');
}

export async function linkDevices(db, body) {
  if (!body || !validPlayer(body.player) || typeof body.target !== 'string')
    return {error: 'Invalid device code', status: 400};
  const value = body.target.replace(/[\s-]/g, '');
  let target;
  if (/^[A-HJ-NP-Z2-9]{6}$/i.test(value)) {
    target = await db.prepare('SELECT player FROM pairing_codes WHERE code = ?')
      .bind(value.toUpperCase()).first();
  } else if (validPlayer(value.toLowerCase())) {
    // Cached older apps and previously copied long codes keep working.
    target = await db.prepare('SELECT player FROM player_links WHERE player = ?')
      .bind(value.toLowerCase()).first();
  } else {
    return {error: 'Invalid device code', status: 400};
  }
  if (!target) return {error: 'Code not found. Check the code shown in Link devices on your other device.', status: 404};
  await registerDevice(db, body.player);
  // Resolve both groups within the same atomic statement. This also handles
  // simultaneous merges and codes copied before their device was linked.
  await db.prepare(`WITH groups AS MATERIALIZED (
      SELECT source.identity AS source, target.identity AS target
      FROM player_links source, player_links target
      WHERE source.player = ? AND target.player = ?
    ) UPDATE player_links SET identity = (SELECT target FROM groups)
      WHERE identity = (SELECT source FROM groups)`)
    .bind(body.player, target.player).run();
  return {ok: true, devices: await deviceCount(db, body.player)};
}

// Joining at read time keeps original submissions intact. If linked devices
// submitted the same seed, only their earliest submission remains eligible.
export const scoreIdentities = `SELECT scores.*, COALESCE(player_links.identity, scores.player) AS identity
  FROM scores LEFT JOIN player_links ON player_links.player = scores.player`;

// More sets rank higher. Sprints always have five, so they rank by time.
export function scoreQuery(unique, filteredSeed, mode = 's2') {
  if (!['s2', '1m', '3m'].includes(mode)) throw new Error('Invalid mode');
  return `WITH runs AS (
      ${scoreIdentities} ${filteredSeed ? 'WHERE seed = ?' : `WHERE seed LIKE '${mode}-%'`}
    ), attempts AS (
      SELECT *, ROW_NUMBER() OVER (PARTITION BY identity, seed ORDER BY id) AS attempt_rank FROM runs
    ), ranked AS (
      SELECT *, ROW_NUMBER() OVER (PARTITION BY identity ORDER BY sets DESC, milliseconds, id) AS player_rank
      FROM attempts WHERE attempt_rank = 1
    ) SELECT name, seed, milliseconds, mistakes, sets FROM ranked
      ${unique ? 'WHERE player_rank = 1' : ''} ORDER BY sets DESC, milliseconds, id LIMIT 100`;
}

export const existingScoreQuery = `SELECT milliseconds, mistakes, sets FROM (${scoreIdentities})
  WHERE seed = ? AND identity = COALESCE((SELECT identity FROM player_links WHERE player = ?), ?)
  ORDER BY id LIMIT 1`;

export const insertScoreQuery = `INSERT INTO scores (player, name, seed, milliseconds, mistakes, sets)
  SELECT ?, ?, ?, ?, ?, ? WHERE NOT EXISTS (${existingScoreQuery})
  ON CONFLICT(player, seed) DO NOTHING`;
