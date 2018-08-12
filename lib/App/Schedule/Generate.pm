package App::Schedule::Generate;

use strict;
use warnings;
use feature qw/state/;

use DateTime;
use Carp q/croak/;
use List::Util qw/pairmap/;
use Template;

our $VERSION = "0.1";

use Class::Accessor::Fast qw/moose-like/;

has fdt => (is => 'ro', isa => 'DateTime');
has tdt => (is => 'ro', isa => 'DateTime');

use constant {
    MON => 1,
    TUE => 2,
    WED => 3,
    THU => 4,
    FRI => 5,
    SAT => 6,
    SUN => 7,
};

use constant {
    DUTY_DAYS  => 0,
    DUTY_OPS   => 1,
    CURRENT_OP => 0,
    WORKDAY    => 0,
    HOLIDAY    => 1,
    ON         => 1,
    OFF        => 0,
};

our @TT_PARAMS = (ABSOLUTE => 1, RELATIVE => 1);

sub new {
    my $class = shift;
    my $p     = shift;

    for (qw/from_date to_date/) {
        croak "Missing required parameter '$_'" unless ($p->{$_});
    }
    if ($p->{holidays} and ref($p->{holidays}) ne 'HASH') {
        croak 'Bad $p->{holidays} parameter, must be hashref';
    }

    my %weekend_conf;
    if ($p->{holidays}) {
        for (qw/or_weekend no_weekend/) {
            if (exists $p->{holidays}{$_}) {
                $weekend_conf{$_} = delete $p->{holidays}{$_};
            }
        }
    }
    if ($p->{holidays}) {
        if (not _load_lib('Date::Holidays', 0)) {
            warn 'Date::Holidays not installed, but holidays is configured';
            delete $p->{holidays};
        }
    }
    if ($p->{holidays} and !grep(exists $p->{holidays}{$_}, qw/countries state regions/)) {
        warn '$p->{holidays} do not properly configured, countries or state or regions should be defined';
        delete $p->{holidays};
    }

    if (not $p->{duties} or ref($p->{duties}) ne 'ARRAY') {
        croak 'duties not defined';
    } else {
        if (@{ $p->{duties} } % 2 == 1) {
            croak 'duties MUST be even sized array in <duty => days> format';
        } else {
            $p->{duties} = [pairmap { [$a => $b] } @{ $p->{duties} }];
        }
    }

    my $self = {
        fdt           => delete $p->{from_date},
        tdt           => delete $p->{to_date},
        holidays_conf => delete $p->{holidays},
        %weekend_conf,
        head => [[Month => 'month_abbr'], [Day => 'day'], [Wday => 'day_abbr'],],
        duties             => delete $p->{duties},
        operators          => delete $p->{operators},
        duties_at_holidays => {},
        duties_at_workdays => {},
        %{$p}
    };
    bless $self, $class;
}

sub make_schedule {
    my $self = shift;
    my @schedule;
    push @schedule, @{ $self->_make_head() };
    push @schedule, @{ $self->_make_body() };
    return \@schedule;
}

sub _make_head {
    my $self = shift;
    [map { [$_->[0], _datetime_method($_->[1] => $self->fdt, $self->tdt)] } @{ $self->{head} }];
}

sub _is_holiday {
    my $self        = shift;
    my $dt          = shift;
    my $is_weekends = _check_weekend($dt);
    if ($self->{holidays_conf}) {
        my $is_holiday = _check_by_date_holidays($dt, $self->{holidays_conf});
        if ($self->{or_weekend}) {
            return $is_weekends || $is_holiday;
        } elsif ($self->{no_weekend}) {
            return $is_weekends ? 0 : $is_holiday;
        } else {
            return $is_holiday;
        }
    } elsif ($self->{no_weekend}) {
        return 0;
    } else {
        return $is_weekends;
    }
}

sub _check_by_date_holidays {
    my ($dt, $conf) = @_;
    my $is_russian_holidays = 0;
    if (grep(/^ru$/i, @{ $conf->{countries} })) {
        _load_lib('Date::Holidays::RU');
        $is_russian_holidays = !Date::Holidays::RU::is_business_day(map { $dt->$_ } qw/year month day/);
        if (1 == @{ $conf->{countries} }) {
            return $is_russian_holidays ? 1 : 0;
        }
    }

    my $holidays = Date::Holidays->is_holiday(%{$conf}, map { $_ => $dt->$_ } qw/year day month/,) || {};

    return grep ($_, values %$holidays) || $is_russian_holidays;
}

