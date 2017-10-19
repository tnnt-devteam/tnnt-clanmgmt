# /DEV/NULL/NETHACK TRIBUTE CLAN MANAGEMENT

This code started as an attempt at reimplementation of /dev/null/nethack's
central server code. With the tournament
[retirement](https://twitter.com/devnull_nethack/status/908441635746279424)
by Krystal, this never came to fruition. Instead, this code was coopted
for clan management of the replacement tournament -- /dev/null/nethack
Tribute. The tag 'pre-tribute' marks the last commit before this event.

## ARCHITECTURE

* Perl Dancer framework
* SQLite as backend storage

## INSTALLATION

Upgrade and configure CPAN.pm to bootstrap local::lib

    perl -MCPAN -e 'upgrade CPAN'

Install required Perl modules

    perl -MCPAN -e 'install Syntax::Keyword::Try'
    perl -MCPAN -e 'install App::Cmd::Setup'
    perl -MCPAN -e 'install Plack::Middleware::Deflater'
    perl -MCPAN -e 'install DBD::SQLite'
    perl -MCPAN -e 'install Dancer2'
    perl -MCPAN -e 'install Dancer2::Plugin::Database'
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
