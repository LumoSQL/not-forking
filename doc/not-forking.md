<!-- Copyright 2020 The LumoSQL Authors, see LICENSES/CC-BY-SA-4.0 -->

<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2021 The LumoSQL Authors -->
<!-- SPDX-ArtifactOfProjectName: LumoSQL -->
<!-- SPDX-FileType: Documentation -->
<!-- SPDX-FileComment: Original by Claudio Calvelli, March 2020 -->


Table of Contents
=================

   * [Not-Forking Upstream Source Code Tracker](#not-forking-upstream-source-code-tracker)
   * [Forking regarded as bad](#forking-regarded-as-bad)
   * [Overall not-forking configuration](#overall-not-forking-configuration-)
   * [Upstream definition file](#upstream-definition-file-)
   * [Modification definition file](#modification-definition-file-)
   * [Example Configuration directory](#example-configuration-directory-)
   * [Not-forking tool](#not-forking-tool-)

Not-Forking Upstream Source Code Tracker <a name="not-forking-upstream-source-code-tracker-"></a>
========================================

Not-Forking semi-automatically incorporates software from upstream projects by
tracking and merging. Designed for use in build and test systems, Not-forking
can combine an arbitary number of upstreams accessible over the internet by
any or all of [git](https://git-scm.org), [fossil](https://fossil-scm.org) and
web download. Not-Forking was originally developed for the 
[LumoSQL project](https://lumosql.org/src/lumosql) and is 
now fully independent.

<b>Simple Use Case:</b> A project needs a particular cryptographic or database
library, and the library maintainers have irregular releases with many bugfixes
inbetween.  In order to protect the project from being influenced by the bugfix
cycles of the library, the project will often decide to copy the library
in-tree, and then periodically hand-port new library versions to suit the
project's release cycle. This is effectively a fork. With Not-forking, the
project never needs to face this decision.

<b>More Advanced Use Case:</b> An embedded software product requires a single
image containing operating system and applications, with a new version twice a
year. Embedded software is frequently shipped with wildly out of date versions
because this is a hard problem and often not a priority for the product
manufacturer. Not-forking reduces the maintenance of pulling many upstreams
into the image, while still giving control over how this is done in the build
process (eg by adding a product-specific version string to imported code.)

The overall effect is something like 
[Fossil merge --cherry-pick](https://www.fossil-scm.org/fossil/help/merge)
or [git-cherry-pick](https://git-scm.com/docs/git-cherry-pick)
except that it additionally copes with the messiness of software including:

* human-style software versioning
* code that is not maintained in the same git/Fossil repo
* code that is not maintained in git, but is just patches or in some other VCS
* custom processing that is needed to be run for a specific patch
* code changes that are smarter than `patch`, for example `sed`-like global string
  replace conditional on some other string in the file.
* failing with an error asking for human intervention when there are major differences with upstream

Not-forking is the grease that helps projects cooperate when creating bugs
in the same codebase, rather than creating mutually incompatible sets of bugs.

<a name="forking-regarded-as-bad"></a>
# Forking Regarded as Bad

Forking is often a social rather than a technical issue.  The not-forking tool
assists in keeping friction low and helping developers only fork when they
absolutely need to.  Not-forking helps avoid projects carrying a fork of
external code they need, even if the upstream code/library is not maintained in
a way that is compatible with the project.  Not-forking also pushes back
against Git/Github's "Fork by default" development philosophy.

In 2021 the most commonly used public source code repositories are based on the
[git SCM](https://git-scm.org), especially Github and Gitlab.  Github puts a
prominent "Fork" button on every project and says 
"[Forking is at the core of social coding at GitHub](https://guides.github.com/activities/forking/)". 
As a result, as of January 2021,
[Github hosts 43 million distinct software projects](https://github.com/search?q=is:public), 
most of them not original but created by Github's Fork, and very many of them abandoned. Github
is used to maintain some wonderful code, but 43 million projects is an impossibly
large number.

In contrast, the [Fossil SCM](https://fossil-scm.org) discourages forking and
encourages regular remerging of branches.  Fossil tries to make it easier to nudge
users and contributors into more engagement, rather than increasingly-divergent
code forks that don't talk to each other. Where Github's flagship feature is "Fork",
the [Fossil timeline](https://sqlite.org/src/timeline) is key to how Fossil works (demonstrated here with the
source code of SQLite, a very busy project). The Fossil Timeline supports the 
[Fossil development philosophy](https://fossil-scm.org/home/doc/trunk/www/fossil-v-git.wiki#devorg).

# Overall not-forking configuration <a name="overall-not-forking-configuration-"></a>

A not-forking configuration is a directory containing one or more subdirectories
each one defining a different project to track.

Each project tracked by not-forking needs to define what to track, and what
changes to apply. This is done by providing a number of files in the project
subdirectory of the configuration:
the minimum requirement is an upstream definition file; other files can also be
present indicating what modifications to apply (if none are provided, the
upstream sources are used unchanged).

The not-forking tool refers to each project using the name of the subdirectory
containing it; when handling all projects at once, it essentially lists this
directory to see what's there.

# Upstream definition file <a name="upstream-definition-file-"></a>

This file describes the nature of the upstream. What version control system
does it use? Where are its repositories? What style of version string does it use?

The file `upstream.conf` has a simple "key = value" format with one such
key, value pair per line: blank lines and lines whose first nonblank
character is a hash (`#`) are ignored; long lines can be split into multiple
lines by ending a line with a backslash meaning continuation into the
next line.

There is a special line format to indicate conditionals, with the general form:

<b>
```
if (condition)
...
[else if (condition)
...]
[else
...]
endif
```
</b>

Note that conditionals cannot at present be nested. The following conditions
are available at the time of writing:

- `if version =|>|>=|<|<=` NUMBER [ `=|>|>=|<|<=` NUMBER ]...
which will be true if all the comparisons listed are true when applied to
the version requested; for example: `if version <= 2 > 1` will be true
when requesting version 1.5 or 2, but not when requesting 0.5, 1, or 2.5.

- `if osname =|!=` NAME [ `=|!=` NAME ]...
which will be true if the operating system name compares as required with
all the elements; for example `if osname != netbsd != linux` will be
true on FreeBSD but not on NetBSD, and `if osname = linux` will be true
on Linux only (note that the NAMEs are specified in all lower case).

- `if hasfile [!]/path/to/file` [ `[!]/path/to/file` ]...
which will be true if all the files listed are present (or absent if preceded
by a "`!`").

If a key is present more than once, the last value seen wins; therefore,
it is possible to define a key inside a conditional block, and then to
define it again outside the block to provide a default value.

The only key which must be present is `vcs`, and there is no default.
It indicates what kind of version control system to use to obtain upstream
sources; the value is the name of a version control module defined by the
not-forking mechanism; at the time of writing `git` and `download` are valid
values; in general, the documentation for the corresponding version control
module defines what else is present in the `upstream.conf` file; this document
describes briefly the configuration for the above two modules.

Optionally, two other keys can be present: `compare` and `subtree`.

The `compare` key indicates what method to use to compare two different
version numbers; if omitted, it default to `version` which compares
"normal" software version numbers: sequences of digits compare
numerically, and sequences of letters compare alphabetically, with the
exception that a suffix "-alpha" or "-beta" cause the version to be
considered before the string without such suffix: examples of version
numbers in order are:

<b>
```
0.9a < 0.9z < 0.10 < 1.0 < 1.1-alpha < 1.1-beta < 1.1 < 1.1a
```
</b>

This definition will even cope with the numbering scheme used by TeX and
METAFONT which are "Pi" and "e" respectively. The definition can be extended to
deal with version numbering schemes used by normal software, however it will
never work correctly with the version numbers used by some software such as the
[CLC-INTERCAL](https://en.wikipedia.org/wiki/INTERCAL#Version_Numbers)
compilers (where for example 0.26 < 1.26 < 0.27).

The `subtree` key indicates a directory inside the sources to use instead
of the top level.

The `version_filter` key has the same format as `if version` and means that
only project versions which make the condition true will be considered;
for example `version_filter = >= 1.0` could indicate that versions of the
project before 1.0 did not provide required functionality and will not be used.

Finally a line starting with the word `block` is special as it introduces
multiple upstream definitions related to the same project; the file will be
considered divided into blocks, with the special "`block`" line separating
them; the first block is used as "base" and concatenated with each of the
subsequent blocks in turn; when looking for a particular version of the
project, the first block containing it will be used; for example, a simplified
version of the "LMDB" project contains:

```
vcs = git

block
repos = https://github.com/openldap/openldap

block
repos = https://github.com/LMDB/lmdb
```

This is equivalent to two separate upstream files, containing:

```
vcs = git
repos = https://github.com/openldap/openldap
```

and

```
vcs = git
repos = https://github.com/LMDB/lmdb
```

When asked for a particular version of LMDB, the program will look for it
first in the OpenLDAP repository, and if not found in the LMDB repository
(which contains only older versions up to 0.9.15). As a result, one can
obtain any version available without having to know that they come from
different places.

Another (fictional) example would be a project which
switched from github to Fossil and at the same time did a bit of
reorganisation of the sources:

```
# nothing here, the two parts have nothing in common!
block
vcs = fossil
repos = https://project.org/src/project
block
vcs = git
repos = https://github.com/some/project
subtree = PROJECT
```

The not-forking tool will then obtain the sources from git for older versions,
looking inside the "PROJECT" directory for them; and for later versions
use fossil instead, and look at the top of the directory checked out (if
a version is available on both, the fossil one will be preferred because
it is listed first).

Note that if one knows at which exact version number things changed it's
also possible to use conditionals, however the `--list-versions` option will
not necessarily work correctly when using conditionals, while it works when
using multiple blocks. If required, a `version_filter` can be added to one
or more block to make particular versions come from a particular source.

## git

The upstream sources are available via a public git repository; the following
keys need to be present:

- `repos` (or `repository`) is a valid argument to the `git clone` command.
- optionally, `branch` to select a branch within the repository.
- optionally, `version` to convert a version string to a tag: the value is
either a single string which is prefixed to the version number, or two
strings separated by space, the first one is prefixed and the second appended.
- optionally, `user` and `password` can be specified to obtain access to the
repository (this is currently not implemented, all repositories must be
accessible without authentication).

A software version can be identified by a generic git commit ID, or by a
version string similar to the one described for the `compare` key, if the
repository offers that as an option.

## fossil

The upstream sources are available via a public fossil repository; the following
keys need to be present:

- `repos` (or `repository`) is a valid argument to the `fossil clone` command.
- optionally, `version` to convert a version string to a tag: the value is
either a single string which is prefixed to the version number, or two
strings separated by space, the first one is prefixed and the second appended.
- optionally, `user` and `password` can be specified to obtain access to the
repository (this is currently not implemented, all repositories must be
accessible without authentication).

A software version can be identified by a generic fossil artifact ID, or by
a version string similar to the one described for the `compare` key, if the
repository offers that as an option.

## download

The upstream sources are released as published versions and downloaded
directly; the following keys need to be present:

- `source-xxx` indicates where to obtain the source for a particular version;
the value is a generic URL; the `xxx` needs to be replaced by a valid version
number.
- `prefix` indicates that a number of directories need to be removed from
the unpacked file names, usually this will be 1 as tarballs start with a
single directory named after the release and that contains all the files.

At the time of writing, the program uses `file` to figure out how to unpack
the sources, and then `tar`, `gunzip`, etc as necessary; a future version
may allow to control the process if the program cannot figure out what to
do with a particular download.

# Modification definition file <a name="modification-definition-file-"></a>

This file contains instructions for modifying files, followed by the
data that the instructions can use to make the modifications. The 
data may be patches or complete file contents, and the instructions 
are operations such as "patch" or "replace".

There can be zero or more modification definition files in the configuration
directory; each file has a name ending in `.mod` and they are processed
in lexycographic order according to the "C" locale (rather than the current
locale, to guarantee consistent ordering). Note that only files are
considered; if the configuration directory contains subdirectories, these
are ignored, but files in there can be referenced by the `.mod` files.

The contents of each modification definition file are an initial part with
format similar to the Upstream definition file described above ("key = value"
pair, possibly with conditional blocks and conditions on the applicability
of the whole file, which have a special format); this initial part ends with
a line containing just dashes and the rest of the file, referred to as "final
part", is interpreted based on information from the initial part.

The applicability conditions have the exact same format as the `if` which
introduces a conditional block, without the word `if`; the overall effect
is to ignore the whole file if the condition is false; refer to the discussion
of conditionals above for the precise syntax and meaning.

One use of the applicability conditions is to indicate that some modifications
are only necessary up to a particular version, because for
example that modification has been accepted by upstream and is no longer
necessary; or that a modification is only necessary on a particular operating
system; another use of these conditions is to identify versions in which
substantial upstream changes make it difficult to specify a modification
which works for every possible version.

The following key is currently understood:

- `method`; the method used to specify the modification; currently, the
value can be one of: `patch`, indicating that the final part of the file is
in a format suitable for passing as standard input to the "patch" program;
`replace` indicating that one or more files in the upstream must be
completely replaced; the final part of the file contains one or more
lines with format "old-file = new-file", where both are relative paths,
the first relative to the root of the extracted upstream sources; the
second path is relative to the configuration directory; `sed` indicating
a sed-like set of replacements, with the final part of the file
containing likes with format "file-glob: regular-expression = replacement"
(the regular expression can contain spaces and equal signs if they are
quoted with a backslash); the replacement is always done on the whole
file at once.

Other keys are interpreted depending on the value of `method`; there are
currently no other keys for the `replace` and `sed` methods, and the
following for the `patch` method:

- `options`: options to pass to the "patch" program (default: "-Nsp1")
- `list`: extra options to the "patch" program to list what it would do
instead of actually doing it (this is used internally to figure out
what changes; the default currently assumes the "patch" program provided
by most Linux distributions, or the "gpatch" program available as a
package for the BSDs).

If a file is modified by more than one method, these are executed in
the sequence determined by the ordering of the modification definition
files, so for example a `replace` method only makes sense if it appears
first (otherwise it undoes all previous changes).

# Example Configuration directory <a name="example-configuration-directory-"></a>

This set of files obtains SQLite sources and replaces `btree.c` and `btreeInt.h`
with the ones from sqlightning, and applying a patch to `vdbeaux.c`:

File `upstream.conf`:

<b>
```
vcs   = git
repos = https://github.com/sqlite/sqlite.git
```
</b>


File `btree.mod`:


<b>

```
method = replace
--
src/btree.c    = files/btree.c
src/btreeInt.h = files/btreeInt.h
```

</b>


File `vdbeaux.mod`:

<b>

```
method = patch
--
--- sqlite-git/src/vdbeaux.c    2020-02-17 19:53:07.030886721 +0100
+++ new/src/vdbeaux.c      2020-03-21 13:52:24.861586555 +0100
@@ -2778,7 +2778,7 @@
      for(i=0; i<db->nDb; i++){
        Btree *pBt = db->aDb[i].pBt;
        if( sqlite3BtreeIsInTrans(pBt) ){
-        char const *zFile = sqlite3BtreeGetJournalname(pBt);
+        char const *zFile = BackendGetJournal(pBt);
          if( zFile==0 ){
            continue;  /* Ignore TEMP and :memory: databases */
          }
```

</b>

Files `files/btree.c` and `files/btreeInt.h`: the entire files with new contents.

A more complete example can be found in the LumoSQL directory "not-fork.d/sqlite"
which tracks upstream updates from SQLite.

# Not-forking tool <a name="not-forking-tool-"></a>

The `tool` directory contain a script, `not-fork` which runs the not-forking
mechanism on a directory.  Usage is:

<b>
```
not-fork \[OPTIONS\] \[NAME\]...
```
</b>

where the following options are available:

- `-i`INPUT\_DIRECTORY (or `--input=`INPUT\_DIRECTORY)
is a not-forking configuration directory as specified
in this document; default is `not-fork.d` within the current directory
- `-o`OUTPUT\_DIRECTORY (or `--output=`OUTPUT\_DIRECTORY)
is the place where the modified upstream sources will
be stored, and it can be either a directory created by a previous run of
this tool, or a new directory (missing or empty directory); default is
`sources` within the current directory; note that existing sources in
this directory may be overwritten or deleted by the tool
- `-k`CACHE\_DIRECTORY (or `--cache=CACHE\_DIRECTORY`)
is a place used by the program to keep downloads
and working copies; it must be either a new (missing or empty) directory
or a directory created by a previous run of the tool; default is
`.cache/LumoSQL/not-fork` inside the user's home directory
- `-v`VERSION (or `--version=`VERSION) will retrieve the specified VERSION
of the next NAME (this option must be repeated for each NAME, in the
assumption that different projects have different version numbering)
- `-c`COMMIT\_ID (or `--commit=`COMMIT\_ID) is similar to `-v` but
only works for version control modules which support commit identifiers,
and will retrieve the corresponding commit for the next NAME, whether
or not it has an official version number; this is incompatible with `-v`
- `-q` (or `--query`) completes all necessary downloads but does not
extract the sources and apply modifications, instead it shows some
information about what has been downloaded, including a version number
if available.
- `--list-versions` completes all necessary downloads but does not
extract the sources and apply modifications, instead it shows all the
version numbers known (these can be used as argument to `-v`/`--version`).
- `--verbose=`LEVEL changes the number of messages produced; higher
numbers may be good for debugging, but may provide a confusing amount
of information; `--quiet` is an alias for `--verbose=`0 and disables
any messages except fatal errors.
- `--update` asks to connect to network and request updates to any
repositories needed to complete the requested operation; this is
the default
- `-n` (or `--no-update`) asks to avoid updating repositories which are
already cached; if the version requested is newer than the last update,
the operation will fail
- `--offline` prohibits any network access; if data required is not
available in a local cache, the operation will fail
- `--online` allows the program to connect to network when data is
not available in a local cache; this is the default behaviour unless
`offline` is specified in the configuration file
- `--check-version=`VERSION checks that the not-fork tool itself is
at least the version specified; it exits with status OK if so, otherwise
it exits with a failure status and produces its version number on
standard output. No other processing happens when this option is specified.
- `--find-version=`VERSION[:TO\_VERSION] checks that the not-fork tool
itself is at least version VERSION and at most TO\_VERSION (if specified);
if so, it prints the path to its own executable; if not in range, it
will attempt to obtain a suitable version from its own sources and prints
the path to a command to call that. The output can be composed of
multiple lines, these will be the command and arguments to use to
call the correct version.
- `-V` (or `--my-version`) prints the version of the program itself
and exits (the `--version` option is already used to select a version
of a package to extract)
- `--check-prereq` checks dependencies necessary to download and install
the required sources; for example this could check for the presence of
`git` or `fossil` if these are required for the operation; prints the
list of anything missing
- `--check-recommend` is similar to `--check-prereq` except that it
looks for any dependency which could possibly be needed to use the
program; for example this could check for `fossil` even if the current
project only needs `git`

If neither VERSION nor COMMIT\_ID is specified, the default is the latest
available version, if it can be determined, or else an error message.
If more than one NAME is specified, VERSION and COMMIT\_ID need to
be provided before each NAME: the assumption is that different
software projects use different version numbers.

If one or more NAMEs are specified, the tool will obtain the upstream
sources as described in INPUT\_DIRECTORY/NAME for each of the NAMEs
specified, and attempt to apply all the required modifications; if that
succeeds, OUTPUT\_DIRECTORY/NAME will contain the modified sources ready
to use; if that fails, an error message will explain the problem and if
possible suggest corrective action (for example, if `patch` determines
that a file has changed too much that it cannot figure out how to apply
a patch supplied, the error message will indicate this and suggest to
obtain a new patch for that version of the sources).

If no NAMEs are specified, the tool, will process all subdirectories
of INPUT\_DIRECTORY. In this special case, any VERSION or COMMIT\_ID
specified will apply to all rather than just the name immediately
following them.

The tool looks for a configuration file located at
`$HOME/.config/LumoSQL/not-fork.conf` to read defaults; if the file exists
and is readable, any non-comment, non-empty lines are processed before
any command-line options with an implicit `--` prepended and with spaces
around the first `=` removed, if present: so for example a file containing:

<b>
```
cache = /var/cache/LumoSQL/not-fork
```
</b>

would change the default cache from `.cache/LumoSQL/not-fork` in the user's
home directory to the above directory inside `/var/cache`; it can still
be overridden by specifying `-c`/`--cache` on the command line.

The program will refuse to overwrite the output directory if it cannot
determine that it has been created by a previous run and that files have
not been modified since; in this case, delete the output directory
completely, or rename it to something else, and run the program again.
There is currently no option to override this safety feature.

We plan to add logging to the not-forking tool, in which all messages are
written to a log file (under control of configuration), while the subset
of messages selected by the verbosity setting will go to standard output;
this will allow us to increase the amount of information provided and make
it available if there is a processing error; however in the current version
this is just planned, and not yet implemented.

The tool may need to access the network to obtain sources; this can be
stopped in two ways:

- adding `offline` to the configuration file, or specifying `--offline` in
the command line prohibits access to the network; this may result in an
operation failing with an error, where the message mentions `--offline`
to suggest why it stopped; this can be overridden with `--online` in the
command line.

- adding `no-update` to the configuration file, or specifying `--no-update`
in the command line will use a local cached repository if available; this
will normally be sufficient, however asking for a version newer than the
last update will fail; the default behaviour can be restored by adding
`--update` to the command line, which will contact the remote server to
see if an update is available and download it if so.

There is a plan to add a time-based default if neither `--update` nor
`--no-update` is specified (in the command line or in the configuration
file): instead of always defaulting to `--update`, the tool would check
the time of the last ypdate, and default to `--no-update` if that time
is "recent"; this is not yet implemented, and also we need to decide what
"recent" actually means in this context.

