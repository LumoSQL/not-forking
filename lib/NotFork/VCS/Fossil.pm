package NotFork::VCS::Fossil;

# Copyright 2020 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020

use strict;
use Carp;
use NotFork::Get qw(add_prereq prereq_program);
use NotFork::VCSCommon;

our @ISA = qw(NotFork::VCSCommon);

sub new {
    @_ == 3 or croak "Usage: new NotFork::VCS::Fossil(NAME, OPTIONS)";
    my ($class, $name, $options) = @_;
    my $obj = $class->_new('FOSSIL', $name, $options);
    $obj;
}

sub get {
    @_ == 2 || @_ == 3 or croak "Usage: FOSSIL->get(DIR [, SKIP_UPDATE?])";
    my ($obj, $fossil, $noupdate) = @_;
    $obj->{offline} and $noupdate = 1;
    my $verbose = $obj->{verbose};
    my $fossil_db = $fossil;
    $fossil_db =~ s|/[^/]*$|/db|;
    my $repo_ok = 0;
    if (-f $fossil_db && -d $fossil) {
	# assume we have already cloned
	my $url = _fossil_get($fossil, 1, 'remote');
	if (! defined $url || $url eq '') {
	    # could be an incomplete open, so try doing another one
	    unlink("$fossil/.fslckout");
	    eval {
		_fossil($fossil, 'open', $fossil_db);
		$url = _fossil_get($fossil, 0, 'remote');
	    };
	    if ($@) {
		print STDERR "Error from fossil:\n$@";
		print STDERR "This probably means that a previous clone has failed\n";
		print STDERR "Trying to repeat the clone\n";
		unlink($fossil_db);
		rmdir($fossil); # this may fail if it's nonempty, so...
		rename($fossil, "$fossil.failed");
		# we could use File::Path to nuke it as well
	    }
	}
	if (defined $url && $url ne '') {
	    $url eq $obj->{repos}
		or die "Inconsistent cache: $url // $obj->{repos}\n";
	    if (! $noupdate) {
		$verbose > 1 and print "Updating $obj->{name} in $fossil\n";
		_fossil($fossil, 'pull', @{$obj->{fossil_args}});
	    }
	    $repo_ok = 1;
	}
    }
    if (! $repo_ok) {
	# need to clone into $fossil_src
	$obj->{offline}
	    and die "Would need to clone $obj->{repos}\nProhibited by --offline\n";
	$verbose > 1 and print "Cloning $obj->{name}: $obj->{repos} --> $fossil_db\n";
	my @args;
	$verbose > 2 and push @args, '-v';
	$obj->{fossil_args} = \@args;
	# XXX user/password?
	mkdir $fossil;
	_fossil($fossil, 'clone', @args, $obj->{repos}, $fossil_db);
	_fossil($fossil, 'open', $fossil_db);
    }
    $obj->{fossil} = $fossil;
    $obj;
}

# check that we have any prerequisite software installed
sub check_prereq {
    @_ == 2 or croak "Usage: FOSSIL->check_prereq(RESULT)";
    my ($obj, $result) = @_;
    add_prereq($result,
	[\&prereq_program, 'fossil', '1.0', 'version', qr/\b(\d[\.\d]*)\b/],
	[\&prereq_modile, 'Digest::SHA'],
	[\&prereq_modile, 'File::Temp'],
    );
    $obj;
}

# calls a function for each file in the repository
sub list_files {
    @_ == 3 or croak "Usage: FOSSIL->list_files(SUBTREE, CALLBACK)";
    my ($obj, $subtree, $call) = @_;
    exists $obj->{fossil} or croak "Need to call FOSSIL->get before list_files";
    my $fossil = $obj->{fossil};
    my $fh = _fossil_read($fossil, 0, 'ls');
    $obj->_list_files($fh, $fossil, 0, $subtree, $call);
    # this does not include files like "manifest" so we look for them specially
    for my $sf (qw(manifest manifest.tags manifest.uuid)) {
	-f "$fossil/$sf" and $call->($sf, "$fossil/$sf");
    }
    _fossil_close($fh);
    $obj;
}

sub set_version {
    @_ == 2 or croak "Usage: FOSSIL->set_version(VERSION)";
    my ($obj, $version) = @_;
    exists $obj->{fossil} or croak "Need to call FOSSIL->get before set_version";
    my $vv;
    delete $obj->{this_version};
    if (exists $obj->{version_map}) {
	exists $obj->{version_map}{$version} or die "Invalid version $version\n";
	$vv = $obj->{version_map}{$version};
    } else {
	$vv = join('', 'tag:', $obj->{version_prefix}, $version, $obj->{version_suffix});
    }
    # if the previous checkout was interrupted, fossil will give an error in this
    # one; the "fossil revert" fixes that
    _fossil_quiet($obj->{fossil}, 'revert', $vv);
    _fossil_quiet($obj->{fossil}, 'checkout', $vv);
    $obj->{this_version} = $version;
    $obj;
}

