package NotFork::Hash;

# Copyright 2022 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2022

use strict;
use Carp;
use File::Path qw(make_path);
use NotFork::Get qw(cache_hash);
use NotFork::Unpack qw(unpack_archive);

my %builtin = (
    sha224    => [ 1, 0, 'sha', 224, \&_shafile, 224 ],
    sha256    => [ 1, 0, 'sha', 256, \&_shafile, 256 ],
    sha384    => [ 1, 0, 'sha', 384, \&_shafile, 384 ],
    sha512    => [ 1, 0, 'sha', 512, \&_shafile, 512 ],
);

sub new {
    @_ == 3 or croak "Usage: new NotFork::Hash(SPEC, IS_DIR?)";
    my ($class, $spec, $is_dir) = @_;
    my ($element, $run) = split(/:/, $spec, 2);
    defined $run or $run = $element;
    my ($alg, $size, @run);
    if ($run =~ s/^builtin://) {
	exists $builtin{$run} or die "Invalid builtin:$run\n";
	my ($F, $D);
	($F, $D, $alg, $size, @run) = @{$builtin{$run}};
	if ($is_dir) {
	    $D or die "Built-in hash $run cannot be used as dirhash\n";
	} else {
	    $F or die "Built-in hash $run cannot be used as filehash\n";
	}
    } else {
	$alg = $run;
	$size = 0;
	@run = (\&_run, split(/\s+/, $run));
    }
    bless {
	spec    => $spec,
	element => $element,
	run     => \@run,
	alg     => $alg,
	size    => $size,
	is_dir  => $is_dir,
    }, $class;
}

sub identify {
    @_ == 1 or croak "Usage: HASH->identify";
    my ($obj) = @_;
    ($obj->{alg}, $obj->{size});
}

sub element {
    @_ == 1 or croak "Usage: HASH->element";
    my ($obj) = @_;
    $obj->{element};
}

sub _cache_path {
    my ($obj, $top, $index) = @_;
    my $hash = cache_hash("$obj->{alg} $obj->{size} $index");
    return ($top . '/' . substr($hash, 0, 2), substr($hash, 2));
}

sub find_cached {
    @_ == 3 or croak "Usage: HASH->find_cached(CACHE, INDEX)";
    my ($obj, $cache, $index) = @_;
    my ($dir, $file) = $obj->_cache_path($cache, $index);
    open(my $fh, '<'. "$dir/$file") or return undef;
    my $sum = <$fh>;
    close $fh;
    defined $sum or return undef;
    chomp $sum;
    $sum =~ /^[[:xdigit:]]+$/ or return undef;
    $sum;
}

sub sum_file {
    @_ == 4 or croak "Usage: HASH->sum_file(CACHE, INDEX, FILE)";
    my ($obj, $cache, $index, $file) = @_;
    my $sum;
    my ($code, @args) = @{$obj->{run}};
    if ($obj->{is_dir}) {
	eval 'use File::Temp';
	$@ and die "Please install the File::Temp module to calculate this checksum\n";
	eval 'use File::Path';
	$@ and die "Please install the File::Path module to calculate this checksum\n";
	# if we ask CLEANUP => 1 the cleanup happens all at end of program, which
	# could fill up /tmp if we calculate a lot of hashes.  Instead we do our
	# clean up as soon as it makes sense
	my $dest = File::Temp::tempdir(CLEANUP => 0);
	unpack_archive($file, $dest);
	$sum = $code->(@args, $dest);
	File::Path::remove_tree($dest);
    } else {
	$sum = $code->(@args, $file);
    }
    my ($cdir, $cfile) = $obj->_cache_path($cache, $index);
    make_path($cdir);
    my $dest = "$cdir/$cfile";
    my $temp = "$dest.tmp";
    open(my $fh, '>'. $temp) or die "$temp: $!\n";
    print $fh "$sum\n" or die "$temp: $!\n";
    close $fh or die "$temp: $!\n";
    rename($temp, $dest) or die "rename($temp, $dest): $!\n";
    $sum;
}

sub _shafile {
    my ($size, $file) = @_;
    eval 'use Digest::SHA';
    $@ and die "Please install the Digest::SHA module to generate checksums\n";
    my $sha = new Digest::SHA($size);
    $sha->addfile($file);
    $sha->hexdigest();
}

sub _run {
    my ($prog, @args) = @_;
    open(my $fh, '-|', $prog, @args) or die "$prog: $!\n";
    my $sum = <$fh>;
    if (! close $fh) {
	$? == -1 and die "$prog: $!\n";
	$? & 0x7f and die "$prog died with signal " . ($? & 0x7f) . "\n";
	die "$prog exited with status " . ($? >> 8) . "\n";
    }
    defined $sum or die "No output from $prog\n";
    chomp $sum;
    $sum =~ /^\s*([[:xdigit:]]+)\b/ or die "$prog returned unrecognised hash: $sum\n";
    $1;
}

1