sub _check_weekend {
    my $dt = shift;
    grep($dt->day_of_week == $_, SAT, SUN) ? 1 : 0;
}

sub _datetime_method {
    my ($m, $f, $t) = @_;
    my @res;
    for (my $f = $f->clone; $f < $t; $f->add(days => 1)) {
        push @res, $f->$m;
    }
    return @res;
}

sub _rotate {
    my $list = shift;
    push @{$list}, shift @{$list};
}

sub _make_body {
    my $self      = shift;
    my $duties    = $self->{duties} || croak '$duties not defined';
    my $operators = $self->{operators} || croak '$operators not defined';
    croak '$duties is empty'    unless (@$duties);
    croak '$operators is empty' unless (@$operators);

    for (@$duties) {
        die "Wrong duties format [@$_], must be ['duties name' => 'duties days']" if (@$_ != 2);
        die "Wrong duties format [@$_], 'duties days' must be positive]" if ($_->[1] < 0);
    }

    my $table = [];
    for (my $i = 0; $i < @$operators; $i++) {
        push @{ $table->[$i] }, $operators->[$i];
    }

    my $duty_queue    = {};
    my @operators_tmp = @$operators;
    for (@$duties) {
        my ($m, $dd) = ($_->[0], $_->[1]);
        $duty_queue->{$m} = [$dd, [@operators_tmp]];
        _rotate(\@operators_tmp);
    }

    my $duty_by_holidays = {};
    for my $d (@$duties) {
        $duty_by_holidays->{ $d->[0] }[WORKDAY] = ON;
        $duty_by_holidays->{ $d->[0] }[HOLIDAY] = OFF;
    }
    for (qw/workdays holidays/) {
        my $h = qq[duties_at_${_}];
        my $v = /workdays/ ? 0 : 1;
        for my $d (keys %{ $self->{$h} }) {
            $duty_by_holidays->{$d}[$v] = $self->{$h}{$d};
        }
    }

    for (my $f = $self->fdt->clone; $f < $self->tdt; $f->add(days => 1)) {

        my $is_holiday = $self->_is_holiday($f);

      OP: for (my $i = 0; $i < @$operators; $i++) {
            my $op = $operators->[$i];

            for my $d (keys %$duty_queue) {
                unless ($duty_by_holidays->{$d}[$is_holiday]) {
                    next;
                }
                if ($duty_queue->{$d}[DUTY_OPS][CURRENT_OP] eq $op) {
                    push @{ $table->[$i] }, $d;
                    $duty_queue->{$d}[DUTY_DAYS]--;
                    next OP;
                }
            }
            push @{ $table->[$i] }, '';
        }

        for my $d (keys %$duty_queue) {
            unless ($duty_queue->{$d}[DUTY_DAYS]) {
                _rotate($duty_queue->{$d}[DUTY_OPS]);
                my $op = $duty_queue->{$d}[DUTY_OPS][CURRENT_OP];
                for (keys %$duty_queue) {
                    unless ($duty_by_holidays->{$_}[$is_holiday]) {
                        next;
                    }
                    if ($duty_queue->{$_}[DUTY_DAYS] and $op eq $duty_queue->{$_}[DUTY_OPS][CURRENT_OP]) {
                        _rotate($duty_queue->{$d}[DUTY_OPS]);
                    }
                }
                $duty_queue->{$d}[DUTY_DAYS] = (grep { $d eq $_->[0] } @$duties)[0][1];
            }
        }
    }

    return $table;
}

sub draw_tt {
    my $class    = shift;
    my $template = shift || croak 'Template not defined';
    my $table    = shift || croak 'table not defined';
    my $vars     = shift || {};
    my $tt       = Template->new(@TT_PARAMS);
    my $output;
    $tt->process($template, { %$vars, table => $table }, \$output) || croak $tt->error();
    $output;
}

