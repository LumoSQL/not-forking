package NotFork::Get;

# Copyright 2021 The LumoSQL Authors, see LICENSES/MIT
#
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2020 The LumoSQL Authors
# SPDX-ArtifactOfProjectName: not-forking
# SPDX-FileType: Code
# SPDX-FileComment: Original by Claudio Calvelli, 2020

use strict;
use version;
require Exporter;
use Carp;
use Config ();
use Digest::SHA qw(sha512_hex);
use File::Path qw(make_path remove_tree);
use File::Find qw(find);
use File::Copy qw(cp);
use Fcntl qw(:flock :seek);
use IO::Handle;

our @EXPORT_OK = qw(
    set_input
    set_cache
    set_output
    get_output
    all_names
    load_file
    list_files
    version_atleast
    version_convert
    cache_hash
    cache_list
    remove_cache
    add_prereq
    add_prereq_or
    prereq_program
    prereq_module
    recommend
);
our @EXPORT = @EXPORT_OK;
our @ISA = qw(Exporter);

my $input = 'not-fork.d';
my $output = 'sources';
my $cache = undef;

my (%checked_input, %checked_output, %checked_cache);

sub cache_hash {
    my ($index) = @_;
    return substr(sha512_hex($index), 42, 32);
}

sub cache_list {
    @_ == 0 or croak "Usage: NotFork::Get::cache_list";
    _set_cache_dir();
    my %list;
    opendir(OD, $cache) or return ();
    for my $ent (readdir OD) {
	$ent eq '.' || $ent eq '..' and next;
	$ent eq '.lock' and next;
	my $ed = "$cache/$ent";
	lstat $ed or next;
	-d _ or next;
	my $uf = "$ed/index";
	lstat $uf or next;
	-f _ or next;
	open(my $fh, '<', $uf) or next;
	my $index = <$fh>;
	close $fh;
	defined $index or $index = '???';
	chomp $index;
	$list{$ent} = $index;
    }
    closedir OD;
    wantarray ? %list : \%list;
}

sub remove_cache {
    @_ == 1 or croak "Usage: NotFork::Get::remove_cache(HASH)";
    my ($hash) = @_;
    _set_cache_dir();
    lstat "$cache" or die "$cache: $!\n";
    -d _ or die "$cache: not a directory\n";
    lstat "$cache/$hash" or die "$cache/$hash: $!\n";
    -d _ or die "$cache/$hash: not a directory\n";
    lstat "$cache/$hash/index" or die "$cache/$hash/index: $!\n";
    -f _ or die "$cache/$hash/index: not a regular file\n";
    remove_tree("$cache/$hash");
}

sub set_input {
    @_ == 1 or croak "Usage: NotFork::Get::set_input(DIR)";
    ($input) = @_;
    # we'll check it when we use it
}

sub set_cache {
    @_ == 1 or croak "Usage: NotFork::Get::set_cache(DIR)";
    ($cache) = @_;
    # we'll check it when we use it
}

sub set_output {
    @_ == 1 or croak "Usage: NotFork::Get::set_output(DIR)";
    ($output) = @_;
    # we'll check it when we use it
}

sub get_output {
    $output;
}

sub all_names {
    _check_input_dir();
    opendir(my $dh, $input) or die "$input: $!\n";
    my @names = sort grep { $_ !~ /^\./ } readdir $dh;
    closedir $dh;
    @names;
}

sub _check_input_dir {
    exists $checked_input{$input} and return;
    $checked_input{$input} = undef;
    _check_dir($input, 0, 0);
    # do we want to check all entries?
}

sub _check_input_name {
    my ($name) = @_;
    _check_input_dir($input);
    $name =~ m!^[/\.]! || $name =~ m![\\/]! and die "$name: Invalid name\n";
    _check_dir("$input/$name", 0, 0);
    _check_file("$input/$name/upstream.conf", 0, 0);
}

sub _check_output_dir {
    _check_input_dir();
    exists $checked_output{$output} and return;
    $checked_output{$output} = undef;
    _check_dir($output, 1, 1) or return;
    opendir(OD, $output) or die "$output: $!\n";
    for my $ent (readdir OD) {
	$ent =~ /^\./ and next;
	lstat "$output/$ent" or die "$output/$ent: $!\n";
	-d _ or die "$output/$ent: not a directory\n";
	-d "$input/$ent"
	    or die "$output/$ent: cannot find matching input $input/$ent\n";
	# XXX anything else to check in the output directory...
    }
    closedir OD;
}

sub _set_cache_dir {
    if (! defined $cache) {
	my $hd = $ENV{HOME} or die "Cannot figure out your \$HOME\n";
	$cache = "$hd/.cache/LumoSQL/not-fork";
    }
}

