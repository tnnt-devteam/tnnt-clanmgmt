PRAGMA foreign_keys=on;

CREATE TABLE clans (
  clans_i INTEGER PRIMARY KEY,
  name text NOT NULL
);

CREATE TABLE players (
  players_i INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  pwd TEXT NOT NULL,
  clans_i INT,
  FOREIGN KEY (clans_i) REFERENCES clans(clans_i)
);
