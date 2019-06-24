#!/bin/bash

if [ ! -d "binaries" ]; then
	echo "Please start \"buildall.sh\" before packaging."
	exit 1
fi

# Extract version from zlib.h using grep and bash regexp
ver=`grep ../zlib/zlib.h -e "#define ZLIB_VERSION"`
[[ "$ver" =~ "\"(.*)\"" ]] && version=${BASH_REMATCH[1]}

tmpdir="tmp"
mkdir -p $tmpdir

cd binaries
/bin/find * | {
	while read line; do
		if [ -d $line ]; then
			mkdir ../$tmpdir/$line
		else
			ext=${line#*.}
			if [ "$ext" != "exp" ]; then
				cp $line ../$tmpdir/$line
			fi
		fi
	done
}

cd ..

cat > $tmpdir/readme.txt <<EOF
This archive contains prebuilt zlib library of version $version compiled with optimized version of deflate.
For more details please visit https://github.com/gildor2/fast_zlib

Directory names combined from <platform>-<calling convention>. Platform is either win32 or win64, calling
convention is cdecl or winapi.

Each directory contains a static library and DLL. Static library file always has name "zlibstat.lib".

For "cdecl", DLL name is zlib1.dll, and it is built with standard C calling convention. This is matches
standard build of zlib for Windows platform.

For "winapi", calling conventions is stdcall, and DLL name is "zlibwapi.dll". This matches behavior from
zlib/contrib/vstudio (by Gilles Vollant). These versions of library, in addition to "cdecl" version,
contains minizip library. To use winapi DLL you should add define ZLIB_WINAPI before including zlib.h.

Konstantin Nosov
https://github.com/gildor2/fast_zlib
http://www.gildor.org
EOF

echo "Now \"tmp\" directory contains data for zipping."
