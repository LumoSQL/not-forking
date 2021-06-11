package NotFork::Method::patch_common;

# Copyright 2021 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2021

# common code to Patch and Fragment_patch

use strict;
use Carp;
use Fcntl ':seek';
use Text::ParseWords qw(shellwords);
use NotFork::Get qw(add_prereq_or prereq_program);

my $patch_prog = undef;

sub _init {
    @_ == 1 or croak "Usage: Notfork::Method::patch_common::_init(OPTIONS)";
    my ($options) = @_;
    # if they've specified options to the "patch" program, use them; otherwise
    # use the defaults
    my $patch = '-tNsp1';
    exists $options->{options} and $patch = $options->{options};
    my @patch = shellwords($patch);
    # additional options to "patch" to get a list of files only
    my $list = '--dry-run --read-only=ignore --verbose';
    exists $options->{list} and $list = $options->{list};
    my @list = shellwords($list);
    return (
	patch   => \@patch,
	list    => \@list,
    );
}

# check that we have any prerequisite software installed
sub check_prereq {
    @_ == 2 or croak "Usage: PATCH->check_prereq(RESULT)";
    my ($obj, $result) = @_;
    add_prereq_or($result,
	[\&prereq_program, 'gpatch', 2.5, '--version', qw/\b([1-9][0-9]*\.\d+)\b/],
	[\&prereq_program, 'patch', 2.5, '--version', qw/\b([1-9][0-9]*\.\d+)\b/],
    );
    $obj;
}

# run 'patch' on the source
sub _run_patch {
    my ($obj, $dir, $srcn, $srch, $srcp, $pipe, @args) = @_;
    if (! defined $patch_prog) {
	my ($patch, $gpatch);
	for my $p (split(/:/, $ENV{PATH})) {
	    ! defined $patch && -x "$p/patch" and $patch = "$p/patch";
	    ! defined $gpatch && -x "$p/gpatch" and $patch = "$p/gpatch";
	}
	if (defined $gpatch) {
	    $patch_prog = $gpatch;
	} elsif (defined $patch) {
	    $patch_prog = $patch;
	} else {
	    die "Cannot find patch or gpatch\n";
	}
    }
    my @patch = ($patch_prog, map { @{$obj->{$_}} } @args);
    my $pid = open(my $ph, '-|');
    defined $pid or die "$patch_prog: $!\n";
    if ($pid == 0) {
	chdir $dir or die "$dir: $!\n";
	seek $srch, $srcp, SEEK_SET or die "$srcn: $!\n";
	open(STDIN, '<&=', $srch);
	exec @patch;
	die "Can't exec $patch[0]\n";
    } elsif ($pipe) {
	return $ph;
    }
    # copy output to STDOUT
    while (defined (my $pl = <$ph>)) {
	print $pl;
    }
}

1
