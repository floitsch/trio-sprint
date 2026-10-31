-- Copyright (C) 2026 Florian Loitsch.
-- Names for players who only train or have not completed a scored run yet.
CREATE TABLE player_names (
  player TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX attempts_solved_player ON attempts(player)
  WHERE json_extract(board, '$.outcome') = 'solved';
