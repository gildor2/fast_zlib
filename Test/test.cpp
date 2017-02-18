#include <stdio.h>
#include <time.h>

// includes for file enumeration
#if _WIN32
#	include <io.h>					// for findfirst() set
#else
#	include <dirent.h>				// for opendir() etc
#	include <sys/stat.h>			// for stat()
#endif

#include <vector>
#include <string>

#include "zlib.h"

#define STR2(s) #s
#define STR(s) STR2(s)

#define BUFFER_SIZE		(256<<20)
#define MAX_ITERATIONS	1			// number of passes to fully fill buffer, i.e. total processed data size will be up to (BUFFER_SIZE * MAX_ITERATIONS)
#define COMPRESS_LEVEL	9

std::vector<std::string> fileList;

static bool ScanDirectory(const char *dir, bool recurse = true)
{
	char Path[1024];
	bool res = true;
//	printf("Scan %s\n", dir);
#if _WIN32
	sprintf(Path, "%s/*.*", dir);
	_finddatai64_t found;
	intptr_t hFind = _findfirsti64(Path, &found);
	if (hFind == -1) return true;
	do
	{
		if (found.name[0] == '.') continue;			// "." or ".."
		sprintf(Path, "%s/%s", dir, found.name);
		// directory -> recurse
		if (found.attrib & _A_SUBDIR)
		{
			if (recurse)
				res = ScanDirectory(Path, recurse);
			else
				res = true;
		}
		else
		{
			fileList.push_back(Path);
			res = true;
		}
	} while (res && _findnexti64(hFind, &found) != -1);
	_findclose(hFind);
#else
	DIR *find = opendir(dir);
	if (!find) return true;
	struct dirent *ent;
	while (/*res &&*/ (ent = readdir(find)))
	{
		if (ent->d_name[0] == '.') continue;			// "." or ".."
		sprintf(Path, "%s/%s", dir, ent->d_name);
		// directory -> recurse
		// note: using 'stat64' here because 'stat' ignores large files
		struct stat64 buf;
		if (stat64(Path, &buf) < 0) continue;			// or break?
		if (S_ISDIR(buf.st_mode))
		{
			if (recurse)
				res = ScanDirectory(Path, recurse);
			else
				res = true;
		}
		else
		{
			fileList.push_back(Path);
			res = true;
		}
	}
	closedir(find);
#endif
	return res;
}

static unsigned char buffer[BUFFER_SIZE];
static int bytesInBuffer = 0;
static int currentFile = 0;

static bool FillBuffer()
{
	bytesInBuffer = 0;

	while (bytesInBuffer < BUFFER_SIZE)
	{
		if (currentFile >= fileList.size()) break;
		const char* filename = fileList[currentFile++].c_str();
		FILE* f = fopen(filename, "rb");
		if (!f) continue; // no error, skip this file

		int bytesRead = fread(buffer + bytesInBuffer, 1, BUFFER_SIZE - bytesInBuffer, f);
		fclose(f);
		bytesInBuffer += bytesRead;
//		printf("file %s %d bytes\n", filename, bytesRead);
	}
//	printf("... %d bytes\n", bytesInBuffer);

	return (bytesInBuffer > 0);
}



int main(int argc, const char **argv)
{
	if (argc <= 1)
	{
		printf("Usage: test <directory>\n");
		return 1;
	}

	ScanDirectory(argv[1]);
//	printf("%d files\n", fileList.size());

	clock_t clocks = 0;

	const char* compressedFile = "compressed-" STR(VERSION) ".gz";
	gzFile gz = gzopen(compressedFile, "wb" STR(COMPRESS_LEVEL));
	int iteration = 0;
	int totalDataSize = 0;
	while (FillBuffer() && iteration < MAX_ITERATIONS)
	{
		clock_t clock_a = clock();
		gzwrite(gz, buffer, bytesInBuffer);
		clocks += clock() - clock_a;
		iteration++;
		totalDataSize += bytesInBuffer;
	}
	gzclose(gz);

	FILE* f = fopen(compressedFile, "rb");
	fseek(f, 0, SEEK_END);
	int compressedSize = ftell(f);
	fclose(f);

	printf("Compressed %.1f Mb of data by method %s with level %d (%s)\n", (float)totalDataSize / (1024*1024), STR(VERSION), COMPRESS_LEVEL, argv[1]);
	printf("Time: %.1f s\n", clocks / (float)CLOCKS_PER_SEC);
	printf("Size: %d\n", compressedSize);

	return 0;
}
