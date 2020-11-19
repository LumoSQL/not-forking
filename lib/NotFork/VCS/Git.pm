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
	[\&prereq_program, 'git', '2.22', 'version', qr/\b(\d[\.\d]*)\b/],
    );
    $obj;
}

sub get {
    @_ == 2 || @_ == 3 or croak "Usage: GIT->get(DIR [, SKIP_UPDATE?])";
    my ($obj, $dir, $noupdate) = @_;
    require Git;
    my $git;
    my $verbose = $obj->{verbose};
    if (-d "$dir/.git") {
	# assume we have already cloned
	$verbose > 1 && ! $noupdate and print "Updating $obj->{name} in $dir\n";
	$git = Git->repository(WorkingCopy => $dir);
	my $url = $git->command_oneline('config', '--get', 'remote.origin.url');
	$url eq $obj->{repos}
	    or die "Inconsistent cache: $url // $obj->{repos}\n";
	# previous run may have switched to a branch, undo that so the
	# following 'pull' works -- we may want to record if this is needed
	# instead of always running it and ignoring the error if it wasn't
	# necessary
	eval { $git->command(['switch', '-q', '-'], STDERR => 0 ); };
	if (! $noupdate) {
	    my @q = $verbose > 2 ? ('-v') : ($verbose == 2 ? () : ('-q'));
	    eval { $git->command('pull', @q); };
	    if ($@) {
		# Git module is rather buggy... 141 is a SIGCHLD rewritten wrongly
		$@ =~ /command returned error: 141/ or die $@;
	    }
	}
    } else {
	# need to clone into $dir
	$verbose > 1 and print "Cloning $obj->{name}: $obj->{repos} --> $dir\n";
	my @args;
	exists $obj->{branch} and push @args, ('-b', $obj->{branch});
	$verbose > 2 and push @args, '-v';
	$verbose < 2 and push @args, '-q';
	# XXX user/password?
	Git::command('clone', @args, $obj->{repos}, $dir);
	$git = Git->repository(WorkingCopy => $dir);
    }
    $obj->{git} = $git;
    $obj->{cache} = $dir;
    $obj;
}

# calls a function for each file in the repository
sub list_files {
    @_ == 3 or croak "Usage: GIT->list_files(SUBTREE, CALLBACK)";
    my ($obj, $subtree, $call) = @_;
    exists $obj->{git} or croak "Need to call GIT->get before list_files";
    my $git = $obj->{git};
    my $cache = $obj->{cache};
    my ($fh, $c) = $git->command_output_pipe('ls-files', '-z');
    local $/ = "\0";
    $obj->_list_files($fh, $cache, 0, $subtree, $call);
    $git->command_close_pipe($fh, $c);
    $obj;
}

sub set_version {
    @_ == 2 or croak "Usage: GIT->set_version(VERSION)";
    my ($obj, $version) = @_;
    exists $obj->{git} or croak "Need to call GIT->get before set_version";
    my $vv = join('', $obj->{version_prefix}, $version, $obj->{version_suffix});
    $obj->{git}->command('checkout', '-q', $vv);
    $obj;
}

sub set_commit {
    @_ == 2 or croak "Usage: GIT->set_commit(COMMIT)";
    my ($obj, $commit) = @_;
    exists $obj->{git} or croak "Need to call GIT->get before set_commit";
    $obj->{git}->command('checkout', '-q', $commit);
    $obj;
}

# list all version numbers
sub all_versions {
    @_ == 1 or croak "Usage: GIT->all_versions";
    my ($obj) = @_;
    exists $obj->{git} or croak "Need to call GIT->get before version";
    my $git = $obj->{git};
    my ($fh, $c) = $git->command_output_pipe('show-ref');
    my @versions = $obj->_all_versions($fh, '\S+\s+refs/tags/', '');
    $git->command_close_pipe($fh, $c);
    @versions;
}

# find the current version number; other commands fail for various
# (weird) repository setups so we do this instead; if the second
# argument is present and true, finds an "approximate" version number,
# which is the highest version tag present before the current commit
sub version {
    @_ == 1 || @_ == 2 or croak "Usage: GIT->version [(APPROXIMATE?)]";
    my ($obj, $approx) = @_;
    exists $obj->{git} or croak "Need to call GIT->get before version";
    my $git = $obj->{git};
    my @stat = grep { /\bbranch\.oid\b/ }
	$git->command('status', '--porcelain=2', '--branch');
    @stat or return undef;
    $stat[0] =~ /\s(\S+)$/ or return undef;
    my $oid = $1;
    my $prefix = $obj->{version_prefix};
    my $suffix = $obj->{version_suffix};
    # XXX this does not find approximate version numbers yet
    my ($fh, $c) = $git->command_output_pipe('show-ref', '--dereference');
    my @versions = $obj->_all_versions($fh, "$oid\\s+refs/tags/", '');
    $git->command_close_pipe($fh, $c);
    my $version = shift @versions;
    defined $version and $version =~ s/\^.*$//;
    wantarray or return $version;
    ($fh, $c) = $git->command_output_pipe('rev-parse', 'HEAD');
    my $commit_id = <$fh>;
    $git->command_close_pipe($fh, $c);
    defined $commit_id and chomp($commit_id);
    ($version, $commit_id);
}

sub info {
    @_ == 2 or croak "Usage: GIT->info(FILEHANDLE)";
    my ($obj, $fh) = @_;
    my $name = $obj->{name};
    if (exists $obj->{git}) {
	my $git = $obj->{git};
	print $fh "Information for $name:\n";
	print $fh "url = ",
	      $git->command_oneline('config', '--get', 'remote.origin.url'), "\n";
	eval {
	    my $branch = $git->command_oneline('branch', '--show-current');
	    defined $branch and print $fh "branch = $branch\n";
	};
	my ($version, $commit_id) = $obj->version;
	defined $version and print $fh "version = $version\n";
	defined $commit_id and print $fh "commit_id = $commit_id\n";
	print $fh "\n";
    } else {
	print $fh "No information for $name\n";
    }
    $obj;
}

1
