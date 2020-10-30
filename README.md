# Not-Forking Tool

This directory contains the not-forking tool as developed for the 
[LumoSQL project](http://lumosql.org). Not forking is like patching or merging,
but is more intelligent so that software can be mostly-automatically kept
in synch with an upstream.

Here you will find the tool and its libraries, and the [full documentation](doc/not-forking.md)
It also contains an example configuration (in directory not-fork.d) which can
be used for testing.

LumoSQL has a more complicated use case, keeping track of multiple upstreams and 
versions. 

To install the tool:

```
perl Makefile.PL
make
make install
```

At which point the `not-fork` command is installed in the system and its
required modules are available where your perl installation expects to
find them.

It is also possible to use the tool without installing by using the
following commands:

```
perl Makefile.PL
make
perl -Iblib/lib bin/not-fork [options] ...
```

