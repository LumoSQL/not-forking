package NotFork::VCS::Download;

# Copyright 2020 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020

use strict;
use Carp;
use NotFork::Get qw(version_convert cache_hash add_prereq add_prereq_or prereq_program);
use NotFork::VCSCommon;

our @ISA = qw(NotFork::VCSCommon);

sub new {
    @_ == 3 or croak "Usage: new NotFork::VCS::Download(NAME, OPTIONS)";
    my ($class, $name, $options) = @_;
    my %versions = ();
    my %vptr = ();
    my $compare = $options->{compare};
    for my $option (keys %$options) {
	$option =~ /^source-(.*)$/ or next;
	$versions{$1} = $options->{$option};
	$vptr{$1} = version_convert($1, $compare);
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
    add_prereq_or($result,
	[\&prereq_program, 'curl'],
	[\&prereq_program, 'wget'],
    );
    add_prereq($result,
	[\&prereq_program, 'file'],
    );
    ref $obj or return $obj;
    # we should check for what this download actually needs...
    # add_prereq($result,
	# [\&prereq_program, 'tar'],
	# [\&prereq_program, 'gzip'],
	# [\&prereq_program, 'bzip2'],
	# [\&prereq_program, 'xz'],
    # );
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

sub set_version {
    @_ == 2 or croak "Usage: DOWNLOAD->set_version(VERSION)";
    my ($obj, $version) = @_;
    exists $obj->{vurl}{$version} or die "No such version: $version\n";
    exists $obj->{dl_dir} or die "Need to call DOWNLOAD->get before set_version\n";
    my $dir = $obj->{dl_dir};
    my $url = $obj->{vurl}{$version};
    my $hash = cache_hash($url);
    my $dstdir = "$dir/$hash.dir";
    my $dstidx = "$dir/$hash.idx";
    if (! -d $dstdir || ! -f $dstidx) {
	my $dstfile = "$dir/$hash.src";
	if (! -f $dstfile) {
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
		die "Don't know how to download files, please install curl or wget\n";
	    }
	    if (system(@cmd) != 0) {
		$? == -1 and die "Cannot execute $cmd[0]\n";
		$? & 0x7f and die "$cmd[0] died with signal " . ($? & 0x7f) . "\n";
		die "$cmd[0] exited with status " . ($? >> 8) . "\n";
	    }
	    -f $dstfile or die "$cmd[0] failed to download $url\n";
	}
	# now determine what file type we are looking at
	my @extract_pipe = ();
	my $type = _file_type($dstfile, @extract_pipe);
	while ($type =~ /^(\S+)\s*compress/) {
	    my $cp = $1;
	    if ($cp eq 'gzip') {
		push @extract_pipe, 'gzip -dc';
	    } elsif ($cp eq 'bzip2') {
		push @extract_pipe, 'bzip2 -dc';
	    } elsif ($cp eq 'XZ') {
		push @extract_pipe, 'xz -dc';
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
	my $extract_pipe = join(' | ', 'cd "$DSTDIR"; cat "$SRCFILE"', @extract_pipe);
	$obj->{verbose} > 1 and print "Unpacking $obj->{name} $version...\n";
	if (system($extract_pipe) != 0) {
	    $? == -1 and die "Cannot unpack $dstfile: running ($extract_pipe) failed with error $!\n";
	    $? & 0x7f and die "unpack ($extract_pipe) died with signal " . ($? & 0x7f) . "\n";
	    die "unpack ($extract_pipe) exited with status " . ($? >> 8) . "\n";
	}
	my $ls_pipe = join(' | ', 'cd "$DSTDIR"; cat "$SRCFILE"', @ls_pipe);
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
    my $pipe = join(' | ', 'cat "$SRCFILE"', @pipe, 'file -');
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

sub info {
    @_ == 2 or croak "Usage: DOWNLOAD->info(FILEHANDLE)";
    my ($obj, $fh) = @_;
    my $name = $obj->{name};
    my $vn = $obj->{vnumber};
    print $fh "Information for $name:\n";
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
