# Copyright 2020 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Dan Shearer, 2020

use strict;
use warnings;

use Test::More tests => 2;

# Add all dependent modules for not-forking to this array
# Make sure they match PM_DEPENDS in ../Makefile.PL
my @perlmodules = ( "Git", "Text::Glob" );

diag "\nChecking Perl modules exist";
for my $module (@perlmodules) {
    if ( require_ok $module) {
        diag "Module " . $module . " present";
    }
    else {
        BAIL_OUT "**** You need to install Perl module $module";
    }
}

# Check git is at least version 2.22
my @gitminor = split( '\.', Git::command_oneline('version') );
my $minor    = $gitminor[1];
my @gitmajor = split( ' ',  $gitminor[0] );
my $major    = $gitmajor[2];
if ( $major >= 2 && $minor >= 22 ) {
    diag "Correct: Git is at least version 2.22";
}
else {
    BAIL_OUT "**** You need at least Git version 2.22";
}

