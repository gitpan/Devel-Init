package Devel::Init;
use strict;

use vars qw<
    $VERSION @EXPORT_OK @Predicates
    %Attribs @Inits $StackTrace $DefaultInit
>;
BEGIN {
    $VERSION= 0.001_002;
    $DefaultInit= 1;    # RunInits('default') at INIT-time?

    # Just in case somebody wants Exporter.pm-like information:
    @EXPORT_OK= (
        ':Init',            # Allows: sub foo :Init(...)
        ':NoDefault',       # Disables default initialization step
        'RegisterInit',     # RegisterInit(\&sub,@predicates)
        'RunInits',         # RunInits(@options,@predicates)
        'InitBlock',        # $single ||= InitBlock { ... return $init; };
        'InitSub',          # $single ||= InitSub( sub { ... return $init; } );
        '-StackTrace',      # Add a stack trace to a fatal error
        '-NoStackTrace',    # Restore default of no stack traces
        '@Predicates',      # Current list of predicates in RunInits()
    );
}

use constant {
    # Name of sub called when "sub foo :Init" code is compiled:
    AttrSetter => 'MODIFY_CODE_ATTRIBUTES',
    # Name of sub called by attributes::get() to retrieve sub attributes:
    AttrGetter => 'FETCH_CODE_ATTRIBUTES',
};

return 1;   # Only subroutine definitions to be found below this point


INIT {
    RunInits( 'default' )
        if  $DefaultInit;
}


sub import
{
    my( $us, @what )= @_;
    my $pkg= caller();

    local( $_ );
    for(  @what  ) {
        if(  /^:Init$/  ) {
            _exportInit( $pkg );
        } elsif(  /^:NoDefault$/  ) {
            $DefaultInit= 0;
        } elsif(  /^-(No)?StackTrace$/  ) {
            $StackTrace= ! $1;
        } elsif(  /^\@(Predicates)$/  ) {
            _export( $pkg, 'ARRAY', '@', $1 );
        } elsif(  /^&?(RunInits|RegisterInit|InitBlock|InitSub)$/  ) {
            my $sub= $1;
            $DefaultInit= 0
                if  'RunInits' eq $sub;
            _export( $pkg, 'CODE', '&', $sub );
        } else {
            _blameCaller( 1, __PACKAGE__, " does not export ($_)" );
        }
    }
}


sub _blameCaller
{
    my( $depth, @text )= @_;
    my( $pkg, $file, $line )= caller($depth);
    die @text, " at $file line $line\n";
}


sub _export
{
    my( $pkg, $type, $sig, $name )= @_;
    my $glob= _getGlob( $pkg, $name );
    my $src= *{ _getGlob( __PACKAGE__, $name ) }{$type};
    die $sig, __PACKAGE__, "::$name is not of type $type?!"
        if  $type ne ref($src);
    die __PACKAGE__, "::$name not defined?!"
        if  ! $src;
    if(  *{$glob}{$type}  ) {
        _blameCaller( 2, __PACKAGE__,
            " won't export $sig$name over existing definition" );
    }
    *{$glob}= $src;
}


sub _getGlob
{
    my( $pkg, $name )= @_;
    my $stash= do { no strict 'refs'; \%{$pkg.'::'} };
    my $glob= \$stash->{$name};
    if(  'GLOB' ne ref $glob  ) {
        # Must be 5.10 with its space optimization!
        # So we need to force a real glob to be created.
        # This means that that sub was actually defined as a constant, but
        # we'll let the likely *{$glob}= sub ...; code trigger the warning.
        # We only do this to prevent the completely unenlightening
        # but fatal "not a GLOB reference" error.
        {
            no strict 'refs';
            ${$pkg.'::'.$name}= undef;
        }
        $glob= \$stash->{$name};
        die "Can't coerce optimized STAB entry ($pkg\::$name) into real GLOB"
            if  'GLOB' ne ref $glob;
    }
    return $glob;
}


sub _exportInit
{
    my( $pkg )= @_;
    # Export a &MODIFY_CODE_ATTRIBUTES to the calling package

    my $glob= _getGlob( $pkg, AttrSetter() );
    my $prev= *{$glob}{CODE};
    if(  ! $prev  ) {
        *{$glob}= \&_newAttrib;
    } else {
        my $prevSetter= $prev;
        *{$glob}= sub {
            return _newAttrib( @_[0,1], $prevSetter->(@_) );
        };
    }

    $glob= _getGlob( $pkg, AttrGetter() );
    $prev= *{$glob}{CODE};
    if(  ! $prev  ) {
        *{$glob}= \&_getAttribs;
    } else {
        my $prevGetter= $prev;
        *{$glob}= sub {
            return( $prevGetter->(@_), _getAttribs(@_) );
        };
    }
}


sub _getAttribs
{
    my( $code )= @_;
    my $addr;
    if(  'CODE' eq ref $code  ) {
        $addr= 0 + $code;
    } else {
        die AttrGetter(), " given a non-code reference: $code";
    }
    return @{ $Attribs{ 0 + $code } || [] };
}


