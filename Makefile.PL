# Copyright 2020 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Notfork',
    DISTNAME      => 'not-fork',
    VERSION_FROM  => 'bin/not-fork',
    AUTHOR        => 'Claudio Calvelli',
    PMLIBDIRS     => [ 'lib' ],
    EXE_FILES     => [ qw(bin/not-fork bin/fragment-diff bin/fragment-patch) ],
    LICENSE       => 'MIT',
    ABSTRACT      => 'merge multiple upstreams without forking them',
    PREREQ_PM     => {
	# most of these modules will always be installed, but just in case...
	'Carp'             => 0,
	'Digest::SHA'      => 0,
	'Exporter'         => 0,
	'Fcntl'            => 0,
	'File::Copy'       => 0,
	'File::Find'       => 0,
	'File::Path'       => 0,
	'File::Temp'       => 0,
	'FindBin'          => 0,
	'Getopt::Long'     => 0,
	'IO::Handle'       => 0,
	'Text::ParseWords' => 0,
    },
);

# check for "recommended" packages

system $^X, '-Ilib', 'bin/not-fork', '--check-recommend', '--verbose=0';

