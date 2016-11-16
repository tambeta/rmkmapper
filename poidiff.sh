#!/bin/bash

[[ -n $1 && -n $2 ]] || {
	echo "Pass two POI index file names for diff" >&2
	exit 1
}

diff -w -U3 <(fgrep '"name"' $1 | sort) <(fgrep '"name"' $2 | sort)
