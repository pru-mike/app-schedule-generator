#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw/$Bin/;
use lib qq[$Bin/../lib];
use Test::More tests => 2;
use Test::Deep;
use Data::Dumper;

use_ok('App::Schedule::Generate');

my $from = DateTime->new(
    year  => '2018',
    month => '08',
    day   => '01',
);
my $to = $from->clone->add(days => 3);

my @res = App::Schedule::Generate::_datetime_method(day => $from, $to);
cmp_deeply(\@res, [1, 2, 3], '_datetime_method');

