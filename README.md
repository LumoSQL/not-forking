<!-- Copyright 2020 The LumoSQL Authors, see LICENSES/CC-BY-SA-4.0 -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2020 The LumoSQL Authors -->
<!-- SPDX-ArtifactOfProjectName: LumoSQL -->
<!-- SPDX-FileType: Documentation -->

# Not-Forking Tool

This directory contains the not-forking tool as developed for the 
[LumoSQL project](http://lumosql.org). Not-forking is like patching or merging,
but is more intelligent so that software can be mostly-automatically kept
in synch with an upstream.

If you are reading this on Github, you are looking at a read-only mirror.
The official home is the [Fossil repository](https://lumosql.org/src/not-forking),
and that is the best way to contribute and interact with the community. You 
may raise PRs on Github, but they will end up being pushed through Fossil anyway.

Here you will find the tool and its libraries, and the [full documentation](doc/not-forking.md).
It also contains an example configuration (in directory doc/examples) which can
be used for testing.

For more advanced uses, the
[LumoSQL not-forking directory](https://lumosql.org/src/lumosql/dir?ci=tip&name=not-fork.d)
is an example of tracking multiple upstreams and versions. 

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
you install it.

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

