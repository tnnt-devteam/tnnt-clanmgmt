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


true;
