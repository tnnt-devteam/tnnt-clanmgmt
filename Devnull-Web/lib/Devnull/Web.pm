#=============================================================================
# THE NOVEMBER NETHACK TOURNAMENT CLAN MANAGEMENT
# """""""""""""""""""""""""""""""""""""""""""""""
# Derived from /dev/null/nethack Tribute clan management code
#
# (c) 2017-2018 Borek Lupomesky <borek@lupomesky.cz>
#=============================================================================

package Devnull::Web;
use Dancer2;
use Dancer2::Plugin::Database;
use Syntax::Keyword::Try;

our $VERSION = '0.1';

use utf8;


#=============================================================================
#====   __   ============   _   _  ===========================================
#===   / _|_   _ _ __   ___| |_(_) ___  _ __  ___   ==========================
#===  | |_| | | | '_ \ / __| __| |/ _ \| '_ \/ __|  ==========================
#===  |  _| |_| | | | | (__| |_| | (_) | | | \__ \  ==========================
#===  |_|  \__,_|_| |_|\___|\__|_|\___/|_| |_|___/  ==========================
#===                                               ===========================
#=============================================================================


#=============================================================================
# Verify player credentials (name, password). Returns reference on success,
# error text otherwise.
#=============================================================================

sub plr_authenticate
{
  #--- arguments

  my (
    $name,     # 1. player name
    $pwd       # 2. password
  ) = @_;

  #--- dgamelaunch trims passwords to 20 chars

  $pwd = substr($pwd, 0, 20);

  #--- canonical name (as stored in dgamelaunch database)

  my $name_canon;

  #--- authenticate

  if($name && $pwd) {
    my $sth = database('dgl')->prepare(
      'SELECT username, password FROM dglusers WHERE lower(username) = ?'
    );
    my $r = $sth->execute(lc($name));
    if(!$r) { return "Failed to query database"; }
    my ($name_canon, $pw_db) = $sth->fetchrow_array();
    if(!defined($pw_db)) {
      return "Account '$name' does not exist";
    }
    if(crypt($pwd, $pw_db) eq $pw_db) {
      return \$name_canon;
    } else {
      return "Wrong player name or password";
    }
  }

  #--- invalid arguments

  return "Player name or password not specified";
}


#=============================================================================
# Tries to find whether player account exists and creates a new one if it does
# not. Returns empty arrayref on success, otherwise error message.
#=============================================================================

sub plr_new
{
  #--- arguments

  my ($name) = @_;

  #--- other variables

  my $players_i;

  #--- try to find the player

  my $dbh = database('clandb');
  if(!ref($dbh)) {
    return 'Failed to connect to database';
  }
  my $sth = $dbh->prepare('SELECT players_i FROM players WHERE name = ?');
  my $r = $sth->execute($name);
  if(!$r) {
    return sprintf('Failed to query database (%s)', $sth->errstr());
  } else {
    ($players_i) = $sth->fetchrow_array();
    if(!defined $players_i) {

  #--- player not found, create new account

      $r = $dbh->do(
        'INSERT INTO players ( name ) VALUES ( ? )', undef, $name
      );
      if(!$r) {
        return sprintf('Failed to initialize account (%s)', $dbh->errstr());
      } else {
        return [];
      }
    } else {
      return [];
    }
  }
}


#=============================================================================
# Check whether player exists in dgamelaunch database and if they do,
# instantiate them in clandb
#=============================================================================

sub plr_new_dgl
{
  #--- arguments

  my ($name) = @_;

  #--- verify that the player exists in the dgamelaunch database

  my $dbh = database('dgl');
  my $sth = $dbh->prepare(
    'SELECT username FROM dglusers WHERE username = ?'
  );
  my $r = $sth->execute($name);
  if(!$r) {
    return sprintf('Database query failed (%s)', $sth->errstr());
  }
  my ($p) = $sth->fetchrow_array();
  if(!defined $p) {
    return 'Player not found';
  }

  #--- now create an account in clandb

  $r = plr_new($name);
  return $r;
}


#=============================================================================
# Returns hashref with player info retrieved from backend database in
# following keys:
#
#   clan_name, clan_admin, clan_id, players_i
#
# If extended info is requested, then additional keys are returned (only if
# clan member!):
#
#   can_leave, sole_admin
#
# 'sole_admin' is true if the player is the only admin in the clan,
# 'can_leave' is true if the player can leave the clan; player can leave only
# when there is another clan admin OR he is the last remaining member.
#=============================================================================

sub plr_info
{
  #--- arguments

  my ($name, $extended) = @_;

  #--- other variables

  my $re;

  #--- get the info

  my $sth = database('clandb')->prepare(
    'SELECT c.name AS clan_name, p.clan_admin AS clan_admin, '
    . 'p.clans_i AS clan_id, p.players_i '
    . 'FROM players p LEFT JOIN clans c '
    . 'USING ( clans_i ) WHERE p.name = ?'
  );
  if(!ref($sth)) { return "Failed to get database handle\n"; }
  my $r = $sth->execute($name);
  if(!$r) { return "Failed to query database\n"; }
  $r = $sth->fetchrow_hashref('NAME_lc');
  if(!$r) {
    return 'Player not found';
  }
  $re = $r;

  #--- get extended information

  if($extended && defined($re->{'clan_name'})) {

    my $clan = $re->{'clan_name'};
    my $clan_info = clan_get_info($clan);
    if(!ref($clan_info)) {
      return sprintf(
        "Failed to get clan info for clan %s (%s)",
        $clan, $clan_info
      );
    }

    my $clan_members_count = keys %{$clan_info->{$clan}{'players'}};
    my $clan_admins_count = grep {
      $clan_info->{$clan}{'players'}{$_}{clan_admin}
    } keys %{$clan_info->{$clan}{'players'}};

    $re->{'sole_admin'} = ($clan_admins_count == 1) + 0;
    if(
      $clan_admins_count > 1
      || $clan_admins_count == $clan_members_count
    ) {
      $re->{'can_leave'} = 1;
    } else {
      $re->{'can_leave'} = 0;
    }
  }

  #--- finish

  return $re;
}