sub _check_cache_dir {
    _check_input_dir();
    _set_cache_dir();
    exists $checked_cache{$cache} and return;
    $checked_cache{$cache} = undef;
    _check_dir($cache, 1, 1) or return;
    opendir(OD, $cache) or die "$cache: $!\n";
    for my $ent (readdir OD) {
	$ent eq '.' || $ent eq '..' and next;
	$ent eq '.lock' and next;
	my $ed = "$cache/$ent";
	lstat $ed or die "$ed: $!\n";
	-d _ or die "$ed: not a directory\n";
	my $uf = "$ed/index";
	lstat $uf or die "$uf: $!\n";
	-f _ or die "$uf: not a regular file\n";
	open(my $fh, '<', $uf) or die "$uf: $!\n";
	my $index = <$fh>;
	close $fh;
	defined $index or die "$uf: empty file?\n";
	# should really check if it's the correct index...
	# XXX anything else to check in the cache directory...
    }
    closedir OD;
}

sub _check_file {
    my ($file, $missing_ok, $writable) = @_;
    if (! stat $file) {
	$missing_ok and return 0;
	die "$file: $!\n";
    }
    -f _ or die "$file: not a regular file\n";
    -r _ or die "$file: not readable\n";
    if ($writable) {
	-w _ or die "$file: not writable\n";
    }
    return 1;
}

sub _check_dir {
    my ($dir, $missing_ok, $writable) = @_;
    if (! stat $dir) {
	$missing_ok and return 0;
	die "$dir: $!\n";
    }
    -d _ or die "$dir: not a directory\n";
    -r _ or die "$dir: not readable\n";
    -x _ or die "$dir: not searchable\n";
    if ($writable) {
	-w _ or die "$dir: not writable\n";
    }
    return 1;
}

sub new {
    @_ == 4 or croak "Usage: new NotFork::Get(NAME, VERSION, COMMIT_ID)";
    my ($class, $name, $version, $commit) = @_;
    _check_input_name($name);
    (my $osname = $Config::Config{myarchname}) =~ s/^.*-//;
    my $obj = bless {
	name          => $name,
	verbose       => 1,
	offline       => 0,
	osname        => $osname,
	local_mirror  => [],
    }, $class;
    defined $version and $obj->version($version);
    defined $commit and $obj->commit($commit);
    $obj->_load_config;
    $obj;
}

sub DESTROY {
    my ($obj) = @_;
    for my $block (@{$obj->{blocks}}) {
	$block->{vcslock} and _unlock($block->{vcslock});
    }
}

my %required_keys_upstream = (
    vcs => \&_load_vcs,
);

my %required_keys_mod = (
    method => \&_load_method,
);

my %condition_keys = (
    version => \&_check_version,
    osname  => \&_check_values,
    hasfile => \&_check_hasfile,
);

sub _load_config {
    my ($obj) = @_;
    my $dn = "$input/$obj->{name}";
    $obj->{directory} = $dn;
    $obj->_load_upstream("$dn/upstream.conf");
    opendir (my $dh, $dn) or die "$dn: $!\n";
    my @files = sort grep { ! /^\./ && /\.mod$/i } readdir $dh;
    closedir $dh;
    $obj->{mod} = [];
    for my $fn (@files) {
	$obj->_load_modfile("$dn/$fn");
    }
    $obj;
}

sub load_file {
    @_ == 4 || @_ == 5
	or croak "Usage: load_file(HANDLE, NAME, DATA, RESULT_HASH [, OPTIONS])";
    my ($fh, $sf, $data, $hash, $options) = @_;
    my $if = undef;
    my $ifval = 1;
    my $beentrue = 0;
    my $stop = defined $options ? $options->{stop} : undef;
    my $block = defined $options ? $options->{block} : undef;
    while (defined (my $line = <$fh>)) {
	defined $stop && $stop->($line) and last;
	defined $block && $block->($line) and return undef;
	$line =~ /^\s*$/ and next;
	$line =~ /^\s*#/ and next;
	chomp $line;
	if ($line =~ s/\\$//) {
	    my $nl = <$fh>;
	    if (defined $nl) {
		$line .= $nl;
		redo;
	    }
	}
	$line =~ s/^\s*(\S+)\s*// or die "$sf.$.: Invalid line format: [$line]\n";
	my $kw = lc($1);
	if ($kw eq 'if') {
	    defined $if and die "$sf.$.: conditional nesting not (yet) allowed\n";
	    $line =~ s/^(\S+)\s*// or die "$sf.$.: Invalid line format for $kw: [$line]\n";
	    my $item = lc($1);
	    exists $condition_keys{$item} or die "$sf.$.: Invalid item ($item)\n";
	    my $code = $condition_keys{$item};
	    my $have = $data->{$item};
	    $ifval = $code->($data, $item, $line);
	    $beentrue = $ifval;
	    $if = 0;
	} elsif ($kw eq 'elseif' || $kw eq 'elsif') {
	    defined $if or die "$sf.$.: $kw outside conditional\n";
	    $if and die "$sf.$.: $kw follows else (lines $if and $.)\n";
	    $line =~ s/^(\S+)\s*// or die "$sf.$.: Invalid line format for $kw: [$line]\n";
	    my $item = lc($1);
	    exists $condition_keys{$item} or die "$sf.$.: Invalid item ($item)\n";
	    my $code = $condition_keys{$item};
	    my $have = $data->{$item};
	    $ifval = ! $beentrue && $code->($data, $item, $line);
	} elsif ($kw eq 'else') {
	    defined $if or die "$sf.$.: $kw outside conditional\n";
	    $if and die "$sf.$.: duplicate $kw (lines $if and $.)\n";
	    $ifval = ! $beentrue;
	    $if = $.;
	} elsif ($kw eq 'endif') {
	    $if or die "$sf.$.: $kw outside conditional\n";
	    $if = undef;
	    $ifval = 1;
	} elsif ($ifval) {
	    exists $options->{condition}{$kw}
		or $line =~ s/^=\s*//
		or die "$sf.$.: Invalid line format for $kw: [$line]\n";
	    $hash->{$kw} = $line;
	}
    }
    defined $options or return 1;
    if (exists $options->{condition}) {
	my $condition = $options->{condition};
	for my $ck (keys %$condition) {
	    exists $hash->{$ck} or next;
	    my $code = $condition->{$ck};
	    $code->($data, $ck, $hash->{$ck}) or return 0;
	}
    }
    if (exists $options->{required}) {
	my $required = $options->{required};
	for my $rq (keys %$required) {
	    exists $hash->{$rq} or die "$sf: required key $rq not provided\n";
	    my $code = $required->{$rq};
	    defined $code && $code->($data, $hash->{$rq}, $hash, $sf, $fh);
	}
    }
    1;
}

