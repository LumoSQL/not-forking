package NotFork::VCS::Git;

# Copyright 2020 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020

use strict;
use Carp;
use NotFork::Get qw(add_prereq prereq_program prereq_module);
use NotFork::VCSCommon;

our @ISA = qw(NotFork::VCSCommon);

sub new {
    @_ == 3 or croak "Usage: new NotFork::VCS::Git(NAME, OPTIONS)";
    my ($class, $name, $options) = @_;
    my $obj = $class->_new('GIT', $name, $options);
    exists $options->{branch} and $obj->{branch} = $options->{branch};
    $obj;
}

# check that we have any prerequisite software installed
sub check_prereq {
    @_ == 2 or croak "Usage: PATCH->check_prereq(RESULT)";
    my ($obj, $result) = @_;
    add_prereq($result,
	[\&prereq_module, 'Git'],
	[\&prereq_module, 'File::Path'],
	[\&prereq_module, 'POSIX'],
	[\&prereq_program, 'git', '2.22', 'version', qr/\b(\d[\.\d]*)\b/],
    );
    $obj;
}

sub _process_pending {
    my ($obj) = @_;
    if (exists $obj->{pending_get}) {
	my ($topdir, $noupdate) = @{delete $obj->{pending_get}};
	require Git;
	my $verbose = $obj->{verbose};
	$obj->{offline} and $noupdate = 1;
	my $repos = $topdir;
	$repos =~ s|[^/]*$|main_clone|;
	if (-d "$repos/.git") {
	    # assume we have already cloned
	    $verbose > 1 && ! $noupdate and print "Updating $obj->{name} in $repos\n";
	    my $git = Git->repository(WorkingCopy => $repos);
	    my $url = $git->command_oneline('config', '--get', 'remote.origin.url');
	    $url eq $obj->{repos}
		or die "Inconsistent cache: $url // $obj->{repos}\n";
	    if (! $noupdate) {
		my @q = $verbose > 2 ? ('-v') : ($verbose == 2 ? () : ('-q'));
		eval { $git->command('fetch', @q); };
		if ($@) {
		    # Git module is rather buggy... 141 is a SIGCHLD rewritten wrongly
		    $@ =~ /command returned error: 141/ or die $@;
		}
	    }
	} else {
	    # need to clone into $repos
	    $obj->{offline}
		and die "Would need to clone $obj->{repos}\nProhibited by --offline\n";
	    $verbose > 1 and print "Cloning $obj->{name}: $obj->{repos} --> $repos\n";
	    my @args = ( '--no-checkout' );
	    exists $obj->{branch} and push @args, ('-b', $obj->{branch});
	    $verbose > 2 and push @args, '-v';
	    $verbose < 2 and push @args, '-q';
	    # XXX user/password?
	    Git::command('clone', @args, $obj->{repos}, $repos);
	}
	$obj->{cache} = $topdir;
	$obj->{main_clone} = $repos;
    }
    if (exists $obj->{pending_checkout}) {
	my ($cmd, $what) = @{delete $obj->{pending_checkout}};
	exists $obj->{main_clone} or croak "Need to call GIT->get before $cmd";
	my $cache = $obj->{cache};
	my $repos = $obj->{main_clone};
	my $vcsdata = $cache;
	$vcsdata =~ s|[^/]*$|vcsdata|;
	if (-d $cache) {
	    if (open(DATA, '<', $vcsdata)) {
		my $line = <DATA>;
		close DATA;
		if (defined $line and $line eq $what) {
		    $obj->{git} = Git->repository(WorkingCopy => $cache);
		    return;
		}
	    }
	    require File::Path;
	    File::Path::remove_tree($cache);
	}
	Git::command('clone', '-q', '--no-checkout', $repos, $cache);
	$obj->{git} = Git->repository(WorkingCopy => $cache);
	$obj->{git}->command('checkout', '-q', $what);
	open(DATA, '>', $vcsdata);
	print DATA $what;
	close DATA;
    }
}

sub get {
    @_ == 2 || @_ == 3 or croak "Usage: GIT->get(DIR [, SKIP_UPDATE?])";
    my ($obj, $topdir, $noupdate) = @_;
    $obj->{pending_get} = [$topdir, $noupdate];
    $obj;
}

