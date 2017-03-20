#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use lib 'mod';

use LEST97;

use Cwd;
use Data::Dumper;
use File::Spec;
use File::Temp qw(tempfile);
use Getopt::Long;
use HTML::TreeBuilder;
use JSON::XS;
use LWP::Simple;
use Time::HiRes qw(time usleep);

use constant {
	RQ_DELAY 		=> 4000,	# rq delay in ms
	ROOT_URL		=> "http://eid.ee/3te",
	GPSBABEL		=> "gpsbabel",
	UNLINK_TMPFILES	=> 1,
};

my %g = (
	lwp			=> undef,
	ts_last_rq	=> undef,
);

# POI functions

sub crawl_web {

	# Crawl RMK root URL for object files

	my ($max_n) = @_;

	my $doc;
	my $dom;
	my @listing;
	my @r;

	dbg("Retrieving root document ...");

	$doc = lwp_get(ROOT_URL);
	$dom = HTML::TreeBuilder->new();
	$dom->parse($doc);
	$dom->eof();

	@listing = $dom->look_down("id", "search-results")
		or die("Main listing not found in root document");
	@listing = $listing[0]->look_down("class", "location-name")
		or die("No list elements not found in root document");
	foreach (@listing) {
		my $href = "http://loodusegakoos.ee" . $_->look_down("_tag", "a")->attr("href");
		enforce_rq_delay();
		dbg("Retrieving / parsing $href");
		push @r, object_parse($href, lwp_get($href));
		last if ($max_n && scalar(@r) >= $max_n);
	}

	\@r;
}

sub crawl_local {

	# Recursively crawl a local directory for *.html object files. See usage()
	# for instructions to generate such cache.
	#
	# Directory hierarchy component names are used to compile the original
	# href. The routine is internally invoked recursively; there is no need to
	# pass the $subdir parameter when called from outside.

	my ($dir, $subdir, $max_n) = @_; $subdir ||= "";

	my $wdir = "$dir/$subdir";
	my $cwd = getcwd();
	my @r;

	(-d $wdir && -x $wdir && -r $wdir)
		or die("Cannot list directory $wdir");
	chdir($wdir);

	foreach(glob("*")) {
		if (-f && -r && /\.html$/) {
			my $id = $_; $id =~ s/\.html//;
			my $href = "loodusegakoos.ee/$subdir/$id";

			$href =~ s|/+|/|g;
			$href = "http://$href";
			dbg("Parsing $wdir/$id");
			open(OBJ, "<:utf8", $_);

			eval {
				push @r, object_parse($href, join("", <OBJ>)); };
			if ($@) {
				warn $@; }

			close(OBJ);
		}
		elsif (-d && -x && -r) {
			push @r, @{crawl_local($dir, "$subdir/$_", $max_n)};
		}

		last if ($max_n && scalar(@r) >= $max_n);
	}

	chdir($cwd);
	\@r;
}

