#!/usr/bin/perl -w
use strict;
use lib do { local $_= __FILE__; s{(^|[/\\])[^/\\]+$}{$1../inc} or die; $_ };

use MyTest  qw< plan Ok SkipIf Eval Dies >;

BEGIN {
    plan(
        tests => 12,
        # todo => [ 2, 3 ],
    );

    require Devel::Init;
    Ok( 1, 1, 'Load module' );
    Devel::Init::RegisterInit(
        sub {
            Ok( 1, 1, "Default init ran" );
        },
        'only_default',
    );
}


{
    $INC{'DBI.pm'}= $INC{'Local/Config.pm'}= __FILE__;
    $ENV{'db_name'}= 'fromEnv';

    sub Local::Config::GetDbConnectParams {
        my( $db )= @_;
        Ok( 'fromEnv', $db, 'Correct DB name used' );
        return( 'DBI:testDB:somehost', 'user', 'pass', { opt => 1 } );
    }

    sub DBI::connect {
        my( $c, $db, $u, $pw, $opt )= @_;
        ++$::DBIconnect;
        Ok( 'user', $u, 'Correct user used' );
    }
}

{

#for RunTime

    # Use this pattern with caution.

    package Some::Module;
    require Devel::Init;
    require Local::Config;
    require DBI;

    {
        my $dbh;
        my $db_name= $ENV{'DB_NAME'} || 'some_db';

        sub getDBH {
#pause
            ++$::getDBH;
#resume
            return $dbh ||= Devel::Init::InitSub( sub {
                DBI->connect(
                    Local::Config::GetDbConnectParams( $db_name ),
                )
                    or  die "Failed to connect to $db_name: $DBI::errstr\n";
            } );
        }
    }
    Devel::Init::RegisterInit( \&getDBH, 'not_prefork' );

#end
    $DBI::errstr= '' if 0;  # Prevent warning

    ::Ok( undef, $::DBIconnect, 'DBI::connect not called yet' );
    ::Ok( undef, $::getDBH, 'getDBH not called yet' );

    Devel::Init::RunInits('prefork');

    ::Ok( undef, $::DBIconnect, 'DBI::connect still not called yet' );
    ::Ok( undef, $::getDBH, 'getDBH still not called yet' );

    Devel::Init::RunInits();

    ::Ok( 1, $::DBIconnect, 'DBI::connect called once' );
    ::Ok( 1, $::getDBH, 'getDBH called once' );

    getDBH();

    ::Ok( 1, $::DBIconnect, 'DBI::connect called only once' );
    ::Ok( 2, $::getDBH, 'getDBH called twice' );

}