# calls a function for each file in the repository
sub list_files {
    @_ == 3 or croak "Usage: GIT->list_files(SUBTREE, CALLBACK)";
    my ($obj, $subtree, $call) = @_;
    $obj->_process_pending;
    exists $obj->{git} or croak "Need to call GIT->get before list_files";
    my $git = $obj->{git};
    my $cache = $obj->{cache};
    my ($fh, $c) = $git->command_output_pipe('ls-files', '-z');
    local $/ = "\0";
    $obj->_list_files($fh, $cache, 0, $subtree, $call);
    $git->command_close_pipe($fh, $c);
    $obj;
}

sub _checkout {
    my ($obj, $cmd, $what) = @_;
    exists $obj->{main_clone} || exists $obj->{pending_get}
	or croak "Need to call GIT->get before $cmd";
    $obj->{pending_checkout} = [$cmd, $what];
}

sub set_version {
    @_ == 2 or croak "Usage: GIT->set_version(VERSION)";
    my ($obj, $version) = @_;
    delete $obj->{this_version};
    my $vv;
    if (exists $obj->{version_map}) {
	exists $obj->{version_map}{$version} or die "Invalid version $version\n";
	$vv = $obj->{version_map}{$version};
    } else {
	$vv = join('', $obj->{version_prefix}, $version, $obj->{version_suffix});
    }
    _checkout($obj, 'set_version', $vv);
    $obj->{this_version} = $version;
    $obj;
}

sub set_commit {
    @_ == 2 or croak "Usage: GIT->set_commit(COMMIT)";
    my ($obj, $commit) = @_;
    delete $obj->{this_version};
    _checkout($obj, 'set_commit', $commit);
    $obj;
}

sub _git_any {
    my ($obj, $cmd) = @_;
    exists $obj->{git} and return $obj->{git};
    $obj->_process_pending;
    exists $obj->{main_clone} or croak "Need to call GIT->get before $cmd";
    return Git->repository(WorkingCopy => $obj->{main_clone});
}

# see if a commit ID is valid
sub commit_valid {
    @_ == 2 or croak "Usage: GIT->commit_valid(COMMIT_ID)";
    my ($obj, $commit) = @_;
    my $ok = 0;
    if (exists $obj->{version_map}) {
	scalar(grep { $_ eq $commit } values %{$obj->{version_map}}) and $ok = 1;
    } else {
	my $git = _git_any($obj, 'commit_valid');
	eval {
	    $git->command('log', "$commit^1..$commit");
	    $ok = 1;
	};
    }
    $ok;
}

# list all version numbers
sub all_versions {
    @_ == 1 or croak "Usage: GIT->all_versions";
    my ($obj) = @_;
    exists $obj->{version_map} and return keys %{$obj->{version_map}};
    my $git = _git_any($obj, 'all_versions');
    my ($fh, $c) = $git->command_output_pipe('show-ref');
    my ($versions) = $obj->_all_versions($fh, '\S+\s+refs/tags/', '');
    $git->command_close_pipe($fh, $c);
    @$versions;
}

# get information about a version
sub version_info {
    @_ == 2 or croak "Usage: GIT->version_info(VERSION)";
    my ($obj, $version) = @_;
    my ($id, $timestamp);
    if (exists $obj->{version_map}) {
	exists $obj->{version_map}{$version} or return ();
	$id = $obj->{version_map}{$version};
	exists $obj->{time_map}{$version}
	    and $timestamp = $obj->{time_map}{$version}
    } else {
	my $git = _git_any($obj, 'version_info');
	my ($fh, $c) = $git->command_output_pipe('show-ref', '--dereference');
	my ($versions, $commits) = $obj->_all_versions($fh, "\\S+\\s+refs/tags/", '', qr/^(\S+)\b/);
	$git->command_close_pipe($fh, $c);
	exists $commits->{$version} or return ();
	$id = $commits->{$version};
	($fh, $c) = $git->command_output_pipe('show', '--format=%ct', '-s', $id);
	while (<$fh>) {
	    chomp;
	    /^\d+$/ and $timestamp = $_;
	}
	$git->command_close_pipe($fh, $c);
	if (defined $timestamp) {
	    # do a require here, rather than a use, so we can list POSIX
	    # in the prerequisites (and not fail to load it in the
	    # unlikely case it's not present)
	    require POSIX;
	    $timestamp = POSIX::strftime('%Y-%m-%d %H:%M:%S', gmtime($timestamp));
	}
    }
    ($id, $timestamp, 'git', $obj->{repos});
}