sub object_parse {

	# Parse a RMK object, given the raw HTML. Returns a hashref. %phash is a
	# "parse hash", with keys corresponding to values in the left column of
	# the info table. In case the hash value is a string, the result hash will
	# contain an entry with this key and the string from the right column of
	# the info table as the value. If the hash value is a coderef, $_ is set
	# to the string from the right column of the info table and a hashref to
	# apply to the end result is expected in return.

	my ($href, $html) = @_;

	my %r;
	my $dom;
	my $name;
	my @tables;
	my %phash = (
		"Objekti tüüp" => sub {
			$_ = lc;
			if ($name =~ /vaate(torn|platvorm)/i) {
				$_ = "vaatetorn"; }
			if ($name =~ /puhkekoh(t|ad)/i) {
				$_ = "puhkekoht"; }
			if ($name =~ /loodusmaja/i) {
				$_ = "looduskeskus"; }
			{type => $_};
		},
		"Koordinaadid" => sub {
			my $lat;
			my $lon;
			my $x;
			my $y;

			if (/WGS/) {
				$lat = (/laiuskraad:\s*([\d\.]+)/, $1);
				$lon = (/pikkuskraad:\s*([\d\.]+)/, $1);
				($x, $y) = wsg84_to_lest97($lat, $lon);
			}
			elsif (/EST/) { # segfaults if elsif used?
				$x = (/x:\s*([\d\.]+)/, $1);
				$y = (/y:\s*([\d\.]+)/, $1);
				($lat, $lon) = lest97_to_wsg84($x, $y);
			}

			($lat && $lon && $x && $y) ?
				{
					coord_lat	=> $lat,
					coord_lon	=> $lon,
					coord_x		=> $x,
					coord_y		=> $y,
				} : {};
		},
		"Vaatamisväärsused" => sub {
			# Remove sentence containing given string,
			# and anything after it

			s/[[:upper:]][^[:upper:]]*Tõnu.*//g;
			s/(^\s+|\s+$)//g;
			{sights => $_};
		},
		"Telkimisvõimalus" => sub {
			my $has = -1;
			if (/on|olemas|lubatud|true/i) {$has = 1;}
			elsif (/ei ole/i) {$has = 0;}
			{has_tenting => $has};
		},
		"Kattega lõkkekoht" => sub {
			my $has = -1;
			if (/on|olemas|lubatud|true/i) {$has = 1;}
			elsif (/ei ole/i) {$has = 0;}
			{has_firesite => $has};
		},
		"Varustus" => "equipment",
		"Asukoht" => "location",
	);

	# Parse HTML, retrieve relevant components

	$dom = HTML::TreeBuilder->new();
	$dom->parse($html);
	$dom->eof();

	$name = $dom->look_down("_tag", "h1")
		or die("Failed to retrieve object name for $href");
	@tables = $dom->look_down("_tag" => "table", "class" => "full-width-table")
		or die("Failed to retrieve info tables for $href");
	$name = $name->as_trimmed_text();
	$r{href} = $href;
	$r{name} = $name;

	# Parse info tables

	foreach my $table (@tables) {
		foreach($table->look_down("_tag", "tr")) {
			my ($title, $content) = $_->look_down("_tag", "td");
			my $action;

			$title = $title->as_trimmed_text();
			$content = $content->as_trimmed_text();
			$action = $phash{$title};

			if ($action && ref($action) eq "CODE") {
				local $_ = $content;
				my $ar = $action->();
				$r{$_} = $ar->{$_}
					foreach(keys %$ar);
			}
			elsif ($action && !ref($action)) {
				$r{$action} = $content;
			}
		}
	}

	\%r;
}

sub normalize_poi_index {

	# Normalize POI index: sort by name, remove duplicates.

	my ($pois) = @_;

	my @r;
	my $last;
	my $make_last;

	$make_last = sub {
		my $poi = shift;
		$poi->{name} . "_" . ($poi->{coord_lat} || "") . "_" . ($poi->{coord_lon} || "");
	};

	foreach (sort {$a->{name} cmp $b->{name}} @$pois) {
		unless ($last) {
			$last = $make_last->($_);
			push(@r, $_);
			next;
		}

		if ($last eq $make_last->($_)) {
			warn "Duplicate entry: $last\n"; }
		else {
			push(@r, $_); }
		$last = $make_last->($_);
	}

	\@r;
}

# Track functions

sub tracks_parse {

	# Parse a Garmin MapSource tab-delimited text format into an arrayref of
	# hashrefs representing tracks.

	my ($fn) = @_;

	my $track_name;
	my $track_length;
	my @tracks;

	open(T, "<", $fn)
		or die("Cannot open $fn for reading");
	while(<T>) {
		if (/^Track\t/) {
			my @f = split(/\t/);

			$track_name = $f[1];
			$track_length = $f[4];

			die("Unable to get track name from $fn")
				unless ($track_name);
			push(@tracks, {
				name		=> $track_name,
				distance	=> $track_length,
				waypoints	=> []
			});
		}
		elsif ($track_name && /^Trackpoint\t/) {
			my @f = split(/\t/);
			my $pos = $f[1]; $pos =~ s/[NE]//g;
			push(@{$tracks[-1]->{waypoints}}, [map(0.0 + $_, split(/\s+/, $pos))]);
		}
	}

	close(T);
	\@tracks;
}

# Utility functions

sub dmp {
	$_[1] ?
		warn  Data::Dumper->Dump([shift]) :
		print Data::Dumper->Dump([shift]) ;
}

sub enforce_rq_delay {
	my $ts = $g{ts_last_rq} || 0;
	my $now = time();

	if ($now - $ts < RQ_DELAY / 1000)
		{ usleep(RQ_DELAY * 1000); }
	$g{ts_last_rq} = time();
	1;
}