sub _load_upstream {
    my ($obj, $sf) = @_;
    open (my $fh, '<', $sf) or die "$sf: $!\n";
    my %kw;
    my %block = %$obj;
    my $block = load_file($fh, $sf, \%block, \%kw, {
	required => \%required_keys_upstream,
	block => sub { $_[0] =~ /^block\b/i },
    });
    my @blocks;
    if (defined $block) {
	# only one block
	$block{kw} = \%kw;
	push @blocks, \%block;
    } else {
	# we have multiple blocks which we store separately
	while (! eof($fh)) {
	    my %bbl = %$obj;
	    my %bkw = %kw;
	    load_file($fh, $sf, \%bbl, \%bkw, {
		required => \%required_keys_upstream,
		stop => sub { $_[0] =~ /^block\b/i },
	    });
	    $bbl{kw} = \%bkw;
	    push @blocks, \%bbl;
	}
    }
    $obj->{blocks} = \@blocks;
    close $fh;
}

sub _load_modfile {
    my ($obj, $mf) = @_;
    open (my $fh, '<', $mf) or die "$mf: $!\n";
    my %kw = ();
    my $keep = load_file($fh, $mf, $obj, \%kw, {
	required => \%required_keys_mod,
	condition => \%condition_keys,
	stop => sub { $_[0] =~ /^-+$/ },
    });
    close $fh;
    $keep and push @{$obj->{mod}}, $kw{method};
}

sub _load_vcs {
    my ($data, $name, $hash, $sf, $fh) = @_;
    my $module = ucfirst(lc($name));
    eval "require NotFork::VCS::$module";
    $@ and die "Cannot load VCS($name): $@";
    my $vcsobj = "NotFork::VCS::$module"->new($data->{name}, $hash);
    $@ and die "$sf: $@";
    exists $data->{verbose} and $vcsobj->verbose($data->{verbose});
    exists $data->{offline} and $vcsobj->offline($data->{offline});
    $vcsobj->local_mirror($data->{local_mirror});
    $data->{vcs} = $vcsobj;
    $data->{cache_index} = $vcsobj->cache_index;
    $data->{hash} = cache_hash($data->{cache_index});
}

sub _load_method {
    my ($data, $name, $hash, $mf, $fh) = @_;
    my $module = ucfirst(lc($name));
    eval "require NotFork::Method::$module";
    $@ and die "Cannot load Method($name): $@";
    my $mobj = "NotFork::Method::$module"->new($data->{name}, $data->{directory}, $hash);
    $@ and die "$mf: $@";
    $mobj->load_data($mf, $fh);
    $hash->{method} = $mobj;
}

# process "version" conditions in a mod file or upstream file
sub _check_version {
    my ($data, $key, $value, $cond_list) = @_;
    my $orig = $value;
    my $ok = 1;
    my $convert = _convert_function('version', $data->{compare});
    my $have = $convert->($data->{version});
    while ($value =~ s/^(==?|!=|>=?|<=?)\s*(\S+)\s*//) {
	my $op = $1;
	my $need = $convert->($2);
	$cond_list and push @$cond_list, [$op, $2, $need];
	if (defined $have) {
	    _cmp($op, $have, $need) or $ok = 0;
	} else {
	    # if no version was provided, it means "latest"
	    $op eq '>' || $op eq '>=' or $ok = 0;
	}
    }
    $value eq "" or die "Invalid value for $key: \"$orig\" (extra \"$value\" at end)\n";
    return $ok;
}

# process "osname" and similar conditions in a mod file or upstream file
sub _check_values {
    my ($data, $key, $value) = @_;
    my $orig = $value;
    my $ok = 1;
    my $have = $data->{$key};
    defined $have or $have = '';
    while ($value =~ s/^(==?|!=)\s*(\S+)\s*//) {
	my $op = $1;
	my $need = $2;
	_cmp($op, $have, $need) or $ok = 0;
    }
    $value eq "" or die "Invalid value for $key: \"$orig\" (extra \"$value\" at end)\n";
    return $ok;
}

