PRAGMA foreign_keys=on;

DROP TABLE clans;
DROP TABLE players;
DROP TABLE invites;

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

CREATE TABLE invites (
  invitor INT NOT NULL,
  invitee INT NOT NULL,
  creat_when INT DEFAULT current_timestamp,
  FOREIGN KEY (invitor) REFERENCES players(players_i) ON DELETE CASCADE,
  FOREIGN KEY (invitee) REFERENCES players(players_i) ON DELETE CASCADE
);
