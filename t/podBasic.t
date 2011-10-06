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
            ++$::default;
        },
        'only_default',
    );
}


{

#for Basic

    package Some::Module;
    use Devel::Init qw< :Init >;

    BEGIN {
        my $single;

        sub get_singleton :Init {
#pause
            ++$::get_singleton;
#resume
            return $single ||= InitBlock {
##                ... # figure out $initialized_value
#pause
                my $initialized_value= ++$::init_block;
#resume
                return $initialized_value;
            };
        }
    }

    sub some_sub {
##        ... get_singleton() ...
#pause
        get_singleton();
#resume
    }

#end

    BEGIN {
        ::Ok( undef, $::default, "Default init not run yet" );
        ::Ok( undef, $::get_singleton, 'get_singleton not called yet' );
        ::Ok( undef, $::init_block, 'InitBlock not called yet' );
    }

    ::Ok( 1, $::default, "Default init ran" );
    ::Ok( 1, $::get_singleton, 'get_singleton called once' );
    ::Ok( 1, $::init_block, 'InitBlock called once' );

}