# process "file" conditions in a mod file or upstream file
sub _check_hasfile {
    my ($data, $key, $value) = @_;
    my $orig = $value;
    my $ok = 1;
    while ($value =~ s|^(!?)\s*(/\S+)\s*||) {
	my $want = ($1 eq '') || 0;
	my $name = $2;
	my $have = (($name =~ s|/$||) ? (-d $name) : (-f $name)) || 0;
	$want == $have or $ok = 0;
    }
    $value eq "" or die "Invalid value for $key: \"$orig\" (extra \"$value\" at end)\n";
    return $ok;
}

# convert "op" to a comparison
sub _cmp {
    my ($op, $ch, $cv) = @_;
    $op eq '=' || $op eq '==' and return $ch eq $cv;
    $op eq '!=' and return $ch ne $cv;
    $op eq '>' and return $ch gt $cv;
    $op eq '>=' and return $ch ge $cv;
    $op eq '<' and return $ch lt $cv;
    $op eq '<=' and return $ch le $cv;
    # why did we end up here?
    undef;
}

sub version_convert {
    @_ == 2 or croak "Usage: version_convert(VERSION, TYPE)";
    my ($val, $type) = @_;
    my $convert = _convert_function($type);
    return $convert->($val);
}

my %convert_version = (
    version => \&_convert_version,
);

sub _convert_function {
    my ($override) = @_;
    defined $override or return $convert_version{'version'};
    exists $convert_version{$override} and return $convert_version{$override};
    die "Invalid version comparison: $override\n";
}

