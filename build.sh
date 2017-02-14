#!/bin/bash

# Command line argument: test specific platform. Special case: when "win" specified, Win32 and Win64 will be used.
PLATFORM=$1
TYPE=$2

if [ -z "$PLATFORM" ]; then
	PLATFORM="vc-win32"
	[ "$OSTYPE" == "linux-gnu" ] || [ "$OSTYPE" == "linux" ] && PLATFORM="linux"
fi

export vc_ver=10

# Build <platform> <type>
function Build()
{
	local opt_platform=$1
	local opt_type=$2

	echo "---- Making $2 target for $opt_platform ----"

	# make a directory for obj files and makefiles, and generate a makefile
	[ -d "obj" ] || mkdir obj
	makefile="obj/makefile-$opt_type-$opt_platform"
	Tools/genmake Test/test.project TARGET=$opt_platform TYPE=$opt_type > $makefile

	# build
	case "$opt_platform" in
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
			echo "Unknown PLATFORM=\"$opt_platform\""
			exit 1
	esac
}

# BuildAll <platform>
function BuildAll()
{
	local opt_platform=$1
	if [ "$TYPE" ]; then
		Build $opt_platform $TYPE
	else
		Build $opt_platform "C"
		Build $opt_platform "Orig"
		if [ "$opt_platform" == "vc-win32" ]; then
			Build $opt_platform "Asm"		#!! TODO: x64 asm, linux32 asm
		fi
	fi
}

#-----------------------------------------

if [ "$PLATFORM" == "win" ]; then
	# both windows targets
	BuildAll "vc-win32"
	BuildAll "vc-win64"
else
	BuildAll $PLATFORM
fi
