-- Board history is private to a device ID, separate from public high scores.
-- Stable local IDs make uploads safe to retry after a lost response.
CREATE TABLE attempts (
  player TEXT NOT NULL,
  attempt_id TEXT NOT NULL,
  board TEXT NOT NULL,
  uploaded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (player, attempt_id)
);
