CREATE TABLE scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  player TEXT NOT NULL,
  name TEXT NOT NULL,
  seed TEXT NOT NULL,
  milliseconds INTEGER NOT NULL CHECK(milliseconds > 0),
  mistakes INTEGER NOT NULL CHECK(mistakes >= 0),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(player, seed)
);
CREATE INDEX scores_time ON scores(milliseconds, id);
CREATE INDEX scores_seed_time ON scores(seed, milliseconds, id);
