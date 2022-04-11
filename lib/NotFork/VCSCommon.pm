package NotFork::VCSCommon;

# Copyright 2020 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020

use strict;
use Carp;

sub _new {
    my ($class, $id, $name, $options) = @_;
    exists $options->{repos} || exists $options->{repository}
	or die "Missing repository\n";
    my $repos = exists $options->{repos} ? $options->{repos} : $options->{repository};
    my $obj = bless {
	repos   => $repos,
	name    => $name,
	verbose => 1,
	offline => 0,
	_id     => $id,
    }, $class;
    exists $options->{user} and $obj->{user} = $options->{user};
    exists $options->{password} and $obj->{password} = $options->{password};
    my ($prefix, $suffix) = ('', '');
    if (exists $options->{version}) {
	($prefix, $suffix) = $options->{version} =~ /^(\S+)\s+(.*)$/
			   ? ($prefix, $suffix)
			   : ($options->{version}, '');
    }
    $obj->{version_prefix} = $prefix;
    $obj->{version_suffix} = $suffix;
    my (%version_map, %time_map);
    for my $v (keys %$options) {
	if ($v =~ /^version-(.*)$/) {
	    $version_map{$1} = $options->{$v};
	}
	if ($v =~ /^time-(.*)$/) {
	    $time_map{$1} = $options->{$v};
	}
    }
    scalar(keys %version_map) and $obj->{version_map} = \%version_map;
    scalar(keys %time_map) and $obj->{time_map} = \%time_map;
    $obj;
}

sub _croak {
    my ($obj, $msg) = @_;
    my $id = $obj ? $obj->{_id} : 'vcs';
    return "Usage: $id$msg";
}

sub verbose {
    @_ == 1 || @_ == 2 or croak _croak($_[0], "->verbose [(LEVEL)]");
    my $obj = shift;
    @_ or return $obj->{verbose};
    $obj->{verbose} = shift(@_) || 0;
    $obj;
}

sub offline {
    @_ == 1 || @_ == 2 or croak _croak($_[0], "->offline [(LEVEL)]");
    my $obj = shift;
    @_ or return $obj->{offline};
    $obj->{offline} = shift(@_) || 0;
    $obj;
}

sub local_mirror {
    @_ == 2 or croak _croak($_[0], "->local_mirror(\\\@dirs)");
    my ($obj, $list) = @_;
    $obj->{local_mirror} = $list;
    $obj;
}

# name used to index elements in download cache; we use the repository URL
# and, if specified, the branch (this would allow to have two separate
# repositories differing only by the branch, and not interfere with each
# other)
sub cache_index {
    @_ == 1 or croak _croak($_[0], "->cache_index");
    my ($obj) = @_;
    my $ci = $obj->{repos};
    defined $obj->{branch} and $ci .= " " . $obj->{branch};
    $ci;
}

# helper function for a VCS's list_files, called with an open filehandle,
# a base directory where to find the files, a number of directories to strip
# off the name and the same arguments as list_files
sub _list_files {
    @_ == 6 or croak "Usage: VCS->_list_files(FILEHANDLE, DIR, PREFIX, SUBTREE, CALLBACK)";
    my ($obj, $fh, $dir, $prefix, $subtree, $call) = @_;
    my $sl = defined $subtree ? length $subtree : 0;
FILE:
    while (defined (my $rl = <$fh>)) {
	chomp $rl;
	my $sf = $rl;
	my $p = $prefix;
	while ($p-- > 0) {
	    $sf =~ s:^.*?/:: or next FILE;
	}
	if (defined $subtree) {
	    substr($sf, 0, $sl) ne $subtree and next;
	    substr($sf, $sl, 1) ne '/' and next;
	    substr($sf, 0, $sl + 1) = '';
	}
	$call->($sf, "$dir/$rl");
    }
    $obj;
}

# regular expression to determine if something is a likely version number,
# only used when the configuration does not specify a prefix and/or suffix;
# for now we just ask that it starts with a number but we could have a more
# specific filter if required
my $likely_version = qr/^\d/;

# helper function for a VCS's all_versions, called with an open filehandle and
# two regular expression indicating common prefixes and suffixes added by the
# VCS (in addition to the prefix and suffix specified by upstream.conf which
# are repository-specific)
sub _all_versions {
    @_ == 4 || @_ == 5
	or croak "Usage: VCS->_all_versions(FILEHANDLE, PREFIX, SUFFIX, [ID_FIND])";
    my ($obj, $fh, $cprefix, $csuffix, $id_find) = @_;
    my $rprefix = $obj->{version_prefix};
    my $rsuffix = $obj->{version_suffix};
    my @versions = ();
    my %commits = ();
    my $re = qr/^$cprefix$rprefix(.*)$rsuffix$csuffix\s*$/;
    while (defined (my $rl = <$fh>)) {
	$rl =~ $re or next;
	my $vn = $1;
	$rprefix eq '' && $rsuffix eq '' && ($vn !~ $likely_version) and next;
	push @versions, $vn;
	defined $id_find or next;
	$rl =~ $id_find or next;
	$commits{$vn} = $1;
    }
    (\@versions, \%commits);
}

# filters an array of tags and returns any which look like a version number
sub _version_grep {
    @_ == 2 or croak "Usage: VCS->_version_grep(ARRAY)";
    my ($obj, $array) = @_;
    my $rprefix = $obj->{version_prefix};
    my $rsuffix = $obj->{version_suffix};
    my @versions = ();
    my $re = qr/^$rprefix(.*)$rsuffix\s*$/;
    for my $rl (@$array) {
	$rl =~ $re or next;
	my $vn = $1;
	$rprefix eq '' && $rsuffix eq '' && ($vn !~ $likely_version) and next;
	push @versions, $vn;
    }
    @versions;
}

sub _nix_lock {
    my ($obj, $fh, $name, $version, $url, $sum) = @_;
    print $fh <<EOF or die "$!\n";
  "$name-$version": {
    "locked": {
      "sha256": "$sum",
      "type": "tarball",
      "url": "$url",
    }
  },
EOF
}

1