sub _newAttrib
{
    my( $pkg, $code, @attribs )= @_;
    my @left;

    local( $_ );
    for(  @attribs  ) {
        if(  /^Init\b/  ) {
            push @{ $Attribs{ 0 + $code } }, $_;
            s/^Init\(?//;
            s/\)$//;
            _registerInitFor( $pkg, $code, split /[,\s]+/, $_ );
        } else {
            push @left, $_;
        }
    }

    return @left;
}


sub _registerInitFor
{
    my( $pkg, $code, @conds )= @_;
    @conds= map {
        if(  /^(\\?)\@(\w+)$/  ) {
            my( $asRef, $name )= ( $1, $2 );
            my $av= *{ _getGlob( $pkg, $name ) }{ARRAY};
            if(  ! $av  ) {
                _blameCaller( 2,
                    "Undeclared array name, \@$pkg\::$name, in :Init(@conds)",
                );
            } elsif(  $asRef  ) {
                $av;
            } else {
                @$av;
            }
        } elsif(  ! /^\w[-.\w]*$/  ) {
            _blameCaller( 2,
                "Invalid predicate name, $_, in :Init(@conds)",
            );
        } else {
            $_;
        }
    } @conds;
    push @Inits, @conds ? [ $code, @conds ] : $code;
}


sub InitBlock(&)
{
    my( $code )= @_;
    return InitSub( $code, 1 );
}


{
    my %running;
    my @stack;


    sub InitSub
    {
        my( $code, $depth )= @_;
        my( $pkg, $file, $line, $sub )= caller( $depth || 0 );
        my $key= join ",", $pkg, $sub, $line, $file;
        for my $val (  $running{$key}  ) {
            if(  defined $val  ) {
                die _cycleReport( $val, $pkg, $sub, $line );
            }
            $val= @stack;
        }
        push @stack, $key;
        my @ret;
        if(  wantarray  ) {
            @ret= $code->();
        } else {
            $ret[0]= $code->();
        }
        delete $running{$key};
        pop @stack;
        return  wantarray  ?  @ret  :  $ret[0];
    }


    sub _cycleReport
    {
        my( $start, $pkg, $sub, $line )= @_;
        my $steps= @stack - $start;
        my $err= "Circular initialization dependency detected.\n";
        if(  $StackTrace  ) {
            require Carp;
            $err= Carp::longmess( $err );
        }
        $err .= join ' ',
            "The following initialization steps",
            "form the $steps-step cycle:\n";
        for my $i (  $start .. $#stack  ) {
            my( $pkg, $sub, $line, $file )= split /,/, $stack[$i];
            $err .= "    $pkg\::$sub() (line $line) calls\n";
        }
        $err .= "    $pkg\::$sub().\n";
        $err .= "$pkg\::$sub() indirectly calls itself!\n";
        return $err;
    }

}


sub RegisterInit
{
    # my( $code, @conds )= @_;
    my $pkg= caller();
    _registerInitFor( $pkg, @_ );
}


sub _runOneInit
{
    my( $code, $svFail )= @_;
    my $error;
    my $okay= do {
        my $prev= $SIG{__DIE__};
        local $SIG{__DIE__}= sub {
            if(  ! $StackTrace  ) {
                $error= $_[0];
            } else {
                require Carp;
                $error= Carp::longmess( $_[0] );
            }
            die @_
                if  ! $prev;
            $prev->( @_ );
        };

        eval { $code->(); 1 };
    };
    if(  ! $okay  ) {
        $$svFail=
            $StackTrace  &&  $error
                ?   $error
                :   $@ || $error || "Unknown failure initializing";
    }
}


sub _rankConds
{
    my( @conds )= @_;
    return map {
        if(  s/^not_//  ) {
            ( $_, -1 );
        } elsif(  s/^only_//  ) {
            ( $_, 2 );
        } else {
            ( $_, 1 );
        }
    } @conds;
}


sub _skipInit
{
    my( $code, $hvHave, $svFail )= @_;
    my @need;
    ( $code, @need )= @$code
        if  'ARRAY' eq ref($code);

    my %need= _rankConds( @need );
    for my $cond (  keys %need, keys %$hvHave  ) {
        return 1    # We skipped this init; keep it around to run later
            if  1 < abs( ($need{$cond}||0) - ($hvHave->{$cond}||0) );
    }

    _runOneInit( $code, $svFail );
    return 0;   # We didn't skip this init; don't run it again
}


sub RunInits
{
    local( $StackTrace )= $StackTrace;
    while(  @_  &&  $_[0] =~ /^-/  ) {
        local $_= shift @_;
        if(  /^-(No)StackTrace$/i  ) {
            $StackTrace= ! $1;
        } else {
            _blameCaller( 1, "Unknown RunInits() option, $_" );
        }
    }
    local( @Predicates )= @_;
    my %have= _rankConds( @_ );
    my $inits= 0+@Inits;

    my $fail;
    @Inits= grep {
        $fail  ||  _skipInit( $_, \%have, \$fail );
    } @Inits;
    die $fail
        if  $fail;

    return $inits;
}