#=============================================================================
# This creates new clan with a player as admin. Returns hashref with 'clan_id'
# key, error text otherwise.
#=============================================================================

sub plr_start_clan
{
  #--- arguments

  my ($player_name, $clan_name) = @_;

  #--- ensure player is not clan member already

  my $plr = plr_info($player_name);
  if(!ref($plr)) { return "Failed to get player info ($plr)"; }
  if($plr->{'clan_name'}) {
    return "Player '$player_name' is already a clan member";
  }

  #--- block clan creatin if freeze is on

  if(setting('app')->{'freeze'}) {
    return 'Clan freeze in effect, you cannot create clans any more';
  }

  #--- start transaction

  my $r = database('clandb')->begin_work();
  if(!$r) { return 'Failed to start database transaction'; }

  my $clans_i;
  try {

  #--- create new clan

    $r = database('clandb')->do(
      'INSERT INTO clans ( name ) VALUES ( ? )',
      undef, $clan_name
    );
    if(!$r) {
      if(database('clandb')->errstr() =~ /^UNIQUE constraint failed/) {
        die "The clan '$clan_name' already exists, please choose different name\n";
      } else {
        die sprintf("Failed to create a new clan (%s)\n", database('clandb')->errstr());
      }
    }

  #--- get the clan's id

    my $sth = database('clandb')->prepare(
      'SELECT clans_i FROM clans WHERE name = ?'
    );
    if(!ref($sth)) { die "Failed to get db query handle\n"; }
    $r = $sth->execute($clan_name);
    if(!$r) { die "Failed to query database\n"; }
    ($clans_i) = $sth->fetchrow_array();
    if(!$clans_i) { die "Failed to get new clan id\n"; }

  #--- make the player member and admin

    $r = database('clandb')->do(
      'UPDATE players SET clan_admin = 1, clans_i = ? WHERE name = ?',
      undef, $clans_i, $player_name
    );
    if(!$r) { die "Failed to make user $player_name a clan admin\n"; }

  }

  #--- handle failure

  catch {
    chomp($@);
    database('clandb')->rollback;
    return $@;
  }

  #--- commit transaction

  database('clandb')->commit();
  return { clan_id => $clans_i };
}


#=============================================================================
# Return true/false depending on whether the clan membership is at the limit
# or not. Throws an exception on failure.
#=============================================================================

sub is_clan_full
{
  my $clan = shift;

  # fail if no clan name supplied
  die 'Internal error (is_clan_full() requires one argument)' if !$clan;

  # if clan limit is not defined, always return true
  return 1 if(!setting('app')->{'clanlimit'});

  # otherwise get number of players and compare it to the clan limit
  my $sth = database('clandb')->prepare(
    'SELECT count(*) FROM clans LEFT JOIN players USING (clans_i)' .
    'WHERE clans.name = ?'
  );
  my $r = $sth->execute($clan);
  if(!$r) {
    die sprintf('Failed to query database (%s)', $sth->errstr());
  }
  my ($members) = $sth->fetchrow_array();
  return $members >= setting('app')->{'clanlimit'};
}


#=============================================================================
# Removes a player from clan. This function also destroys the clan if there
# are no remaining members and drops all outstanding invitation the player
# has issued for the clan. This function does not check if the remaining
# clan has any admins! Returns ref on success, error text otherwise.
#=============================================================================

sub plr_leave_clan
{
  #--- arguments

  my ($name) = @_;

  #--- start transaction

  my $r = database('clandb')->begin_work();
  if(!$r) { return "Failed to start transaction"; }

  try {

  #--- get clan id

    my $plr = plr_info($name);
    die "Failed to get clan id for player '$name' ($plr)\n" if !ref($plr);
    my $clan_id = $plr->{'clan_id'};
    if(!$clan_id) { die "User not member of any clan already\n"; }

  #--- leave clan

    $r = database('clandb')->do(
      'UPDATE players SET clans_i = NULL, clan_admin = 0 WHERE name = ?',
      undef, $name
    );
    if($r != 1) { die "Failed to leave clan\n"; }

  #--- drop all your invitations

    $r = database('clandb')->do(
      'DELETE FROM invites WHERE invitor = ?', undef, $plr->{'players_i'}
    );
    if(!$r) {
      die sprintf("Failed to delete invitations (%s)\n", $r);
    }

  #--- delete the clan if no more users remain

    my $sth = database('clandb')->prepare(
      'SELECT count(*) FROM players WHERE clans_i = ?'
    );
    $r = $sth->execute($clan_id);
    die "Failed to query database\n" if !$r;
    my ($remaining_cnt) = $sth->fetchrow_array();
    if($remaining_cnt == 0) {
      $r = database('clandb')->do(
        'DELETE FROM clans WHERE clans_i = ?',
        undef, $clan_id
      );
      die "Failed to remove empty clan\n" if !$r;
    }

  } catch {
    chomp($@);
    database('clandb')->rollback();
    return "Could not leave the clan ($@)";
  }

  #--- commit transaction

  database('clandb')->commit();
  return [];
}


#=============================================================================
# Return players based on partial match anchored at start and optionally
# excluding players from specified clan. Search is performed on both clandb
# and dglusers database and results are merged.
#=============================================================================

