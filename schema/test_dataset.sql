------------------------------------------------------------------------------
-- dataset for testing the Devnull::Web application
------------------------------------------------------------------------------

PRAGMA FOREIGN_KEYS = ON;

-- clean up

DELETE FROM clans;
DELETE FROM players;

-- create two clans: "clan1" and "clan2"

INSERT INTO clans VALUES ( 1, 'clan1' );
INSERT INTO clans VALUES ( 2, 'clan2' );

-- create users, all of them have password 'pw'
-- players 1 to 4 are clan1 members, players 5-8 are clan2 members
-- player 9 is member of no clan
-- players 1 and 5 are admins of their respective clans

INSERT INTO players (name,pwd,clans_i,clan_admin ) VALUES ('player1','',1,1);
INSERT INTO players (name,pwd,clans_i,clan_admin ) VALUES ('player2','',1,0);
INSERT INTO players (name,pwd,clans_i,clan_admin ) VALUES ('player3','',1,0);
INSERT INTO players (name,pwd,clans_i,clan_admin ) VALUES ('player4','',1,0);
INSERT INTO players (name,pwd,clans_i,clan_admin ) VALUES ('player5','',2,1);
INSERT INTO players (name,pwd,clans_i,clan_admin ) VALUES ('player6','',2,0);
INSERT INTO players (name,pwd,clans_i,clan_admin ) VALUES ('player7','',2,0);
INSERT INTO players (name,pwd,clans_i,clan_admin ) VALUES ('player8','',2,0);
INSERT INTO players (name,pwd,clans_i,clan_admin ) VALUES ('player9','',NULL,0);

UPDATE players
SET pwd = '{CRYPT}$2a$04$UY6M3D72VPwBGg9djgyZTehWgRH1N55QuyY3otCS8Any97mlItji2';
