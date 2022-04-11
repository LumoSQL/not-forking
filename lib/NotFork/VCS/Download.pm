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
	vnumber => $versions[-1],
	prefix  => $prefix,
    }, $class;
    $obj;
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
    @_ == 2 or croak "Usage: PATCH->check_prereq(RESULT)";
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
    $obj;
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
    my $dir = $obj->{dl_dir};
    my $url = $obj->{vurl}{$version};
    my $hash = cache_hash($url);
    my $dstdir = "$dir/$hash.dir";
    my $dstfile = "$dir/$hash.src";
    my $dstidx = "$dir/$hash.idx";
    # if file already present, and we have checksums to verify, verify them
    -f $dstfile and $obj->_checksum($version, $dstfile);
    if (! -d $dstdir || ! -f $dstidx) {
	if (! -f $dstfile) {
	    -l $dstfile and unlink $dstfile; # remove any dangling symlink
	    my $local_source = undef;
	    if ($url =~ s|^file:/+|/|) {
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
		if (defined (my $curl = _find('curl'))) {
		    @cmd = ($curl);
		    $verbose > 2 and push @cmd, '-v';
		    $verbose < 1 and push @cmd, '-s';
		    push @cmd, '-o', $dstfile, $url;
		} elsif (defined (my $wget = _find('wget'))) {
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
	# now determine what file type we are looking at
	my @extract_pipe = ();
	my $type = _file_type($dstfile, @extract_pipe);
	while ($type =~ /^(\S+)\s*compress/) {
	    my $cp = $1;
	    if ($cp eq 'gzip' || $cp eq 'bzip2' || $cp eq 'xz') {
		my $prog = _find($cp);
		defined $prog or die "Cannot find $cp to uncompress source, please install it\n";
		push @extract_pipe, "$prog -dc";
	    } else {
		die "Don't know how to uncompress \"$cp\"\n";
	    }
	    $type = _file_type($dstfile, @extract_pipe);
	}
	my @ls_pipe = @extract_pipe;
	if ($type =~ /\btar\b.*\barchive/i) {
	    push @ls_pipe, 'tar -tf - > "$IDXFILE"';
	    push @extract_pipe, 'tar -xf -';
	} else {
	    die "Don't know how to unpack \"$type\"\n";
	}
	-d $dstdir or mkdir $dstdir or die "$dstdir: $!\n";
	local $ENV{SRCFILE} = $dstfile;
	local $ENV{IDXFILE} = $dstidx;
	local $ENV{DSTDIR} = $dstdir;
	my $cat = _find('cat');
	defined $cat or die "Cannot find 'cat' command\n";
	my $pipe_start = "cd \"\$DSTDIR\"; $cat \"\$SRCFILE\"";
	my $extract_pipe = join(' | ', $pipe_start, @extract_pipe);
	$obj->{verbose} > 1 and print "Unpacking $obj->{name} $version...\n";
	if (system($extract_pipe) != 0) {
	    $? == -1 and die "Cannot unpack $dstfile: running ($extract_pipe) failed with error $!\n";
	    $? & 0x7f and die "unpack ($extract_pipe) died with signal " . ($? & 0x7f) . "\n";
	    die "unpack ($extract_pipe) exited with status " . ($? >> 8) . "\n";
	}
	my $ls_pipe = join(' | ', $pipe_start, @ls_pipe);
	$obj->{verbose} > 1 and print "Updating content list for $obj->{name} $version...\n";
	if (system($ls_pipe) != 0) {
	    $? == -1 and die "Cannot unpack $dstfile\n";
	    $? & 0x7f and die "unpack died with signal " . ($? & 0x7f) . "\n";
	    die "unpack exited with status " . ($? >> 8) . "\n";
	}
    }
    $obj->{vnumber} = $version;
    $obj->{vdata} = $dstdir;
    $obj->{vindex} = $dstidx;
    $obj->{vcsbase} = $dstdir;
    $obj;
}

sub _find {
    my ($prog) = @_;
    for my $p (split(/:/, $ENV{PATH})) {
	-f "$p/$prog" and return "$p/$prog";
    }
    undef;
}

sub _file_type {
    my ($file, @pipe) = @_;
    local $ENV{SRCFILE} = $file;
    my $cat = _find('cat');
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
    $obj->{vnumber};
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
    my $vn = $obj->{vnumber};
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
    exists $obj->{vdata} && exists $obj->{vindex}
	or croak "Need to call DOWNLOAD->version before list_files";
    my $vdata = $obj->{vdata};
    my $vindex = $obj->{vindex};
    open(my $fh, '<', $vindex) or die "$vindex: $!\n";
    $obj->_list_files($fh, $vdata, $obj->{prefix}, $subtree, $call);
    close $fh;
    $obj;
}

1