__END__


BEGIN {
    my $depth= 0;

    sub _newAttrib
    {
        my( $pkg, $code, @attribs )= @_;
        return @attribs
            if  $depth;
        my @left;
        local( $_ );

        for(  @attribs  ) {
            if(  /^Init\b/  ) {
                push @{ $Attribs{ 0 + $code } }, $_;
                s///;
                s/^\(//;
                s/\)$//;
                _registerInitFor( ??, $code, split /[,\s]+/, $_ );
            } else {
                push @left, $_;
            }
        }

        # The rest of this craziness is due to the poor design choices of
        # Attribute::Handlers (and to attribute.pm for not discouraging such):
        return
            if  ! @left;
        local( $depth )= 1 + $depth;
        my @pkgs= $pkg;
        while(  @pkgs  ) {
            my $next= shift @pkgs;
            my $glob= _getGlob( $next, AttrSetter() );
            my $can= *{$glob}{CODE};
            @left= $can->( $pkg, $code, @left )
                or  last
                if  $can
                &&  $can != \&_newAttrib;
            $glob= _getGlob( $next, 'ISA' );
            unshift @pkgs, @{ *{$glob}{ARRAY} };
        }
        return @left;
    }
}

               not_X    n/a      X     only_X
               -----    ---     ---    ------
    not_X  :    Run     Run     no      no
    n/a    :    Run     Run     Run     no
    X      :    no      Run     Run     Run
    only_X :    no      no      Run     Run



=head1 NAME

Devel::Init - Control when initialization happens, depending on situation.


=head1 SYNOPSYS

=for test Synops1

    package Some::Module;

    use Devel::Init qw< :Init InitBlock >;

    BEGIN {
        my $dbh;

        sub getDBH :Init(not_prefork) {
            return $dbh ||= InitBlock { _connect_to_database() };
        }
    }

    sub readRecords {
        # ...
        my $dbh= getDBH();
        # ...
    }

    # ...

=for test Synops2

    package main;
    use Devel::Init qw< RunInits >;
    use Some::Module;

    RunInits('prefork');
    fork_worker_children(
        sub {
            RunInits();
            do_work();
        },
    );


=head1 DESCRIPTION

Devel::Init provides aspect-oriented control over initialization.  It can make
your server code more efficient, allow for faster diagnosis of configuration
(and other) problems, make your interactive code more responsive, and make
your modules much easier to unit test (and other benefits).

=head2 Motivation

The best time to do complex or costly initialization can vary widely, even
for the same piece of code.  It is impossible for a module author to pick
the best time because there is more than one best time, depending on the
situation.

C<Devel::Init> allows module authors to declare what initialization steps
are required and then allows each situation to very easily drive which types
of initializations should be run when (and which types should not be run
until they are actually needed).

The documentation also lays out best practices for ensuring that
initialization will always be done before it is needed and not before
it is possible, even when complex interdependencies between initialization
steps exist.

And C<Devel::Init> makes it easy to write your initialization code so that
a circular dependency will be detected and be reported in an informative way.

=head2 When to initialize

A good example that highlights many benefits of doing initializations
at the "right" time is a daemon that C<fork()>s a bunch of worker children.
A common example of that is an Apache web server using mod_perl.

For an initialization step that allocates a large structure of static data,
running it I<before> the worker children are C<fork()>ed can have several
benefits.  The work of building the structure doesn't need to be repeated
in each child.  The pages of memory holding parts of the structure can
stay shared among the children, reducing the amount of physical memory
required.

Conversely, for an initialization step that connects to a database server,
doing that before C<fork()>ing is wasteful (and may even be problematic)
because the children would inherit the underlying socket handle but couldn't
actually make shared use of it and so would just have to connect to the DB
server all over again.

But you might want to have database connections made I<quickly> after each
child is C<fork()>ed so that any problems with database connectivity or
configuration will be noticed immediately.

When doing unit testing on some part of the larger application, you may want
to avoid making database connections early.  If the unit test never
exercises code that needs the database connection, then you wouldn't need
to set up a database that can be reached from within the test environment.

And if you are writing complex servers but are not using C<Devel::Init>,
then you probably have run into cases where you can't even use

    perl -c Some/Module.pm

to check for simple syntax errors in a module that you are working on.
It is too easy to end up with way too much initialization happening at
"compile time" so that the above never gets around to checking the syntax
of that module:

    $ perl -c Some/Module.pm
    Can't connect to database ...

=head2 Interdependent initializations

You may not want to connect to the DB before C<fork()>ing, but you might have
some other step that needs to connect to the DB in order to build a large
data structure.  If one registers the connecting to the DB as a step to be
run after C<fork()>ing, then that registration should not prevent the
connecting to the DB before C<fork()>ing if such is I<required> before then.

So it is important to ensure that initialization steps don't get run "too
late".  Each needs to be run when it is needed, even if that isn't the "best"
time you were hoping for.

You need to write your initialization code to ensure that complex
dependencies between initialization steps get carried out in an acceptable
order.

=head2 Singletons

