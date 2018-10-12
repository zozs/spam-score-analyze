#!/usr/bin/env perl

use warnings;
use strict;

use DateTime;
use Text::Table;

my $mail_dir = "linus";
my @ham_dirs = qw(. .Reports .Social .Archive .Archive.2018);
my @spam_dirs = qw(.Junk);

if (scalar(@ARGV) != 1) {
    print "usage: score.pl <threshold>\n";
    exit 1;
}
my $required = $ARGV[0];

# First analyze spam.
my ($no_spam_score, @spam_scores) = analyze_dir(@spam_dirs);
my $has_spam_score = scalar @spam_scores;
print "Spam: no score: $no_spam_score, has score: $has_spam_score\n";

# Then ham.
my ($no_ham_score, @ham_scores) = analyze_dir(@ham_dirs);
my $has_ham_score = scalar @ham_scores;
print "Ham: no score: $no_ham_score, has score: $has_ham_score\n";

# First get number of mails below or above the threshold.
my ($slt, $sge) = divide($required, @spam_scores);
my ($hlt, $hge) = divide($required, @ham_scores);

# Calculate false negatives and false positives for a given threshold.
# Calculate FPR, FNR.
my $fpr = $hge / ($hlt + $hge);
my $fnr = $slt / ($slt + $sge);
my $tpr = $sge / ($slt + $sge);
my $tnr = $hlt / ($hlt + $hge);

# If you don't have Text::Table, you can use this instead for an uglier presentation.
#print "TPR: $tpr ($sge mails correctly classified as spam)\n";
#print "TNR: $tnr ($hlt mails correctly classified as ham)\n";
#print "FPR: $fpr ($hge mails incorrectly marked as spam)\n";
#print "FNR: $fnr ($slt mails missed by spam filter)\n";

my $tb = Text::Table->new("", 
    { title => "True spam", align => "right", align_title => "right" },
    { is_sep => 1, title => ' | ' },
    { title => "True ham", align => "right", align_title => "right" }
);
$tb->load(
    [ "Predicted spam", $sge, $hge ],
    [ "Predicted ham",  $slt, $hlt ],
);
print "\n";
foreach my $line ($tb->table) {
    print $line;
    print $tb->rule('-', '+');
}

sub divide {
    # Returns two counts, number of values less than threshold, and number of values
    # greater than or equal to the threshold.
    my ($threshold, @array) = @_;
    my $lt = 0;
    my $ge = 0;
    foreach my $mail (@array) {
        if ($mail->{score} < $threshold) {
            $lt++;
        } else {
            $ge++;
        }
    }
    return ($lt, $ge);
}

sub analyze_dir {
    my (@dirs) = @_;
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
            
            my $mail = analyze_file($path, $file);
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
    my ($path, $filename) = @_;
    open my $h, "<", $path or die "Cannot open $path\n";
    my $found = 0;
    my $score;
    my $datetime;

    # Go through headers and find spam score.
    while (<$h>) {
        if (/^X-Spam-Status: (?:Yes|No), score=(?<score>-?\d+\.\d+) /) {
            $found++;
            $score = $+{score};
        }
    }

    # Parse UNIX timestamp in filename and convert to ISO-8859-1 date.
    if ($filename =~ /^(?<epoch>\d+)\.M/) {
        $datetime = DateTime->from_epoch(epoch => $+{epoch});
    } else {
        print "File: $path does not have a timestamp.\n";
        return {};
    }

    if ($found == 0) {
        print "File: $path does not have a spam score.\n";
        return {};
    } elsif ($found > 1) {
        print "File: $path has multiple spam scores!\n";
        return {};
    }

    return {
        score => $score,
        datetime => $datetime,
        yearmonth => substr $datetime->date, 0, 7
    }
}
