#!/bin/bash

platform=win32

# build all targets with hiding build output
./build.sh vc-$platform > /dev/null 2>&1

function DoTests
{
	local dir=$1
	obj/bin/test-Asm-$platform $dir
	obj/bin/test-C-$platform $dir
	obj/bin/test-Orig-$platform $dir
}

if [ $1 ]; then
	DoTests $1
else
	DoTests C:/Projects/Epic/UnrealEngine4-latest/Engine/Source/Runtime
	DoTests C:/3-UnrealEngine/4.14/Engine/Binaries/Win64
	DoTests C:/1
fi
