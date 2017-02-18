#!/bin/bash

export vc_ver=10
R=..
obj=$R/obj

function Build()
{
	local opt_platform=$1
	local opt_type=$2

	echo "---- Making $2 target for $opt_platform ----"

	# make a directory for obj files and makefiles, and generate a makefile
	[ -d $obj ] || mkdir $obj
	makefile="$obj/makefile-dll-$opt_type-$opt_platform"
	$R/Tools/genmake zlibdll.project TARGET=$opt_platform CONV=$opt_type > $makefile

	# build
	case "$opt_platform" in
		"vc-win32")
			vc32tools --make $makefile || exit 1
			;;
		"vc-win64")
			vc32tools --64 --make $makefile || exit 1
			;;
		*)
			echo "Unknown PLATFORM=\"$opt_platform\""
			exit 1
	esac
}

Build "vc-win32" "cdecl"
Build "vc-win64" "cdecl"
Build "vc-win32" "winapi"
Build "vc-win64" "winapi"