sub plr_search
{
  #--- arguments

  my (
    $search,            # search string
    $exclude_clan_id    # exclude players with clan_id
  ) = @_;

  #--- query clandb database

  my @args = ( "$search%" );
  my $qry =
    'SELECT p.name AS name, c.name AS clan, players_i, clans_i, clan_admin '
    . 'FROM players p LEFT JOIN clans c USING (clans_i)'
    . q{ WHERE p.name LIKE ?};
  if($exclude_clan_id) {
    $qry .= ' AND ( p.clans_i <> ? OR p.clans_i IS NULL )';
    push(@args, $exclude_clan_id);
  }
  my $sth = database('clandb')->prepare($qry);
  if(!ref($sth)) { return "Failed to get database handle"; }
  my $r = $sth->execute(@args);
  if(!$r) {
    return sprintf "Failed to query database (%s)", $sth->errstr();
  }
  my $result_clandb = $sth->fetchall_hashref('name');

  for my $plr (keys %$result_clandb) {
    $result_clandb->{$plr}{'_clandb'} = 1;
    $result_clandb->{$plr}{'_dgl'} = 0;
  }

  #--- query dglusers database

  $qry = 'SELECT username AS name FROM dglusers WHERE name LIKE ?';
  $sth = database('dgl')->prepare($qry);
  if(!ref($sth)) { return "Failed to get database handle"; }
  $r = $sth->execute($args[0]);
  if(!$r) {
    return sprintf "Failed to query database (%s)", $sth->errstr();
  }
  my $result_dgl = $sth->fetchall_hashref('name');

  #--- merge results

  my %result = %$result_clandb;
  for my $plr (keys %$result_dgl) {
    $result{$plr}{'_dgl'} = 1;
  }

  return \%result;
}


#=============================================================================
# Invite a player to a clan.
#=============================================================================

sub plr_invite
{
  #--- arguments

  my (
    $name,        # player doing the inviting
    $invitee      # player being invited
  ) = @_;

  #--- block issuing invites if clan freeze is on

  if(setting('app')->{'freeze'}) {
    return 'Clan freeze in effect, you cannot issue invites';
  }

  #--- get information about invitor

  my $plr_invitor = plr_info($name);
  if(!ref($plr_invitor)) { return $plr_invitor; }

  #--- only admins can invite

  if(!$plr_invitor->{'clan_admin'}) {
    return "Only clan admins can invite players";
  }

  #--- are there available slots?

  try {
    if(!can_invite($plr_invitor->{'clan_name'})) {
      return 'No more invitations can be given without overpromising';
    }
  } catch {
    return "Failed to check available invitation slots ($@)";
  }

  #--- get information about invitee, if invitee doesn't exist in clandb
  #--- but exists in dgamelaunch db, then create their account in clandb

  my $plr_invitee = plr_info($invitee);
  if($plr_invitee eq 'Player not found') {
    my $r = plr_new_dgl($invitee);
    if(!ref($r)) { return $r; }
    $plr_invitee = plr_info($invitee);
  } elsif (!ref($plr_invitee)) {
    return $plr_invitee;
  }

  #--- sanity checks

  if(
    exists $plr_invitee->{'clan_id'}
    && defined $plr_invitee->{'clan_id'}
    && $plr_invitor->{'clan_id'} == $plr_invitee->{'clan_id'}
  ) {
    return "The invited player already is member of the clan";
  };

  #--- redundant invitation

  my $sth = database('clandb')->prepare(
    'SELECT count(*) FROM invites WHERE invitor = ? AND invitee = ?'
  );
  if(!ref($sth)) { return "Failed to get database handle"; }
  my $r = $sth->execute(
    $plr_invitor->{'players_i'}, $plr_invitee->{'players_i'}
  );
  if(!$r) { return "Failed to query database"; }
  my ($cnt) = $sth->fetchrow_array();
  if($cnt == 1) { return "The player already has invitation waiting"; }

  #--- create new invitation

  $r = database('clandb')->do(
    'INSERT INTO invites ( invitor, invitee ) VALUES ( ?, ? )', undef,
    $plr_invitor->{'players_i'}, $plr_invitee->{'players_i'}
  );
  if(!$r) { return "Failed to create an invitation"; }

  return [];
}


#=============================================================================
# For player supplied as the argument, return two lists references from
# hashref with two keys.  The 'invites' key references list of pending
# invites for the player as [ <invitor>, <clan> ]; the 'invitees' key
# references list of invitation the player has issued as [ <invitee> ].
#=============================================================================

sub plr_get_invitations
{
  #--- arguments

  my ($name) = @_;

  #--- get player info

  my $plr = plr_info($name);
  if(!ref($plr)) { return "Could not get player info ($plr)"; }

  #--- list of invites the player has issued

  my @my_invitees;
  my $sth = database('clandb')->prepare(
    'SELECT name '
    . 'FROM invites LEFT JOIN players ON players_i = invitee '
    . 'WHERE invitor = ?'
  );
  if(!ref($sth)) { return "Failed to get database handle"; }
  my $r = $sth->execute($plr->{'players_i'});
  while(my ($invitee) = $sth->fetchrow_array()) {
    push(@my_invitees, $invitee);
  }

  #--- list of invites waiting for the player

  my @my_invites;
  $sth = database('clandb')->prepare(
    'SELECT p.name AS player, c.name AS clan '
    . 'FROM invites i LEFT JOIN players p ON players_i = invitor '
    . 'LEFT JOIN clans c USING ( clans_i ) '
    . 'WHERE invitee = ?'
  );
  if(!ref($sth)) { return "Failed to get database handle"; }
  $r = $sth->execute($plr->{'players_i'});
  while(my @invite = $sth->fetchrow_array()) {
    push(@my_invites, \@invite);
  }

  return { invites => \@my_invites, invitees => \@my_invitees };
}


