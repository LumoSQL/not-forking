package NotFork::VCS::Download;

# Module to download sources from a per-version URL and figure out how to unpack them

# Copyright 2020, 2022 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020, 2022

use strict;
use Carp;
use NotFork::Get qw(version_convert cache_hash add_prereq add_prereq_or prereq_program prereq_module);
use NotFork::VCSCommon;
use NotFork::Unpack qw(unpack_archive unpack_prereq find_program);

our @ISA = qw(NotFork::VCSCommon);

sub new {
    @_ == 3 or croak "Usage: new NotFork::VCS::Download(NAME, OPTIONS)";
    my ($class, $name, $options) = @_;
    my %versions = ();
    my %vptr = ();
    my %digests = ();
    my $compare = $options->{compare};
    for my $option (keys %$options) {
	if ($option =~ /^source-(.*)$/) {
	    my $version = $1;
	    $versions{$version} = $options->{$option};
	    $vptr{$version} = version_convert($version, $compare);
	} elsif ($option =~ /^sha(224|256|384|512)-(.*)$/) {
	    my ($size, $version) = ($1, $2);
	    # here we would check if it's a valid hex or b64 string...
	    $digests{$version}{sha}{$size} = $options->{$option};
	}
    }
    keys %versions or die "No sources defined\n";
    my @versions = sort { $vptr{$a} cmp $vptr{$b} } keys %versions;
    my $prefix = 0;
    if (exists $options->{prefix}) {
	$options->{prefix} =~ /^\d+$/ or die "Invalid prefix: $options->{prefix}\n";
	$prefix = $options->{prefix} + 0;
    }
    my $obj = bless {
	name    => $name,
	verbose => 1,
	_id     => 'DOWNLOAD',
	vlist   => \@versions,
	vurl    => \%versions,
	digests => \%digests,
	pending => $versions[-1],
	prefix  => $prefix,
    }, $class;
    $obj;
}

# creates a special object which can only be used to unpack sources for
# a single version, or else to use already-unpacked sources for a single
# version; it is meant to be used instead of the "proper" VCS when the
# sources are provided in a local mirror
sub mirror_new {
    @_ == 5 or croak "Usage: mirror_new NotFork::VCS::Download(NAME, VERSION, SRC, IS_DIR?)";
    my ($class, $name, $version, $src, $isdir) = @_;
    stat $src or die "$src: $!\n";
    if ($isdir) {
	-d _ or die "$src: not a directory\n";
    } else {
	-f _ or die "$src: not a regular file\n";
    }
    bless {
	name    => $name,
	verbose => 1,
	_id     => 'DOWNLOAD',
	vlist   => [$version],
	vurl    => {$version => $src},
	digests => {},
	pending => $version,
	prefix  => ! $isdir,
	mirror  => $isdir,
    }, $class;
}

# name used to index elements in download cache; we use the same cache index for
# all downloads, but then we'll also add a hash of the actual URL
sub cache_index {
    'not-fork-downloads';
}

# we never have a valid commit ID...
sub commit_valid {
    return 0;
};

# check that we have any prerequisite software installed
sub check_prereq {
    @_ == 2 or croak "Usage: DOWNLOAD->check_prereq(RESULT)";
    my ($obj, $result) = @_;
    # how to get the sources
    add_prereq_or($result,
	[\&prereq_program, 'curl'],
	[\&prereq_program, 'wget'],
    );
    # how to verify archives
    add_prereq($result,
	[\&prereq_module, 'Digest::SHA'],
    );
    # we may also need to find all unpacked files (tar provides the list
    # while unpacking, but we cannot use that if somebody else has
    # provided an unpacked source in a mirror directory)
    add_prereq($result,
	[\&prereq_module, 'File::Find'],
    );
    # and anything we need to unpack the files
    unpack_prereq($result);
    $obj;
}

sub get {
    @_ == 2 || @_ == 3 or croak "Usage: DOWNLOAD->get(DIR [, SKIP_UPDATE?])";
    my ($obj, $dir, $noupdate) = @_;
    # we don't actually do much here...
    $dir =~ s|/vcs|/download| or croak "DOWNLOAD->get called with invalid directory";
    $obj->{dl_dir} = $dir;
    -d $dir and return;
    mkdir $dir or die "$dir: $!\n";
}

# list all version numbers
sub all_versions {
    @_ == 1 or croak "Usage: DOWNLOAD->all_versions";
    my ($obj) = @_;
    @{$obj->{vlist}};
}

sub _checksum {
    my ($obj, $version, $file) = @_;
    for my $size (keys %{$obj->{digests}{$version}{sha}}) {
	eval 'use Digest::SHA';
	$@ and die "Please install the Digest::SHA module to verify downloads\n";
	my $sum = $obj->{digests}{$version}{sha}{$size};
	my $sha = Digest::SHA->new($size);
	$sha->addfile($file);
	my $res;
	if (length($sum) == int($size / 4) && $sum =~ /^[[:xdigit:]]+$/) {
	    $res = lc($sha->hexdigest);
	    $sum = lc($sum);
	} else {
	    $res = $sha->b64digest;
	    # Digest::SHA does not pad Base64 outputs as everybody else expects it
	    $res .= '=' while length($res) % 4;
	}
	$res eq $sum or die "SHA-$size digest does not match\n";
    }
}

