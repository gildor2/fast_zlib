Optimized version of longest_match for zlib
===========================================

Summary
-------

Fast ZLIB longest_match function. Produces slightly smaller compressed files for significantly faster time.
For more details and updates please visit [this page](http://www.gildor.org/en/projects/zlib).

Source code repository is located [on Github](https://github.com/gildor2/fast_zlib). [Wiki page](https://github.com/gildor2/fast_zlib/wiki)
contains some additional notes and test results.


Build instructions
------------------

This library consists of 2 versions: C and assembly.

### Building C version

You should replace longest_match() function in deflate.c with one located in Sources/match.h. One of possible ways
is to making a file with contents looking like

	#define ASMV
	#include "deflate.c"

	#undef local
	#define local

	#include "match.h"

	void match_init()
	{
	}

and linking zlib with this file instead of deflate.c.


### Building assembly version

This version is compatible only with x86 platform. To build a matcher, please start with obtaining the copy of the
[Netwide Assembler](http://www.nasm.us/)

For use with the Microsoft Visual Studio compile it with the following command line:

    nasm match32.asm -f win32 -o match.obj

For the Watcom C use this:

    nasm match32.asm -f obj -o match.obj -D OMF_FORMAT


License
-------

This library is licensed under the [BSD license](LICENSE.txt).
