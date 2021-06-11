package NotFork::Method::Append;

# Copyright 2021 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2021

use strict;
use Carp;

sub new {
    @_ == 4 or croak "Usage: Notfork::Method::Append->new(NAME, SRCDIR, OPTIONS)";
    my ($class, $name, $srcdir, $options) = @_;
    # if we had options for the "append" method, we'd do something here
    bless {
	name   => $name,
	srcdir => $srcdir,
	mods   => [],
    }, $class;
}

# check that we have any prerequisite software installed
sub check_prereq {
    @_ == 2 or croak "Usage: APPEND->check_prereq(RESULT)";
    my ($obj, $result) = @_;
    $obj;
}

sub load_data {
    @_ == 3 or croak "Usage: APPEND->load_data(FILENAME, FILEHANDLE)";
    my ($obj, $fn, $fh) = @_;
    my $srcdir = $obj->{srcdir};
    while (defined (my $fname = <$fh>)) {
	# first line must be a file name and we'll fail later if it isn't
	chomp $fname;
	# followed by file contants and terminated by EOF or a line of dashes
	# except that "- ---" does not terminate but adds "---"
	my $data;
	while (defined (my $line = <$fh>)) {
	    $line =~ /^-+\s*$/ and last;
	    $line =~ s/^-\s+//;
	    $data .= $line;
	}
	push @{$obj->{mods}}, [$fname, $data];
    }
    $obj;
}

sub apply {
    @_ == 8 or croak "Usage: APPEND->apply(VCS_DIR, VCS_OBJ, SUBTREE, REPLACE_CALLBACK, EDIT_CALLBACK, VERSION, COMMIT_ID)";
    my ($obj, $vcs, $vcs_obj, $subtree, $r_call, $e_call, $version, $commit_id) = @_;
    my $src = $obj->{srcdir};
    for my $mods (@{$obj->{mods}}) {
	my ($fname, $data) = @$mods;
	my $copy = $e_call->($fname);
	my $repl = "$copy/$fname";
	open my $dst, '>>', $repl or die "$repl: $!\n";
	print $dst $data or die "$repl: $!\n";
	close $dst or die "$repl: $!\n";
	$r_call->($fname, $repl);
    }
}

1
