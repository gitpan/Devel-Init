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


{
    package Safer;
    BEGIN { $INC{'DBI.pm'}= __FILE__ }
    sub DBI::connect {
        my( $c, $db, $u, $pw, $opt )= @_;
        ++$::DBIconnect;
        ::Ok( 'dnelson', $u, 'Correct user used' );
    }

#for Safer

    use Devel::Init qw< :Init InitBlock >;

    our( $Connect, $DB_user, $DB_pass );
    BEGIN {
        $Connect= 'DBI:pick:dick@trw:1965';
        $DB_user= 'dnelson';
        $DB_pass= 'convair3537';
    }

    BEGIN {
        my $dbh;

        sub getDBH :Init(not_prefork) {
#pause
            ++$::getDBH;
#resume
            return $dbh ||= InitBlock {
                DBI->connect(
                    $Connect, $DB_user, $DB_pass,
                    { RaiseError => 1, PrintError => 0 },
                ),
            };
        }
    }

#end

    BEGIN {
        ::Ok( undef, $::DBIconnect, 'DBI::connect not called yet' );
        ::Ok( undef, $::getDBH, 'getDBH not called yet' );
    }

    ::Ok( 1, $::DBIconnect, 'DBI::connect called once' );
    ::Ok( 1, $::getDBH, 'getDBH called once' );

}
