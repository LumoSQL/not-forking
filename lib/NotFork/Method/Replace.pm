package NotFork::Method::Replace;

use strict;
use Carp;

sub new {
    @_ == 4 or croak "Usage: Notfork::Method::Replace->new(NAME, SRCDIR, OPTIONS)";
    my ($class, $name, $srcdir, $options) = @_;
    # if we had options for the "replace" method, we'd do something here
    bless {
	name   => $name,
	srcdir => $srcdir,
	mods   => [],
    }, $class;
}

sub load_data {
    @_ == 3 or croak "Usage: REPLACE->load_data(FILENAME, FILEHANDLE)";
    my ($obj, $fn, $fh) = @_;
    my $srcdir = $obj->{srcdir};
    while (defined (my $line = <$fh>)) {
	$line =~ /^\s*$/ and next;
	$line =~ /^\s*#/ and next;
	chomp $line;
	$line =~ /^\s*(\S+)\s*=\s*(\S+)\s*$/ or die "$fn.$.: Invalid line format\n";
	my ($from, $to) = ($1, $2);
	my $replace = ($to =~ s/^\+//);
	stat "$srcdir/$to" or die "$fn.$.: $to: $!\n";
	-f _ or die "$fn.$.: $to: Not a regular file\n";
	-r _ or die "$fn.$.: $to: Not readable\n";
	push @{$obj->{mods}}, [$from, $to, $replace];
    }
    $obj;
}

sub apply {
    @_ == 6 or croak "Usage: REPLACE->apply(VCS_DIR, REPLACE_CALLBACK, EDIT_CALLBACK, VERSION, COMMIT_ID)";
    my ($obj, $vcs, $r_call, $e_call, $version, $commit_id) = @_;
    my $src = $obj->{srcdir};
    for my $mods (@{$obj->{mods}}) {
	my ($from, $to, $replace) = @$mods;
	my $repl = "$src/$to";
	if ($replace) {
	    my $copy = $e_call->($from);
	    open(my $src, '<', "$src/$to") or die "$src/$to: $!\n";
	    open(my $dst, '>', "$copy/$from") or die "$copy/$from: $!\n";
	    while (<$src>) {
		s(\$(LUMO_\w+)){
		    {
			LUMO_VERSION   => $version,
			LUMO_COMMIT_ID => $commit_id,
		    }->{$1} || '';
		}ge;
		print $dst $_ or die "$copy/$from: $!\n";
	    }
	    close $dst or die "$copy/$from: $!\n";
	    close $src;
	    $repl = "$copy/$from";
	}
	$r_call->($from, $repl);
    }
}

1