sub set_commit {
    @_ == 2 or croak "Usage: FOSSIL->set_commit(COMMIT)";
    my ($obj, $commit) = @_;
    exists $obj->{fossil} or croak "Need to call FOSSIL->get before set_commit";
    _fossil_quiet($obj->{fossil}, 'checkout', $commit);
    $obj;
}

# see if a commit ID is valid
sub commit_valid {
    @_ == 2 or croak "Usage: FOSSIL->commit_valid(COMMIT_ID)";
    my ($obj, $commit) = @_;
    _fossil_check($obj->{fossil}, 'timeline', '-n', 1, $commit);
}

# list all version numbers
sub all_versions {
    @_ == 1 or croak "Usage: FOSSIL->all_versions";
    my ($obj) = @_;
    exists $obj->{version_map} and return keys %{$obj->{version_map}};
    exists $obj->{fossil} or croak "Need to call FOSSIL->get before version";
    my $fossil = $obj->{fossil};
    my $fh = _fossil_read($fossil, 0, 'tag', 'ls');
    my ($versions) = $obj->_all_versions($fh, '', '');
    _fossil_close($fh);
    @$versions;
}

# get information about a version
sub version_info {
    @_ == 2 or croak "Usage: Fossil->version_info(VERSION)";
    my ($obj, $version) = @_;
    my $fossil = $obj->{fossil};
    my $repo = _fossil_get($fossil, 0, 'remote');
    my $tag;
    if (exists $obj->{version_map}) {
	exists $obj->{version_map}{$version} or return ();
	if (exists $obj->{time_map}{$version}) {
	    return ($obj->{version_map}{$version},
		    $obj->{time_map}{$version},
		    'fossil',
		    $repo);
	}
	$tag = $obj->{version_map}{$version};
    } else {
	$tag = "tag:$obj->{version_prefix}$version$obj->{version_suffix}";
    }
    my $commit_id = undef;
    my $timestamp = undef;
    my $fh = _fossil_read($fossil, 0, 'info', $tag);
    while (defined (my $rl = <$fh>)) {
	$rl =~ /^hash\s*:\s*(\S+)\s+(\S+)\s+(\S+)\b/
	    and ($commit_id, $timestamp) = ($1, "$2 $3");
    }
    _fossil_close($fh);
    ($commit_id, $timestamp, 'fossil', _fossil_get($fossil, 0, 'remote'));
}

# find the current version number; if the second argument is present and true,
# finds an "approximate" version number, which is the highest version tag present
# before the current commit
sub version {
    @_ == 1 || @_ == 2 or croak "Usage: FOSSIL->version [(APPROXIMATE?)]";
    my ($obj, $approx) = @_;
    exists $obj->{fossil} or croak "Need to call FOSSIL->get before version";
    my $fossil = $obj->{fossil};
    my ($version, $commit_id, $timestamp);
    if (exists $obj->{version_map} && exists $obj->{this_version}) {
	$version = $obj->{this_version};
	wantarray or return $version;
	($commit_id, $timestamp) = $obj->version_info($version);
    } else {
	# get a checkout ID and maybe a tag from "fossil status"
	my $fh = _fossil_read($fossil, 0, 'status');
	while (defined (my $rl = <$fh>)) {
	    $rl =~ /^checkout:\s*(\S+)\s+(\S+)\s+(\S+)\b/
		and ($commit_id, $timestamp) = ($1, "$2 $3");
	    $rl =~ s/^tags:\s*\b// or next;
	    $rl =~ s/\s+$//;
	    my @rl = split(/,\s*/, $rl);
	    ($version) = $obj->_version_grep(\@rl);
	}
	_fossil_close($fh);
    }
    # if we have the information, or else we aren't looking for an
    # approximate version, we're done
    defined $version || ! $approx
	and return wantarray ? ($version, $commit_id, $timestamp) : $version;
    # TODO - get approximate version
    ($version, $commit_id, $timestamp);
}

sub info {
    @_ == 2 or croak "Usage: FOSSIL->info(FILEHANDLE)";
    my ($obj, $fh) = @_;
    my $name = $obj->{name};
    if (exists $obj->{fossil}) {
	my $fossil = $obj->{fossil};
	print $fh "Information for $name:\n";
	print $fh "vcs = fossil\n";
	print $fh "url = ", _fossil_get($fossil, 0, 'remote'), "\n";
	my ($version, $commit_id, $timestamp) = $obj->version;
	defined $version and print $fh "version = $version\n";
	defined $commit_id and print $fh "commit_id = $commit_id\n";
	defined $timestamp and print $fh "commit_timestamp = $timestamp UTC\n";
	print $fh "\n";
    } else {
	print $fh "No information for $name\n";
    }
    $obj;
}

