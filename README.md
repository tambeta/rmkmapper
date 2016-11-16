# rmkmapper

## Rationale

The Estonian State Forest Management Centre maintains many [recreational
sites](http://loodusegakoos.ee/en) (or points of interest in rmkmapper's
terms). There are two issues:

* Despite much fanfare about launching an [open data
  initiative](https://opendata.riik.ee/) years ago, this has fizzled in
  Estonia and as such, most public sector organizations including the
  SFMC has not provided machine-readable data of their activities
* The official site has no overview map of all the various types of
  sites

rmkmapper solves these issues by:

* providing a command-line tool to crawl SFMC's web site and compile a
  machine-readable dump of all the POIs
* providing a simple web application displaying a zoomable, filterable,
  interactive map of all the POIs.

**An occasionally updated [demo is available]
(http://biit.cs.ut.ee/~arak/projects/rmk/)**.

In addition, this project provides a Perl module for conversion between
the L-EST 97 and WSG84 (latitude / longitude) coordinate systems.

## Command-line tool

The CLI tool requires a reasonably recent version of Perl 5,
HTML::TreeBuilder, JSON::XS, LWP::Simple.

Usage:

```
$ ./rmkmapper.pl --help
rmkmapper.pl [-p | -t url] [-o dir]

Print a JSON string representing all RMK objects.

--ofile-dir, -o - Directory containing pre-downloaded RMK object HTML files.
                  Skip crawling for object files on the web. Note that this mode
                  is more tolerant to errors, merely warning if a file cannot be
                  parsed into an object. Use a command similar to the following
                  to generate a local cache of object files in cwd:

                  wget -O - http://eid.ee/3te |
                  wget -rLEnH -A '*.html' -l0 -Fi - -B http://loodusegakoos.ee
--pois, -p      - Generate an index of points of interest (default)
--tracks, -t    - Generate an index of tracks based on the passed Garmin GDB file
--max-num, -n   - Maximum number of POIs to parse, for debugging
```

## Notes

This is a legacy project not under active development. Feel free to fork
and improve.
