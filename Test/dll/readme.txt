Put zlibwapi.dll from http://www.winimage.com/zLibDll/ here. Names used by test.sh script are zlibwapi32.dll and zlibwapi64.dll.
Put zlib1.dll from zlib-ng with names zlib-ng_32.dll and zlib-ng_64.dll

How to build zlib-ng:
- obtain source code from https://github.com/Dead2/zlib-ng
- modify win32/Makefile.msc, set WITH_GZFILEOP = 1
- execute "nmake -f win32/Makefile.msc" or "vc32tools [--64] --version=2013 --make win32/Makefile.msc"
- copy compiled zlib1.dll to this directory

Possible problems with zlib-ng:
- use Visual Studion 2013+ (2010 can't build zlib-ng)
- there are possible type conflicts: replace ssize_t with size_t
