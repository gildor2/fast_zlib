#!/bin/bash

PLATFORM="vc-win32"
[ "$OSTYPE" == "linux-gnu" ] || [ "$OSTYPE" == "linux" ] && PLATFORM="linux"

export vc_ver=10

function Build()
{
	PLATFORM=$1

	# make a directory for obj files and makefiles, and generate makefile
	[ -d "obj" ] || mkdir obj
	makefile="obj/makefile-$PLATFORM"
	Tools/genmake Test/test.project TARGET=$PLATFORM > $makefile

	# build
	case "$PLATFORM" in
		"vc-win32")
			vc32tools --make $makefile || exit 1
			;;
		"vc-win64")
			vc32tools --64 --make $makefile || exit 1
			;;
		"mingw32"|"cygwin")
			PATH=/bin:/usr/bin:$PATH			# configure paths for Cygwin
			gccfilt make -f $makefile || exit 1
			;;
		linux*)
			make -j 4 -f $makefile || exit 1	# use 4 jobs for build
			;;
		*)
			echo "Unknown PLATFORM=\"$PLATFORM\""
			exit 1
	esac
}

#-----------------------------------------

Build $PLATFORM

if [ "$PLATFORM" == "vc-win32" ]; then
	# additional target
	Build "vc-win64"
fi
