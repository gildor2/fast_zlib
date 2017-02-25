#!/bin/bash

platform=win32

noorig=0
noasm=0
noc=0
nodll=0
extraargs="--delete --compact"
dllname=zlibwapi32.dll

if [ "$OSTYPE" == "linux-gnu" ] || [ "$OSTYPE" == "linux" ]; then
	platform=unix
	nodll=1
fi

for arg in "$@"; do		# using quoted $@ will allow to correctly separate arguments like [ --path="some string with spaces" -debug ]
#	echo "ARG=$arg"
	case $arg in
	--noasm)
		noasm=1
		;;
	--noc)
		noc=1
		;;
	--noorig)
		noorig=1
		;;
	--nodll)
		nodll=1
		;;
	--c)
		noasm=1
		nodll=1
		noorig=1
		;;
	--asm)
		noc=1
		nodll=1
		noorig=1
		;;
	--win64)
		platform=win64
		dllname=zlibwapi64.dll
		;;
	--level=*|--exclude=*|--verify)
		extraargs="$extraargs $arg"
		;;
	*)
		if [ -d "$arg" ]; then
			dir="$arg"
		else
			cat <<EOF
Usage: test.sh [path] [options]
Options:
  --no[asm|c|orig|dll]  disable particular target
  --c                   test only C implementation
  --asm                 test only Asm implementation
  --win64               test for 64-bit Windows
  --level=X             select compression level
  --exclude=dir         exclude directory from testing
  --verify              unpack compressed file
EOF
			exit
		fi
	esac
done

# build all targets with hiding build output
target=vc-$platform
[ "$platform" == "unix" ] && target=linux	# shame, "unix" vs "linux"
[ "$platform" == "win64" ] && noasm=1

if ! ./build.sh $target > /dev/null 2>&1; then
	echo "Build failed!"
	exit 1
fi

echo "Testing for $platform"

function DoTests
{
	local dir="$1"
	shift

	echo "--- Processing data at $dir ---"

	if [ "$platform" == "unix" ]; then
		# convert Windows path to Linux (VM)
		if [ "${dir:1:1}" == ":" ]; then
			dir="/mnt/hgfs/${dir:0:1}${dir:2}"
		fi
	fi

	if [ $noasm == 0 ]; then
		obj/bin/test-Asm-$platform "$dir" $extraargs $*
	fi
	if [ $noc == 0 ]; then
		obj/bin/test-C-$platform "$dir" $extraargs $*
	fi
	if [ $nodll == 0 ]; then
		obj/bin/test-Orig-$platform "$dir" $extraargs --dll=test/dll/$dllname $*
	fi
	if [ $noorig == 0 ]; then
		obj/bin/test-Orig-$platform "$dir" $extraargs $*
	fi
}

if [ "$dir" ]; then
	DoTests "$dir"
else
	DoTests C:/Projects/Epic/UnrealEngine4-latest/Engine/Source --exclude=ThirdParty
	DoTests C:/3-UnrealEngine/4.14/Engine/Binaries/Win64
	DoTests C:/1
fi
