#include <windows.h>
#include <stdio.h>
#include "zlib/zlib.h"

//#pragma comment(lib, "lib/Release/zlib.lib")


void main (int argc, const char **argv)
{
	FILE *f;
	gzFile gz;
	char buf[8192];

	if (!(f = fopen("uncompressed.txt", "rb")))
	{
		puts("!open");
		exit(1);
	}

	int t = GetTickCount();
	gz = gzopen("compressed2.gz", "wb9");
	while (!feof(f))
	{
		int len = fread(buf, 1, sizeof(buf), f);
		gzwrite(gz, buf, len);
	}
	fclose(f);
	gzclose(gz);

	printf("seconds:%d/10\n", (GetTickCount()-t) / 100);
	f = fopen("compressed2.gz", "rb");
	fseek(f, 0, SEEK_END);
	int len = ftell(f);
	fclose(f);
	printf("size:%d\n", len);
}
