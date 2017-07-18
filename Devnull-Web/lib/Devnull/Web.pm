#=============================================================================
# /DEV/NULL/NETHACK TOURNAMENT WEBSITE
# """"""""""""""""""""""""""""""""""""
# (c) 2017 Borek Lupomesky <borek@lupomesky.cz>
#
# Reimplementation if /dev/null/nethack website code to replace the original
# Krystal one. Please read the README for installation and deployment info.
#=============================================================================

package Devnull::Web;
use Dancer2;
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Passphrase;
use Syntax::Keyword::Try;

our $VERSION = '0.1';

#=============================================================================
#=== front page ==============================================================
#=============================================================================

get '/' => sub {
  my $data = { title => 'Devnull Front Page' };
  my $logname = session('logname');
  if($logname) { $data->{'logname'} = $logname; }
  template 'index', $data;
};

#=============================================================================
#=== logout ==================================================================
#=============================================================================

get '/logout' => sub {
  app->destroy_session();
  redirect '/';
};

#=============================================================================
#=== login ===================================================================
#=============================================================================

any '/login' => sub {
  my $data = { title => 'Devnull Log In' };
  my $name = body_parameters->get('reg_name');
  my $pw_web = body_parameters->get('reg_pwd1');

  try {
    if($name && $pw_web) {
      my $sth = database->prepare('SELECT pwd FROM players WHERE name = ?');
      my $r = $sth->execute($name);
      if(!$r) { die "Failed to query database\n"; }
      my ($pw_db) = $sth->fetchrow_array();
      if($pw_db && passphrase($pw_web)->matches($pw_db)) {
        session logname => $name;
        redirect '/';
      } else {
        die "Wrong player name or password\n";
      }
    }
  } catch {
    chomp($data->{'errmsg'} = $@);
  }

  template 'login', $data;
};

#=============================================================================
#=== player registration =====================================================
#=============================================================================

get '/register' => sub {
  template 'register', {
    title => 'Devnull New User Registration'
  };
};

post '/register' => sub {
  my $response = { title => 'Devnull New User Registration' };

  try {
    my $name = body_parameters->get('reg_name');
    my $pw1 = body_parameters->get('reg_pwd1');
    my $pw2 = body_parameters->get('reg_pwd2');

    # one or more inputs not filled in
    if(!$name || !$pw1 || !$pw2) {
      die "Please fill in all three fields\n";
    }

    # non-matching passwords
    if($pw1 ne $pw2) {
      die "The passwords do not match\n";
    }

    # password is too short
    if(length($pw1) < 6) {
      die "Please use longer password (at least 6 characters)\n";
    }

    # player name already exists
    {
      my $sth = database->prepare(
        'SELECT count(*) FROM players WHERE name = ?'
      );
      if(!ref($sth)) { die "Failed to get database handle\n"; }
      my $r = $sth->execute($name);
      if(!$r) { die "Failed to query database\n"; }
      my ($cnt) = $sth->fetchrow_array();
      if($cnt > 0) {
        die "Player '$name' already exists, please choose different name\n";
      }
    }

    # create new player
    {
      my $r = database->do(
        'INSERT INTO players ( name, pwd ) VALUES ( ?, ? )',
        undef, $name, passphrase($pw1)->generate->rfc2307()
      );
      if(!$r) {
        die "Failed to create new player\n";
      } else {
        session logname => $name;
        redirect '/';
      }
    }

  } catch {
    chomp($response->{'errmsg'} = $@);
  }

  return template 'register', $response;
};

#=============================================================================
#=== player admin page =======================================================
#=============================================================================

get '/player' => sub {

  #--- this is only for authenticated users, boot anyone who is not logged in

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- get team information for the user

  my ($clan_name, $clan_admin);
  try {
    my $sth = database->prepare(
      'SELECT c.name, p.clan_admin FROM players p LEFT JOIN clans c '
      . 'USING ( clans_i ) WHERE p.name = ?'
    );
    if(!ref($sth)) { die "Failed to get database handle\n"; }
    my $r = $sth->execute($name);
    if(!$r) { die "Failed to query database\n"; }
    ($clan_name, $clan_admin) = $sth->fetchrow_array();
  } catch {
    return "Database error ($@)";
  }

  template 'player', {
    title => "Devnull Player $name",
    clan => $clan_name,
    admin => $clan_admin,
    logname => $name
  };
};


