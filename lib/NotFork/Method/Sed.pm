package NotFork::Method::Sed;

# Copyright 2020 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020

use strict;
use Carp;
use Fcntl ':seek';
use File::Find;
use Text::Glob 'glob_to_regex';

sub new {
    @_ == 4 or croak "Usage: Notfork::Method::Sed->new(NAME, SRCDIR, OPTIONS)";
    my ($class, $name, $srcdir, $options) = @_;
    # if we had options for the "sed" method, we'd do something here
    bless {
	name   => $name,
	srcdir => $srcdir,
	mods   => [],
    }, $class;
}

# this is called after NotFork::Get has read the first part of a modification
# file: for us, the rest is a list of "regular-expression = replacement"
# which we parse and save
sub load_data {
    @_ == 3 or croak "Usage: SED->load_data(FILENAME, FILEHANDLE)";
    my ($obj, $fn, $fh) = @_;
    my $srcdir = $obj->{srcdir};
    while (defined (my $line = <$fh>)) {
	$line =~ /^\s*$/ and next;
	$line =~ /^\s*#/ and next;
	chomp $line;
	$line =~ s/^\s+//;
	$line =~ s/^\s*([^:\s]+)\s*:\s*// or die "$fn.$.: Missing file pattern\n";
	my $file_glob = $1;
	my $file_regex = glob_to_regex($file_glob);
	my $search_regex;
	if ($line =~ s/^(['"])//) {
	    my $quote = $1;
	    $line =~ s/^([^$quote]*)$quote\s*=\s*// or die "$fn.$.: Missing search regex\n";
	    $search_regex = $1;
	} else {
	    $line =~ s/^\s*([^=\s]+)\s*=\s*// or die "$fn.$.: Missing search regex\n";
	    $search_regex = $1;
	}
	my $replacement = $line;
	$replacement =~ s(\\([ntr])){ { n => "\n", t => "\t", r => "\r" }->{$1} }ge;
	my $text_regex = eval { qr/$search_regex/ };
	$@ and die "$fn:$.: Invalid pattern: $@";
	push @{$obj->{mods}}, [$file_regex, $text_regex, $replacement];
	$file_glob =~ m|/| and next;
    }
    $obj;
}

# this is called to apply the substitutions; we read the file in memory, run
# the changes, then write it to a temporary file
# TODO - rewrite this using $vcs->list_files
sub apply {
    @_ == 7 or croak "Usage: SED->apply(VCS_DIR, SUBTREE, REPLACE_CALLBACK, EDIT_CALLBACK, VERSION. IID)";
    my ($obj, $vcs, $subtree, $r_call, $e_call, $version, $commit_id) = @_;
    my $src = $obj->{srcdir};
    $vcs =~ m|/$| or $vcs .= '/';
    if (defined $subtree && $subtree ne '') {
	$vcs .= $subtree;
	$vcs =~ m|/$| or $vcs .= '/';
    }
    my $len = length($vcs);
    for my $mods (@{$obj->{mods}}) {
	my ($file_regex, $text_regex, $replacement) = @$mods;
	# figure out which files match
	my @files;
	find({
	    wanted => sub {
		-f or return;
		substr($_, 0, $len) eq $vcs and $_ = substr($_, $len);
		my $orig;
		if ($_ =~ $file_regex) {
		    $orig = $_;
		} else {
		    $orig = $_;
		    s|^.*/|| or return;
		    $_ =~ $file_regex or return;
		}
		my $dest = $orig;
		if (defined $subtree && $subtree ne '') {
		    $orig = $subtree;
		    $orig =~ m|/$| or $orig .= '/';
		    $orig .= $dest;
		}
		push @files, [$orig, $dest];
	    },
	    no_chdir => 1,
	}, $vcs);
	# replace some variables in $replacement
	$replacement =~ s(\$(LUMO_\w+)){
	    {
		LUMO_VERSION   => $version,
		LUMO_COMMIT_ID => $commit_id,
	    }->{$1} || ''
	}ge;
	# ask to make a copy
	my $copy = $e_call->(map { $_->[0] } @files);
	# and now update them
	local $/ = undef;
	for my $fp (@files) {
	    my ($fo, $fd) = @$fp;
	    open(my $fh, '+<', "$copy/$fo") or die "$fo: $!\n";
	    my $data = <$fh>;
	    $data =~ s/$text_regex/$replacement/g;
	    seek $fh, 0, SEEK_SET;
	    print $fh $data or die "$fo: $!\n";
	    truncate $fh, tell($fh) or die "$fo: $!\n";;
	    close $fh or die "$fo: $!\n";;
	    $r_call->($fd, "$copy/$fo");
	}
    }
}

1
