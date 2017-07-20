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
#====   __   ============   _   _  ===========================================
#===   / _|_   _ _ __   ___| |_(_) ___  _ __  ___   ==========================
#===  | |_| | | | '_ \ / __| __| |/ _ \| '_ \/ __|  ==========================
#===  |  _| |_| | | | | (__| |_| | (_) | | | \__ \  ==========================
#===  |_|  \__,_|_| |_|\___|\__|_|\___/|_| |_|___/  ==========================
#===                                               ===========================
#=============================================================================

sub plr_authenticate
{
  #--- arguments

  my (
    $name,     # 1. player name
    $pwd       # 2. password
  ) = @_;

  #--- authenticate

  if($name && $pwd) {
    my $sth = database->prepare('SELECT pwd FROM players WHERE name = ?');
    my $r = $sth->execute($name);
    if(!$r) { return "Failed to query database"; }
    my ($pw_db) = $sth->fetchrow_array();
    if($pw_db && passphrase($pwd)->matches($pw_db)) {
      return [];
    } else {
      return "Wrong player name or password";
    }
  }

  #--- invalid arguments

  return "Player name or password not specified";
}


sub plr_register
{
  #--- arguments

  my (
    my $name,
    my $pwd
  ) = @_;

  #--- perform registration

  my $r = database->do(
    'INSERT INTO players ( name, pwd ) VALUES ( ?, ? )',
    undef, $name, passphrase($pwd)->generate->rfc2307()
  );
  if(!$r) {
    my $err = database->errstr();
    if($err =~ /^UNIQUE constraint failed/) {
      return "Player name '$name' already exists, please choose different name";
    } else {
      return "Failed to create new player";
    }
  }

  return [];
}


sub plr_info
{
  #--- arguments

  my ($name) = @_;

  #--- get the info

  my $sth = database->prepare(
    'SELECT c.name AS clan_name, p.clan_admin AS clan_admin, '
    . 'p.clans_i AS clan_id '
    . 'FROM players p LEFT JOIN clans c '
    . 'USING ( clans_i ) WHERE p.name = ?'
  );
  if(!ref($sth)) { return "Failed to get database handle\n"; }
  my $r = $sth->execute($name);
  if(!$r) { return "Failed to query database\n"; }
  $r = $sth->fetchrow_hashref('NAME_lc');
  if(!$r) {
    return "Player not found";
  }

  return $r;
}


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

  #--- start transaction

  my $r = database->begin_work();
  if(!$r) { return 'Failed to start database transaction'; }

  my $clans_i;
  try {

  #--- create new clan

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

  #--- get the clan's id

    my $sth = database->prepare(
      'SELECT clans_i FROM clans WHERE name = ?'
    );
    if(!ref($sth)) { die "Failed to get db query handle\n"; }
    $r = $sth->execute($clan_name);
    if(!$r) { die "Failed to query database\n"; }
    ($clans_i) = $sth->fetchrow_array();
    if(!$clans_i) { die "Failed to get new clan id\n"; }

  #--- make the player member and admin

    $r = database->do(
      'UPDATE players SET clan_admin = 1, clans_i = ? WHERE name = ?',
      undef, $clans_i, $player_name
    );
    if(!$r) { die "Failed to make user $player_name a clan admin\n"; }

  }

  #--- handle failure

  catch {
    chomp($@);
    database->rollback;
    return $@;
  }

  #--- commit transaction

  database->commit();
  return { clan_id => $clans_i };
}


sub plr_leave_clan
{
  #--- arguments

  my ($name) = @_;

  #--- start transaction

  try {

  #--- get clan id

    my $plr = plr_info($name);
    die "Failed to get clan id for player '$name' ($plr)\n" if !ref($plr);
    my $clan_id = $plr->{'clan_id'};
    if(!$clan_id) { die "User not member of any clan already\n"; }

  #--- leave clan

    my $r = database->do(
      'UPDATE players SET clans_i = NULL, clan_admin = 0 WHERE name = ?',
      undef, $name
    );
    if($r != 1) { die "Failed to leave clan\n"; }

  #--- delete the clan if no more users remain

    my $sth = database->prepare(
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

  } catch {
    chomp($@);
    database->rollback();
    return "Could not leave the clan ($@)";
  }

  #--- commit transaction

  database->commit();
  return [];
}


#=============================================================================
#==================   _  =====================================================
#===  _ __ ___  _   _| |_ ___  ___   =========================================
#=== | '__/ _ \| | | | __/ _ \/ __|  =========================================
#=== | | | (_) | |_| | ||  __/\__ \  =========================================
#=== |_|  \___/ \__,_|\__\___||___/  =========================================
#===                                ==========================================
#=============================================================================

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

get '/login' => sub {
  template 'login', {
    title => 'Devnull Log in'
  };
};

post '/login' => sub {
  my $name = body_parameters->get('reg_name');
  my $pw_web = body_parameters->get('reg_pwd1');

  my $r = plr_authenticate($name, $pw_web);
  if(ref($r)) {
    session logname => $name;
    redirect '/';
  }

  template 'login', {
    title => 'Devnull Log in',
    errmsg => "Cannot login: $r"
  };
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

    #--- one or more inputs not filled in

    if(!$name || !$pw1 || !$pw2) {
      die "Please fill in all three fields\n";
    }

    #--- non-matching passwords

    if($pw1 ne $pw2) {
      die "The passwords do not match\n";
    }

    #--- password is too short

    if(length($pw1) < 6) {
      die "Please use longer password (at least 6 characters)\n";
    }

    #--- create new player

    my $r = plr_register($name, $pw1);
    if(ref($r)) {
      session logname => $name;
      redirect '/';
    } else {
      die "Failed to create new player\n";
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

  my $plr = plr_info($name);
  if(!ref($plr)) {
    return $plr;
  }

  template 'player', {
    title => "Devnull Player $name",
    clan => $plr->{'clan_name'},
    admin => $plr->{'clan_admin'},
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

  #--- leave clan

  my $r = plr_leave_clan($name);
  if(!ref($r)) { return $r; }
  redirect '/player';
};


#=============================================================================
#=== player clan create ======================================================
#=============================================================================

any '/create_clan' => sub {

  my $data = {
    title => 'Devnull / Start a new clan'
  };

  #--- this is only for authenticated users, boot anyone who is not logged in

  my $name = session('logname');
  if(!$name) { return "Unauthenticated!"; }

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
        $data->{'errmsg'} = "Failed to start a clan: $r";
      }
    }

  }

  #--- finish

  if($data->{'errmsg'} || request->is_get) {
    return template 'clan_create', $data;
  } else {
    redirect '/player';
  }

};


true;
