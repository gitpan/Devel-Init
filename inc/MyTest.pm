package MyTest;
use strict;

use Test qw< plan ok skip >;
use vars qw< @EXPORT_OK >;

BEGIN {
    @EXPORT_OK= qw< plan ok skip Ok SkipIf Eval Dies >;
    require Exporter;
    *import= \&Exporter::import;
}

$|= 1;
for my $base (  '', '../'  ) {
    if(  -d $base.'blib/arch'  ||  -d $base.'blib/lib'  ) {
        require lib;
        lib->import( $base.'blib/arch', $base.'blib/lib' );
        last;
    }
}

return 1;


sub Ok($;$$) {
    @_=  @_ < 3  ?  reverse @_  :  @_[1,0,2];
    return &ok(@_);
}


sub SkipIf($;$$$) {
    my $skip= shift @_;
    die "Can't not skip a non-test"
        if  ! $skip  &&  ! @_;
    $skip= 'Prior test failed'
        if  $skip  &&  1 eq $skip;
    @_=  @_ < 3  ?  reverse @_  :  @_[1,0,2];
    return &skip( $skip, @_ );
}


sub Eval {
    my( $code, $desc )= @_;
    $desc ||= $code;
    my( $pkg, $file, $line )= caller();
    ++$line;
    my $eval= qq(\n#line $line "$file"\n) . $code . "\n1;\n";
    Ok( 1, eval $eval, "Should not die:\n$desc\n$@" );
}


sub Dies {
    my( $code, $omen, $desc )= @_;
    #if(  ref $code  ) {
    #    SkipIf(
    #        ! Ok( undef, eval { $code->() }, "Should die:\n$desc" ),
    #        $omen, $@, "Error from:\n$desc",
    #    );
    #}
    $desc ||= $code;
    my( $pkg, $file, $line )= caller();
    ++$line;
    my $eval= qq(\n#line $line "$file"\n) . $code . "\n1;\n";
    SkipIf(
        ! Ok( undef, eval $eval, "Should die:\n$desc" ),
        $omen, $@, "Error from:\n$desc",
    );
}