sub _convert_version {
    defined $_[0] or return undef;
    my $vn = lc($_[0]);
    my $suffix = '';
    if ($vn =~ s/-alpha$//) {
	$suffix = 'a';
    } elsif ($vn =~ s/-beta$//) {
	$suffix = 'b';
    } elsif ($vn =~ s/-gamma$//) {
	$suffix = 'c';
    } elsif ($vn =~ s/-delta$//) {
	$suffix = 'd';
    } elsif ($vn =~ s/-git$//) {
	$suffix = '0';
    } else {
	$suffix = 'z';
    }
    # we need to add extra ".0" components before adding the suffix, otherwise
    # alpha and beta may sort later than stable which is not what we like to see
    my @vn = split(/(\d+)/, $vn);
    @vn < 16 ? push(@vn, ('.000000000000000') x (16 - @vn)) : ($#vn = 15);
    @vn = map { /^\d/ ? sprintf("%015d", $_) : $_ } @vn;
    join('', @vn, $suffix);
}

# run some code for each known VCS
sub _forall {
    my ($type, $code, @args) = @_;
    my %vcs_seen;
    for my $inc (@INC) {
	-d "$inc/NotFork/$type" or next;
	opendir(D, "$inc/NotFork/$type") or next;
	while (defined (my $ent = readdir D)) {
	    $ent =~ /^\./ and next;
	    (my $pm = $ent) =~ s/\.pm$//i or next;
	    exists $vcs_seen{$ent} and next;
	    $vcs_seen{$ent} = 0;
	    eval {
		my $name = "NotFork::$type\::$pm";
		eval "require $name";
		$@ and die $@;
		$code->($name, @args);
	    };
	    $@ and die $@;
	}
	closedir D;
    }
}

# make a list of all prerequisite programs and modules
sub recommend {
    @_ == 0 or croak "Usage: recommend";
    my %prereq;
    _forall('VCS', sub { $_[0]->check_prereq(\%prereq); });
    _forall('Method', sub { $_[0]->check_prereq(\%prereq); });
    %prereq;
}

# check that we have all prerequisites for a particular configuration
sub check_prereq {
    @_ == 2 or croak "Usage: GET->check_prereq(RESULT)";
    my ($obj, $result) = @_;
    for my $block (@{$obj->{blocks}}) {
	my $vcs = $block->{vcs};
	$vcs->check_prereq($result);
    }
    if (exists $obj->{mod}) {
	for my $mobj (@{$obj->{mod}}) {
	    $mobj->check_prereq($result);
	}
    }
    $obj;
}

# helper functions to implement a module's check_prereq
sub _add_prereq_internal {
    my $find_any = shift @_;
    my $result = shift @_;
    my $first_item = $_[0];
    while (@_) {
	my ($code, $name, $version_min, @args) = @{shift @_};
	if (exists $result->{$name} && defined $result->{$name}) {
	    # if we don't care which version, reuse the previous result
	    if (! defined $version_min) {
		$find_any and return;
		next;
	    }
	    my ($ok, $version) = @{$result->{$name}};
	    if ($ok) {
		# we found one before, if it's new enough that'll do
		if (version_atleast($version, $version_min)) {
		    $find_any and return;
		    next;
		}
	    } else {
		# we did not find one before, if we looked for a recent enough
		# version no need to look again
		if (defined $version && version_atleast($version, $version_min)) {
		    $find_any and return;
		    next;
		}
	    }
	    # we cannot reuse the previous check
	}
	my $version = $code->($name, $version_min, @args);
	# if we found it, and it's new enough, then we're done
	if (defined $version &&
	    (! defined $version_min || version_atleast($version, $version_min)))
	{
	    $result->{$name} = [1, $version];
	    $find_any and return;
	} else {
	    $find_any and next;
	    # remember what version we actually wanted
	    $result->{$name} = [0, $version_min];
	}
    }
    $find_any or return;
    # not found... add the first (preferred) one as requirement
    $result->{$first_item->[1]} = [0, $first_item->[2]];
}

sub add_prereq {
    @_ >= 2 or croak "Usage: add_prereq(RESULT, DATA...)";
    _add_prereq_internal(0, @_);
}

sub add_prereq_or {
    @_ >= 2 or croak "Usage: add_prereq_or(RESULT, DATA...)";
    _add_prereq_internal(1, @_);
}

sub prereq_program {
    my ($name, $version_min, $version_call, $version_regex) = @_;
    for my $p (split(/:/, $ENV{PATH})) {
	-x "$p/$name" or next;
	defined $version_call or return '';
	my $have = `$p/$name $version_call`;
	defined $have or return '';
	defined $version_regex and $have =~ $version_regex and return $1;
	return $have;
    }
    # not found
    return undef;
}

sub prereq_module {
    my ($name, $version_min) = @_;
    local $@;
    # getting a package's version is not simple; perl will check a minimum
    # version for us, and we'll have to re-check if somebody else wants
    # a newer one later
    if (defined $version_min) {
	eval "require $name $version_min;";
    } else {
	eval "require $name;";
    }
    $@ and return undef;
    defined $version_min and return $version_min;
    return '';
}

sub _set_vcs {
    my ($obj, $key, $val) = @_;
    $val ||= 0;
    $obj->{$key} = $val;
    for my $block (@{$obj->{blocks}}) {
	exists $block->{vcs} and $block->{vcs}->$key($obj->{$key});
    }
    $obj;
}

sub verbose {
    @_ == 1 || @_ == 2 or croak "Usage: NOTFORK->verbose [(LEVEL)]";
    my $obj = shift;
    @_ or return $obj->{verbose};
    _set_vcs($obj, 'verbose', @_);
}

sub offline {
    @_ == 1 || @_ == 2 or croak "Usage: NOTFORK->offline [(BOOLEAN)]";
    my $obj = shift;
    @_ or return $obj->{offline};
    _set_vcs($obj, 'offline', @_);
}

sub local_mirror {
    @_ > 1 or croak "Usage: NOTFORK->local_mirror(DIR [,DIR]...)";
    my $obj = shift;
    push @{$obj->{local_mirror}}, @_;
    for my $block (@{$obj->{blocks}}) {
	exists $block->{vcs} and $block->{vcs}->local_mirror($obj->{local_mirror});
    }
    $obj
}

sub version {
    @_ == 1 || @_ == 2 or croak "Usage: NOTFORK->version [(VERSION)]";
    my $obj = shift;
    @_ or return $obj->{version};
    $obj->{version} = shift;
    delete $obj->{commit};
    $obj;
}

sub commit {
    @_ == 1 || @_ == 2 or croak "Usage: NOTFORK->commit [(COMMIT)]";
    my $obj = shift;
    @_ or return $obj->{commit};
    $obj->{commit} = shift;
    delete $obj->{version};
    $obj;
}

sub version_info {
    @_ == 2 or croak "Usage: NOTFORK->version_info(VERSION)";
    my ($obj, $version) = @_;
    for my $block (@{$obj->{blocks}}) {
	my @data = $block->{vcs}->version_info($version);
	@data and return @data
    }
    ();
}

sub _lock {
    my ($mode, $file, $name) = @_;
    open (my $fh, $mode, $file) or die "$file: $!\n";
    if (! flock $fh, LOCK_EX|LOCK_NB) {
	print STDERR "Waiting for lock on $name...";
	flock $fh, LOCK_EX or die " $file: $!\n";
	print STDERR "OK\n";
    }
    $fh;
}

sub _unlock {
    my ($fh) = @_;
    flush $fh;
    flock $fh, LOCK_UN;
    close $fh;
}

sub get {
    @_ == 1 || @_ == 2 or croak "Usage: NOTFORK->get [(SKIP_UPDATE?)]";
    my ($obj, $noupdate) = @_;
    _check_cache_dir();
    $obj->{offline} and $noupdate = 1;
    my %versions = ();
    my $commit_block;
    for my $block (@{$obj->{blocks}}) {
	my $vcs = $block->{vcs};
	my $vl = $obj->{verbose} && $obj->{verbose} > 2;
	make_path($cache, { verbose => $vl, mode => 0700 });
	my $cd = $block->{cache} = "$cache/$block->{hash}";
	my $vlfh;
	if (-d $cd) {
	    $vlfh = _lock('<', "$cd/index", "cache for $block->{cache_index}");
	    my $index = <$vlfh>;
	    defined $index or die "Missing index for cache $cd\n";
	    chomp $index;
	    $index eq $vcs->cache_index
		or die "Invalid cache directory $cd\n";
	} else {
	    make_path($cd, { verbose => $vl, mode => 0700 });
	    # somebody could have created the file while we waited for the lock,
	    # but if we open it for appending and check the file contents after
	    # we acquire the lock, we'll know
	    $vlfh = _lock('>>', "$cd/index", "cache for $block->{cache_index}");
	    # opening with +>> is not necessarily supported but we can open
	    # another file for reading...
	    open(my $auxfh, '<', "$cd/index") or die "$cd/index: $!\n";
	    my $index = <$auxfh>;
	    close $auxfh;
	    if (defined $index) {
		chomp $index;
		$index eq $vcs->cache_index
		    or die "Invalid cache directory $cd\n";
	    } else {
		print $vlfh "$block->{cache_index}\n" or die "$cd/index $!\n";
	    }
	    $noupdate = undef;
	}
	# somebody else could lock the cache directory at this point, but
	# we keep the lock on our bit until we've done the VCS part; there
	# is no danger of deadlock if everybody uses this subroutine to
	# do the locking or make sure to do things in the right order
	$block->{vcslock} = $vlfh;
	my $top = "$cd/vcs";
	$block->{vcsbase} = $top;
	$vcs->get($top, $noupdate);
	my @v = $vcs->all_versions;
	if ($block->{kw}{version_filter}) {
	    # some versions are excluded, for whatever reason, so trim the list
	    my $convert = _convert_function($obj->{blocks}[0]{compare});
	    my $line = $block->{kw}{version_filter};
	    while ($line =~ s/^(==?|!=|>=?|<=?)\s*(\S+)\s*//) {
		my $op = $1;
		my $need = $convert->($2);
		@v = grep { _cmp($op, $convert->($_), $need) } @v;
	    }
	    $line eq ""
		or die "Invalid operand for version_filter "
		     . \"$block->{kw}{version_filter}\" (extra \"$line\" at end)\n";
	}
	for my $v (@v) {
	    exists $versions{$v} or $versions{$v} = $block;
	}
	defined $obj->{commit} or next;
	$vcs->commit_valid($obj->{commit}) and $commit_block = $block;
    }
    $obj->{version_map} = \%versions;
    # if they have inconsistent version compares, all bets are off
    # so we just use the one from the first block
    my $convert = _convert_function($obj->{blocks}[0]{compare});
    $obj->{all_versions} = [ sort { $convert->($a) cmp $convert->($b) } keys %versions ];
    my ($nv, $nb);
    if (defined $obj->{version}) {
	my $v = $obj->{version};
	exists $versions{$v} or die "Unknown version: $v\n";
	$nb = $versions{$v};
	my $vcs = $nb->{vcs};
	$vcs->set_version($v);
	$nv = $vcs->version;
    } elsif (defined $obj->{commit}) {
	my $c = $obj->{commit};
	defined $commit_block or die "Unknown commit ID: $c\n";
	$nb = $commit_block;
	my $vcs = $nb->{vcs};
	$vcs->set_commit($c);
	$nv = $vcs->version;
    } elsif (keys %versions) {
	my $v = $obj->{all_versions}[-1];
	$nb = $versions{$v};
	my $vcs = $nb->{vcs};
	$vcs->set_version($v);
	$nv = $vcs->version;
    } else {
	$nb = $obj->{blocks}[0];
    }
    defined $nv and $obj->{version} = $nv;
    defined $nb and $obj->{vblock} = $nb;
    $obj;
}

sub all_versions {
    @_ >= 1 && @_ <= 3 or croak "Usage: NOTFORK->all_versions [(MIN [, MAX])]";
    my ($obj, $min, $max) = @_;
    exists $obj->{all_versions} or croak "Need to call get() before all_versions()";
    if (defined $min) {
	$min = _convert_version($min);
	defined $max or return grep { $min le _convert_version($_) } @{$obj->{all_versions}};
	$max = _convert_version($max);
	return grep { my $x = _convert_version($_); $min le $x && $x le $max } @{$obj->{all_versions}};
    } else {
	defined $max or return @{$obj->{all_versions}};
	$max = _convert_version($max);
	return grep { _convert_version($_) le $max } @{$obj->{all_versions}};
    }
}

sub last_version {
    @_ == 1 or croak "Usage: NOTFORK->last_version";
    my ($obj) = @_;
    exists $obj->{version_map} or croak "Need to call get() before last_version()";
    my @vers = $obj->all_versions;
    @vers or return undef;
    $vers[-1];
}

sub info {
    @_ == 2 or croak "Usage: NOTFORK->info(FILEHANDLE)";
    my ($obj, $fh) = @_;
    exists $obj->{version_map} or croak "Need to call get() before info()";
    my $block = $obj->{vblock} || $obj->{blocks}[0];
    $block->{vcs}->info($fh);
    $obj;
}

sub install {
    @_ == 1 or croak "Usage: NOTFORK->install";
    my ($obj) = @_;
    exists $obj->{version_map} or croak "Need to call get() before install()";
    exists $obj->{vblock} or croak "Need to call get() before install()";
    my $verbose = $obj->{verbose} || 0;
    my %filelist = ();
    my $block = $obj->{vblock};
    my $vcsobj = $block->{vcs};
    my $subtree = $block->{kw}{subtree};
    $vcsobj->list_files($subtree, sub { _store_file(\%filelist, @_); });
    my %oldlist = ();
    my $index = "$output/.index";
    make_path($index, { verbose => $verbose > 2, mode => 0700 });
    my $dest = "$output/$obj->{name}";
    $verbose and print "Installing $obj->{name} into $dest\n";
    my $destlist = "$index/$obj->{name}";
    my $lock = _lock('>', "$index/.lock.$obj->{name}", "output directory for $obj->{name}");
    if (stat $dest) {
	$verbose > 1 and print "Checking existing output directory $dest\n";
	-d _ or die "$dest exists but it is not a directory\n";
	opendir(my $dh, $dest) or die "$dest: $!\n";
	my $has_entries = 0;
	while (defined (my $ent = readdir $dh)) {
	    $ent eq '.' || $ent eq '..' and next;
	    $has_entries = 1;
	    last;
	}
	closedir $dh;
	if ($has_entries) {
	    # we need to verify that what we put in here wasn't changed,
	    # otherwise we refuse to overwrite it; also, any new files
	    # from sources must not overwrite existing files which we
	    # didn't know about; if necessary, people can delete these
	    # files and retry.
	    _load_filelist($destlist, \%oldlist);
	    my $ok = 1;
	    for my $ofp (sort keys %oldlist) {
		lstat "$dest/$ofp" or next;
		my ($_src, $type, $size, $data) = @{$oldlist{$ofp}};
		if ($type eq 'f') {
		    # file is equal if size and hash matches
		    _file_type() eq 'f'
			&& $size == (lstat _)[7]
			    && $data eq _filehash("$dest/$ofp", '')
				and next;
		} elsif (_file_type() eq 'l') {
		    # symlink is equal if target matches
		    my $rl = readlink("$dest/$ofp");
		    defined $rl && $rl eq $data and next;
		}
		# file did not match...
		warn "Will not overwrite or delete $dest\n";
		$ok = 0;
		last;
	    }
	    $ok or exit 1;
	}
    }
    # OK, either they passed us a new directory, or they passed us something
    # which we created and they didn't modify except for building objects;
    my ($version, $commit_id) = $vcsobj->version;
    # apply modifications as requested in a temporary cache area; we remove
    # any old version and start again, so things don't get confused
    if (exists $obj->{mod}) {
	$verbose > 1 and print "Applying source modifications\n";
	my $cd = "$block->{cache}/mods";
	-d $cd and remove_tree($cd);
	make_path($cd);
	my %cached = ();
	my $vcs = $block->{vcsbase};
	my $subtree = $block->{kw}{subtree};
	my $sp = defined $subtree ? "$subtree/" : '';
	for my $mobj (@{$obj->{mod}}) {
	    $mobj->apply($vcs, $vcsobj, $subtree, sub { # replace callback
		my ($path, $newdata) = @_;
		_store_file(\%filelist, $path, $newdata);
	    }, sub { # edit callback
		for my $path (@_) {
		    if (! exists $cached{$path}) {
			# make a copy of this file before editing
			$path =~ m!(.*)/[^/]+$!
			    and make_path("$cd/$1", { verbose => 0, mode => 0700 });
			cp("$vcs/$sp$path", "$cd/$path");
			$cached{$path} = 1;
		    }
		}
		return $cd;
	    }, $version, $commit_id);
	}
    }
    # We can now copy the files to the output directory; if the hash and size
    # hasn't changed we don't copy them though, so a "make" doesn't need to
    # rebuild everything unless the user wants it to
    # Before copying we rename the old file list if it was present, and
    # we write the new one as a temporary file: if the operation gets
    # interrupted it may be possible to continue (if not, delete the whole
    # output directory and recreate it)
    rename ($destlist, "$destlist.old");
    unlink $destlist; # in case the above rename failed
    _write_filelist("$destlist.new", \%filelist);
    $verbose > 1 and print "Copying files...\n";
COPY_FILE:
    for my $fp (sort keys %filelist) {
	my ($src, $type, $size, $data) = @{$filelist{$fp}};
	# if file was in the old list, use that information to decide whether
	# to copy it again; and delete it from the old list so at the end
	# anything left in there will be deleted
	if (exists $oldlist{$fp}) {
	    my ($osrc, $otype, $osize, $odata) = @{delete $oldlist{$fp}};
	    if ($otype eq $type && $osize == $size && $odata eq $data) {
		$verbose > 2 and print "==== $fp\n";
		next COPY_FILE;
	    }
	}
	# otherwise, if file is already in the output directory check if it
	# we need to copy it or use what we find; this is only possible if
	# this used to be a generated file and now is in the repository, and
	# we may decide in future that we abort the copy if it differs
	my $dp = "$dest/$fp";
	if (lstat $dp) {
	    if ($type eq 'f') {
		-f _ && (lstat _)[7] == $size && _filehash($dp, '') eq $data
		    and next COPY_FILE;
	    } elsif (-l _) {
		my $rl = readlink($dp);
		defined $rl && $rl eq $data
		    and next COPY_FILE;
	    }
	    $verbose > 1 and print "(rm) $fp\n";
	    unlink $dp;
	}
	# copy this file
	my $dir = '.';
	if ($dp =~ m!^(.*)/[^/]*$!) {
	    $dir = $1;
	    make_path($dir, { verbose => $verbose > 2, mode => 0755 });
	}
	if ($type eq 'f') {
	    $verbose > 1 and print "(cp) $fp\n";
	    cp($src, $dp) or die "copy($src, $dp): $!\n";
	} else {
	    $verbose > 1 and print "(ln) $fp\n";
	    symlink($data, $dp);
	}
    }
    # delete anything in old filelist but not in new; we've already deleted
    # the keys corresponding to anything we've replaced so what's left in
    # %oldlist can go
    for my $fp (keys %oldlist) {
	my $dp = "$dest/$fp";
	$verbose > 1 and print "(rm) $fp\n";
	unlink $dp;
    }
    # all done... rename new filelist and delete old
    rename ("$destlist.new", $destlist) or die "rename($destlist.new, $destlist): $!\n";
    unlink "$destlist.old";
    $verbose and print "Copy complete to $dest\n";
    _unlock($lock);
    $obj;
}

sub _write_filelist {
    my ($fn, $list) = @_;
    open (my $fh, '>', $fn) or die "$fn: $!\n";
    for my $fp (sort keys %$list) {
	my ($src, $type, $size, $data) = @{$list->{$fp}};
	print $fh "$type $size $fp\0$data\0" or die "$fn: $!\n";
    }
    close $fh or die "$fn: $!\n";
}

sub _load_filelist {
    my ($fn, $list) = @_;
    open (my $fh, '<', $fn) or die "$fn: $!\n";
    local $/ = "\0";
    while (defined (my $fp = <$fh>)) {
	chomp $fp;
	$fp =~ s/^([fl])\s(\d+)\s// or die "$fn: Invalid file format (line=$fp)\n";
	my ($type, $size) = ($1, $2);
	my $data = <$fh>;
	defined $data or die "$fn: Invalid file format (missing file data)\n";
	chomp $data;
	$list->{$fp} = [undef, $type, $size, $data];
    }
    close $fh;
}

# called after executing a stat or (better) lstat
sub _file_type {
    -l _ and return 'l';
    -f _ and return 'f';
    -d _ and return 'd';
    0;
}

# calculates hash of a file, returns undef (or $defhash) if there is
# an error but sets $@ in case we want to print a message
sub _filehash {
    my ($path, $defhash) = @_;
    eval {
	open (my $fh, '<', $path) or die "$path: $!\n";
	my $sha = Digest::SHA->new(512);;
	$sha->addfile($fh);
	close $fh;
	$defhash = $sha->hexdigest;
    };
    $defhash;
}

# helper function for a VCS to list files using "find"; if all files to be
# found are inside $top/$subtree and we are looking for file names relative
# to $base then their list_files can just call this one with arguments
# ($top, $subtree, \@dir_exclude, \@file_exclude, $callback)
# -- the excludes are relative to the search root i.e. $top/$subtree
sub list_files {
    @_ == 5 or croak "Usage: list_files(TOP, SUBTREE, DIR_EXCLUDE, FILE_EXCLUDE, CALLBACK)";
    my ($top, $subtree, $dir_excl, $file_excl, $code) = @_;
    my $base = $top;
    my $prefix = '';
    if (defined $subtree) {
	$base .= '/' . $subtree;
	$prefix = $subtree . '/';
    }
    my $bl = length $base;
    find({
	preprocess => sub {
	    scalar(@$dir_excl) || scalar(@$file_excl) or return @_;
	    my @result = ();
	NAME:
	    for my $name (@_) {
		if ($name ne '.' && $name ne '..') {
		    my $fp = "$File::Find::dir/$name";
		    lstat $fp or next;
		    my $excl = -d _ ? $dir_excl : $file_excl;
		    substr($fp, 0, $bl) eq $base
			&& substr($fp, $bl, 1) eq '/'
			    and substr($fp, 0, $bl + 1) = '';
		    for my $xp (@$excl) {
			if (ref($xp) eq 'Regexp') {
			    $fp =~ $xp and next NAME;
			} else {
			    $xp eq $fp and next NAME;
			}
		    }
		}
		push @result, $name;
	    }
	    @result;
	},
	wanted => sub {
	    my $name = $File::Find::name;
	    my $idx = $name;
	    substr($idx, 0, $bl) eq $base
		&& substr($idx, $bl, 1) eq '/'
		    and substr($idx, 0, $bl + 1) = '';
	    $code->($prefix . $idx, $name);
	},
	no_chdir => 1,
    }, $base);
}

sub _store_file {
    my ($filelist, $idx, $name) = @_;
    lstat($name) or return; # Hmmm
    my $type = _file_type();
    if (! $type) {
	warn "Ignoring $name, not a regular file or symlink\n";
	return;
    }
    $type eq 'd' and return;
    my $size = (lstat _)[7];
    my $data;
    if ($type eq 'f') {
	$data = _filehash($name);
	defined $data or die $@;
    } else {
	$data = readlink($name);
	defined $data or die "$name: $!\n";
    }
    $filelist->{$idx} = [$name, $type, $size, $data];
}

sub version_atleast {
    @_ == 2 or croak "Usage: version_atleast(VERSION1, VERSION2)";
    my ($v1, $v2) = @_;
    return _convert_version($v1) ge _convert_version($v2);
}

1