An easy and reliable way to do this is to have a function that you call
whenever you want to use the result of an initialization step.  An obvious
example is the handle for a connection to a database.

You write a subroutine that returns this DB handle and you ensure that nobody
can access the DB handle without first calling that function.  A great way
to ensure such is to "hide" the DB handle in a lexical variable that is only
in scope to that initialization method.  For example:

    BEGIN {
        my $dbh;

        sub get_dbh {
            return $dbh
                if  $dbh;
            # ...
            $dbh= ...;
            # ...
            return $dbh;
        }
    }

    # ...
        my $sth= get_dbh()->prepare( $sql );
    # ...
        my $dbh= get_dbh();
        for my $sql (  @queries  ) {
            my $sth= $dbh->prepare( $sql );
            ...
        }
    # ...

You might recognize this as a common way to implement the DB handle as a
"singleton".

The code to initialize the DB handle might be complex.  But the function
immediately returns the stashed handle if it has already been initialized
and so only adds insignificant overhead which is not worth worrying about.

=head2 Depending on a simple initialization

There are also simple initializations that you probably don't want to control
via C<Devel::Init> that need to happen before other initialization steps can
be run.  So it is important to not allow an initialization step to be run
"too early" where it would fail to find some data it needs.

For example:

    # A bad example!

    use Devel::Init qw< :Init >;

    my $Connect= 'dbi:pick:dick@trw:1965';
    my $DB_user= 'dnelson';
    my $DB_pass= 'convair3537';

    {
        my $dbh;
        sub getDBH :Init(not_prefork) {
            $dbh ||= DBI->connect(
                $Connect, $DB_user, $DB_pass,
                { RaiseError => 1, PrintError => 0 },
            );
            return $dbh;
        }
    }

    # Don't do the above!

It is possible for C<getDBH()> to get called before C<$Connect> etc. get
initialized.  The C<:Init(not_prefork)> attribute notifies C<Devel::Init> of
C<\&getDBH> as soon as Perl has finished I<compiling> the C<sub getDBH> code.
It may be much later before the code to initialize C<$Connect> etc.
gets I<run>.

Compare that to:

=for test BetterEx

    # A better example.

    use Devel::Init qw< :Init >;
    use DBI;

    BEGIN {
        my $Connect= 'DBI:pick:dick@trw:1965';
        my $DB_user= 'dnelson';
        my $DB_pass= 'convair3537';

        my $dbh;
        sub getDBH :Init(not_prefork) {
            $dbh ||= DBI->connect(
                $Connect, $DB_user, $DB_pass,
                { RaiseError => 1, PrintError => 0 },
            );
            return $dbh;
        }
        # Devel::Init is notified when the above line is compiled
    }
    # $Connect etc. are initialized when the above line is compiled

C<Devel::Init> gets notified of the desire to run C<getDBH()> before
C<$Connect> etc. get initialized, but there is no opportunity for other
code to be run between those two steps so this code should be safe.

Even safer (and more flexible) would be:

=for test Safer

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
            return $dbh ||= InitBlock {
                DBI->connect(
                    $Connect, $DB_user, $DB_pass,
                    { RaiseError => 1, PrintError => 0 },
                ),
            };
        }
    }

[The I<second> C<BEGIN> has no impact in the above example.  But we consider
the use of C<BEGIN> for blocks around such "static" (or "state") variables
(like C<$dbh> above) to be a "best practice" because there are many cases
where it can prevent problems.]

=head2 Depending on initialization provided by another module

Below is another pattern that could lead to initialization being run before
it is ready:

    # A bad example!

    package Some::Module;
    use Devel::Init ':Init';
    require Local::Config;  # Oops

    {
        my $dbh;

        sub getDBH :Init(not_prefork) {
            $dbh ||= DBI->connect(
                Local::Config::GetDbConnectParams('some_db'),
            );
            return $dbh;
        }
    }

    # Avoid the above!

This could cause C<Local::Config::GetDbConnectParams()> to be called before
it has even been defined -- because C<getDBH()> could be called before the
C<require Local::Config;> line gets run so the C<Local::Config> module might
not have been loaded yet.

=head2 The compile-time pattern

The simplest (and likely most common) pattern to prevent such problems is to
load the other module at compile time via C<use>.  To demonstrate the benefit
of a C<BEGIN> block, we also add a simple data initialization (C<$db_name>):

=for test Best

    # A "best practice"!

    package Some::Module;
    use Devel::Init     qw< :Init InitBlock >;
    use Local::Config   qw< GetDbConnectParams >;
    use DBI             ();

    BEGIN {
        my $dbh;
        my $db_name= $ENV{'DB_NAME'} || 'some_db';

        sub getDBH :Init(not_prefork) {
            return $dbh ||= InitBlock {
                DBI->connect(
                    GetDbConnectParams( $db_name ),
                )
                    or  die "Failed to connect to $db_name: $DBI::errstr\n";
            };
        }
    }

=head2 The run-time pattern

If you find yourself in the somewhat unusual situation of trying to delay the
loading of module code, then you might instead use the following "run-time"
pattern:

