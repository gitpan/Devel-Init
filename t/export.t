#!/usr/bin/perl -w
use strict;
my $FILE;   BEGIN { $FILE= __FILE__; }
use lib do { local $_= $FILE; s{(^|[/\\])[^/\\]+$}{$1../inc} or die; $_ };

use MyTest  qw< plan Ok SkipIf Eval Dies >;

BEGIN {
    plan(
        tests => 8,
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

sub UNIVERSAL::import {
    die "No Devel::Init::import() defined!"
        if  "Devel::Init" eq $_[0];
}

use Devel::Init ':NoDefault';

Ok( undef, $::default, ':NoDefault prevents default init step' );

Eval( <<'EVAL', 'export @Predicates' );
    package One;
    use Devel::Init '@Predicates';
    @Devel::Init::Predicates= qw< One Two >;
    ::Ok( 'One Two', "@Predicates", '@Predicates exported' );
EVAL

Dies( <<'EVAL',
    package Two;
    our @Predicates;
    use Devel::Init '@Predicates';
    @Devel::Init::Predicates= qw< Two Three >;
    ::Ok( 'Two Three', "@Predicates", '@Predicates exported' );
EVAL
    qr/ won't export \@Predicates over existing definition at \Q$FILE\E line /,
    'export @Predicates',
);

Dies(
    "use Devel::Init 'Communism';",
    qr/Devel::Init does not export \(Communism\) at \Q$FILE\E line /,
);
