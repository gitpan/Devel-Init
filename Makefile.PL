#!/usr/bin/perl -w
use strict;
use ExtUtils::MakeMaker;
# Run "perldoc ExtUtils::MakeMaker" for more information.

WriteMakefile(
    'NAME'              => 'Devel::Init',
    'VERSION_FROM'      => 'Init.pm',
    #'PREREQ_PM'         => {
    #    'strict' => 0,
    #    'constant' => 0,
    #},
    # LICENSE ?
    $] < 5.005  ?  ()  :  (
        'AUTHOR'        => 'Tye McQueen',
        'ABSTRACT_FROM' => 'Init.pm',
    ),
);
