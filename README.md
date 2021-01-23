<!-- Copyright 2020 The LumoSQL Authors, see LICENSES/CC-BY-SA-4.0 -->

<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2020 The LumoSQL Authors -->
<!-- SPDX-ArtifactOfProjectName: LumoSQL -->
<!-- SPDX-FileType: Documentation -->
<!-- SPDX-FileComment: Original by Dan Shearer, October 2020 -->

# The Not-Forking Tool

Not-forking avoids duplicating the source code of one project within another
project, where the projects are external to each other. This is something that is not handled by 
[version control systems](https://en.wikipedia.org/wiki/Distributed_version_control) such as 
[Fossil](https://fossil-scm.org), [Git](https://git-scm.org), or [GitHub](https://github.com).

Not-forking **avoids project-level forking** by largely automating change management in ways that 
a version control system cannot.

The following diagram represents the simplest case of the problem that
Not-forking solves, where some external piece of software, here called
*Upstream*, forms a part of a new project called *Combined Project*.
*Upstream* is not a library provided on your system, because then you could simply
link to *libupstream*. Instead, it is source code that you copy into the *Combined Project*
directory tree like this:


``` pikchr indent toggle source-inline
// Diagram 1
// Colours chosen for maximum visibility in all browsers, devices, light conditions and eyeballs
// given the limitations of Pikchr, which is in turn limited by SVG being rendered independent of CSS
color=white
Upstream: file "Upstream Project" "file repository" fit rad 10px fill black
          file same rad 10px at 0.1cm right of Upstream fill none
          move ; move

box at 1.2cm below Upstream.sw "checkout then" "manually copy files" rjust color green invisible

MyProj:   file "Combined Project" "file repository" fit rad 10px with .n at Upstream.se+(0.5,-0.5) fill black
MyProj2:  file same rad 10px at 0.1cm right of MyProj fill none

arrow from Upstream.s down 1.5cm then right 1 to MyProj.w rad 20px thick color blue fill black
```

Some questions immediately arise:

* Should you import *Upstream* into your source code management system? All source code should be under version management, but having a checkout of an external repository within your local repository feels wrong... and do we want to lose upstream project history?
* If *Upstream* makes modifications, how can you pull those modifications into *Combined Project* safely?
* If *Combined Project* has changed files in *Upstream*, how can you then merge the changes and any new changes made in *Upstream*?

This is how pressure arises to separate *Upstream* project code from its repository and maintain it within the
*Combined Project* tree, because in the short term it is just simpler. But that brings the very big
problem of the Reluctant Project Fork. A Reluctant Project Fork, or "vendoring"
as the [Debian Project](https://debian.org) calls it, is where *Combined Project's* 
version of *Upstream* starts to drift from the original *Upstream*. 
Nobody wants to maintain code that is currently being
maintained by its original authors if it can be avoided, but it can become complicated
to avoid that. Not-Forking makes this a much easier problem to solve.

Not-forking addresses more complicated scenarios, such as when two
unrelated projects are upstream of *Combined Project*:


``` pikchr indent toggle source-inline
// Diagram 2
// Colours chosen for maximum visibility in all browsers, devices, light conditions and eyeballs
// given the limitations of Pikchr, which is in turn limited by SVG being rendered independent of CSS
scale=0.8
color=white
Upstream1: file "Upstream 1" "Git repo" fit rad 10px fill black
           file same rad 10px at 0.1cm right of Upstream1 fill none
           move ; move
Upstream2: file "Upstream 2" "tarball source" fit rad 10px fill black
           file same rad 10px at 0.1cm right of Upstream2 fill none
	   move ; move
MyProj:    file "Not-Forking configs" "& source modifications" "Fossil repo" fit rad 10px fill black
MyProj2:   file same rad 10px at 0.1cm right of MyProj fill none
           down

Make:      box "make combined-project" italic fit rad 20px ht 1 with .n at Upstream2.s+(0,-0.7) fill black
           down

NotFork:   file "Makefile calls Not-Forking" "to create combined build tree" "from upstreams+config+modifications" fit rad 10px with .n at Make.s+(0,-0.8) fill black
           down

Combined:  file "Combined Project" "binary" fit rad 10px with .n at NotFork.s+(0,-0.9) fill black

arrow from Upstream1.s down 1.5cm then right 1 to Make.w rad 20px thick color blue
arrow from Upstream2.s down 1.5cm to Make.n rad 20px thick color blue
arrow from MyProj.s down 1.5cm then left 1 to Make.e rad 20px thick color blue
arrow from Make.s to NotFork.n rad 50px thick thick thick color red
arrow from NotFork.s to Combined.n rad 50px thick thick thick color red
```

In more detail, the problem of project forking includes these cases:

* Tracking multiple upstreams, each with a different release schedule and version control system. Manual merging is difficult, but failing to merge or only occasionally merging will often result in a hard fork. LumoSQL tracks [three upstreams](https://lumosql.org/src/lumosql/dir?ci=tip&name=not-fork.d) that differ in all these ways
* Tracking an upstream where you wish to make changes that are not mergable. Without Not-Forking a manual merge is the only option even if there is only one upstream and even if the patch set is not complicated. The simplest case of this is replacing, deleting or creating whole files
* [Vendoring](https://lwn.net/Articles/836911/), where a package copies a library or module into its own tree, avoiding the versioning problems that arise when using system-provided libraries. This then becomes a standalone fork until the next copy is done, which often involves a manual porting task. Not-Forking can stop this problem arising at all
* Vendoring with version control, for example some of the [132 forks of LibVNC on GitHub](https://github.com/LibVNC/libvncserver/network/members) are for maintained, shipping products which are up to hundreds of commits behind the original. Seemingly they are manually synced with the original every year or two, but potentially Not-Forking could remove most of this manual work

The following diagram indicates how more complex scenarios are managed with
Not-Forking. Any of the version control systems could be swapped with any
other, and production use of Not-Forking today handles up to 50 versions of
three upstreams with ease. 


``` pikchr indent toggle source-inline
// Diagram 3
// Colours chosen for maximum visibility in all browsers, devices, light conditions and eyeballs
// given the limitations of Pikchr, which is in turn limited by SVG being rendered independent of CSS
scale=0.8
color=white
Upstream1_1: file "Upstream 1" "version 1" fit rad 10px fill black
             file same rad 10px at 0.1cm right of Upstream1_1 fill none
Upstream1_2: file "Upstream 1" "version 2" at Upstream1_1.e+(0.4,-0.5) fit rad 10px fill black
             file same rad 10px at 0.1cm right of Upstream1_1 fill none
             move

Upstream2_1: file "Upstream 2" "version 1" fit rad 10px fill black at Upstream1_1.e+(1.5,0)
             file same rad 10px at 0.1cm right of Upstream1_1 fill none
Upstream2_2: file "Upstream 2" "version 2" at Upstream2_1.e+(0.4,-0.5) fit rad 10px fill black
             file same rad 10px at 0.1cm right of Upstream2_1 fill none
             move

MyProj:      file "Not-Forking configs" "& source modifications" "Fossil repo" fit rad 10px fill black at Upstream2_1.e+(3,0)
MyProj2:     file same rad 10px at 0.1cm right of MyProj fill none
             down

Make:        box "make combined-project Upstream1v2+Upstream2v1" italic fit rad 20px ht 0.8 with .n at Upstream2_2.s+(0,-0.7) fill black
             down

NotFork:   file "Makefile calls Not-Forking" "to combine two upstreams" "plus any custom code" fit rad 10px with .n at Make.s+(0,-0.8) fill black
           down

Combined:  box "Combined Project" "binary created" fit rad 20px ht 0.8 with .n at NotFork.s+(0,-0.9) fill black

arrow from Upstream1_2.s down 1.5cm then right 1 to Make.w rad 20px thick color blue
arrow from Upstream2_1.s down until even with Upstream1_2 then to Make.n rad 20px thick color blue
arrow from MyProj.s down 1.5cm then left 1 to Make.e rad 20px thick color blue
arrow from Make.s to NotFork.n rad 50px thick thick thick color red
arrow from NotFork.s to Combined.n rad 50px thick thick thick color red
```

# Download and Install Not-Forking

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

The term "fork" has several meanings. Not-Forking is addressing only one
meaning: when source code maintained elsewhere is modified locally, creating
the problem of how to maintain the modifications without also maintaining the
entire original codebase. 

A permanent whole-project fork tends to be a large and rare, such as when
[LibreOffice](https://libreoffice.org) split off from
[OpenOffice.org](https://openoffice.org), or [MariaDB](https://mariadb.org)
from [MySQL](https://mysql.org).  These were expected, planned and managed
project forks. Not-forking is definitely not intended for this case. Another
example was decided by Debian on 20th January 2021 regarding extreme vendoring, where the upstream is 
[vast, motivated and funded](https://lwn.net/ml/debian-ctte/handler.971515.D971515.16111708995535.ackdone@bugs.debian.org/) and provides a guarantee that it will maintain all of its own upstreams.

Not-forking is strictly about unintentional/reluctant project forks, or
ordinary-scale vendoring.

Here are some other meanings for the word "fork" that are nothing to do with Not-Forking:

* In Fossil, a "fork" can be a point where a linear branch of development
splits into two linear branches by the same name. [Fossil has a forking/branching document](https://fossil-scm.org/home/doc/trunk/www/branching.wiki) .

* in Git,  a "fork" is just another clone of the repository.

* GitHub uses the same definition as Git. As well as providing tools to identify and re-import changes made in the new clone, GitHub promotes forking repositories. As a result it is common for a project on GitHub to have dozens of forks/clones, and for a popular project there can be hundreds.