#=============================================================================
# Revoke (= remove) invitation(s) player has given to another player. If the
# invitee player is not specified, all invitations by the player are revoked.
# On error, error message is returned; on success hashref is returned with
# key 'deleted' which gives number of entries that were actually deleted.
#=============================================================================

sub plr_revoke_invitations
{
  #--- arguments

  my ($name, $invitee) = @_;

  #--- get info on both players

  my $plr_info = plr_info($name);
  if(!ref($plr_info)) { return $plr_info; }
  my $invitee_info;
  if($invitee) {
    $invitee_info = plr_info($invitee);
    if(!ref($invitee_info)) { return $invitee_info; }
  }

  #--- delete the invites

  my @args = $plr_info->{'players_i'};
  my $qry = 'DELETE FROM invites WHERE invitor = ?';
  if($invitee) {
    $qry .= ' AND invitee = ?';
    push(@args, $invitee_info->{'players_i'});
  }
  my $r = database('clandb')->do($qry, undef, @args);
  if(!$r) {
    return
      sprintf "Failed to delete the invitation() (%s)", database('clandb')->errstr();
  }

  #--- finish successfully

  return { deleted => $r };
}

#=============================================================================
# Clan-centric invitations revocation. Revokes all invitations to a clan for
# a given invitee (if specified) or all invitations (if invitee not
# specified). Note, that this function does not check any authorizations --
# that must be done by the caller.
#=============================================================================

sub clan_revoke_invitations
{
  #--- arguments

  my ($clan, $invitee) = @_;

  #--- drop invitations

  my $qry =
    'DELETE FROM invites WHERE rowid IN ( '
    . 'SELECT invites.rowid FROM invites '
    . 'LEFT JOIN players p1 ON invitor = p1.players_i '
    . 'LEFT JOIN players p2 ON invitee = p2.players_i '
    . 'LEFT JOIN clans USING (clans_i) '
    . 'WHERE clans.name = ?';
  my @arg = ($clan);
  if($invitee) {
    $qry .= ' AND p2.name = ?';
    push(@arg, $invitee);
  }
  $qry .= ')';
  my $r = database('clandb')->do($qry, undef, @arg);
  if(!$r) {
    return sprintf 'Failed to drop invitations (%s)', database('clandb')->errstr();
  }

  #--- finish successfully

  return { deleted => $r };
}


#=============================================================================
# Function declines invitation the player has pending from another. Only the
# matching invitation is removed. Invitations from the other players for the
# same clan will not be deleted. If invitor is omitted, all pending
# invitations are declined.
#=============================================================================

sub plr_decline_invitation
{
  #--- arguments

  my ($name, $invitor) = @_;

  #--- get info on both players

  my $plr_info = plr_info($name);
  if(!ref($plr_info)) { return $plr_info; }
  my $invitor_info;
  if($invitor) {
    $invitor_info = plr_info($invitor);
    if(!ref($invitor_info)) { return $invitor_info; }
  }

  #--- delete the invite

  my @args = ( $plr_info->{'players_i'} );
  my $qry = 'DELETE FROM invites WHERE invitee = ?';
  if($invitor) {
    $qry .= ' AND invitor = ?';
    push(@args, $invitor_info->{'players_i'});
  }
  my $r = database('clandb')->do($qry, undef, @args);
  if(!$r) {
    return
      sprintf "Failed to delete the invitation(s) (%s)", database('clandb')->errstr();
  }

  #--- finish successfully

  return { deleted => $r };
}


#=============================================================================
# Function that accepts pending invitation from an invitor. This function
# also drops all pending invitiation for the same clan as the invitor's clan.
#=============================================================================

sub plr_accept_invitation
{
  #--- arguments

  my ($name, $invitor) = @_;

  #--- block issuing invites if clan freeze is on

  if(setting('app')->{'freeze'}) {
    return 'Clan freeze in effect, you cannot accept invites';
  }

  #--- get info on both players

  my $plr_info = plr_info($name, 1);
  if(!ref($plr_info)) { return $plr_info; }
  my $invitor_info;
  if($invitor) {
    $invitor_info = plr_info($invitor);
    if(!ref($invitor_info)) { return $invitor_info; }
  }

  #--- sole admins cannot leave, they must pass the admin privilege first

  if($plr_info->{'admin'} && $plr_info->{'sole_admin'}) {
    return 'Sole admins cannot leave';
  }

  #--- get invitations list

  my $invitations = plr_get_invitations($name);

  #--- begin transaction

  my $r = database('clandb')->begin_work();
  if(!$r) { return "Could not start database transaction"; }

  try {

  #--- update player record to include clan id

    my $r = database('clandb')->do(
      'UPDATE players SET clans_i = ? WHERE players_i = ?', undef,
      $invitor_info->{'clan_id'}, $plr_info->{'players_i'}
    );
    if(!$r) { die "Failed to update database ($r)\n"; }

  #--- find all invitations for the same clan

    my $sth = database('clandb')->prepare(
      'SELECT invitor, invitee ' .
      'FROM invites ' .
      'LEFT JOIN players ON invitor = players_i ' .
      'LEFT JOIN clans USING (clans_i) ' .
      'WHERE invitee = ? AND clans_i = ?'
    );
    if(!ref($sth)) {
      die sprintf("Failed to get query handle (%s)\n", database('clandb')->errstr());
    }
    $r = $sth->execute($plr_info->{'players_i'},$invitor_info->{'clan_id'});
    if(!$r) { die sprint("Failed to query database (%s)\n", $sth->errstr()); }
    my $invites = $sth->fetchall_arrayref();
    if(!$invites) {
      die sprintf "Failed to retrieve database query (%s)\n", $sth->errstr();
    }

  #--- delete all invitations matched in previous step

    for my $row (@$invites) {
      $r = database('clandb')->do(
        'DELETE FROM invites WHERE invitor = ? AND invitee = ?', undef,
        @$row
      );
      if(!$r) {
        die sprintf("Failed to delete invitation (%s)\n", database('clandb')->errstr());
      }
    }

  #--- abort transaction on error

  } catch {
    chomp($@);
    database('clandb')->rollback();
    return "Could not accept clan invitation ($@)";
  }

  #--- commit transaction

  database('clandb')->commit();
  return [];
}