sub lwp_get {

	# Fetch URL, returning the decoded
	# Perl Unicode string.

	my ($href) = @_;
	my $http_r;

	$http_r = $g{lwp}->get($href);
	$http_r->is_success()
		or die("Failed to retrieve object $href: HTTP/" . $http_r->code());
	$http_r->decoded_content();
}

sub lwp_store {

	# Fetch URL, saving it into $fn.

	my ($href, $fn) = @_;
	my $http_r;

	$http_r = $g{lwp}->get($href);
	$http_r->is_success()
		or die("Failed to retrieve object $href: HTTP/" . $http_r->code());

	open(OUT, ">", $fn)
		or die("Failed to open $fn for writing");
	binmode(OUT);
	print OUT $http_r->content();
	close(OUT);
	1;
}

sub sys_run {

	# A simple wrapper around system(), throwing an exception on error
	# or process dying on an unhandled signal, otherwise returning
	# its return value. $procname is the name of the process to use
	# in exception messages (optional).

	my ($cmd, $procname) = @_;
	my $r;

	$procname ||= "Child process";
	$r = system($cmd);

	if ($r == -1) {
		die("$procname failed to execute: $!");
	}
	elsif ($r & 127) {
		die("$procname died on signal " . ($r & 127));
	}

	$r >> 8;
}

sub parse_cmdline {
	Getopt::Long::Configure("bundling");
	my %o;

	GetOptions(\%o,
		'pois|p',
		'tracks|t=s',
		'tracks-type|T=s',
		'max-num|n=i',
		'ofile-dir|d=s',
		'ugly|u',
		'help|h',
	) or exit;

	if ($o{help}) {
		usage();
		exit;
	}

	if ($o{tracks} && $o{pois}) {
		die("Specify one of --tracks, --pois.\n");
	}
	elsif (!$o{tracks} && !$o{pois}) {
		$o{pois} = 1;
	}

	unless ($o{"tracks-type"}) {
		$o{"tracks-type"} = "gpx";
	}

	\%o;
}

sub usage {
print
<<END
rmkmapper.pl [-p | -t url] [-o dir]

Print a JSON string representing all RMK objects.

--ofile-dir, -o   - Directory containing pre-downloaded RMK object HTML files.
                    Skip crawling for object files on the web. Note that this
                    mode is more tolerant to errors, merely warning if a file
                    cannot be parsed into an object. Use a command similar to
                    the following to generate a local cache of object files in
                    cwd:

                    wget -O - http://eid.ee/3te | \
                    wget -rLEnH -A '*.html' -l0 -Fi - -B http://loodusegakoos.ee
--pois, -p        - Generate an index of points of interest (default)
--tracks, -t      - Generate an index of tracks based on the passed GPS file or
                    URL (requires gpsbabel on \$PATH)
--tracks-type, -T - The type of the tracks file, passed to gpsbabel via -i
--max-num, -n     - Maximum number of POIs to parse, for debugging
--ugly, -u        - Print compact JSON with minimal whitespace
END
}

sub dbg {
	warn shift, "\n";
}

# Entry point

sub main {
	my $r;
	my $o = parse_cmdline();

	$g{lwp} = LWP::UserAgent->new(
		agent => "rmkmapper.pl/0.1",
	);

	# Generate POI index

	unless (exists($o->{tracks})) {
		my $n = $o->{'max-num'};

		if ($o->{'ofile-dir'}) {
			$r = crawl_local($o->{'ofile-dir'}, undef, $n); }
		else {
			$r = crawl_web($n); }
		$r = normalize_poi_index($r);
	}

	# Generate track index

	else {
		my $gpsfn = $o->{tracks};
		my $txtfn = (tempfile(UNLINK => UNLINK_TMPFILES))[1];
		my $gpsfn_type = $o->{"tracks-type"};
		my $cmd;

		if ($gpsfn =~ /^http/) {
			my $url = $gpsfn;

			$gpsfn = (tempfile(UNLINK => UNLINK_TMPFILES))[1];
			lwp_store($url, $gpsfn);
		}

		$cmd =
			GPSBABEL . " -i $gpsfn_type -f $gpsfn " .
			"-o garmin_txt,grid=ddd,prec=5 -c utf-8 -F $txtfn";
		sys_run($cmd);
		$r = tracks_parse($txtfn);
	}

	print JSON::XS->new->utf8->canonical->pretty($o->{ugly} ? 0 : 1)->encode($r);
}

main();

