<!-- Copyright 2020 The LumoSQL Authors, see LICENSES/CC-BY-SA-4.0 -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2020 The LumoSQL Authors -->
<!-- SPDX-ArtifactOfProjectName: LumoSQL -->
<!-- SPDX-FileType: Documentation -->

# Not-Forking Tool

This directory contains the not-forking tool as developed for the 
[LumoSQL project](http://lumosql.org). Not-forking automates the task 
of maintaining changes (including patches) against one or more upstreams.
Not-Forking addresses the problem of reluctant forks (or "vendoring"), a class 
of problem that includes these cases:

* Tracking multiple upstreams, each with a different release schedule and version control system. Manual merging is difficult, but failing to merge or only occasionally merging will often result in a hard fork. LumoSQL tracks [three upstreams](https://lumosql.org/src/lumosql/dir?ci=tip&name=not-fork.d) that differ in all these ways
* Tracking an upstream where you wish to make changes that are not mergable. Without Not-Forking a manual merge is the only option even if there is only one upstream and even if the patch set is not complicated. The simplest case of this is replacing, deleting or creating whole files
* [Vendoring](https://lwn.net/Articles/836911/), where a package copies a library or module into its own tree, avoiding the versioning problems that arise when using system-provided libraries. This then becomes a standalone fork until the next copy is done, which often involves a manual porting task. Not-Forking can stop this problem arising at all
* Vendoring with version control, for example some of the [132 forks of LibVNC on GitHub](https://github.com/LibVNC/libvncserver/network/members) are for maintained, shipping products which are up to hundreds of commits behind the original. Seemingly they are manually synced with the original every year or two, but potentially Not-Forking could remove most of this manual work

The term "fork" has several meanings. All of the examples above use the same
meaning: when source code maintained elsewhere is modified locally, creating the
problem of how to maintain the modifications without also maintaining the
entire original codebase. Nobody wants to maintain code that is currently being
maintained by its original authors, and Not-Forking makes it easier to avoid that case.

If you are reading this on Github, you are looking at a read-only mirror.
The official home is the [Fossil repository](https://lumosql.org/src/not-forking),
and that is the best way to contribute and interact with the community. You 
may raise PRs on Github, but they will end up being pushed through Fossil anyway.

Here you will find the tool and its libraries, and the [full documentation](doc/not-forking.md).
It also contains an example configuration (in directory doc/examples) which can
be used for testing.

To install the tool:

```
perl Makefile.PL
make
make install     <== you will likely need root for this
```

At which point the `not-fork` command is installed in the system and its
required modules are available where your perl installation expects to
find them.

You might be wondering about runtime dependencies. That is covered in the
full documentation, but in brief, not-fork knows what is needed for each of
many different scenarios and it does not need to be addressed now. That 
means you don't need to worry about what not-fork might be used for when
you install it. Currently not-fork can use access methods including 
Git, Fossil, wget/tar and ftp. Modules will likely be added, for example for
Mercurial.

It is also possible to use the tool without installing by using the
following commands:

```
perl Makefile.PL
make
perl -Iblib/lib bin/not-fork [options] ...
```

To try the tools using the included example configuration, use:

```
perl -Iblib/lib bin/not-fork -idoc/examples [other_options] ...
```

