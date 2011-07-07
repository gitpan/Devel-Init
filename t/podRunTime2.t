#!/usr/bin/perl -w
use strict;
use lib do { local $_= __FILE__; s{(^|[/\\])[^/\\]+$}{$1../inc} or die; $_ };

use MyTest  qw< plan Ok SkipIf Eval Dies >;

BEGIN {
    plan(
        tests => 6,
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


Ok( 1, $::default, "Default init already run" );
{

#for RunTime2

    package Some::Module;
    use Devel::Init qw< RegisterInit InitBlock >;

    {
        my $single;

        sub get_singleton {
#pause
            ++$::get_singleton;
#resume
            $single ||= InitBlock {
##                ... # figure out $initialized_value
#pause
                my $initialized_value= ++$::init_block;
#resume
                return $initialized_value;
            };
            return $single;
        }
    }
    RegisterInit( \&get_singleton );

#end

    ::Ok( undef, $::get_singleton, 'get_singleton not called yet' );
    ::Ok( undef, $::init_block, 'InitBlock not called yet' );

    Devel::Init::RunInits();

    ::Ok( 1, $::get_singleton, 'get_singleton called once' );
    ::Ok( 1, $::init_block, 'InitBlock called once' );

}