sub draw_ascii {
    my $class = shift;
    my $table = shift || croak 'table not defined';
    my $args  = shift || {};
    _load_lib('Text::ASCIITable');
    my $t = Text::ASCIITable->new({ alignHeadRow => 'center', %$args });
    $t->setCols([map { join '/', $table->[0][$_], $table->[1][$_] } 0 .. $#{ $table->[0] }]);
    $t->addRow(@{ $table->[$_] }) for 3 .. $#{$table};
    "$t";
}

sub _load_lib {
    my $lib = shift;
    my $required = shift // 1;
    state $cache = {};
    $cache->{$lib} = eval "use $lib;1" if not exists $cache->{$lib};
    !$cache->{$lib} and $required and die "Can't load $lib library";
    $cache->{$lib};
}

sub load {
    my $class = shift;
    my $input = shift;
    my $data  = shift;
    my $table;
  INPUT:
    for ($input) {
        if (/^json$/) {
            _load_lib('JSON');
            $table = JSON->new->decode($data);
            last INPUT;
        }
        if (/^yaml$/) {
            _load_lib('YAML');
            $table = YAML::Load($data);
            last INPUT;
        }
    }
    return $table;
}

sub find_in_table {
    my $class = shift;
    my $dt    = shift || croak 'DateTime not defined';
    my $table = shift || croak 'Table not defined';
    my ($mon, $day) = ($dt->month_abbr, $dt->day);

    my (@col, $col, $op);
    for (my $i = 1; $i < @{ $table->[0] }; $i++) {
        push @col, $i if $table->[0][$i] eq $mon;
    }
    for (@col) {
        if ($table->[1][$_] == $day) {
            $col = $_;
            last;
        }
    }
    unless ($col) {
        return;
    }

    for (my $i = 3; $i < @$table; $i++) {
        if ($table->[$i][$col]) {
            $op = $table->[$i][0];
            last;
        }
    }
    unless ($op) {
        return;
    }
    return ($op, $col);
}

1;

__END__

=pod

=head1 NAME

App::Schedule::Generate - Simple schedule table generator

=head1 SYNOPSIS

  use App::Schedule::Generate;

  my $app = App::Schedule::Generate->new({
      from_date => DateTime->now,
      to_date => DateTime->now->add(weeks => 1),
      duties => ['carry ring' => 1, 'find food' => 1],
      operators => [qw/Frodo Sam Golum/],
  });

  my $table = $app->make_schedule();
  print App::Schedule::Generate->draw_ascii($table);

=head1 DESCRIPTION

Simple module to generate and draw duty schedule table, looking like:

  .-------------------------------------------------------------------------------.
  | Month/Day |  Aug/13 |  Aug/14 |  Aug/15 |  Aug/16 |  Aug/17 | Aug/18 | Aug/19 |
  +-----------+---------+---------+---------+---------+---------+--------+--------+
  | Mike      | support |         | support |         | tasks   |        |        |
  | John      | tasks   | tasks   |         | support |         |        |        |
  | Bob       |         | support | tasks   | tasks   | support |        |        |
  '-----------+---------+---------+---------+---------+---------+--------+--------'

=head1 Methods

=head2 new($href)

Define schedule parameters

=head3 Required

=over 4

=item from_date => Date::Time

Schedule start date

=item to_date => Date::Time

Schedule end date

=item duties => $arrayref

Even sized duities list in format B<duty =E<gt> days>, e.g.

  duties => [support => 1, tasks => 2]

=item operators => $arrayref

Operators list, e.g.

  operators => [qw/Mike John Bob/]

=back

=head3 Optional

=over 4

=item holidays => $hashref

Configure holidays

  holidays => {
      or_weekend => 1,
      countries  => 'ru'
  }

  holidays => {
      no_weekend => 0,
      countries  => 'us'
      state      => ...
  }

=back

=over 8

=item or_weekend

Weekend is holiday

=item no_weekend

Weekend is no holiday

=item countries or state or regions

Define holidays via L<Date::Holidays> module.

=back

=head2 make_schedule()

  $table = $app->make_schedule()

Return hashref table with schedule in format:

=head2 draw_tt($tt,$table,$args)

  $output = App::Schedule::Generate->draw_tt($tt,$table,{});

Draw table B<$table> via template <$tt>

=head2 draw_ascii($table,$args)

  $output = App::Schedule::Generate->draw_ascii($table);

Draw table B<$table> via L<Text::ASCIITable>
L<Text::ASCIITable> module must be installed;

=head2 load($input,$data)

  $input = 'json'; # yaml
  $table = App::Schedule::Generate->load($input => $data);

Conversion beetwen yaml or json to perl data
Relevant module (JSON,YAML) must be installed

=head2 find_in_table($date_time,$table)

  $date = Date::Time->now;
  ($operator, $column) = App::Schedule::Generate->find_in_table($date,$table);

Find current operator on presented day in schedule table.

=head1 AUTHOR

Mike Pruzhanskiy <pru.mike@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2018 Mike Pruzhanskiy <pru.mike@gmail.com>

This is free software; you can redistribute it and/or modify it under the same terms 
as the Perl 5 programming language system itself.

=cut