#=============================================================================
#=== player clan leave =======================================================
#=============================================================================

get '/leave_clan' => sub {

  #--- this is only for authenticated users, boot anyone who is not logged in

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- start transaction

  my $r = database->begin_work();
  if(!$r) {
    return "Failed to start database transaction";
  }

  try {

  #--- get clan id

    my $sth = database->prepare(
      'SELECT clans_i FROM players WHERE name = ?'
    );
    die "Failed to get query handle\n" if !ref($sth);
    my $r = $sth->execute($name);
    die "Failed to query database\n" if !$r;
    my ($clan_id) = $sth->fetchrow_array();
    die "Failed to get clan id for player '$name'\n" if !$clan_id;

  #--- leave clan

    $r = database->do(
      'UPDATE players SET clans_i = NULL, clan_admin = 0 WHERE name = ?',
      undef, $name
    );
    if($r != 1) { die "Failed to leave clan\n"; }

  #--- delete the clan if no more users remain

    $sth = database->prepare(
      'SELECT count(*) FROM players p LEFT JOIN clans c USING (clans_i) '
      . 'WHERE c.name = ?'
    );
    $r = $sth->execute($clan_id);
    die "Failed to query database\n" if !$r;
    my ($remaining_cnt) = $sth->fetchrow_array();
    if($remaining_cnt == 0) {
      $r = database->do(
        'DELETE FROM clans WHERE clans_i = ?',
        undef, $clan_id
      );
      die "Failed to remove empty clan" if !$r;
    }

  #--- abort transaction

  } catch {
    chomp($@);
    database->rollback();
    return "Could not leave the clan ($@)";
  }

  #--- commit transaction

  database->commit();
  redirect '/player';

};

#=============================================================================
#=== player clan create ======================================================
#=============================================================================

get '/create_clan' => sub {

  #--- this is only for authenticated users, boot anyone who is not logged in

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- get the clan name

  template 'clan_create', { title => 'Devnull / Start a new clan' };
};

post '/create_clan' => sub {

  #--- this is only for authenticated users, boot anyone who is not logged in

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

  #--- get clan name, make sure it is sensible (FIXME: more checks needed)

  my $clan_name = body_parameters->get('clan_name');
  if(!$clan_name) {
    return template 'clan_create', {
      title => 'Devnull / Start a new clan',
      errmsg => 'Please fill in clan name'
    };
  }

  #--- start a transaction

  my $r = database->begin_work;
  if(!$r) { return "Failed to start database transaction"; }

  #--- transaction body

  try {

    # create new clan
    $r = database->do(
      'INSERT INTO clans ( name ) VALUES ( ? )',
      undef, $clan_name
    );
    if(!$r) {
      if(database->errstr() =~ /^UNIQUE constraint failed/) {
        die "The clan '$clan_name' already exists, please choose different name\n";
      } else {
        die sprintf("Failed to create a new clan (%s)\n", database->errstr());
      }
    }

    # get the clan's id
    my $sth = database->prepare(
      'SELECT clans_i FROM clans WHERE name = ?'
    );
    if(!ref($sth)) { die "Failed to get db query handle\n"; }
    $r = $sth->execute($clan_name);
    if(!$r) { die "Failed to query database\n"; }
    my ($clans_i) = $sth->fetchrow_array();
    if(!$clans_i) { die "Failed to get new clan id\n"; }

    # make the player member and admin
    $r = database->do(
      'UPDATE players SET clan_admin = 1, clans_i = ? WHERE name = ?',
      undef, $clans_i, $name
    );
    if(!$r) { die "Failed to make user $name a clan admin\n"; }

  } catch {

    chomp($@);
    database->rollback;
    return template 'clan_create', {
      title => 'Devnull / Start a new clan',
      errmsg => $@
    };

  }

  #--- finish the transcation

  database->commit;
  redirect '/player';
};


true;
