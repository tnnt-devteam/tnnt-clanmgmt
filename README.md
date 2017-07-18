# /DEV/NULL/NETHACK WEBSITE REIMPLEMENTATION

Reimplementation od /dev/null/nethack tournament's central website. **Work in
progress, not yet functional**. This code is written in an attempt to hedge
against Krystal not appearing again to run /dev/null/nethack 2017.

The game server setup was replicated and updated by
[Tangles](https://github.com/NHtangles) and is available on github
[here](https://github.com/NHTangles/devnull-gameserver). The problem is
that the control server code that links the game servers together and
the public facing website was never made public. Therefore if we want to
make sure /dev/null/nethack 2017 happens even in the case Krystal won't
run it as usual we need to rewrite this part.

## ARCHITECTURE

* Perl Dancer framework
* SQLite as backend storage

## INSTALLATION

Upgrade and configure CPAN.pm to bootstrap local::lib

    perl -MCPAN -e 'upgrade CPAN'

Install required Perl modules

    perl -MCPAN -e 'install App::Cmd::Setup'
    perl -MCPAN -e 'install Plack::Middleware::Deflater'
    perl -MCPAN -e 'install DBD::SQLite'
    perl -MCPAN -e 'install Dancer2'
    perl -MCPAN -e 'install Dancer2::Plugin::Database'
    perl -MCPAN -e 'install Dancer2::Plugin::Passphrase'
    perl -MCPAN -e 'install Dancer2::Session::Cookie'

Clone the git repository.

## DEPLOYMENT

For testing, you can fire up the application with Plack, just go into the
Dancer app directory `Devnull-Web` and run:

    plackup -p 5000 bin/app.psgi

Then just point your browser to http://*your_ip*:5000/

Info about production deployment will be filled in later.

## AUTHOR

You can contact me as *Mandevil* on FreeNode.
