#!/usr/bin/env perl

use strict;
use warnings;
use v5.10;

use DateTime;
use DateTime::Format::Strptime;
use JSON::MaybeXS qw(encode_json decode_json);

# The purpose of this file is to take the logs from the destdir of log_handler
# and then scan it to procure some output which is the summarized statistics.
# The idea is then that these stats can be presented by different frontends.
# This is essentially the old score.pl script, but slightly reworked and
# (hopefully) somewhat more elegant.

# the directories where mail logs and actual mails are stored.
# for maildir, assume "maildir" format for mail storage.
my $logdir = "/root/.spamscoreanalyze/logs";
my $maildir = "/var/vmail/linus";

# the mail folders that we should treat as spam or ham respectively.
# other folders are ignored.
my @ham_dirs = qw(. .Reports .Social .Archive .Archive.2018 .Archive.2019);
my @spam_dirs = qw(.Junk);

# the domains that we care about (used to determine valid Delivered-To headers)
# 1 is not important.
my %domains = (
    'linuskarlsson.se' => 1,
    'imaginar.se' => 1,
    'cryptosec.se' => 1,
    'zozs.se' => 1,
    'labqueue.com' => 1,
    'labqueue.org' => 1,
);

# the output file where to store procured data (single file)
my $destfile =  "/var/www/htdocs/spamstats/spamstats.json";

# the score that your imap server/sieve is configured to treat as spam,
# as well as the score which we consider as discard.
my $required_score = 4.0;
my $discard_score = 10.0;
my $not_discard_before = DateTime->new(
    year => 2018,
    month => 8,
    day => 30,
    hour => 18,
    minute => 40,
    second => 30
);
# Why?
# Ugly hack incoming:
# Before this e-mail in 2018, no e-mails were discarded regardless of score,
# so add a specific check for this later on when the date above is needed.
# Aug 30 18:40:31 imap spampd[47664]: identified spam <E4CA5DC67C47D42E541F57DD9AE0B5D5@gtwadncdx.net> (16.59/4.00) from <bkxmsoab@gtwadncdx.net> for <user.domain> in 1.28s, 7093 bytes.

# constants
my $IS_HAM = 0;
my $IS_SPAM = 1;

main();

sub aggregate_stats {
    my (@mails) = @_;

    # Start by grouping stats per month.
    my $grouped_mails = group_by_yearmonth(@mails);

    my @yearmonths;
    foreach my $yearmonth (sort keys %{$grouped_mails}) {
        # for each yearmonth, start by partition into spam and ham and count discards.
        my $part = partition($required_score, $grouped_mails->{$yearmonth});
        $part->{yearmonth} = $yearmonth;
        push @yearmonths, $part;
    }

    # Then count destination address by checking Delivered-To headers.
    # Count spam and ham separately.
    my $destinations = {};
    for my $mail (@mails) {
        my $class = $mail->{spam} ? "spam" : "ham";
        for my $destination (@{$mail->{delivered}}) {
            $destinations->{$destination}->{$class}++;
            $destinations->{$destination}->{email} = $destination;
        }
    }

    # Convert hash to array instead, since it is a more elegant JSON representation.
    my @destination_array = map { $destinations->{$_} } keys %$destinations;

    return {
        'yearmonths' => \@yearmonths,
        'destinations' => \@destination_array
    }
}

sub analyse_log {
    my ($path, $file) = @_;

    my $fh;
    if ($file =~ /.gz$/) {
        # if file ends with .gz, we load it through zcat to decompress on the fly.
        open $fh, "zcat $path |" or die "Cannot open logfile at $path (zcat)\n";
    } else {
        open $fh, "<", $path or die "Cannot open logfile at $path\n";
    }

    # Go through log entries and find spam score. Assume syslogd is running with -Z switch so it
    # prints log messages using ISO 8601. If it isn't, fall back to MMM DD numbering and assume
    # year of 2018.
    my @mails;
    while (<$fh>) {
        if (/identified spam (?:<\S*>|\(unknown\)) \((?<score>\d+\.\d+)\/\d+\.\d+\) from <\S*> for <(?<destination>\S+)>/) {
            my $score = $+{score};
            # one line can contain multiple destinations.
            my @destinations = split('>,<', $+{destination});
            if ($score >= $discard_score) {
                # Discarded spam message because score is high!
                my $datetime;
                if (/^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})T/) {
                    $datetime = DateTime->new(
                        year => $+{year},
                        month => $+{month},
                        day => $+{day}
                    );
                } elsif (/^(?<bsddate>\w+  ?\d+) (?<time>\d{2}:\d{2}:\d{2})/) {
                    my $parser = DateTime::Format::Strptime->new(pattern => '%B %d %Y %H:%M:%S');
                    $datetime = $parser->parse_datetime($+{bsddate} . " 2018 " . $+{time}); # certain old logs did not have year.
                }

                if (!$datetime) {
                    say "Parsing of date failed for line: ";
                    say;
                } elsif ($datetime < $not_discard_before) {
                    # ignored due to before discarding was enabled.
                } else {
                    foreach my $destination (@destinations) {
                        push @mails, {
                            score => $score,
                            spam => 1,
                            delivered => [$destination],
                            discarded => 1,
                            datetime => $datetime,
                            yearmonth => substr $datetime->date, 0, 7
                        };
                    }
                }
            }
        }
    }

    return @mails;
}