#=============================================================================
#=============================================================================

sub clan_disband
{
  #--- arguments

  my ($name) = @_;

  #--- get player info

  my $plr = plr_info($name);
  if(!ref($plr)) {
    return "Could not get player information ($plr)";
  }
  if(!$plr->{'clan_admin'}) {
    return "Only admins can disband clans";
  }

  #--- begin transaction

  my $r = database('clandb')->begin_work();
  if(!$r) { return "Could not start database transaction"; }

  try {

  #--- delete all invites for the clan

    $r = clan_revoke_invitations($plr->{'clan_name'});
    if(!ref($r)) {
      die "$r\n";
    }

  #--- remove all players and clear their admin flag

    $r = database('clandb')->do(
      'UPDATE players SET clans_i = NULL, clan_admin = 0 WHERE clans_i = ?',
      undef, $plr->{'clan_id'}
    );
    if(!$r) {
      die sprintf(
        "Could not remove players from clan (%s)\n", database('clandb')->errstr()
      );
    }

  #--- delete clan

    $r = database('clandb')->do(
      'DELETE FROM clans WHERE clans_i = ?', undef, $plr->{'clan_id'}
    );

  #--- handle failure

  } catch {
    chomp($@);
    database('clandb')->rollback();
    return "Could not disband clan ($@)";
  }

  #--- commit transaction

  database('clandb')->commit();
  return [];
}


#=============================================================================
# For given clan return number of outstanding invites for distinct players
# (players can be invited multiple times into the same clan).
#=============================================================================

sub distinct_invites
{
  my $clan = shift;

  die 'Internal error (can_invite() requires one argument' if !$clan;

  my $query = <<EOHD;
SELECT COUNT(DISTINCT p2.name) AS invitees
  FROM invites
  LEFT JOIN players p1 ON invitor = p1.players_i
  LEFT JOIN players p2 ON invitee = p2.players_i
  LEFT JOIN clans c USING ( clans_i)
  WHERE c.name = ?;
EOHD

  my $sth = database('clandb')->prepare($query);
  if(!ref($sth)) { die 'Failed to get database handle'; }
  my $r = $sth->execute($clan);
  if(!$r) {
    die sprintf 'Failed to query database (%s)', $sth->errstr();
  }
  my ($num_invites) = $sth->fetchrow_array();

  return $num_invites;
}


#=============================================================================
# Return number of invites clan can give without overcommiting; if no clan
# limits are set, return -1
#=============================================================================

sub can_invite
{
  my $clan = shift;

  die 'Internal error (can_invite() requires one argument)' if !$clan;
  return -1 if !setting('app')->{'clanlimit'};

  my $query = 'SELECT count(*) FROM players JOIN clans USING (clans_i) ' .
              'WHERE clans.name = ?';
  my $sth = database('clandb')->prepare($query);
  if(!ref($sth)) { die 'Failed to get query handle'; }
  my $r = $sth->execute($clan);
  if(!$r) {
    die sprintf 'Failed to query database (%s)', $sth->errstr();
  }
  my ($clan_members) = $sth->fetchrow_array();

  my $num_invites = distinct_invites($clan);
  my $can_invite = setting('app')->{'clanlimit'} - $clan_members - $num_invites;
  if($can_invite < 0) { $can_invite = 0; }

  return $can_invite;
}


#=============================================================================
# Get clan info listing for specified clan or all clans. The result is
# returned as hashref of following structure:
#
# HASHREF = {
#             CLAN_NAME => {
#               players => {
#                 PLAYER_NAME => {
#                   clan, clans_i, player, players_i, clan_admin
#                 },
#                 ...
#               },
#               invites => [
#                 { invitor, invitee },
#                 ...
#               ]
#             },
#             ...
#           }
#
#=============================================================================

sub clan_get_info
{
  #--- arguments

  my ($clan) = @_;

  #--- query the database for clans/players

  my $sth = database('clandb')->prepare(
    'SELECT c.name AS clan, clans_i, p.name AS player, players_i, clan_admin ' .
    'FROM clans c LEFT JOIN players p USING (clans_i)' .
    ($clan ? ' WHERE c.name = ?' : '')
  );
  if(!ref($sth)) { return "Couldn't get query handle\n"; }
  my $r = $sth->execute($clan ? ($clan) : ());
  if(!$r) {
    return sprintf("Failed to query database (%s)\n", $sth->errstr());
  }

  my %re;
  while(my $row = $sth->fetchrow_hashref()) {
    $re
      {$row->{'clan'}}
      {'players'}
      {$row->{'player'}}
    = $row;
  }

  #--- query the database for outstanding invitations

  $sth = database('clandb')->prepare(
    'SELECT p1.name AS invitor, p2.name AS invitee, c.name AS clan '
    . 'FROM invites LEFT JOIN players p1 ON invitor = p1.players_i '
    . 'LEFT JOIN players p2 ON invitee = p2.players_i '
    . 'LEFT JOIN clans c USING ( clans_i)'
    . ($clan ? ' WHERE c.name = ?' : '')
    . ' ORDER BY creat_when'
  );
  if(!ref($sth)) {
    return sprintf "Could not get query handle (%s)\n", database('clandb')->errstr();
  }
  $r = $sth->execute($clan ? ($clan) : ());
  if(!$r) {
    return sprintf("Failed to query database (%s)\n", $sth->errstr());
  }

  while(my $row = $sth->fetchrow_hashref()) {
    push(
      @{$re{$row->{'clan'}}{'invites'}},
      { 'invitor' => $row->{'invitor'}, 'invitee' => $row->{'invitee'} }
    );
  }

  #--- flag to signal whether new invites can be issued for this clan

  if($clan) {
    try { $re{$clan}{'caninvite'} = can_invite($clan); } catch {}
  }

  return \%re;
}


