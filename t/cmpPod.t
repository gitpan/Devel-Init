#!/usr/bin/perl -w
use strict;
use lib do { local $_= __FILE__; s{(^|[/\\])[^/\\]+$}{$1../inc} or die; $_ };

use MyTest  qw< plan Ok SkipIf Eval Dies >;

BEGIN {
    plan(
        tests => 10,
        # todo => [ 2, 3 ],
    );

    require Devel::Init;
    Ok( 1, 1, 'Load module' );
}

@ARGV= $INC{'Devel/Init.pm'};
my( %pod, %podline );
my $sect;
while(  <>  ) {
    if(  /^=for test (\w+)\s*$/  ) {
        $sect= $1;
        if(  $pod{$sect}  ) {
            warn "'=for test $sect' appears at lines $podline{$sect} and $.\n";
        }
        $podline{$sect}= $.;
    } elsif(  /^\S/  ) {
        $sect= '';
    } elsif(  $sect  ) {
        $pod{$sect} .= $_;
    }
}

( my $dir= __FILE__ ) =~ s{(^|[/\\])[^/\\]+$}{$1}  or  die;
@ARGV= glob( "$dir/pod*.t" );
my( %test, %file, %line );
my $skip;
while(  <>  ) {
    if(  /^#for (\w+)\s*$/  ) {
        $sect= $1;
        if(  $test{$sect}  ) {
            warn "'#for $sect' appears at $file{$sect} line $line{$sect} ",
                "and at $ARGV line $.\n";
        }
        $skip= 0;
        $file{$sect}= $ARGV;
        $line{$sect}= $.;
    } elsif(  /^#pause\s*$/  ) {
        $skip= 1;
    } elsif(  /^#resume\s*$/  ) {
        $skip= 0;
    } elsif(  /^#end\s*$/  ) {
        $sect= '';
    } elsif(  $sect  &&  ! $skip  ) {
        s/^##//;
        $test{$sect} .= $_;
    }
}

my $tmp= $ENV{TMPDIR} || $ENV{TMP} || $ENV{TEMP} || '/tmp';
for $sect (  keys %pod  ) {
    my( $pod, $podline, $test, $file, $line )= (
        $pod{$sect}, $podline{$sect},
        $test{$sect}, $file{$sect}, $line{$sect},
    );
    delete $test{$sect};
    if(  ! $test  ) {
        Ok( 1, 0, join ' ',
            "No '#for $sect' in any t/pod*.t file found",
            "(see line $podline of Init.pm)",
        );
    } elsif(  $pod eq $test  ) {
        Ok( 1 );
    } else {
        my $podFile=    "$tmp/pod.txt";
        my $testFile=   "$tmp/test.txt";
        open OUT, '>', $podFile
            or  die "Can't write $podFile: $!\n";
        print OUT $pod;
        open OUT, '>', $testFile
            or  die "Can't write $testFile: $!\n";
        print OUT $test;
        close OUT;
        my $diff= join '',
            "'=for test $sect' (Init.pm line $podline) ne ",
            "'#for $sect' ($file line $line)\n",
            qx( diff -U1 $podFile $testFile 2>&1 );
        Ok( 1, 2, $diff );
    }
}
my @left= keys %test;
Ok( '', "@left",
    "t/pod*.t '#for' sections for which there is no '=for test' in Init.pm" );