=for test RunTime

    # Use this pattern with caution.

    package Some::Module;
    require Devel::Init;
    require Local::Config;
    require DBI;

    {
        my $dbh;
        my $db_name= $ENV{'DB_NAME'} || 'some_db';

        sub getDBH {
            return $dbh ||= Devel::Init::InitSub( sub {
                DBI->connect(
                    Local::Config::GetDbConnectParams( $db_name ),
                )
                    or  die "Failed to connect to $db_name: $DBI::errstr\n";
            } );
        }
    }
    Devel::Init::RegisterInit( \&getDBH, 'not_prefork' );

Note that deviating from this "run time" pattern elsewhere in the code for the
above C<Some::Module> could then cause problems.


=head1 USAGE

=head2 InitBlock

The InitBlock() function can be imported at compile-time (via C<use>).  It
is declared with a subroutine "prototype", C<sub InitBlock(&)>, so that you
must pass it a single block (code surrounded by curly braces, C<{> and C<}>)
and that block will be treated as a subroutine (as a "CODE" reference).

The passed-in block of code is called (from a scalar- or list-context to
match the context InitBlock() was called from) and the value(s) returned
by the block are returned by InitBlock().

So, InitBlock() acts like a no-op, simply returning whatever is returned by
the code you passed to it.

    BEGIN {
        my $singleton;

        sub get_singleton :Init {
            return $singleton ||= InitBlock {
                ... # do the hard work of initializing $initializedValue
                return $initializedValue;
            };
        }
    }

However, InitBlock() keeps track of which initialization steps are still
in-progress and thus can detect circular dependencies between initialization
steps.  When a circular dependency is detected, InitBlock() will C<die>,
providing an informative summary of exactly what components make up that
cycle of dependence.

=head2 InitSub

InitSub() behaves exactly the same as InitBlock() but it is not declared
with a subroutine "prototype" so you must pass a single scalar to it which
must be a "CODE" reference (like "C<sub { ... }>" or "C<\&subname>", for
example):

    {
        my $dbh;

        sub getDBH {
            return $dbh ||= Devel::Init::InitSub( sub {
                DBI->connect( @connect_params )
                    or  die "Failed to connect to DB: $DBI::errstr\n";
            } );
        }
    }
    Devel::Init::RegisterInit( \&getDBH, 'not_prefork' );

=head2 :Init

The basic (compile-time) initialization pattern:

=for test Basic

    package Some::Module;
    use Devel::Init qw< :Init >;

    BEGIN {
        my $single;

        sub get_singleton :Init {
            return $single ||= InitBlock {
                ... # figure out $initialized_value
                return $initialized_value;
            };
        }
    }

    sub some_sub {
        ... get_singleton() ...
    }

The C<< use Devel::Init qw<:Init>; >> line allows the current package to use
the C<:Init> attribute on any sub(routine)s it declares.  By including that
attribute you tell C<Devel::Init> that you want that subroutine
[C<get_singleton()>, above] called [with no arguments passed to it] at
whatever point the current environment arranges as the "best" time.

You can also pass predicates via the C<:Init> attribute that provide hints
about which times might be more or less appropriate for each initialization
step.  To specify more than one predicate, separate them with spaces, tabs,
commas, and/or other white-space.  For example:

    ...
        sub get_dynamic_config :Init(not_prefork,not_unittest) {
            ...
        }
    ...

Note that the text inside the parentheses after C<:Init> is not Perl code.
Do not put quotes around the predicates.  You also can't interpolate
scalars inside there:

    sub getFoo :Init(prefork,$other);   # Not what it appears!

