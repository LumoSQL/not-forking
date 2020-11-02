# Copyright 2020 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020

# Gentoo ebuild, to be saved to your repository overlay in dev-util/not-fork

EAPI=7

inherit perl-module toolchain-funcs

DESCRIPTION="LumoSQL not-fork tool, extracts and modifies third-party sources"
HOMEPAGE="https://lumosql.org/src/not-forking/"
SRC_URI="https://lumosql.org/dist/${P}.tar.gz"
RESTRICT="mirror"

LICENSE="MIT"
SLOT="0"
KEYWORDS="amd64 x86"
IUSE="+git"

RDEPEND="git? ( dev-vcs/git[perl] )"
DEPEND=""
BDEPEND=""

src_prepare() {
	default
	use git || rm lib/NotFork/Git.pm
}

