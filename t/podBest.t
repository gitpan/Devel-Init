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
            Ok( 1, 1, "Default init ran" );
        },
        'only_default',
    );
}


BEGIN {
    $INC{'DBI.pm'}= $INC{'Local/Config.pm'}= __FILE__;

    require Exporter;
    @Local::Config::EXPORT_OK= 'GetDbConnectParams';
    *Local::Config::import= \&Exporter::import;
    sub Local::Config::GetDbConnectParams {
        return( 'DBI:testDB:somehost', 'user', 'pass', { opt => 1 } );
    }

    sub DBI::connect {
        my( $c, $db, $u, $pw, $opt )= @_;
        ++$::DBIconnect;
        Ok( 'user', $u, 'Correct user used' );
    }
}

{

#for Best

    # A "best practice"!

    package Some::Module;
    use Devel::Init     qw< :Init InitBlock >;
    use Local::Config   qw< GetDbConnectParams >;
    use DBI             ();

    BEGIN {
        my $dbh;
        my $db_name= $ENV{'DB_NAME'} || 'some_db';

        sub getDBH :Init(not_prefork) {
#pause
            ++$::getDBH;
#resume
            return $dbh ||= InitBlock {
                DBI->connect(
                    GetDbConnectParams( $db_name ),
                )
                    or  die "Failed to connect to $db_name: $DBI::errstr\n";
            };
        }
    }

#end
    $DBI::errstr= '' if 0;  # Prevent warning

    BEGIN {
        ::Ok( undef, $::DBIconnect, 'DBI::connect not called yet' );
        ::Ok( undef, $::getDBH, 'getDBH not called yet' );
    }

    ::Ok( 1, $::DBIconnect, 'DBI::connect called once' );
    ::Ok( 1, $::getDBH, 'getDBH called once' );

}
