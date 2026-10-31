// Copyright (C) 2026 Florian Loitsch.

export async function savePlayerName(db, player, name) {
  await db.prepare(`INSERT INTO player_names (player, name) VALUES (?, ?)
    ON CONFLICT(player) DO UPDATE SET name = excluded.name, updated_at = CURRENT_TIMESTAMP`)
    .bind(player, name.trim()).run();
}

// Each uploaded attempt is immutable and unique to its device, so retries do
// not increase totals. Repeated solves and solves from unfinished runs count.
// Resolve device links at read time to include past and future solves.
export const totalSetsQuery = `WITH totals AS (
    SELECT COALESCE(links.identity, attempts.player) AS identity, COUNT(*) AS sets
    FROM attempts LEFT JOIN player_links links ON links.player = attempts.player
    WHERE json_extract(board, '$.outcome') = 'solved'
    GROUP BY COALESCE(links.identity, attempts.player)
  ), names AS (
    SELECT player, name, updated_at, 1 AS priority FROM player_names
    UNION ALL
    SELECT player, name, created_at AS updated_at, 0 AS priority FROM scores
  ), ranked_names AS (
    SELECT COALESCE(links.identity, names.player) AS identity, name,
      ROW_NUMBER() OVER (
        PARTITION BY COALESCE(links.identity, names.player)
        ORDER BY priority DESC, updated_at DESC, names.player, name
      ) AS name_rank
    FROM names LEFT JOIN player_links links ON links.player = names.player
  ) SELECT ranked_names.name, totals.sets
    FROM totals JOIN ranked_names USING (identity)
    WHERE name_rank = 1
    ORDER BY sets DESC, totals.identity LIMIT 100`;
