Optimized version of longest_match for zlib
===========================================

Summary
-------

Fast zlib longest_match function. Produces slightly smaller compressed files for significantly faster time.
For more details and updates please visit [this page](http://www.gildor.org/en/projects/zlib).
Brief algorithm description is available on [the home page](http://www.gildor.org/en/projects/zlib)
of the project.

Source code repository is located [on Github](https://github.com/gildor2/fast_zlib). [Wiki page](https://github.com/gildor2/fast_zlib/wiki)
contains some additional notes and test results.

You may get precompiled binaries for Windows platform at [this location](https://github.com/gildor2/fast_zlib/releases)


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

#### Zlib 1.2.13 or newer

Note: since zlib 1.2.13 (October 2022), ASMV option has been removed from zlib source, therefore there's no possibility to replace longest_match
function without patching the original source code. So, you'll need to apply patch to the zlib source code in order to make things buildable. You
may find the patch in Sources/zlib_1.2.13.patch.


### Building a 32-bit assembly version

This version is compatible only with x86 platform. To build a matcher, please start with obtaining the copy of the
[Netwide Assembler](http://www.nasm.us/)

For use with the Microsoft Visual Studio compile it with the following command line:

    nasm match32.asm -f win32 -o match.obj

For the Watcom C use this:

    nasm match32.asm -f obj -o match.obj -D OMF_FORMAT

For Linux use this command line:

    nasm match32.asm -f elf32 -o match.o

Running tests
-------------

The library goes with built-in test application. Some information about its features could be found on [wiki page](https://github.com/gildor2/fast_zlib/wiki).

On Unix platforms (those which has bash and perl out-of-the-box) you may simply run build.sh script located at the root directory
of the project. This will build several versions of the test application and put them to obj/bin. There's a script which will run
tests in automated mode, test.sh. Run `test.sh --help` to see available options. By default it will run several predefined tests
for data locations from my own PC. If you'll need to change locations, just modify several bottom lined in the script (see `DoTests <directory>`).

For Windows platform, you'll need bash and perl to be installed and available via PATH environment variable. This could be achieved by
installing [Gygwin](https://www.cygwin.com/) or [MSYS](http://www.mingw.org/wiki/MSYS) projects to your computer. You may also get a set
of required binaries [here](https://github.com/gildor2/UModel/releases) (you'll need `BuildTools.zip`).


License
-------

This library is licensed under the [BSD license](LICENSE.txt).