sub set_version {
    @_ == 2 or croak "Usage: DOWNLOAD->set_version(VERSION)";
    my ($obj, $version) = @_;
    exists $obj->{vurl}{$version} or die "No such version: $version\n";
    exists $obj->{dl_dir} or die "Need to call DOWNLOAD->get before set_version\n";
    $obj->{pending} = $version;
    $obj;
}

sub _process_pending {
    my ($obj) = @_;
    exists $obj->{pending} or return;
    my $version = delete $obj->{pending};
    my $dir = $obj->{dl_dir};
    my $url = $obj->{vurl}{$version};
    my $hash = cache_hash($url);
    my $dstdir = "$dir/$hash.dir";
    my $dstfile = "$dir/$hash.src";
    my $dstidx = "$dir/$hash.idx";
    # if file already present, and we have checksums to verify, verify them
    -f $dstfile and $obj->_checksum($version, $dstfile);
    if (! -d $dstdir || ! -f $dstidx) {
	-l $dstdir and unlink $dstdir; # remove any dangling symlink
	my $mirror = $obj->{mirror};
	if ($mirror) {
	    # this is an unpacked local mirror of something else
	    -d $url or die "URL points to a local directory ($url) which does not exist\n";
	    symlink($url, $dstdir) or die "symlink($url): $!\n";
	    -d $dstdir or die "Symlink to $url seems broken\n";
	} elsif (! -f $dstfile) {
	    -l $dstfile and unlink $dstfile; # remove any dangling symlink
	    my $local_source = undef;
	    if (defined $mirror or $url =~ s|^file:/+|/|) {
		-f $url or die "URL points to a local file ($url) which does not exist\n";
		$local_source = $url;
	    } elsif (@{$obj->{local_mirror}}) {
		my $base = $url;
		$base =~ s|/+$||;
		$base =~ s|^.*/||;
		for my $dir (@{$obj->{local_mirror}}) {
		    -f "$dir/$base" or next;
		    eval { $obj->_checksum($version, "$dir/$base"); };
		    $@ and next; # checksum failed
		    $local_source = "$dir/$base";
		    last;
		}
	    }
	    if (defined $local_source) {
		symlink($local_source, $dstfile) or die "symlink($local_source): $!\n";
		-f $dstfile or die "Symlink to $local_source seems broken\n";
	    } else {
		$obj->{offline}
		    and die "Would require downloading $url\nProhibited by --offline\n";
		my $verbose = $obj->{verbose};
		$verbose > 1 and print "Downloading $url -> $dir\n";
		my @cmd;
		if (defined (my $curl = find_program('curl'))) {
		    @cmd = ($curl);
		    $verbose > 2 and push @cmd, '-v';
		    $verbose < 1 and push @cmd, '-s';
		    push @cmd, '-o', $dstfile, $url;
		} elsif (defined (my $wget = find_program('wget'))) {
		    @cmd = ($wget);
		    $verbose > 2 and push @cmd, '-v';
		    $verbose < 1 and push @cmd, '-nv';
		    push @cmd, '-O', $dstfile, $url;
		} else {
		    # we could also check for LWP module installed
		    die "Don't know how to download files, please install curl or wget\n";
		}
		if (system(@cmd) != 0) {
		    $? == -1 and die "Cannot execute $cmd[0]\n";
		    $? & 0x7f and die "$cmd[0] died with signal " . ($? & 0x7f) . "\n";
		    die "$cmd[0] exited with status " . ($? >> 8) . "\n";
		}
		-f $dstfile or die "$cmd[0] failed to download $url\n";
	    }
	    $obj->_checksum($version, $dstfile);
	}
	if ($mirror) {
	    # get file list from mirror directory
	    eval 'use File::Find ()';
	    $@ and die "Please install File::Find to get contents of a mirrored source directory\n";
	    open(my $idx, '>', $dstidx) or die "$dstidx: $!\n";
	    my $len = length($dstdir) + 1;
	    File::Find::finddepth({ wanted => sub {
		lstat($_) or return;
		-d _ || -f _ || -l _ or return;
		substr($_, 0, $len) eq "$dstdir/" or return;
		print $idx substr($_, $len), (-d _ ? '/' : ''), "\n" or die "$dstidx: $!\n";
	    }, no_chdir => 1 }, "$dstdir/");
	    close $idx or die "$dstidx: $!\n";
	} else {
	    # ask the Unpack module to deal with this
	    $obj->{verbose} > 1 and print "Unpacking $obj->{name} $version...\n";
	    unpack_archive($dstfile, $dstdir, $dstidx);
	}
    }
    $obj->{vnumber} = $version;
    $obj->{vdata} = $dstdir;
    $obj->{vindex} = $dstidx;
    $obj->{vcsbase} = $dstdir;
}

