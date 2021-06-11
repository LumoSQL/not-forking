package NotFork::Method::Patch;

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
use NotFork::Method::patch_common;

our @ISA = qw(NotFork::Method::patch_common);

sub new {
    @_ == 4 or croak "Usage: Notfork::Method::Patch->new(NAME, SRCDIR, OPTIONS)";
    my ($class, $name, $srcdir, $options) = @_;
    bless {
	name    => $name,
	srcdir  => $srcdir,
	NotFork::Method::patch_common::_init($options),
    }, $class;
}

# this is called after NotFork::Get has read the first part of a modification
# file; for us, the rest is something to pass unchanged to "patch"; we do
# not load it in memory, rather we remember where it comes from
sub load_data {
    @_ == 3 or croak "Usage: PATCH->load_data(FILENAME, FILEHANDLE)";
    my ($obj, $fn, $fh) = @_;
    my $pos = tell $fh;
    defined $pos or die "$fn: $!\n";
    push @{$obj->{mods}}, [$fn, $pos];
    $obj;
}

# this is called to apply a patch; we copy the file from the original
# (VCS dir) into a cache directory then apply the patch there
sub apply {
    @_ == 8 or croak "Usage: PATCH->apply(VCS_DIR, VCS_OBJ, SUBTREE, REPLACE_CALLBACK, EDIT_CALLBACK, VERSION, ID)";
    my ($obj, $vcs, $vcs_obj, $subtree, $r_call, $e_call, $version, $commit_id) = @_;
    my $src = $obj->{srcdir};
    for my $mods (@{$obj->{mods}}) {
	my ($fn, $pos) = @$mods;
	open(my $fh, '<', $fn) or die "$fn: $!\n";
	# first figure out what files will change...
	my %files = ();
	my $th = $obj->_run_patch($vcs, $fn, $fh, $pos, 1, 'patch', 'list');
	while (defined (my $po = <$th>)) {
	    $po =~ s/^\s*checking\s+file\s+// or next;
	    chomp $po;
	    $files{$po} = undef;
	}
	close $th;
	# ask to make a copy so we can patch
	my $copy = $e_call->(keys %files);
	# patch them...
	$obj->_run_patch($copy, $fn, $fh, $pos, 0, 'patch');
	# and tell callback what we've changed
	for my $f (sort keys %files) {
	    $r_call->($f, "$copy/$f");
	}
    }
}

1
