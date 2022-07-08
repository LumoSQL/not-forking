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
use NotFork::Get qw(add_prereq prereq_module);

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

# check that we have any prerequisite software installed
sub check_prereq {
    @_ == 2 or croak "Usage: PATCH->check_prereq(RESULT)";
    my ($obj, $result) = @_;
    add_prereq($result,
	[\&prereq_module, 'Text::Glob'],
    );
    $obj;
}

# this is called after NotFork::Get has read the first part of a modification
# file: for us, the rest is a list of "regular-expression = replacement"
# which we parse and save
sub load_data {
    @_ == 3 or croak "Usage: SED->load_data(FILENAME, FILEHANDLE)";
    my ($obj, $fn, $fh) = @_;
    require Text::Glob;
    my $srcdir = $obj->{srcdir};
    while (defined (my $line = <$fh>)) {
	$line =~ /^\s*$/ and next;
	$line =~ /^\s*#/ and next;
	chomp $line;
	$line =~ s/^\s+//;
	$line =~ s/^\s*([^:\s]+)\s*:\s*// or die "$fn.$.: Missing file pattern\n";
	my $file_glob = $1;
	my $file_regex = Text::Glob::glob_to_regex($file_glob);
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
sub apply {
    @_ == 8 or croak "Usage: SED->apply(VCS_DIR, VCS_OBJ, SUBTREE, REPLACE_CALLBACK, EDIT_CALLBACK, VERSION. IID)";
    my ($obj, $vcs, $vcs_obj, $subtree, $r_call, $e_call, $version, $commit_id) = @_;
    my $src = $obj->{srcdir};
    for my $mods (@{$obj->{mods}}) {
	my ($file_regex, $text_regex, $replacement) = @$mods;
	# figure out which files match
	my @files;
	$vcs_obj->list_files($subtree, sub {
	    my ($name, $path) = @_;
	    if ($name !~ $file_regex) {
		(my $short = $name) =~ s|^.*/|| or return;
		$short =~ $file_regex or return;
	    }
	    push @files, [$name, $path];
	});
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
	    my ($name, $path) = @$fp;
print "<$name> <$path> <$copy/$name>\n";
	    open(my $fh, '+<', "$copy/$name") or die "$name: $!\n";
	    my $data = <$fh>;
	    $data =~ s/$text_regex/$replacement/g;
	    seek $fh, 0, SEEK_SET;
	    print $fh $data or die "$name: $!\n";
	    truncate $fh, tell($fh) or die "$name: $!\n";;
	    close $fh or die "$name: $!\n";;
	    $r_call->($name, "$copy/$name");
	}
    }
}

1
