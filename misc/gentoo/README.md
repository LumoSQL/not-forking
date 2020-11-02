<!-- Copyright 2020 The LumoSQL Authors, see LICENSES/CC-BY-SA-4.0 -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2020 The LumoSQL Authors -->
<!-- SPDX-ArtifactOfProjectName: LumoSQL -->
<!-- SPDX-FileType: Documentation -->
<!-- SPDX-FileComment: Original by Claudio Calvelli, 2020 -->

# Gentoo ebuild

This directory contains an example ebuild for not-fork; to use it you
are supposed to have your own overlay where you put your own ebuilds,
and the contents of this directory go to dev-util/not-fork; in future
we may provide our own overlay

The ebuild contains a single USE flag, `git`, to control dependency on an
installed `dev-vcs/git` with perl support.