#=============================================================================
#==================   _  =====================================================
#===  _ __ ___  _   _| |_ ___  ___   =========================================
#=== | '__/ _ \| | | | __/ _ \/ __|  =========================================
#=== | | | (_) | |_| | ||  __/\__ \  =========================================
#=== |_|  \___/ \__,_|\__\___||___/  =========================================
#===                                ==========================================
#=============================================================================

# following URLs are implemented:
#
# GET  /                  ... front page
# GET  /logout            ... log out
# GET  /leave_clan        ... leave current clan
# any  /create_clan       ... starts new clan with the player as admin
# any  /invite            ... display player invitation page
# GET  /invite/<invitee>  ... invite a player to a clan
# GET  /revoke/<invitee>  ... revoke an existing invitation
# GET  /revoke            ... revoke all issued invitations
# GET  /clan_revoke       ... revoke all clan invitations
# GET  /clan_revoke/<plr> ... revoke all clan invitations of a player
# GET  /decline/<invitor> ... decline a pending invitation
# GET  /decline           ... decline all pending invitations
# GET  /accept/<invitor>  ... accept a pending invitation
# GET  /make_admin/<plr>  ... give admin rights to another clan member
# GET  /resign_admin      ... resign admin rights
# GET  /clan/<clan>       ... clan info page
# GET  /kick/<plr>        ... kick player out of a clan
# GET  /disband           ... disband clan


#=============================================================================
#=== front page ==============================================================
#=============================================================================

any [ 'get', 'post' ] => '/' => sub {

  my %data;

  #--- attempt to get login name from session cookie

  my $logname = session('logname');

  #---------------------------------------------------------------------------

  try {

  #--- NOT LOGGED IN - request is GET

    if(!$logname && request->is_get) {
      return template 'index', {
        'title' => 'TNNT Login'
      };
    }

  #--- NOT LOGGED IN - request is POST

    if(!$logname) {
      my $name = body_parameters->get('reg_name');
      my $pw_web = body_parameters->get('reg_pwd1');

  #--- authenticate against dgamelaunch user database

      my $r = plr_authenticate($name, $pw_web);
      if(!ref($r)) {
        $data{'errmsg'} = $r;
        die "Cannot login ($r)\n";
      } else {
        $name = $$r;
      }

  #--- if this is a first login, create the user

      $r = plr_new($name);
      if(!ref($r)) {
        $data{'errmsg'} = $r;
        die "Could not create new user ($r)\n";
      }

  #--- create session

      $logname = $name;
      session logname => $name;

    }

  #--- now get info about the player

    my $plr = plr_info($logname, 1);
    if(ref($plr)) {
      $data{'clan'} = $plr->{'clan_name'};
      $data{'admin'} = $plr->{'clan_admin'};
      $data{'sole_admin'} = $plr->{'sole_admin'};
      $data{'can_leave'} = $plr->{'can_leave'};
    }

    my $invinfo = plr_get_invitations($logname);
    $data{'invinfo'} = $invinfo;

    if($data{'clan'}) {
      my $clan_info = clan_get_info($data{'clan'});
      if(ref($plr)) {
        $data{'clan_info'} = $clan_info->{$data{'clan'}};
      }
    }

    $data{'logname'} = $logname;
    $data{'title'} = 'TNNT Clan Management';
    $data{'freeze'} = setting('app')->{'freeze'};
    $data{'clanlimit'} = setting('app')->{'clanlimit'};

    return template 'index', \%data;

  #---------------------------------------------------------------------------

  }

  #--- handle errors

  catch {
    template 'index', {
      title => 'TNNT Login Failed',
      errmsg => "$@"
    };
  }
};


#=============================================================================
#=== logout ==================================================================
#=============================================================================

get '/logout' => sub {
  app->destroy_session();
  redirect '/tnnt/clanmgmt/';
};

#=============================================================================
#=== player clan leave =======================================================
#=============================================================================

get '/leave_clan' => sub {

  my $name = session('logname');
  if($name) {
    plr_leave_clan($name);
    # FIXME error not handled
  }
  redirect '/';
};


#=============================================================================
#=== player clan create ======================================================
#=============================================================================

any '/create_clan' => sub {

  my $data = {
    title => 'TNNT / Start a new clan'
  };

  #--- get login name (if logged in)

  my $name = session('logname');
  if(!$name) { redirect '/'; }
  $data->{'logname'} = $name if $name;

  #--- if this is POST request, process the submitted data

  if(request->is_post) {

  #--- get clan name, make sure it is sensible (FIXME: more checks needed)

    my $clan_name = body_parameters->get('clan_name');
    if(!$clan_name) {
      $data->{'errmsg'} = 'Please fill in clan name'
    }

  #--- create a new clan

    else {
      my $r = plr_start_clan($name, $clan_name);
      if(!ref($r)) {
        $data->{'errmsg'} = $r;
      }
    }

  }

  #--- finish

  if($data->{'errmsg'} || request->is_get) {
    return template 'clan_create', $data;
  } else {
    redirect '/';
  }

};


