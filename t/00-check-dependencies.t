# Copyright 2020 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Dan Shearer, 2020

use strict;
use warnings;

use Test::More tests => 1;

# Add all dependent modules for not-forking to this array
# Make sure they match PM_DEPENDS in ../Makefile.PL
my @perlmodules = ( "Text::Glob" );

diag "\nChecking Perl modules exist";
for my $module (@perlmodules) {
    if ( require_ok $module) {
        diag "Module " . $module . " present";
    }
    else {
        BAIL_OUT "**** You need to install Perl module $module";
    }
}

