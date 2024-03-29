# Copyright 2021 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2021

# Gentoo ebuild, to be saved to your repository overlay in dev-util/not-fork

EAPI=7

inherit perl-module toolchain-funcs

DESCRIPTION="LumoSQL not-fork tool, extracts and modifies third-party sources"
HOMEPAGE="https://lumosql.org/src/not-forking/"
SRC_URI="https://lumosql.org/dist/${P}.tar.gz"
RESTRICT="mirror"

LICENSE="MIT"
SLOT="0"
KEYWORDS="amd64 arm x86"
IUSE="+fossil +git"

RDEPEND="
fossil? ( dev-vcs/fossil )
git? ( dev-vcs/git[perl] )
dev-perl/Text-Glob"
DEPEND=""
BDEPEND=""

src_prepare() {
	default
	use fossil || rm lib/NotFork/Fossil.pm
	use git || rm lib/NotFork/Git.pm
}

