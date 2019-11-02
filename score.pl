#!/usr/bin/env perl

use warnings;
use strict;

use DateTime;
use DateTime::Format::Strptime;
use Text::TabularDisplay;

my $mail_dir = "linus";
my @ham_dirs = qw(. .Reports .Social .Archive .Archive.2018 .Archive.2019);
my @spam_dirs = qw(.Junk);
my $maillog_dir = "maillog";

if (scalar(@ARGV) != 1) {
    print "usage: score.pl <threshold>\n";
    exit 1;
}
my $required_score = $ARGV[0];

# First analyze spam.
my ($no_spam_score, @spam_mails) = analyze_dir(1, @spam_dirs);
my $has_spam_score = scalar @spam_mails;
print "Spam: no score: $no_spam_score, has score: $has_spam_score\n";

# Then ham.
my ($no_ham_score, @ham_mails) = analyze_dir(0, @ham_dirs);
my $has_ham_score = scalar @ham_mails;
print "Ham: no score: $no_ham_score, has score: $has_ham_score\n";

# Then count number of spams that have been discarded already in the sieve stage without delivery.
my (@discard_mails) = analyze_log_dir($maillog_dir);

print "Spam discarded before delivery: " . scalar(@discard_mails) . "\n";

my @mails = (@spam_mails, @ham_mails, @discard_mails);

# Now print statistics per month.
my $grouped_mails = group_by_yearmonth(@mails);

# TODO: add columns which shows what percentage of spams that are discarded before delivery.

my $tb2 = Text::TabularDisplay->new;
$tb2->columns(('', 'True positive', 'True negative', 'False positive', 'False negative', 'FNR', 'Discard rate'));
foreach my $ym (sort keys %{$grouped_mails}) {
    my %div = divide($required_score, @{$grouped_mails->{$ym}});
    my $fnr = sprintf("%6.2f %%", $div{slt} / ($div{slt} + $div{sge}) * 100);
    my $dr = sprintf("%6.2f %%", $div{discarded} / ($div{sge} + $div{slt}) * 100);
    $tb2->add(($ym, $div{sge}, $div{hlt}, $div{hge}, $div{slt}, $fnr, $dr));
}
print $tb2->render . "\n";

# TODO: fix better, this is just PoC
# Print the number of different spam destination addresses by counting Delivered-To headers.
# (currently this only counts non-discarded e-mails)
my %destinations;
for my $mail (@mails) {
    if ($mail->{spam}) {
        for my $destination (@{$mail->{delivered}}) {
            $destinations{$destination}++;
        }
    }
}

# Now walk through all mails again, this time counting the number of *ham* messages
# delivered to the spam-destinations above. This way we can get the distribution between
# spam and ham for certain destinations.
my %ham_destinations;
for my $mail (@mails) {
    if (!$mail->{spam}) {
        for my $destination (@{$mail->{delivered}}) {
            if (exists($destinations{$destination})) {
                $ham_destinations{$destination}++;
            }
        }
    }
}