sub analyse_logs {
    my ($logdir) = @_;

    opendir(DIR, "$logdir") or die "Cannot open $logdir\n";
    my @files = readdir(DIR);
    closedir(DIR);

    my @mails;
    foreach my $file (@files) {
        next if $file =~ /^\.\.?$/;  # skip . and .. directories
        my $filepath = "$logdir/$file";
        push @mails, analyse_log($filepath, $file);
    }

    return @mails;
}

sub analyse_mail {
    my ($filepath, $file, $is_spam) = @_;
    open(my $fh, "<", $filepath) or die "Cannot open $filepath\n";
    my $found_delivered = 0;
    my $found_scores = 0;
    my @delivered;
    my $score;
    my $datetime;

    # Go through headers and find spam score and 
    while (<$fh>) {
        if (/^X-Spam-Status: (?:Yes|No), score=(?<score>-?\d+\.\d+) /) {
            $found_scores++;
            $score = $+{score};
        }
        if (/^Delivered-To: (?<user>\S+)@(?<domain>\S+)/) {
            # check so that we only pick out supported domains here.
            # this useful since some e-mails have multiple headers, e.g. mailing lists
            if (exists($domains{$+{domain}})) {
                $found_delivered++;
                push @delivered, $+{user} . "@" . $+{domain};
            } else {
                # DEBUG: 
                #say "Found Delivered-To but ignored due to unknown domain: " . $+{domain};
            }
        }
    }
    close($fh);

    # Parse UNIX timestamp in filename and convert to ISO-8859-1 date.
    if (my ($epoch) = $file =~ /^(\d+)\.M/) {
        $datetime = DateTime->from_epoch(epoch => $epoch);
    } else {
        say "File: $filepath does not have a timestamp.";
        return {};
    }

    if ($found_scores == 0) {
        #say "File: $filepath has no spam score.";
        return {};
    }

    if ($found_scores > 1) {
        say "File: $filepath has $found_scores spam scores.";
        return {};
    }

    if ($found_delivered != 1) {
        say "File: $filepath has $found_delivered Delivered-To headers.";
    }

    return {
        score => $score,
        spam => $is_spam,
        discarded => 0,
        delivered => \@delivered,
        datetime => $datetime,
        filename => $file,
        yearmonth => substr $datetime->date, 0, 7
    }
}

sub analyse_mails {
    my ($is_spam, @dirs) = @_;
    my @scores;
    my $no_score = 0;

    # for each directory that we look at
    while (my $pwd = shift @dirs) {
        my $dirpath = "$maildir/$pwd/cur";
        opendir(DIR, "$dirpath") or die "Cannot open $dirpath\n";
        my @files = readdir(DIR);
        closedir(DIR);

        foreach my $file (@files) {
            next if $file =~ /^\.\.?$/;  # skip . and .. directories.
            my $filepath = "$dirpath/$file";

            my $mail = analyse_mail($filepath, $file, $is_spam);
            if (%{$mail}) {
                # if mail could be parsed and had spam score.
                push @scores, $mail;
            } else {
                # no spam score found.
                $no_score++;
            }
        }
    }

    return ($no_score, @scores);
}

sub group_by_yearmonth {
    # Returns a new hashref with entries grouped by their year-month value.
    my (@array) = @_;
    my %grouped;
    foreach my $mail (@array) {
        push @{$grouped{$mail->{yearmonth}}}, $mail;
    }
    $grouped{Total} = \@array;

    return \%grouped;
}

sub output_stats {
    my ($stats, $destfile) = @_;

    # serialize to json string.
    my $json = encode_json($stats);

    # write json string to file.
    open(my $fh, '>', $destfile);
    print $fh $json;
    close($fh);
}

sub partition {
    # Returns four counts, number of values less than threshold, and number of values
    # greater than or equal to the threshold for spam and hams respectively.
    # Also count number of discarded mails as "discarded"
    my ($threshold, $array) = @_;
    my %div = (slt => 0, hlt => 0, sge => 0, hge => 0, discarded => 0);
    foreach my $mail (@{$array}) {
        if ($mail->{score} < $threshold) {
            if ($mail->{spam}) {
                $div{slt}++;  # false negative
            } else {
                $div{hlt}++;  # true negative
            }
        } else {
            if ($mail->{spam}) {
                $div{sge}++;  # true positive
            } else {
                $div{hge}++;  # false positive
                say "False positive: " . $mail->{filename};
            }
        }

        if ($mail->{discarded}) {
            $div{discarded}++;
        }
    }

    return \%div;
}

sub main {
    # Start by parsing the contents of spam folders.
    my ($no_spam_score, @spam_mails) = analyse_mails($IS_SPAM, @spam_dirs);

    # Then analyse the ham folders.
    my ($no_ham_score, @ham_mails) = analyse_mails($IS_HAM, @ham_dirs);

    # Then analyse discard counts by parsing mail logs.
    my @discard_mails = analyse_logs($logdir);

    # Derive procured data (i.e. the statistics)
    my @mails = (@spam_mails, @ham_mails, @discard_mails);
    my $stats = aggregate_stats(@mails);

    # Serialize stats as JSON object.
    output_stats($stats, $destfile);

    # TODO: add verbose flag for debugging?
    say "Spam discarded before delivery: " . scalar @discard_mails;
    say "Spam: no score: $no_spam_score, has score: " . scalar @spam_mails;
    say "Ham: no score: $no_ham_score, has score: " . scalar @ham_mails;
}
