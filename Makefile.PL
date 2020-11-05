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
    VERSION       => '0.2',
    PMLIBDIRS     => [ 'lib' ],
    EXE_FILES     => [ 'bin/not-fork' ],
    LICENSE       => 'MIT',
    ABSTRACT      => 'merge multiple upstreams without forking them',
);

