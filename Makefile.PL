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
    LICENSE       => 'MIT',
    ABSTRACT      => 'merge multiple upstreams without forking them',
);

# No longer use PREREQ_PM and PREREQ_PRINT. All dependency
# checking for Perl modules and anything else is now moved
# to t/00-check-dependencies.t run by "make test". See
# https://perldoc.perl.org/ExtUtils::MakeMaker under
# "your tests should fail with missing dependencies..."