#=============================================================================
#=== invite ==================================================================
#=============================================================================

any '/invite' => sub {

  my $data = {
    title => 'TNNT / Invite a player'
  };

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) {
    redirect '/';
  }

  $data->{'logname'} = $name;

  #--- only for clan admins

  my $plr = plr_info($name);
  if(!ref($plr)) { return "Failed to get player info"; }
  if(!$plr->{'clan_admin'}) { return "Only clan admins can invite players"; }
  $data->{'clan'} = $plr->{'clan_name'};

  #--- process POST data

  if(request->is_post) {
    my $invite_search = body_parameters->get('invite_name');
    my $plrlist = plr_search($invite_search, $plr->{'clan_id'});
    if(!ref($plrlist)) {
      return "Couldn't get list of players ($plrlist)";
    }
    $data->{'plrlist'} = [ sort keys %$plrlist ];
  }

  #--- serve a form

  template 'invite', $data;

};

get '/invite/:invitee' => sub {

  my $data = {
    title => 'TNNT / Invite a player'
  };

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- only for clan admins

  my $plr = plr_info($name);
  if(!ref($plr)) { return "Failed to get player info"; }
  if(!$plr->{'clan_admin'}) { return "Only clan admins can invite players"; }

  #--- create invitiation

  my $invitee = route_parameters->get('invitee');
  my $r = plr_invite($name, $invitee);
  if(!ref($r)) {
    return $r;
  } else {
    redirect '/';
  }
};


#=============================================================================
#=== revoke invitations ======================================================
#=============================================================================

get '/revoke/:player' => sub {

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- perform revocation

  my $invitee = route_parameters->get('player');
  my $r = plr_revoke_invitations($name, $invitee);
  if(!ref($r)) { return $r; }

  redirect '/';

};

get '/revoke' => sub {

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- perform revocation

  my $r = plr_revoke_invitations($name);
  if(!ref($r)) { return $r; }

  redirect '/';

};


#=============================================================================
#=== decline invitations =====================================================
#=============================================================================

get '/decline/:player' => sub {

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- perform decline

  my $invitor = route_parameters->get('player');
  my $r = plr_decline_invitation($name, $invitor);
  if(!ref($r)) { return $r; }

  redirect '/';

};

get '/decline' => sub {

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- perform decline

  my $invitor = route_parameters->get('player');
  my $r = plr_decline_invitation($name);
  if(!ref($r)) { return $r; }

  redirect '/';

};


#=============================================================================
#=== accept invitation =======================================================
#=============================================================================

get '/accept/:player' => sub {

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- accept invitation

  my $invitor = route_parameters->get('player');
  my $r = plr_accept_invitation($name, $invitor);
  if(!ref($r)) { return $r; }

  redirect '/';
};


#=============================================================================
#=== give admin rights to a player ===========================================
#=============================================================================

get '/make_admin/:player' => sub {

  my $grantee = route_parameters->get('player');
  my $rt = query_parameters->get('rt');

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- only for clan admins

  my $plr = plr_info($name);
  if(!ref($plr)) { return "Couldn't find player '$name'"; }
  if(!$plr->{'clan_id'} || !$plr->{'clan_admin'}) {
    return "Only clan admins can give admin rights";
  }
  my $clan = $plr->{'clan_name'};

  #--- get clan information about the clan

  my $clan_info = clan_get_info($clan);
  if(!ref($clan_info)) { return "Failed to get clan info ($clan_info)"; }
  if(!exists $clan_info->{$clan}) {
    return "Fatal error while trying to get clan info";
  }

  #--- get info about the grantee

  my $grantee_info = plr_info($grantee);
  if(!ref($grantee_info)) {
    return "Failed to get player info on $grantee ($grantee_info)";
  }
  if($grantee_info->{'clan_admin'}) {
    return "Player $grantee already is admin";
  }

  #--- grantor and grantee clans must match

  if($plr->{'clan_id'} != $grantee_info->{'clan_id'}) {
    return "You cannot grant admin rights to player not in your clan";
  }

  #--- give admin rights

  my $r = database('clandb')->do(
    'UPDATE players SET clan_admin = 1 WHERE players_i = ?', undef,
    $grantee_info->{'players_i'}
  );
  if(!$r) {
    return "Failed to grant admin rights to $grantee ($r)";
  }

  #--- finish

  redirect '/';

};


#=============================================================================
#=== give admin rights to a player ===========================================
#=============================================================================

get '/resign_admin' => sub {

  #--- return page

  my $rt = query_parameters->get('rt');

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- only for clan admins

  my $plr = plr_info($name, 1);
  if(!ref($plr)) { return "Couldn't find player '$name'"; }
  if(!$plr->{'clan_id'} || !$plr->{'clan_admin'}) {
    return "Only clan admins can give admin rights";
  }
  my $clan = $plr->{'clan_name'};

  #--- the only admin on the team is blocked from resigning

  if($plr->{'sole_admin'}) {
    return "Sole admin for the team cannot resign";
  }

  #--- start database transaction

  my $r = database('clandb')->begin_work();
  if(!$r) { return "Could not start database transaction"; }

  try {

  #--- perform resignation

    $r = database('clandb')->do(
      'UPDATE players SET clan_admin = 0 WHERE players_i = ?', undef,
      $plr->{'players_i'}
    );
    if(!$r) {
      die "Failed to remove admin rights for $name ($r)\n";
    }

  #--- drop all given invites

    $r = database('clandb')->do(
      'DELETE FROM invites WHERE invitor = ?', undef,
      $plr->{'players_i'}
    );
    if(!$r) {
      die "Failed to remove invites upon resignation ($r)\n";
    }

  #--- abort transaction

  } catch {
    database('clandb')->rollback();
    return "Failed to resign admin role ($@)";
  }

  #--- finish successfully

  database('clandb')->commit();
  redirect '/';

};