print "Spam / Ham: destination address\n";
for my $destination (sort { $destinations{$a} <=> $destinations{$b} } keys %destinations) {
    print "$destinations{$destination} / " . ($ham_destinations{$destination} // 0) . ": $destination\n";
}

sub divide {
    # Returns four counts, number of values less than threshold, and number of values
    # greater than or equal to the threshold for spam and hams respectively.
    # Also count number of discarded mails as "discarded"
    my ($threshold, @array) = @_;
    my %div = (slt => 0, hlt => 0, sge => 0, hge => 0, discarded => 0);
    foreach my $mail (@array) {
        if ($mail->{score} < $threshold) {
            if ($mail->{spam}) {
                $div{slt}++;
            } else {
                $div{hlt}++;
            }
        } else {
            if ($mail->{spam}) {
                $div{sge}++;
            } else {
                $div{hge}++;
                print "False positive: " . $mail->{filename} . "\n";
            }
        }

        if ($mail->{discarded}) {
            $div{discarded}++;
        }
    }

    return %div;
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

sub analyze_dir {
    my ($is_spam, @dirs) = @_;
    my @scores;
    my $no_score = 0;
    while (my $pwd = shift @dirs) {
        my $fulldir = "$mail_dir/$pwd/cur";
        opendir(DIR, "$fulldir") or die "Cannot open $fulldir\n";
        my @files = readdir(DIR);
        closedir(DIR);

        foreach my $file (@files) {
            next if $file =~ /^\.\.?$/;
            my $path = "$fulldir/$file";
            
            my $mail = analyze_file($path, $file, $is_spam);
            if (%{$mail}) {
                push @scores, $mail;
            } else {
                $no_score++;
            }
        }
    }

    return ($no_score, @scores);
}

sub analyze_file {
    my ($path, $filename, $is_spam) = @_;
    open my $h, "<", $path or die "Cannot open $path\n";
    my $found_delivered = 0;
    my $found_scores = 0;
    my @delivered;
    my $score;
    my $datetime;

    # Go through headers and find spam score and 
    while (<$h>) {
        if (/^X-Spam-Status: (?:Yes|No), score=(?<score>-?\d+\.\d+) /) {
            $found_scores++;
            $score = $+{score};
        }
        if (/^Delivered-To: (?<user>\S+)@(?<domain>\S+)/) {
            # TODO: add check so that we only pick out supported domains here.
            $found_delivered++;
            push @delivered, $+{user} . "@" . $+{domain};
        }
    }

    # Parse UNIX timestamp in filename and convert to ISO-8859-1 date.
    if ($filename =~ /^(?<epoch>\d+)\.M/) {
        $datetime = DateTime->from_epoch(epoch => $+{epoch});
    } else {
        print "File: $path does not have a timestamp.\n";
        return {};
    }

    if ($found_scores != 1) {
        print "File: $path has $found_scores spam scores.\n";
        return {};
    }

    if ($found_delivered != 1) {
        print "File: $path has $found_delivered Delivered-To headers.\n";
    }

    return {
        score => $score,
        spam => $is_spam,
        discarded => 0,
        delivered => \@delivered,
        datetime => $datetime,
        filename => $filename,
        yearmonth => substr $datetime->date, 0, 7
    }
}

sub analyze_log_dir {
    my ($logdir) = @_;

    my @mails;
    opendir(DIR, "$logdir") or die "Cannot open $logdir\n";
    my @files = readdir(DIR);
    closedir(DIR);

    foreach my $file (@files) {
        next if $file =~ /^\.\.?$/;
        my $path = "$logdir/$file";
        push @mails, analyze_log_file($path, $file);
    }

    return @mails;
}

sub analyze_log_file {
    my ($path, $filename) = @_;
    my $h;
    if ($filename =~ /.gz$/) {
        open $h, "zcat $path |" or die "Cannot open $path piped through zcat\n";
    } else {
        open $h, "<", $path or die "Cannot open $path\n";
    }
    my @mails;

    # Go through log entries and find spam score. Assume syslogd is running with -Z switch so it
    # prints log messages using ISO 8601. If it isn't, fall back to MMM DD numbering and assume
    # year of 2018.
    while (<$h>) {
        # 2018-10-26T17:12:00.271Z imap spampd[55849]: identified spam <9bf701d46d3e$710eeaf0$9acf4af3@PaulWilson> (18.41/4.00) from <PaulWilson@pinebrook-farms.com> for <user@domain.se> in 3.07s, 11524 bytes.
        # TODO: look for this line instead and see if it matches the discard action count below :)
        
        if (/\(discard action\)$/) {
            # Discarded spam message because score is high!
            my $datetime;
            if (/^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})T/) {
                $datetime = DateTime->new(
                    year => $+{year},
                    month => $+{month},
                    day => $+{day}
                );
            } elsif (/^(?<bsddate>\w+  ?\d+) \d{2}:\d{2}:\d{2}/) {
                my $parser = DateTime::Format::Strptime->new(pattern => '%B %d %Y');
                $datetime = $parser->parse_datetime($+{bsddate} . " 2018");
            }

            if (!$datetime) {
                print "Parsing of date failed for line: ";
                print;
                print "\n";
            } else {
                push @mails, {
                    score => 10.0, # TODO: use real score instead of this threshold?
                    spam => 1,
                    delivered => [],
                    discarded => 1,
                    datetime => $datetime,
                    yearmonth => substr $datetime->date, 0, 7
                };
            }
        }
    }

    return @mails;
}
