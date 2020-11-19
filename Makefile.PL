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
    VERSION       => '0.2.1',
    AUTHOR	  => 'Claudio Calvelli',
    PMLIBDIRS     => [ 'lib' ],
    EXE_FILES     => [ 'bin/not-fork' ],
    PREREQ_PM     => { 'Text::Glob' => 0,
                       'Git' => 0 },
    LICENSE       => 'MIT',
    ABSTRACT      => 'merge multiple upstreams without forking them',
);

# Dependency checking in addition to PREREQ_PM is done in "make test".
#
# https://perldoc.perl.org/ExtUtils::MakeMaker says:
# "your tests should fail with missing dependencies informing
# the user more strongly that something is wrong...."
