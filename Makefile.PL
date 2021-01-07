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
    EXE_FILES     => [ 'bin/not-fork' ],
    LICENSE       => 'MIT',
    ABSTRACT      => 'merge multiple upstreams without forking them',
);

# check for "recommended" packages

system $^X, '-Ilib', 'bin/not-fork', '--check-recommend', '--verbose=0';

