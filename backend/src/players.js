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

export async function linkDevices(db, body) {
  if (!body || !validPlayer(body.player) || !validPlayer(body.target))
    return {error: 'Invalid device code', status: 400};
  const target = await db.prepare('SELECT player FROM player_links WHERE player = ?')
    .bind(body.target).first();
  if (!target) return {error: 'Device code not found. Copy the code from Link devices on the other device.', status: 404};
  await registerDevice(db, body.player);
  // Resolve both groups within the same atomic statement. This also handles
  // simultaneous merges and codes copied before their device was linked.
  await db.prepare(`WITH groups AS MATERIALIZED (
      SELECT source.identity AS source, target.identity AS target
      FROM player_links source, player_links target
      WHERE source.player = ? AND target.player = ?
    ) UPDATE player_links SET identity = (SELECT target FROM groups)
      WHERE identity = (SELECT source FROM groups)`)
    .bind(body.player, body.target).run();
  return {ok: true, devices: await deviceCount(db, body.player)};
}

// Joining at read time keeps original submissions intact. If linked devices
// submitted the same seed, only their earliest submission remains eligible.
export const scoreIdentities = `SELECT scores.*, COALESCE(player_links.identity, scores.player) AS identity
  FROM scores LEFT JOIN player_links ON player_links.player = scores.player`;

export function scoreQuery(unique, filteredSeed) {
  return `WITH runs AS (
      ${scoreIdentities} ${filteredSeed ? 'WHERE seed = ?' : "WHERE seed LIKE 's2-%'"}
    ), attempts AS (
      SELECT *, ROW_NUMBER() OVER (PARTITION BY identity, seed ORDER BY id) AS attempt_rank FROM runs
    ), ranked AS (
      SELECT *, ROW_NUMBER() OVER (PARTITION BY identity ORDER BY milliseconds, id) AS player_rank
      FROM attempts WHERE attempt_rank = 1
    ) SELECT name, seed, milliseconds, mistakes FROM ranked
      ${unique ? 'WHERE player_rank = 1' : ''} ORDER BY milliseconds, id LIMIT 100`;
}

export const existingScoreQuery = `SELECT milliseconds, mistakes FROM (${scoreIdentities})
  WHERE seed = ? AND identity = COALESCE((SELECT identity FROM player_links WHERE player = ?), ?)
  ORDER BY id LIMIT 1`;

export const insertScoreQuery = `INSERT INTO scores (player, name, seed, milliseconds, mistakes)
  SELECT ?, ?, ?, ?, ? WHERE NOT EXISTS (${existingScoreQuery})
  ON CONFLICT(player, seed) DO NOTHING`;
