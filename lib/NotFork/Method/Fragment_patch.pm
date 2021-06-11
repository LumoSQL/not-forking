package NotFork::Method::Fragment_patch;

# Copyright 2021 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2021

# Handle a "fragment_patch" modification file; this is similar to a normal
# patch but considers the source file built of fragments (normally functions
# or some other easily identifiable feature) and applies patches to all
# fragments separately; this makes it easier to adjust to upstream changes,
# for example if the function being patched is the only thing in the whole
# source which hasn't changed, the normal "patch" may not find it, this
# one will.

use strict;
use Carp;
use Fcntl ':seek';
use File::Temp 'tempdir';
use NotFork::Method::patch_common;
use Exporter;

our @ISA = qw(NotFork::Method::patch_common Exporter);
our @EXPORT = ();
our @EXPORT_OK = qw(quote unquote);

sub new {
    @_ == 4 or croak "Usage: Notfork::Method::Fragment_patch->new(NAME, SRCDIR, OPTIONS)";
    my ($class, $name, $srcdir, $options) = @_;
    bless {
	name      => $name,
	srcdir    => $srcdir,
	fragments => [],
	files     => [],
	NotFork::Method::patch_common::_init($options),
    }, $class;
}

# this is called after NotFork::Get has read the first part of a modification
# file; we scan it to determine a list of files to patch and fragments within
# each file
sub load_data {
    @_ == 3 or croak "Usage: FRAGMENT_PATCH->load_data(FILENAME, FILEHANDLE)";
    my ($obj, $fn, $fh) = @_;
    my %files = ();
    NAME: while (defined (my $name = <$fh>)) {
	chomp $name;
	$name =~ s/^\s+//;
	$name =~ s/\s+$//;
	$name = unquote($name);
	$files{$name} = undef;
	while (1) {
	    my @data;
	    for my $what (qw(start end)) {
		my $data = <$fh>;
		defined $data or die "$fn: Missing $what\n";
		chomp $data;
		$data =~ s/^\s+//;
		$data =~ s/\s+$//;
		my $value;
		if ($what eq 'start' && $data eq '-----') {
		    next NAME;
		} elsif ($data eq $what) {
		    $data = undef;
		} elsif ($data =~ /^\//) {
		    if ($what eq 'start') {
			$data =~ s/\/\s+(\S+)$//
			    or die "$fn: Invalid line ($what): $data\n";
			$value = unquote($1);
		    } else {
			$data =~ s/\/$//
			    or die "$fn: Invalid line ($what): $data\n";
		    }
		    $data =~ s/^\///;
		    $data = qr/$data/;
		} else {
		    die "$fn: Invalid line ($what): $data\n";
		}
		push @data, $data, $value;
	    }
	    my $pos = tell $fh;
	    defined $pos or die "$fn: $!\n";
	    my $end_pos = $pos;
	    while (<$fh>) {
		chomp;
		$_ eq '---' and last;
		$end_pos = tell $fh;
		defined $end_pos or die "$fn: $!\n";
	    }
	    push @{$obj->{fragments}}, [$name, $fn, $pos, $end_pos, @data];
	}
    }
    push @{$obj->{files}}, sort keys %files;
    $obj;
}

# this is called to apply a patch; we copy the file from the original
# (VCS dir) into a cache directory then apply the patch there
# we could make this more efficient by ordering the fragments
# and not splitting/joining the file for each fragment; maybe in
# a future version
sub apply {
    @_ == 8 or croak "Usage: FRAGMENT_PATCH->apply(VCS_DIR, VCS_OBJ, SUBTREE, REPLACE_CALLBACK, EDIT_CALLBACK, VERSION, ID)";
    my ($obj, $vcs, $vcs_obj, $subtree, $r_call, $e_call, $version, $commit_id) = @_;
    my $dir = File::Temp->newdir(CLEANUP => 1);
    for my $lp (@{$obj->{fragments}}) {
	my ($name, $fn, $pos, $end_pos, $pattern, $value, $end_pattern) = @$lp;
	# extract patch fragment
	open my $fh, '<', $fn or die "$fn: $!\n";
	seek $fh, $pos, SEEK_SET;
	open my $pf, '>', "$dir/patch" or die "$dir/patch: $!\n";
	print $pf "--- a/fragment 2021-01-01 00:01:42 +0000\n",
	          "+++ b/fragment 2022-01-01 00:01:42 +0000\n"
	    or die "$dir/patch: $!\n";
	my $diff = $end_pos - $pos;
	my $buffer;
	while ($diff > 0) {
	    my $todo = $diff;
	    $todo > 4096 and $todo = 4096;
	    read $fh, $buffer, $todo;
	    $diff -= $todo;
	    print $pf $buffer or die "$dir/patch: $!\n";
	}
	close $pf or die "$dir/patch: $!\n";
	# extract fragment from source file
	my $copy = $e_call->($name);
	open my $of, '<', "$copy/$name" or die "$name: $!\n";
	open my $bf, '>', "$dir/before" or die "$dir/before: $!\n";
	open my $ff, '>', "$dir/fragment" or die "$dir/fragment: $!\n";
	if (defined $pattern) {
	    my $ok = 0;
	    while (<$of>) {
		if ($_ =~ $pattern && (! defined $value || $value eq $1)) {
		    print $ff $_ or die "$dir/fragment: $!\n";
		    $ok = 1;
		    last;
		}
		print $bf $_ or die "$dir/before: $!\n";
	    }
	    $ok or die "$name: Fragment not found ($value)\n";
	}
	close $bf or die "$dir/before: $!\n";
	open my $af, '>', "$dir/after" or die "$dir/after: $!\n";
	while (<$of>) {
	    if (defined $end_pattern && $_ =~ $end_pattern) {
		print $af $_ or die "$dir/after: $!\n";
		last;
	    }
	    print $ff $_ or die "$dir/fragment: $!\n";
	}
	close $ff or die "$dir/fragment: $!\n";
	while (<$of>) {
	    print $af $_ or die "$dir/after: $!\n";
	}
	close $af or die "$dir/after: $!\n";
	close $of;
	# now patch the fragment
	open $pf, '<', "$dir/patch" or die "$dir/patch: $!\n";
	$obj->_run_patch($dir, "$dir/patch", $pf, 0, 0, 'patch');
	close $pf;
	# check if anything failed
	stat "$dir/fragment.rej"
	    and die "patch failed on $name, "
		  . (defined $pattern ? "fragment \"$value\"" : "initial fragment") . "\n";
	# and rebuild the file
	open my $nf, '>', "$copy/$name" or die "$copy/$name: $!\n";
	for my $src (qw(before fragment after)) {
	    open my $sf, '<', "$dir/$src" or die "$dir/$src: $!\n";
	    while (<$sf>) {
		print $nf $_ or die "$copy/$name: $!\n";
	    }
	    close $sf;
	}
	close $nf or die "$copy/$name: $!\n";
	# tell callback we've finished
	$r_call->($name, "$copy/$name");
    }
}

sub quote {
    my ($v) = @_;
    $v =~ s(([\s\\])){ sprintf "\\x%02x", ord($1) }ge;
    $v;
}

sub unquote {
    my ($v) = @_;
    $v =~ s(\\x([[:xdigit:]]{2})){ chr(hex $1) }ge;
    $v;
}

1;
