#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use App::Schedule::Generate;
use LWP::UserAgent;
use URL::Encode qw/url_encode/;

our @TT_PARAMS = (ABSOLUTE => 1, RELATIVE => 1);

sub HELP_MESSAGE(;$);

my $tt = q[templates/slack.tt];
my ($h, $url, $input, $dump, $date, $link, $title);
my @inputs = qw/json yaml/;
my $dt = DateTime->now();

GetOptions(
    "input|in=s"    => \$input,
    "dump|d"        => \$dump,
    "url|u=s"       => \$url,
    "tempalte|tt=s" => \$tt,
    "help|h"        => \$h,
    "date=s"        => \$date,
    "link|l=s"      => \$link,
    "title|t=s"     => \$title,
);
HELP_MESSAGE() if $h;
HELP_MESSAGE "URL not defined"          unless $url;
HELP_MESSAGE "Input format not defined" unless $input;
HELP_MESSAGE "Template not defined"     unless -f $tt;

if ($date) {
    if ($date =~ /(\d{4})-(\d\d)-(\d\d)/) {
        $dt = DateTime->new(
            year  => $1,
            month => $2,
            day   => $3,
        );
    } else {
        HELP_MESSAGE "wrong --date <date> format";
    }
}

my $data = do { local $/; <> };
my $table = App::Schedule::Generate->load($input => $data);

HELP_MESSAGE "Bad input [$input], MUST be one of {@inputs}" unless $table;

send_slack_notification($tt, $dt, $url, $table, $dump);

sub send_slack_notification {
    my ($tt, $dt, $slack_webhook_url, $table, $dump) = @_;

    my ($op) = App::Schedule::Generate->find_in_table($dt, $table);
    unless ($op) {
        warn "No one is on duty at $dt\n";
        return;
    }

    my $content;
    my $template = Template->new(@TT_PARAMS);
    $template->process($tt, { op => lc($op) }, \$content) || die $template->error();

    my $ua  = LWP::UserAgent->new();
    my $req = HTTP::Request->new(
        POST => $slack_webhook_url,
        ['Content-Type' => 'application/x-www-form-urlencoded'],
        'payload=' . url_encode($content)
    );
    if ($dump) {
        print " ================ message ================\n";
        print $content;
        print " ============= http request ==============\n";
        print $req->as_string;
        print " =========================================\n";
    } else {
        my $res = $ua->request($req);
        unless ($res->is_success) {
            warn 'Request failed: ', $res->status_line, "\n";
        }
    }
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

send_to_slack.pl - Find today operator and send to slack

=head1 SYNOPSIS

  send_to_slack.pl -u <url> -in <yaml|json> -h < schedule.json

=head1 OPTIONS

=over 4

=item B<--url|-u>

Slack webhook url

=item B<--template|-tt>

Slack json message template, default templates/slack.tt

=item B<--input|-in>

Input message format, one of json, yaml

=item B<--dump|-d>

Dump message to stdout insted of POST to slack

=item B<--link|-l>

Pass to template link to schedule

=item B<--title|-t>

Pass to template message title 

=item B<-h>

This message

=back

=head1 AUTHOR

Mike Pruzhanskiy <pru.mike@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2018 Mike Pruzhanskiy <pru.mike@gmail.com>

This is free software; you can redistribute it and/or modify it under the same terms 
as the Perl 5 programming language system itself.

=head1 SEE ALSO

L<App::Schedule::Generate>, B<schedule.pl>

=cut