However, as a special case that you are unlikely to use, you can pretend
to interpolate arrays or references to arrays.  See L<Use in public modules>
for the details (on second thought, you probably shouldn't).

=head2 :NoDefault

C<Devel::Init> declares its own C<INIT> block as follows:

    INIT {
        RunInits( 'default' )
            if  $DefaultInit;
    }

This means that C<RunInits('default')> will be run just after the main script
has finished being compiled (just before the main script's "run time" begins),
unless this default initialization step is disabled prior to that.

The default initialization step is usually disabled by the main script (or
some module that it C<use>s) importing RunInits() (usually so that the main
script can call RunInits() at the most appropriate time):

    use Devel::Init qw< RunInits >; # Disables default initialization

But you can also disable the default inititialization step by "importing"
C<':NoDefault'> (which does not import anything into the caller's namespace):

    use Devel::Init qw< :NoDefault >; # Disables default initialization

Note that several environments (such as when Perl is embedded, such as is the
case with mod_perl) may not run C<INIT> blocks.  So don't be surprised if
the default initialization step fails to run in some environments (even if
nobody disabled it).

The default initialization step is provided mainly for authors of public
modules who might otherwise be tempted to concoct their own schemes meant
to force early initialization for cases when the users of their module fail
to make use of C<Devel::Init> in the main script to define the best point
in time for initialization to happen.

It means that using C<Devel::Init> in a public module defaults to acting
the same as doing your initialization inside of your own C<INIT> block.

Note that the default initialization step specifies the predicate 'default'
just in case somebody wants to declare steps that should only be run by
the default step (C<'only_default'>) or that should not be run by the default
step (C<'not_default'>).  However, the author of C<Devel::Init> has not
yet imagined any reasons why somebody should want to specify such.

=head2 RegisterInit()

The less-likely run-time initialization pattern:

=for test RunTime2

    package Some::Module;
    use Devel::Init qw< RegisterInit InitBlock >;

    {
        my $single;

        sub get_singleton {
            $single ||= InitBlock {
                ... # figure out $initialized_value
                return $initialized_value;
            };
            return $single;
        }
    }
    RegisterInit( \&get_singleton );

The first argument to C<RegisterInit()> should be a reference to a subroutine
that should be run (with no arguments passed to it) at the desired
initialization time.  Subsequent arguments to RegisterInit(), if any, should
be predicate string(s).

As a special case that you are unlikely to use, a predicate string can
instead be a references to an array.  The contents of that array will
be used as predicates I<at the time of> any future calls to C<RunInits()>.
See L<Use in public modules> for why you might do that (or not).

=head3 Predicates

When you register an initialization step, you can specify zero or more
predicates that provide hints as to which initialization point in time
might be more or less appropriate for that step to be run at.

A predicate is just a word that describes a property that a point in time
for initialization might or might not possess.  Each predicate may be
prefixed by "not_" or "only_" (or have no prefix).

Registering an initialization step with "not_X" would mean that it would
avoid being run at a time that was designated as either "X" or "only_X".
Registering an initialization step with "only_X" would mean that it would
avoid being run at a time that was I<NOT> designated as either "X" or
"only_X".  More details on how predicates interact are given later.

You can invent and use any predicate words that make sense to you.

It is expected that most initialization steps will be registered with
no predicates specified.  The next-most-expected registrations are
ones designated as 'not_prefork' [those that connect to external
resources in ways that can't be shared with C<fork()>ed children].

=head2 RunInits()

Calling C<RunInits()> causes (some of) the previously registered
initialization steps to be immediately run.

    use Devel::Init qw< RunInits >;
    ...
    RunInits( '-StackTrace', 'not_prefork' );

If the first argument to C<RunInits()> is either C<'-StackTrace'> or
C<'-NoStackTrace'>, then it overrides the default behavior specified by
C<< use Devel::Init qw< -StackTrace >; >> (see below).  Other arguments
must not begin with a dash character, C<'-'>, as such are reserved for
future use as other options.

The remaining arguments to C<RunInits()> are predicate strings that
describe aspects of the current initialization phase.  These serve
to select which of the previously registered initialization steps
will get run now.

Just as with C<:Init> and C<RegisterInit()>, each predicate can be
prepended with C<'not_'> or C<'only_'>.  See L<Predicate details>
for more details.

If an initialization step C<die>s, then C<RunInits()> will cleanly remove
that step (and any prior steps that were just run) from the list of pending
initializations and then re-C<die> with the same exception or message.

[You likely don't care, but RunInits() returns the count of initialization
steps that it just ran -- and this might change in future.]

=head2 -StackTrace and -NoStackTrace

Importing C<-StackTrace> from C<Devel::Init> will generate a stack trace
(see the Carp module) if C<Devel::Init> detects a fatal error [though this
is overridden by RunInits('-NoStackTrace',...), of course].

    use Devel::Init qw< RunInits -StackTrace >;

Importing C<-NoStackTrace> restores the default of not generating a stack
trace when fatal errors are detected.


=head1 Predicate details

=head2 More predicate examples

The most-expected arrangements of running initialization steps are:

A simple command-line utility:

    ...
    if(  ! GetOpts()  ) {
        die Usage();
    }
    # Don't do costly init when we only issue a 'usage' message.
    RunInits();
    ...

A server with worker children:

    ...
    RunInits('prefork');
    fork_worker_children(
        sub {
            RunInits();
            do_work();
        },
    );
    ...

A unit test script:

    use Test::More ...;
    ...
    require_ok( 'Some::Module' );
    RunInits( 'only_unittest' );
    ...

Some possible arrangements of predicates when registering are illustrated
below (with subroutine names and comments to help justify each choice),
roughly from most-likely to least-likely:

    sub getDriverHash :Init {
        # Run as soon as possible in all "normal" environments.
        # For unit tests, doesn't get run unless/until needed.
    }

    sub getDBH :Init(not_prefork) {
        # Connects to a DB so should not be done before forking.
    }

    sub getHugeData :Init(only_prefork) {
        # Doesn't need to be run until needed, unless we plan
        # to fork a bunch of children such that we should
        # try to pre-load the huge data so it will likely be
        # shared between children.
    }

    sub getConfig :Init(unittest) {
        # Run as soon as possible.
        # Even run when unit testing does RunInits('only_unittest')
        # because this 'config' knows how to stub itself out then.
    }

    sub checkContracts :Init(only_unittest) {
        # Only do these constly checks when doing unit tests.
    }

    sub autoStubbedConnection :Init(not_prefork,unittest) {
        # Don't run pre-fork but otherwise run as soon as possible,
        # even when in a unit test.
    }

    sub getDynamicConfig :Init(only_unittest) :Init(only_prefork) {
        # This step can be expensive.  Don't run it until needed.
        # Except that we want to run it before fork()ing if we
        # will have worker children (lots of data to share).
        # And we want to run it early for unit testing where it
        # gets stubbed out and so isn't expensive and also arranges
        # to stub out other stuff.
        # When part of a command-line utility, this step can be
        # completely skipped when a "usage" error is detected,
        # saving significant time.
    }

=head2 How predicates interact

When multiple predicates are specified as part of a registration or are
passed to C<RunInits()>, it means that all predicates must be "satisfied"
for an initialization step to be run at that time.

So, C<sub getFoo :Init(bar,baz) ...> indicates that C<getFoo();> should
be run only when I<both> 'bar' and 'baz' are appropriate.

If you want to specify an "C<or>" relationship, then register the
initialization step more than once:

    sub getFud :Init(bar,baz) :Init(fig,fug) {
        ...
    }

The above indicates that C<getFud();> should be called when I<both> 'bar' and
'baz' are appropriate -- I<or> -- when I<both> 'fig' and 'fug' are appropriate.
Actually, this means that C<getFud();> might get called twice (which isn't
usually a problem with the 'get singleton' initialization pattern that is
encouraged).

Similarly, writing the following:

    RunInits( 'bar', 'baz' );
    RunInits( 'fig', 'fug' );

would mean that you want to run all steps where 'bar' I<and> 'baz' are
appropriate -- I<or> -- where 'fig' I<and> 'fug' are appropriate.

What does it mean for a predicate word to be appropriate?  The following
table illustrates all of the different possible cases for a single
predicate word ("X", in this case).  Note that "n/a" denotes when "X" was
not specified as a predicate, not even with any prefix:

               not_X    n/a      X     only_X
               -----    ---     ---    ------
    not_X  :    run     run     NOT     NOT
    n/a    :    run     run     run     NOT
    X      :    NOT     run     run     run
    only_X :    NOT     NOT     run     run

These interactions were carefully chosen to allow "common sense" (more
like "common English usage", really) to reveal how they work.  But, just
in case the author's "sense" has little in common with the reader's "sense",
let's beat this horse to a proper death.

Below we re-use our extensive examples of initialization steps from above
and then give example C<RunInits()> invocations and list which steps would
be run in each case.

    sub getDriverHash :Init;
    sub getDBH :Init(not_prefork);
    sub getHugeData :Init(only_prefork);
    sub getConfig :Init(unittest);
    sub checkContracts :Init(only_unittest);
    sub autoStubbedConnection :Init(not_prefork,unittest);
    sub getDynamicConfig :Init(only_unittest) :Init(only_prefork);

The command-line utility use-case:

    RunInits();
    # Runs  getDriverHash()
    # Runs  getDBH()
    # Saves getHugeData for later ('only_prefork' not met)
    # Runs  getConfig()
    # Saves checkContracts for later ('only_unittest' not met)
    # Runs  autoStubbedConnection()
    # Saves getDynamicConfig (both registrations) for later

The C<fork()>ing server use-case:

    RunInits('prefork');
    # Runs  getDriverHash()
    # Saves getDBH for later ('not_prefork')
    # Runs  getHugeData()
    # Runs  getConfig()
    # Saves checkContracts for later ('only_unittest')
    # Saves autoStubbedConnection for later ('not_prefork' not met)
    # Runs  getDynamicConfig() /once/ ('only_unittest' not met)

    RunInits();
    # Ran   getDriverHash above (no longer registered)
    # Runs  getDBH()
    # Ran   getHugeData above
    # Ran   getConfig above
    # Saves checkContracts for later ('only_unittest')
    # Runs  autoStubbedConnection()
    # Saves getDynamicConfig's 'only_unittest' entry for later

The unit test use-case:

    RunInits( 'only_unittest' );
    # Saves getDriverHash for later ('unittest' not specified)
    # Saves getDBH for later ('unittest' not specified)
    # Saves getHugeData for later ('only_prefork' not met either)
    # Runs  getConfig()
    # Runs  checkContracts()
    # Runs  autoStubbedConnection()
    # Runs  getDynamicConfig() /once/ ('only_prefork' not met)

Finally, the flog-the-dead-horse, non-sensical use-case [such invocations
of C<RunInits()> really make no sense]:

    RunInits( 'only_prefork', 'not_unittest' ); # Don't do this!
    # Saves getDriverHash for later ('prefork' not specified)
    # Saves getDBH for later ('not_prefork' very not met)
    # Runs  getHugeData()
    # Saves getConfig for later ('unittest' not met)
    # Saves checkContracts for later ('prefork' not specified)
    # Saves autoStubbedConnection for later (nothing "met")
    # Runs  getDynamicConfig() /once/ ('only_unittest' not met)

    RunInits( 'not_prefork', 'not_postfork' ); # Don't do this!
    # Runs  getDriverHash()
    # Runs  getDBH()
    # Ran   getHugeData above (no longer registered)
    # Runs  getConfig()
    # Saves checkContracts for later ('only_unittest' not met)
    # Runs  autoStubbedConnection()
    # Saves getDynamicConfig's 'only_unittest' entry for later


=head1 LIMITATIONS

=head2 Compatibility with Attribute::Handlers, etc.

The design of C<attributes.pm> encourages complex and hard-to-coordinate
usage patterns that are (unfortunately) well demonstrated by
C<Attribute::Handlers>.  Although early drafts of C<Devel::Init> included
complex code to try to support compatibility with C<Attribute::Handlers>,
it was determined that it is more appropriate for such compatibility to
be handled in a more sane manner via changes to C<attributes.pm> (or at
least some other module).

C<Devel::Init> uses a much, much simpler approach for supporting attributes
and also supports C<attributes::get()> (which C<Attribute::Handlers> appears
to have completely ignored).

Using C<< use Devel::Init qw<:Init>; >> in a package is likely to cause
uses of C<Attribute::Handlers> or similar attribute-handling modules
to be ignored.  This is because C<attributes.pm> basically does
C<Some::Module->can('MODIFY_CODE_ATTRIBUTES')> and C<Devel::Init>
directly defines C<Some::Module::MODIFY_CODE_ATTRIBUTES()> (and
C<Some::Module::FETCH_CODE_ATTRIBUTES>) while C<Attribute::Handlers>
makes complicated use of multiple layers of inheritance.  Only one
C<MODIFY_CODE_ATTRIBUTES()> method is found and used by C<attributes.pm>,
and it will be the one defined by C<Devel::Init>.

Note that C<Attribute::Handlers> does

    push @UNIVERSAL::ISA, 'Attribute::Handlers::UNIVERSAL'

which means that every single class now magically inherits from
C<Attribute::Handlers::UNIVERSAL>. This is an extremely heavy-handed
way to implement anything.

C<Devel::Init> I<will> cooperate with an attribute-handling module that
directly defines a C<Some::Module::MODIFY_CODE_ATTRIBUTES()> method provided
either that C<Devel::Init> is loaded second or the other module also
cooperates.

=head2 Use in public modules

C<Devel::Init> was primarily designed for use within a large code base
maintained by some organization, such as a company's internal code base.
The I<precise> meaning of possible common predicates like 'prefork' or
'unittest' is difficult to nail down for the universe of all possible
environments.  Even more difficult would be defining the full set of
predicates that might be desired.

So if you make use of Devel::Init in a public module, you may want to allow
the user of the module to override which predicates to apply.  You could do
that by writing your module code something like:

[NOTE: This only works for I<global> arrays from the current package.
Specifying what looks like an array is like passing in the values from that
array I<at the time of the subroutine declaration being compiled>.
Specifying what looks like a I<reference> to an array delays the reading
of predicates from the array until I<each time RunInits() is called>.]

    package Public::Package;

    our @InitWhen= qw< not_prefork >;
    # @InitWhen must be a /global/ array declared via 'our' or 'use vars'!
    # "my @InitWhen" would break this example!

    sub foo :Init(\@InitWhen) {
        ...
    }

    sub import {
        my( $pkg, %opts )= @_;
        for my $when (  $opts{InitWhen}  ) {
            @InitWhen= @$when
                if  $when;
        }
        ...
    }

and then documenting that the user can write code similar to the following
to override the C<Devel::Init> predicates that are applied:

    package main;

    use Public::Package( InitWhen => [qw< make_db_ready >] );

The code

    sub foo :Init(\@InitWhen) {

actually has the same effect as:

    BEGIN { RegisterInit( \&foo, '\\@InitWhen' ); }

[Note that the second argument is just a string.]


=head1 AUTHOR

Tye McQueen -- http://www.perlmonks.org/?node=tye

Many thanks to http://www.whitepages.com/ and http://www.marchex.com/ for
supporting the creation of this module and allowing me to release it to the
world.


=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself (see
http://www.perl.com/perl/misc/Artistic.html).


=head1 SEE ALSO

Theo Chocolate Factory, Fremont, WA.US - http://www.theochocolate.com/

git://github.com/TyeMcQueen/Devel-Init.git

=cut

    Perl provides quite a few choices for when to do initialization.

    =over

    =item require

    Just top-level code in a module.  It gets run right after the module is
    first loaded.

    =item import

    Code inside 'sub import' that gets run each time the module gets 'use'd.

    =item BEGIN

    Code in a BEGIN block.  This gets run while the (module's) code is being
    loaded (compiled).

    =item UNITCHECK

    Code in a UNITCHECK block.  This gets run just before 'require'-time code.

    =item CHECK

    Code in a CHECK block.  This gets run immediately after the main script has
    been compiled.

    =item INIT

    Code in an INIT block.  This gets run immediately after CHECK-time code.

    =item First time you need it

        BEGIN {
            my $singleton;
            sub getSingleton {
                if(  ! $singleton  ) {
                    ...
                }
                return $singleton;
            }
        }

    =back
