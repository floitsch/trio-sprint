-- A short, stable code for each device. Existing identities and scores stay intact.
CREATE TABLE pairing_codes (
  player TEXT PRIMARY KEY REFERENCES player_links(player),
  code TEXT NOT NULL UNIQUE
);
