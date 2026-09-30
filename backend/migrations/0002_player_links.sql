-- Device IDs stay stable; all linked devices point directly to one identity.
-- Scores retain their original device ID, so linking never deletes a score.
CREATE TABLE player_links (
  player TEXT PRIMARY KEY,
  identity TEXT NOT NULL
);
CREATE INDEX player_links_identity ON player_links(identity);
