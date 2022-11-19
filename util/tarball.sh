#!/bin/sh
#
## Tarball the source directory $1 into output file $2, optionally with
## compression.
##
## This script will detect .tar.lz as requested and use the massively parallel
## tarlz utility to properly compress them. It will also detect
## .tar.{gz,bz2,xz} and pass the appropriate flags to the tar invocation.
## Otherwise, it will unconditionally produce a plain, uncompressed tarball,
## regardless of any file extensions in the output name.

if test "$1" = '' || test "$2" = ''; then
	echo 'Usage:';
	echo '   util/tarball.sh <srcdir> <out.tar{.lz,}>';
	echo '';
	exit 0;
fi

if ! test -d "$1"; then
	echo "'$1' is not a valid directory. Exiting...";
	exit 127;
fi

if test -f "$2"; then
	echo "'$2' already exists; this script will not overwrite it. Exiting...";
	exit 127;
fi

if test -d tmp; then
	echo 'Warning: tmp directory was found dirty. Removing it.';
	rm -rf tmp;
fi

mkdir tmp;

for file in $(ls -1 "$1"); do
	test "${file%\~}" = "$file" && cp -r "$1/$file" "tmp/.$file";
done

cd tmp;

if test "${2#*.}" = 'tar.lz'; then
	if ! command -v tarlz 2>&1 1>/dev/null; then
		echo 'tarlz was not found on your system. are you running Alabaster?';
		echo 'Exiting...';
		exit 127;
	fi
	if test "${2#/}" != "$2"; then
		tarlz -c9n 512 -f "$2" $(ls -A1);
	else
		tarlz -c9n 512 -f "../$2" $(ls -A1);
	fi
elif test "${2#*.}" = 'tar.gz'; then
	if test "${2#/}" != "$2"; then
		tar -czf "$2" $(ls -A1);
	else
		tar -czf "../$2" $(ls -A1);
	fi
elif test "${2#*.}" = 'tar.bz2'; then
	if test "${2#/}" != "$2"; then
		tar -cjf "$2" $(ls -A1);
	else
		tar -cjf "../$2" $(ls -A1);
	fi
elif test "${2#*.}" = 'tar.xz'; then
	if test "${2#/}" != "$2"; then
		tar -cJf "$2" $(ls -A1);
	else
		tar -cJf "../$2" $(ls -A1);
	fi
else
	if test "${2#/}" != "$2"; then
		tar -cf "$2" $(ls -A1);
	else
		tar -cf "../$2" $(ls -A1);
	fi
fi

cd ..;
rm -rf tmp;