# find the current version number; other commands fail for various
# (weird) repository setups so we do this instead; if the second
# argument is present and true, finds an "approximate" version number,
# which is the highest version tag present before the current commit
sub version {
    @_ == 1 || @_ == 2 or croak "Usage: GIT->version [(APPROXIMATE?)]";
    my ($obj, $approx) = @_;
    my ($version, $commit_id, $timestamp);
    if (exists $obj->{version_map} && exists $obj->{this_version}) {
	$version = $obj->{this_version};
	$commit_id = $obj->{version_map}{$version};
	exists $obj->{time_map}{$version}
	    and $timestamp = $obj->{time_map}{$version}
    } else {
	my $git = _git_any($obj, 'version');
	my @stat = grep { /\bbranch\.oid\b/ }
	    $git->command('status', '--porcelain=2', '--branch');
	@stat or return undef;
	$stat[0] =~ /\s(\S+)$/ or return undef;
	my $oid = $1;
	my $prefix = $obj->{version_prefix};
	my $suffix = $obj->{version_suffix};
	# XXX this does not find approximate version numbers yet
	my ($fh, $c) = $git->command_output_pipe('show-ref', '--dereference');
	my ($versions, $commits) = $obj->_all_versions($fh, "$oid\\s+refs/tags/", '', qr/^(\S+)\b/);
	$git->command_close_pipe($fh, $c);
	$version = exists $obj->{this_version} ? $obj->{this_version} : shift @$versions;
	defined $version and $version =~ s/\^.*$//;
	wantarray or return $version;
	$commit_id = $commits->{$version};
	if (! defined $commit_id) {
	    ($fh, $c) = $git->command_output_pipe('rev-parse', 'HEAD');
	    $commit_id = <$fh>;
	    $git->command_close_pipe($fh, $c);
	    defined $commit_id and chomp($commit_id);
	}
	$timestamp = $git->command_oneline('show', '--format=%ct', '-s');
	if (defined $timestamp) {
	    # do a require here, rather than a use, so we can list POSIX
	    # in the prerequisites (and not fail to load it in the
	    # unlikely case it's not present)
	    require POSIX;
	    $timestamp = POSIX::strftime('%Y-%m-%d %H:%M:%S', gmtime($timestamp));
	}
    }
    ($version, $commit_id, $timestamp);
}

sub info {
    @_ == 2 or croak "Usage: GIT->info(FILEHANDLE)";
    my ($obj, $fh) = @_;
    my $name = $obj->{name};
    print $fh "Information for $name:\n";
    print $fh "vcs = git\n";
    print $fh "url = $obj->{repos}\n";
    eval {
	my $git = _git_any($obj, 'info');
	my $branch = $git->command_oneline('branch', '--show-current');
	defined $branch and print $fh "branch = $branch\n";
    };
    my ($version, $commit_id, $timestamp) = $obj->version;
    defined $version and print $fh "version = $version\n";
    defined $commit_id and print $fh "commit_id = $commit_id\n";
    defined $timestamp and print $fh "commit_timestamp = $timestamp UTC\n";
    print $fh "\n";
    $obj;
}

sub upstream_info {
    @_ == 2 or croak "Usage: GIT->upstream_info(FILEHANDLE)";
    my ($obj, $fh) = @_;
    print $fh "vcs = git\n" or die "$!\n";
    print $fh "repository = $obj->{repos}\n" or die "$!\n";
    $obj;
}

sub version_map {
    @_ == 7 or croak "Usage: GIT->version_map(FILEHANDLE, VERSION, DATA)";
    my ($obj, $fh, $version, $commit, $timestamp, $git, $url) = @_;
    print $fh "version-$version = $commit\n" or die "$!\n";
    print $fh "time-$version = $timestamp\n" or die "$!\n";
    $obj;
}

sub json_lock {
    @_ == 9 or croak "Usage: GIT->json_lock(FILEHANDLE, NAME, DATA, VERSION, DATA)";
    my ($obj, $fh, $name, $data, $version, $commit, $timestamp, $vcs, $url) = @_;
    # XXX $data->{prefer_tarball} is currently not implemented
    # XXX $data->{distribution} is ignored - we are not generating tarballs
    # XXX $data->{hash} is ignored - we are not generating tarballs
    print $fh <<EOF or die "$!\n";
  "$name-$version": {
    "locked": {
      "type": "git",
      "url": "$url",
      "rev": "$commit"
    }
  },
EOF
}

1
