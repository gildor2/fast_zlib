#!/bin/bash

platform=win32

if [ "$OSTYPE" == "linux-gnu" ] || [ "$OSTYPE" == "linux" ]; then
	platform=unix
fi

noorig=0
noasm=0

for arg in "$@"; do		# using quoted $@ will allow to correctly separate arguments like [ --path="some string with spaces" -debug ]
#	echo "ARG=$arg"
	case $arg in
	--noasm)
		noasm=1
		;;
	--noorig)
		noorig=1
		;;
	--win64)
		platform=win64
		;;
	*)
		if [ -d "$arg" ]; then
			dir="$arg"
		else
			echo "Usage: test.sh [path] [--noasm] [--noorig] [--win64]"
			exit
		fi
	esac
done

# build all targets with hiding build output
if ! ./build.sh vc-$platform > /dev/null 2>&1; then
	echo "Build failed!"
	exit 1
fi

echo "Testing for $platform"

function DoTests
{
	local dir="$1"
	if [ "$platform" != "win64" ] && [ $noasm == 0 ]; then
		obj/bin/test-Asm-$platform "$dir"
	fi
	obj/bin/test-C-$platform "$dir"
	if [ $noorig == 0 ]; then
		obj/bin/test-Orig-$platform "$dir"
	fi
}

if [ "$dir" ]; then
	DoTests "$dir"
else
	DoTests C:/Projects/Epic/UnrealEngine4-latest/Engine/Source/Runtime
	DoTests C:/3-UnrealEngine/4.14/Engine/Binaries/Win64
	DoTests C:/1
fi
