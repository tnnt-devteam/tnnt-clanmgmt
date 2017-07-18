PRAGMA foreign_keys=on;

DROP TABLE clans;
DROP TABLE players;

CREATE TABLE clans (
  clans_i INTEGER PRIMARY KEY,
  name text NOT NULL UNIQUE
);

CREATE TABLE players (
  players_i INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  pwd TEXT NOT NULL,
  clans_i INT,
  clan_admin INT NOT NULL DEFAULT 0,
  FOREIGN KEY (clans_i) REFERENCES clans(clans_i)
);