sub upstream_info {
    @_ == 2 or croak "Usage: FOSSIL->upstream_info(FILEHANDLE)";
    my ($obj, $fh) = @_;
    my $fossil = $obj->{fossil};
    print $fh "vcs = fossil\n" or die "$!\n";
    print $fh "repository = ", _fossil_get($fossil, 0, 'remote'), "\n" or die "$!\n";
    $obj;
}

sub version_map {
    @_ == 7 or croak "Usage: FOSSIL->version_map(FILEHANDLE, VERSION, DATA)";
    my ($obj, $fh, $version, $commit, $timestamp, $vcs, $url) = @_;
    print $fh "version-$version = $commit\n" or die "$!\n";
    print $fh "time-$version = $timestamp\n" or die "$!\n";
    $obj;
}

sub nix_lock {
    @_ == 8 or croak "Usage: FOSSIL->nix_lock(FILEHANDLE, NAME, VERSION, DATA)";
    my ($obj, $fh, $name, $version, $commit, $timestamp, $vcs, $url) = @_;
    my $path = "/tarball/$commit/$name-$version.tar.gz";
    eval 'use Digest::SHA';
    $@ and die "Please install the Digest::SHA module to generate checksums\n";
    eval 'use File::Temp';
    $@ and die "Please install the File::Temp module to generate checksums\n";
    my $sha = Digest::SHA->new(256);
    my $fossil = $obj->{fossil};
    my ($tmpfh, $tmpfile) = File::Temp::tempfile(CLEANUP => 1);
    _fossil_quiet($fossil, 'tarball', $commit, $tmpfile, '--name', "$name-$version");
    $sha->addfile($tmpfile);
    unlink($tmpfile);
    my $sum = $sha->hexdigest;
    $obj->_nix_lock($fh, $name, $version, "$url$path", $sum);
}

sub _fossil {
    my ($dir, @cmd) = @_;
    local $SIG{CHLD} = sub { };
    my $pid = fork;
    defined $pid or die "Cannot fork: $!\n";
    if (! $pid) {
	chdir $dir or die "$dir: $!\n";
	exec 'fossil', @cmd
	    or die "exec fossil: $!\n";
    }
    waitpid($pid, 0) < 0 and die "wait: $!\n";
    $? == 0 and return;
    $? & 0x7f and die "fossil died with signal " . ($? & 0x7f) . "\n";
    die "fossil exited with status " . ($? >> 8) . "\n";
}

sub _fossil_quiet {
    my ($dir, @cmd) = @_;
    local $SIG{CHLD} = sub { };
    my $pid = fork;
    defined $pid or die "Cannot fork: $!\n";
    if (! $pid) {
	chdir $dir or die "$dir: $!\n";
	open(STDOUT, '>/dev/null');
	exec 'fossil', @cmd
	    or die "exec fossil: $!\n";
    }
    waitpid($pid, 0) < 0 and die "wait: $!\n";
    $? == 0 and return;
    $? & 0x7f and die "fossil died with signal " . ($? & 0x7f) . "\n";
    die "fossil exited with status " . ($? >> 8) . "\n";
}

sub _fossil_read {
    my ($dir, $ignore_error, @cmd) = @_;
    my $fh;
    my $pid = open($fh, '-|');
    defined $pid or die "Cannot fork: $!\n";
    if (! $pid) {
	chdir $dir or die "$dir: $!\n";
	$ignore_error and open(STDERR, '>', '/dev/null');
	exec 'fossil', @cmd
	    or die "exec fossil: $!\n";
    }
    $fh;
}

sub _fossil_close {
    my ($fh) = @_;
    close $fh and return;
    $! and die "fossil: $!\n";
    $? & 0x7f and die "fossil died with signal " . ($? & 0x7f) . "\n";
    die "fossil exited with status " . ($? >> 8) . "\n";
}

sub _fossil_get {
    my ($dir, $ignore_error, @cmd) = @_;
    my $fh = _fossil_read($dir, $ignore_error, @cmd);
    local $/ = undef;
    my $res = <$fh>;
    eval { _fossil_close($fh); };
    $@ && ! $ignore_error and die $@;
    defined $res and $res =~ s/\n+$//;
    return $res;
}

sub _fossil_check {
    my ($dir, @cmd) = @_;
    local $SIG{CHLD} = sub { };
    my $pid = fork;
    defined $pid or die "Cannot fork: $!\n";
    if (! $pid) {
	chdir $dir or die "$dir: $!\n";
	open(STDOUT, '>/dev/null');
	open(STDERR, '>/dev/null');
	exec 'fossil', @cmd
	    or die "exec fossil: $!\n";
    }
    waitpid($pid, 0) < 0 and die "wait: $!\n";
    $? == 0 and return 1;
    $? & 0x7f and die "fossil died with signal " . ($? & 0x7f) . "\n";
    return 0;
}

1
