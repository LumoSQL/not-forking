<!-- Copyright 2020 The LumoSQL Authors, see LICENSES/CC-BY-SA-4.0 -->

<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2020 The LumoSQL Authors -->
<!-- SPDX-ArtifactOfProjectName: LumoSQL -->
<!-- SPDX-FileType: Documentation -->
<!-- SPDX-FileComment: Original by Dan Shearer, October 2020 -->

# The Not-Forking Tool

Not-forking avoids duplicating the source code of one project within another
project. This is something that is not handled by [version control systems](https://en.wikipedia.org/wiki/Distributed_version_control) such as Fossil, Git, or GitHub. 

Not-forking **avoids project-level forking** by largely automating change management in ways that 
a version control system cannot.

The following diagram represents the simplest case of the problem that Not-forking solves, where 
some external piece of software, here called Upstream, forms a part of a new Combined Project.
Upstream is not a library provided on your system, because then you could link to it. It is source
code that you incorporate into Combined Project:

``` pikchr
Upstream: file "Upstream project" "file repository" fit rad 10px
           file same rad 10px at 0.1cm right of Upstream
           move ; move
        
MyProj:    file "Combined Project" "file repository" fit rad 10px with .n at Upstream.se+(0.5,-0.5)
MyProj2:   file same rad 10px at 0.1cm right of MyProj

arrow from Upstream.s down 1.5cm then right 1 to MyProj.w rad 20px thick
```

Some questions immediately arise:

* Should you import Upstream into your source code management system?
* If Upstream makes modifications, how can you pull those modifications into Combined Project safely?
* If Combined Project has changed files in Upstream, how can you then merge the changes and any new changes made in Upstream?

This is how pressure arises to start maintaining Upstream code within the
Combined Project tree, because it is just simpler. But that brings the very big
problem of the Reluctant Project Fork. A Reluctant Project Fork, or vendoring
as the [Debian Project](https://debian.org) calls it, is where Combined
Project's version of Upstream starts to drift from the original Upstream. 
Nobody wants to maintain code that is currently being
maintained by its original authors if it can be avoided, but it can become complicated
to avoid that. Not-Forking makes this a much easier problem to solve.

Not-forking addresses more complicated scenarios, such as when two
unrelated projects are upstream of Combined Project:

``` pikchr
Upstream1: file "Upstream 1" "files" fit rad 10px
           file same rad 10px at 0.1cm right of Upstream1
           move ; move
Upstream2: file "Upstream 2" "files" fit rad 10px
           file same rad 10px at 0.1cm right of Upstream2
           down
        
MyProj:    file "Combined Project" "files" fit rad 10px with .n at Upstream1.se+(0.5,-0.5)
MyProj2:   file same rad 10px at 0.1cm right of MyProj

arrow from Upstream1.s down 1.5cm then right 1 to MyProj.w rad 20px thick
arrow from Upstream2.s down 1.5cm then left 1 to MyProj2.e rad 20px thick
```



In more detail, the problem of project forking includes these cases:

* Tracking multiple upstreams, each with a different release schedule and version control system. Manual merging is difficult, but failing to merge or only occasionally merging will often result in a hard fork. LumoSQL tracks [three upstreams](https://lumosql.org/src/lumosql/dir?ci=tip&name=not-fork.d) that differ in all these ways
* Tracking an upstream where you wish to make changes that are not mergable. Without Not-Forking a manual merge is the only option even if there is only one upstream and even if the patch set is not complicated. The simplest case of this is replacing, deleting or creating whole files
* [Vendoring](https://lwn.net/Articles/836911/), where a package copies a library or module into its own tree, avoiding the versioning problems that arise when using system-provided libraries. This then becomes a standalone fork until the next copy is done, which often involves a manual porting task. Not-Forking can stop this problem arising at all
* Vendoring with version control, for example some of the [132 forks of LibVNC on GitHub](https://github.com/LibVNC/libvncserver/network/members) are for maintained, shipping products which are up to hundreds of commits behind the original. Seemingly they are manually synced with the original every year or two, but potentially Not-Forking could remove most of this manual work

The term "fork" has several meanings. All of the examples above use the same
meaning: when source code maintained elsewhere is modified locally, creating the
problem of how to maintain the modifications without also maintaining the
entire original codebase. 

# How to Get Not-Forking

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

# Disambiguation of "Fork"

Here are some meanings for the word "fork" that are nothing to do with Not-Forking:

In Fossil, a "fork" is just a point where a linear branch of development
splits into two linear branches by the same name.

Unless I'm  mistaken, in Git,  a "fork" is something  entirely different
and has nothing to  do with branching per se, but  is rather simply just
another clone of the repository.




