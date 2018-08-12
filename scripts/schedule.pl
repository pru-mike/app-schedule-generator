#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use App::Schedule::Generate;

sub HELP_MESSAGE(;$);

my $from = 'now';
my $to   = '+3w';
my @operators;
my @duties;
my $h;
my $cc;
my $tt;
my @inputs = qw/json yaml/;
my $input;
my @outputs = qw/ascii tt json yaml/;
my $output  = $outputs[0];
my $table;
my $today = 'now';
my $todaydt;

GetOptions(
    "help|h"          => \$h,
    "from|f=s"        => \$from,
    "to|t=s"          => \$to,
    "ops|o=s"         => \@operators,
    "duties|d=s"      => \@duties,
    "country_code|cc" => \$cc,
    "input|in=s"      => \$input,
    "output|out=s"    => \$output,
    "today=s"         => \$today,
);
HELP_MESSAGE() if $h;

if ($output && $output =~ /^(tt)=(.+)/) {
    ($output, $tt) = ($1, $2);
}
HELP_MESSAGE "Bad output [$output], MUST be one of {@outputs}" if not grep($_ eq $output, @outputs);
HELP_MESSAGE "Template not defined" if $output eq 'tt' and not -f $tt;

check_date(today => $today, \$todaydt);

if (not $input) {

    @operators = split(/,/, join(',', @operators));
    @duties    = split(/,/, join(',', @duties));

    {
        my @tmp;
        for (@duties) {
            my ($d, $n) = split /=/, $_, 2;
            $n ||= 1;
            push @tmp, $d, $n;
        }
        @duties = @tmp;
        unless (@duties) {
            @duties = qw/D 1/;
        }
    }

    HELP_MESSAGE "Operators not defined" unless (@operators);

    my ($fdt, $tdt);

    check_date(from => $from, \$fdt);

    if ($to =~ /(\d{4})-(\d\d)-(\d\d)/) {
        $tdt = DateTime->new(
            year  => $1,
            month => $2,
            day   => $3,
        );
    } elsif ($to =~ m{\+\s*(\d+)?\s*(w(?:eek)?|d(?:ay)?|m(?:onth)?)s?}) {
        my $num = $1 || 1;
        my $dim = substr($2, 0, 1);
        my $add = $dim eq 'w' ? 'weeks' : $dim eq 'm' ? 'months' : 'days';
        $tdt = $fdt->clone->add($add => $num);
    } else {
        HELP_MESSAGE "wrong --to <date> format";
    }

    my $holidays;
    if ($cc) {
        $holidays = { countries => [$cc], };
    }

    my $app = App::Schedule::Generate->new({
            from_date => $fdt,
            to_date   => $tdt,
            duties    => \@duties,
            operators => \@operators,
            holidays  => $holidays,
        }
    );

    $table = $app->make_schedule()

} else {

    my $data = join '', <>;

    $table = App::Schedule::Generate->load($input => $data);
    HELP_MESSAGE "Bad input [$input], MUST be one of {@inputs}" unless $table;

}

OUTPUT:
for ($output) {
    if (/^tt$/) {
        my ($op, $tcn) = App::Schedule::Generate->find_in_table($todaydt, $table);
        print App::Schedule::Generate->draw_tt($tt, $table, { operator => $op, today_col_num => $tcn });
        last OUTPUT;
    }
    if (/^ascii$/) {
        print App::Schedule::Generate->draw_ascii($table);
        last OUTPUT;
    }
    if (/^json$/) {
        eval "use JSON;1" or die "Can't load JSON library";
        print JSON->new->encode($table);
        last OUTPUT;
    }
    if (/^yaml$/) {
        eval "use YAML;1" or die "Can't load YAML library";
        print YAML::Dump($table);
        last OUTPUT;
    }
}

sub check_date {
    my ($name, $text, $dt) = @_;
    if ($text =~ /(\d{4})-(\d\d)-(\d\d)/) {
        $$dt = DateTime->new(
            year  => $1,
            month => $2,
            day   => $3,
        );
    } elsif ($text eq 'now') {
        $$dt = DateTime->now;
    } else {
        HELP_MESSAGE "wrong --$name <$text> format";
    }
    return;
}

sub HELP_MESSAGE(;$) {
    my $err_msg = shift;

    pod2usage({
            -msg     => "\n[ERROR]: $err_msg\n",
            -vebose  => 0,
            -exitval => 2,
        }
    ) if $err_msg;

    pod2usage({ -verbose => 2 });
}

__END__

=pod

=head1 NAME

schedule.pl - Print duty schedule table

=head1 SYNOPSIS

  schedule.pl -f <from date> -t <to date> -o <op list> --duties <duties> -out <tt|yaml|json|ascii> -h 
  schedule.pl -in <yaml|json> -out <tt|yaml|json|ascii> < schedule.json

  Options:
    -f from date
    -t to date
    -o comma separated operators list
    -d duties
    -out <tt=<template path>|yaml|json>
    -in <json|yaml>
    -h help

=head1 OPTIONS

=over 4

=item B<--from|-f>

Schedule start date in format YYYY-MM-DD or 'now', default now

=item B<--to|-t>

Schedule end date in format YYYY-MM-DD or +<num><d|w|m>, default +3weeks

=item B<---operators|-o>

Comma separated duty operators list, eg. -o ivanov,petrov,sidorov

=item B<--duties|-d>

Duties in format duty=days, eg.  -d Support=1,Release=2

=item B<--output|-out>

Choose output format <tt=<template path>|yaml|json>, default -out ascii

=item B<--input|-in>

Read inpout from stdin in format <json|yaml>, insted generation

=item B<--country_code|-cc>

Dtermine holidays via Date::Holidays
(specific country module must be installed)
                      
=item B<--today>

Day to pass to template as 'today' in format YYYY-MM-DD, default today

=item B<-h>

This message

=back

=head1 DESCRIPTION

B<scheduel.pl> is program to to generate and draw duty schedule table in several formats

  $ perl scripts/schedule.pl -o Mike,John,Bob -out ascii -f 2018-08-13 -t +7d -d "support=1,tasks=2"

  .-------------------------------------------------------------------------------.
  | Month/Day |  Aug/13 |  Aug/14 |  Aug/15 |  Aug/16 |  Aug/17 | Aug/18 | Aug/19 |
  +-----------+---------+---------+---------+---------+---------+--------+--------+
  | Mike      | support |         | support |         | tasks   |        |        |
  | John      | tasks   | tasks   |         | support |         |        |        |
  | Bob       |         | support | tasks   | tasks   | support |        |        |
  '-----------+---------+---------+---------+---------+---------+--------+--------'

=head1 AUTHOR

Mike Pruzhanskiy <pru.mike@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2018 Mike Pruzhanskiy <pru.mike@gmail.com>

This is free software; you can redistribute it and/or modify it under the same terms 
as the Perl 5 programming language system itself.

=head1 SEE ALSO

L<App::Schedule::Generate>

=cut