#=============================================================================
#=== list a clan membership ==================================================
#=============================================================================

get '/clan/:clan' => sub {

  #--- gather info, note, that this page doesn't require user to be logged in

  my $name = session('logname');
  my $clan = route_parameters->get('clan');

  #--- response hash

  my %response;

  #--- load player info

  my ($plr_info, $clan_info);

  if($name) {
    $plr_info = plr_info($name, 1);
    if(!ref($plr_info)) {
      return "Failed to get info on user $name ($plr_info)";
    }
    $response{'name'} = $name;
    $response{'admin'} = $plr_info->{'clan_admin'};
  }

  #--- load clan info

  $clan_info = clan_get_info($clan);
  if(!ref($clan_info)) {
    return "Failed to get info on clan $clan ($clan_info)";
  }
  $response{'title'} = "TNNT / Clan $clan";
  $response{'clan'}{'name'} = $clan;

  #--- list of all players

  my $players_all = $response{'clan'}{'players'} = [
    sort keys %{$clan_info->{$clan}{'players'}}
  ];

  #--- list of admin players

  my $players_admin = $response{'clan'}{'admins'} = [
    grep {
      $clan_info->{$clan}{'players'}{$_}{'clan_admin'};
    } sort keys %{$clan_info->{$clan}{'players'}}
  ];

  #--- list of regular (non-admin) players

  my $players_reg = $response{'clan'}{'regulars'} = [
    grep {
      !$clan_info->{$clan}{'players'}{$_}{'clan_admin'};
    } sort keys %{$clan_info->{$clan}{'players'}}
  ];

  #--- attach "actions" to each players

  $response{'actions'} = {};
  if($name) {
    for my $player (@$players_all) {

      # kick, give admin
      if(
        $response{'admin'}
        && grep { $_ eq $player } @$players_reg
      ) {
        push(@{$response{'actions'}{$player}},
          [ "/kick/$player", "Kick" ],
          [ "/make_admin/$player", "Make admin" ]
        );
      }

      # resign admin
      if(
        $response{'admin'}
        && !$plr_info->{'sole_admin'}
        && $player eq $name
      ) {
        push(@{$response{'actions'}{$player}},
          [ '/resign_admin', 'Resign admin' ]
        );
      }

    }
  }

  #--- outstanding invites

  $response{'clan'}{'invites'} = $clan_info->{$clan}{'invites'};

  #--- finish

  template 'clan', \%response;

};


#=============================================================================
#=== kick player out of a clan ===============================================
#=============================================================================

get '/kick/:player' => sub {

  #--- get parameters

  my $target = route_parameters->get('player');
  my $rt = query_parameters->get('rt');

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- only for clan admins

  my $plr = plr_info($name);
  if(!ref($plr)) { return "Couldn't find player '$name'"; }
  if(!$plr->{'clan_id'} || !$plr->{'clan_admin'}) {
    return "Only clan admins can kick players";
  }
  my $clan = $plr->{'clan_name'};

  #--- get information about the player to be kicked

  my $target_info = plr_info($target);
  if(!ref($target_info)) {
    return 'Cannot get info on player to be kicked';
  }

  #--- admin can only kick players in the same clan

  if($plr->{'clan_id'} != $target_info->{'clan_id'}) {
    return 'You cannot kick player not in your clan';
  }

  #--- kick player

  my $r = database('clandb')->do(
    'UPDATE players SET clans_i = NULL, clan_admin = 0 WHERE players_i = ?',
    undef, $target_info->{'players_i'}
  );
  if(!$r) {
    return sprintf(
      'Failed to kick player %s (%s)', $target, database('clandb')->errstr()
    );
  }

  #--- finish

  redirect '/';
};


#=============================================================================
# Clan-centric invites revocation
#=============================================================================

get '/clan_revoke' => sub {

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- only for clan admins

  my $plr = plr_info($name);
  if(!ref($plr)) { return "Couldn't find player '$name'"; }
  if(!$plr->{'clan_id'} || !$plr->{'clan_admin'}) {
    return "Only clan admins can kick players";
  }
  my $clan = $plr->{'clan_name'};

  #--- perform revocation

  my $r = clan_revoke_invitations($clan);
  if(!ref($r)) {
    return $r;
  }

  #--- finish

  redirect '/';

};

get '/clan_revoke/:player' => sub {

  #--- get parameters

  my $player = route_parameters->get('player');

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- only for clan admins

  my $plr = plr_info($name);
  if(!ref($plr)) { return "Could not find player '$name' ($plr)"; }
  if(!$plr->{'clan_id'} || !$plr->{'clan_admin'}) {
    return "Only clan admins can kick players";
  }
  my $clan = $plr->{'clan_name'};

  #--- perform revocation

  my $r = clan_revoke_invitations($clan, $player);
  if(!ref($r)) {
    return $r;
  }

  #--- finish

  redirect '/';

};


#=============================================================================
# Disband the player's clan
#=============================================================================

get '/disband' => sub {

  #--- only for logged in users

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- disband clan

  my $r = clan_disband($name);
  if(!ref($r)) {
    return $r;
  }

  #--- finish

  redirect '/';
};



true;
