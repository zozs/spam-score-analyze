#!/usr/bin/env perl

use strict;
use warnings;
use v5.10;

use DateTime;
use DateTime::Format::Strptime;
use JSON::MaybeXS qw(encode_json decode_json);
use Text::TabularDisplay;

# The purpose of this file is to take the aggreggated data from procure_logs,
# and present a neat looking ascii table with relevant information.
# As input, we expect either the filename of the procured data, or the same
# data sent to stdin. Note that data analysis is not performed until stdin
# is closed.

main();

sub main {
    my $json = join("", <>);
    my $stats = decode_json($json);

    spam_destinations($stats);
    stats_per_month($stats);
}

sub spam_destinations {
    my ($stats) = @_;
    my $destinations = $stats->{destinations};

    # For each destination that has received spam, sort by received spams.
    my $tb = Text::TabularDisplay->new;
    $tb->columns('Destination', 'Spam', 'Ham');

    for my $destination (sort { ($destinations->{$a}->{spam} // 0 ) <=> ($destinations->{$b}->{spam} // 0) } keys %$destinations) {
        next unless $destinations->{$destination}->{spam};
        $tb->add($destination, $destinations->{$destination}->{spam}, $destinations->{$destination}->{ham} // 0);
    }
    say $tb->render;
}

sub stats_per_month {
    my ($stats) = @_;

    my $tb = Text::TabularDisplay->new;
    $tb->columns('', 'True positive', 'True negative', 'False positive', 'False negative', 'Discarded', 'FNR', 'Discard rate');
    foreach my $ym (sort keys %{$stats->{yearmonth}}) {
        my %div = %{$stats->{yearmonth}->{$ym}};
        my $fnr = sprintf("%6.2f %%", $div{slt} / ($div{slt} + $div{sge}) * 100);
        my $dr = sprintf("%6.2f %%", $div{discarded} / ($div{sge} + $div{slt}) * 100);
        $tb->add(($ym, $div{sge}, $div{hlt}, $div{hge}, $div{slt}, $div{discarded}, $fnr, $dr));
    }
    say $tb->render;
}
