#!/usr/bin/perl -w
use strict;
use lib do { local $_= __FILE__; s{(^|[/\\])[^/\\]+$}{$1../inc} or die; $_ };

use MyTest  qw< plan Ok SkipIf Eval Dies >;

BEGIN {
    plan(
        tests => 7,
        # todo => [ 2, 3 ],
    );

    require Devel::Init;
    Ok( 1, 1, 'Load module' );
    Devel::Init::RegisterInit(
        sub {
            warn "# Default init ran despite RunInits imported below";
        },
        'only_default',
    );
}


# Verify the synopsis:

BEGIN { $INC{'Some/Module.pm'}= __FILE__; }
{

#for Synops1

    package Some::Module;

    use Devel::Init qw< :Init InitBlock >;

    BEGIN {
        my $dbh;

        sub getDBH :Init(not_prefork) {
#pause
            ++$::getDBH;
#resume
            return $dbh ||= InitBlock { _connect_to_database() };
        }
    }

    sub readRecords {
        # ...
        my $dbh= getDBH();
        # ...
    }

    # ...

#end

    sub _connect_to_database { return ++$::connectToDB; }
}

Ok( undef, $::connectToDB, 'connectToDB not called yet' );
Ok( 1, Some::Module::readRecords(), 'connectToDB called once when needed' );
Ok( 1, $::getDBH, 'getDBH called once when needed' );

{

#for Synops2

    package main;
    use Devel::Init qw< RunInits >;
    use Some::Module;

    RunInits('prefork');
#pause

    ::Ok( 1, $::getDBH, 'getDBH not run again prefork' );

    sub fork_worker_children {
        my( $code )= @_;
        $code->();
    }
    sub do_work { }

#resume
    fork_worker_children(
        sub {
            RunInits();
            do_work();
        },
    );


#end

    ::Ok( 2, $::getDBH, 'getDBH run again post-fork' );
    ::Ok( 1, $::connectToDB, 'connectToDB not run again post-fork' );

}
