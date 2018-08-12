#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw/$Bin/;
use lib qq[$Bin/../lib];
use Test::More tests => 17;
use Test::Deep;
use Data::Dumper;
use App::Schedule::Generate;

my ($res, $case, $date, $self);

my $is_date_holidays_installed = eval "require Date::Holidays;1;";

SKIP: {

    skip 'Date::Holidays not installed', 17 unless $is_date_holidays_installed;

    $case = q[Russian workday];
    $date = DateTime->new(year => '2018', month => '08', day => '01');
    $res  = App::Schedule::Generate::_check_by_date_holidays($date, { countries => ['ru'] });
    is(App::Schedule::Generate::_check_weekend($date), 0, "_check_weekend $case");
    is($res,                                           0, "_check_by_date_holidays $case");

    $case = q[Russian weekend];
    $date = DateTime->new(year => '2018', month => '08', day => '04');
    $res  = App::Schedule::Generate::_check_by_date_holidays($date, { countries => ['ru'] });
    is(App::Schedule::Generate::_check_weekend($date), 1, "_check_weekend $case");
    is($res,                                           1, "_check_by_date_holidays $case");

    $case = q[Russian weekend but business day];
    $date = DateTime->new(year => 2018, month => 6, day => 9);
    $res  = App::Schedule::Generate::_check_by_date_holidays($date, { countries => ['ru'] });
    is(App::Schedule::Generate::_check_weekend($date), 1, "_check_weekend $case");
    is($res,                                           0, "_check_by_date_holidays $case");

    $case = q[France holiday];
    $date = DateTime->new(year => 2018, month => 8, day => 15);
    $res  = App::Schedule::Generate::_check_by_date_holidays($date, { countries => ['fr'] });
    is(App::Schedule::Generate::_check_weekend($date), 0, "_check_weekend $case");
    is($res,                                           1, "_check_by_date_holidays $case");

    $case = q[France workday];
    $date = DateTime->new(year => 2018, month => 8, day => 16);
    $res  = App::Schedule::Generate::_check_by_date_holidays($date, { countries => ['fr'] });
    is(App::Schedule::Generate::_check_weekend($date), 0, "_check_weekend $case");
    is($res,                                           0, "_check_by_date_holidays $case");

    $case = q[France weekend];
    $date = DateTime->new(year => 2018, month => 8, day => 18);
    $res  = App::Schedule::Generate::_check_by_date_holidays($date, { countries => ["fr"] });
    is(App::Schedule::Generate::_check_weekend($date), 1, "_check_weekend $case");
    is($res,                                           0, "_check_by_date_holidays $case");

    $case = q[France weekend];
    $self = {};
    $date = DateTime->new(year => 2018, month => 8, day => 18);
    $res  = App::Schedule::Generate::_is_holiday($self, $date);
    is($res, 1, "_is_holiday $case");

    $case = q[France weekend + no_weekend];
    $self = { no_weekend => 1 };
    $date = DateTime->new(year => 2018, month => 8, day => 18);
    $res  = App::Schedule::Generate::_is_holiday($self, $date);
    is($res, 0, "_is_holiday $case");

    $case = q[France holiday];
    $date = DateTime->new(year => 2018, month => 8, day => 15);
    $self = { holidays_conf => { countries => ['fr'] } };
    $res  = App::Schedule::Generate::_is_holiday($self, $date);
    is($res, 1, "_is_holiday $case");

    $case = q[France weekend];
    $date = DateTime->new(year => 2018, month => 8, day => 19);
    $self = { holidays_conf => { countries => ['fr'] } };
    $res  = App::Schedule::Generate::_is_holiday($self, $date);
    is($res, 0, "_is_holiday $case");

    $case = q[France weekend + or_weekend];
    $date = DateTime->new(year => 2018, month => 8, day => 19);
    $self = {
        holidays_conf => { countries => ['fr'] },
        or_weekend    => 1,
    };
    $res = App::Schedule::Generate::_is_holiday($self, $date);
    is($res, 1, "_is_holiday $case");

}
