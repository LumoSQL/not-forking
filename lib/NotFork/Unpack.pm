package NotFork::Unpack;

# Module to unpack an archive file (usually a tarball) to a directory

# Copyright 2020, 2022 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020, 2022

use strict;
use Carp;
use Exporter;
use NotFork::Get qw(add_prereq add_prereq_or prereq_program prereq_module);

our @EXPORT_OK = qw(unpack_archive unpack_prereq find_program);
our @ISA = qw(Exporter);

# check that we have any prerequisite software installed
sub unpack_prereq {
    @_ == 1 or croak "Usage: check_prereq(RESULT)";
    my ($result) = @_;
    # how to get the sources
    add_prereq_or($result,
	[\&prereq_program, 'curl'],
	[\&prereq_program, 'wget'],
    );
    # how to verify archives
    add_prereq($result,
	[\&prereq_module, 'Digest::SHA'],
    );
    # how to figure out what they are
    add_prereq($result,
	[\&prereq_program, 'file'],
    );
    # how to uncompress sources
    add_prereq($result,
	[\&prereq_program, 'gzip'],
	[\&prereq_program, 'bzip2'],
	[\&prereq_program, 'cat'], # used to get the "unpack" pipe started
	# [\&prereq_program, 'xz'],
    );
    # how to unpack archives
    add_prereq($result,
	[\&prereq_program, 'tar'],
    );
}

sub unpack_archive {
    @_ == 2 || @_ == 3 or croak "Usage: unpack_archive(FILE, DESTINATION [, FILELIST_])";
    my ($file, $dest, $fl) = @_;
    # determine what file type we are looking at
    my @extract_pipe = ();
    my $type = _file_type($file, @extract_pipe);
    while ($type =~ /^(\S+)\s*compress/) {
	my $cp = $1;
	if ($cp eq 'gzip' || $cp eq 'bzip2' || $cp eq 'xz') {
	    my $prog = find_program($cp);
	    defined $prog or die "Cannot find $cp to uncompress source, please install it\n";
	    push @extract_pipe, "$prog -dc";
	} else {
	    die "Don't know how to uncompress \"$cp\"\n";
	}
	$type = _file_type($file, @extract_pipe);
    }
    my @ls_pipe = @extract_pipe;
    if ($type =~ /\btar\b.*\barchive/i) {
	push @ls_pipe, 'tar -tf - > "$IDXFILE"';
	push @extract_pipe, 'tar -xf -';
    } else {
	die "Don't know how to unpack \"$type\"\n";
    }
    -d $dest or mkdir $dest or die "$dest $!\n";
    local $ENV{SRCFILE} = $file;
    local $ENV{DSTDIR} = $dest;
    my $cat = find_program('cat');
    defined $cat or die "Cannot find 'cat' command\n";
    my $pipe_start = "cd \"\$DSTDIR\"; $cat \"\$SRCFILE\"";
    my $extract_pipe = join(' | ', $pipe_start, @extract_pipe);
    if (system($extract_pipe) != 0) {
	$? == -1 and die "Cannot unpack $file: running ($extract_pipe) failed with error $!\n";
	$? & 0x7f and die "unpack ($extract_pipe) died with signal " . ($? & 0x7f) . "\n";
	die "unpack ($extract_pipe) exited with status " . ($? >> 8) . "\n";
    }
    if ($fl) {
	local $ENV{IDXFILE} = $fl;
	my $ls_pipe = join(' | ', $pipe_start, @ls_pipe);
	if (system($ls_pipe) != 0) {
	    $? == -1 and die "Cannot unpack $file\n";
	    $? & 0x7f and die "unpack died with signal " . ($? & 0x7f) . "\n";
	    die "unpack exited with status " . ($? >> 8) . "\n";
	}
    }
}

sub find_program {
    my ($prog) = @_;
    for my $p (split(/:/, $ENV{PATH})) {
	-f "$p/$prog" and return "$p/$prog";
    }
    undef;
}

sub _file_type {
    my ($file, @pipe) = @_;
    local $ENV{SRCFILE} = $file;
    my $cat = find_program('cat');
    defined $cat or die "Cannot find 'cat' command\n";
    my $pipe = join(' | ', "$cat \"\$SRCFILE\"", @pipe, 'file -');
    open (my $fh, $pipe . ' |') or die "pipe: $!\n";
    my $line = <$fh>;
    close $fh;
    defined $line or die "$file: cannot determine file type\n";
    $line =~ s/^.*?:\s*//;
    $line =~ s/\s+$//;
    $line;
}

1
