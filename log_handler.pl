#!/usr/bin/env perl

# The purpose of this application is to maintain the logs/ directory used when analysing discarded
# emails. The application reads /var/log/maillog *including* its rotated logs (maillog.2.gz), and
# checks if we already have such a log-gzip-bundle in our local cached directory. If we do, we don't
# copy it over, otherwise we do.
# The /var/log/maillog must be handled separately, since it is not constant like the other files,
# thus we always copy the latest version and use it as-is.

use strict;
use warnings;
use v5.10;

use Digest::SHA;
use File::Copy;
use File::Path qw(make_path);
use IO::Zlib;

# The destination where we'll store cached copies of all logs.
my $destdir = "/root/.spamscoreanalyze/logs";

# The source dir where we look for logs (typically /var/log)
my $sourcedir = "/var/log";

main();

sub main {
    # start with creating the destination directory if it does not exist.
    make_path($destdir, { mode => 0770 });

    # first load hashes of already existing log files.
    my $existing = analyse_existing_logs($destdir);

    # now check source log directory for new log files, and if required, copy
    # them to the destination dir (and rename them accordingly)
    my $new = find_new_logs($sourcedir, $existing);
    if (@$new) {
        # if there are any new logs, copy them to destination directory and rename them.
        copy_new_logs($new);
    } else {
        # DEBUG:
        #say "found no new logs";
    }

    # Finally handle the maillog, which is the non-rotated logfile. just use the most
    # recent version.
    copy("$sourcedir/maillog", "$destdir/maillog") or die "failed to copy current maillog";
}

sub analyse_existing_logs {
    my ($logdir) = @_;

    opendir(DIR, $logdir) or die "Cannot open $logdir\n";
    my @files = readdir(DIR);
    closedir(DIR);

    my %existing;

    foreach my $file (@files) {
        next if $file =~ /^\.\.?$/;
        next if $file !~ /\.gz$/; # only consider .gz log files.
        my $path = "$logdir/$file";

        if (!consistent_filename($path, $file)) {
            # print warning about non-consistent log file name.
            # TODO: offer to fix or fix automatically?
            my $expected = derive_log_filename($path);
            say "Inconsistent log filename, was $file expected $expected.";
            my $destpath = "$logdir/$expected";
            if (-e $destpath) {
                die "non-unique filename, $destpath already exists!";
            }
            move($path, $destpath) or die "failed to rename to consistent filename";
            say "Renamed $path -> $destpath";
            $path = $destpath;
        }

        # calculate hash of file.
        my $sha = Digest::SHA->new(512);
        $sha->addfile($path, "b");
        my $digest = $sha->hexdigest;
        
        $existing{$digest} = $file;
    }
    return \%existing;
}

sub consistent_filename {
    my ($path, $file) = @_;

    my $expected = derive_log_filename($path);
    return $file eq $expected;
}

sub copy_new_logs {
    my ($new) = @_;

    # copies files from source array with new files to destination directory
    # and rename accordingly. check for filename collision too.
    foreach my $source (@$new) {
        my $destfile = derive_log_filename($source);
        my $destpath = "$destdir/$destfile";
        if (-e $destpath) {
            die "non-unique filename, $destpath already exists!";
        }

        copy($source, $destpath) or die "file copy $source -> $destpath failed for some reason!";
        say "copied $source -> $destpath";
    }
}

sub derive_log_filename {
    my ($path) = @_;

    # look at the first line of the file which should be something like this, otherwise fail.
    # 2019-05-03T17:00:01.044Z imap newsyslog[33424]: logfile turned over
    my $handle = IO::Zlib->new($path, "rb");
    my $line = <$handle>;
    undef $handle;

    if (my ($year, $month, $day) = $line =~ /^(\d{4})-(\d{2})-(\d{2})T.+logfile turned over$/) {
        return "maillog.$year-$month-$day.gz";
    } else {
        die "invalid format on first line of $path, got line $line\n";
    }
}

sub find_new_logs {
    my ($logdir, $existing) = @_;

    opendir(DIR, $logdir) or die "Cannot open $logdir\n";
    my @files = readdir(DIR);
    closedir(DIR);

    my @new;
    foreach my $file (@files) {
        next if $file =~ /^\.\.?$/;
        next if $file !~ /^maillog.*\.gz$/; # we only care about .gz-files in this stage.
        my $path = "$logdir/$file";

        my $sha = Digest::SHA->new(512);
        $sha->addfile($path, "b");
        my $digest = $sha->hexdigest;

        if (!exists($existing->{$digest})) {
            push @new, $path;
        }
    }
    return \@new;
}