sub source_dir {
    @_ == 2 or croak "Usage: DOWNLOAD->source_dir(VCSDIR)";
    my ($obj, $dir) = @_;
    $obj->_process_pending;
    exists $obj->{vcsbase} or croak "Need to call get before source_dir";
    $obj->{vcsbase};
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

sub set_commit {
    @_ == 2 or croak "Usage: DOWNLOAD->set_commit(COMMIT)";
    my ($obj, $commit) = @_;
    die "Commit ID not available for downloads\n";
}

# finds an "approximate" version number, which is the highest version tag present
# before the current commit; since we don't have generic commit IDs, all version
# numbers are exact
sub version {
    @_ == 1 || @_ == 2 or croak "Usage: DOWNLOAD->version [(APPROXIMATE?)]";
    my ($obj, $approx) = @_;
    exists $obj->{pending} ? $obj->{pending} : $obj->{vnumber};
}

sub version_info {
    @_ == 2 or croak "Usage: DOWNLOAD->version_info(VERSION)";
    my ($obj, $version) = @_;
    my $name = $obj->{name};
    return ('-', '-', 'download', $obj->{vurl}{$version});
}

sub info {
    @_ == 2 or croak "Usage: DOWNLOAD->info(FILEHANDLE)";
    my ($obj, $fh) = @_;
    my $name = $obj->{name};
    my $vn = exists $obj->{pending} ? $obj->{pending} : $obj->{vnumber};
    print $fh "Information for $name:\n";
    print $fh "vcs = download\n";
    print $fh "version = $vn\n";
    print $fh "source = $obj->{vurl}{$vn}\n";
    print $fh "\n";
    $obj;
}

# calls a function for each file in the repository
sub list_files {
    @_ == 3 or croak "Usage: DOWNLOAD->list_files(SUBTREE, CALLBACK)";
    my ($obj, $subtree, $call) = @_;
    $obj->_process_pending;
    exists $obj->{vdata} && exists $obj->{vindex}
	or croak "Need to call DOWNLOAD->version before list_files";
    my $vdata = $obj->{vdata};
    my $vindex = $obj->{vindex};
    open(my $fh, '<', $vindex) or die "$vindex: $!\n";
    $obj->_list_files($fh, $vdata, $obj->{prefix}, $subtree, $call);
    close $fh;
    $obj;
}

sub upstream_info {
    @_ == 2 or croak "Usage: DOWNLOAD->upstream_info(FILEHANDLE)";
    my ($obj, $fh) = @_;
    print $fh "vcs = download\n" or die "$!\n";
    $obj;
}

sub version_map {
    @_ == 7 or croak "Usage: DOWNLOAD->version_map(FILEHANDLE, VERSION, DATA)";
    my ($obj, $fh, $version, $commit, $timestamp, $vcs, $url) = @_;
    print $fh "source-$version = $url\n" or die "$!\n";
    for my $size (keys %{$obj->{digests}{$version}{sha}}) {
	my $sum = $obj->{digests}{$version}{sha}{$size};
	print $fh "sha$size-$version = $sum\n" or die "$!\n";
    }
    $obj;
}

sub json_lock {
    @_ == 9 or croak "Usage: DOWNLOAD->json_lock(FILEHANDLE, NAME, DATA, VERSION, DATA)";
    my ($obj, $fh, $name, $data, $version, $commit, $timestamp, $vcs, $url) = @_;
    # $data->{prefer_tarball} is irrelevant for Download
    # $data->{distribution} is ignored - we are not generating tarballs, only reading them
    # $data->{hash} is used if present and set
    my ($sum, $element);
    my $hash = $data->{hash};
    if (defined $hash) {
	# XXX hash is only available if cached already, or else we have a copy of the download
	$element = $hash->element;
	my ($alg, $size) = $hash->identify;
	if (! exists $obj->{digests}{$version}{$alg}{$size}) {
	    my $dir = $obj->{dl_dir};
	    my $url = $obj->{vurl}{$version};
	    my $hash = cache_hash($url);
	    my $hashdir = "$dir/$hash.hash";
	    $sum = $hash->find_cached($hashdir, $url);
	    if (! defined $sum) {
		my $dstdir = "$dir/$hash.dir";
		my $dstfile = "$dir/$hash.src";
		# XXX see above comment, for now we require a copy of the download already present
		-f $dstfile or die "No cached $alg-$size digest for $version and file not available\n";
		$sum = $obj->{digests}{$version}{$alg}{$size} = $hash->sum_file($hashdir, $url, $dstfile);
	    }
	}
	$sum = $obj->{digests}{$version}{$alg}{$size};
    }
    $obj->_json_tarball_lock($fh, $name, $version, $url, $element, $sum);
}

1
