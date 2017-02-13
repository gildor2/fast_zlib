Fast zlib compression patch
===========================

Summary
-------

Fast ZLIB longest_match function.
For more details and updates please visit
http://www.gildor.org/en/projects/zlib


Build instructions
------------------

Obtain the copy of the Netwide Assembler [here](http://www.nasm.us/)

For use with the Microsoft Visual Studio compile it with the following command line:

    nasm match32.asm -O3 -fwin32 -o match.obj

For the Watcom C use this:

    nasm match32.asm -O3 -fobj -o match.obj -D OMF_FORMAT

You can get precompiled object files in the VisualC and WatcomC directories in this distribution.

This repository also contains C version of algorithm, in match_new.h. **Please note** that this version was
not heavily tested yet, and was not tested on non-PC platforms at all.
