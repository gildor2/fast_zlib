#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// includes for file enumeration
#if _WIN32
#	include <io.h>					// for findfirst() set
#	ifndef _WIN64
#		define PLATFORM				"win32"
#	else
#		define PLATFORM				"win64"
#	endif
#else
#	include <dirent.h>				// for opendir() etc
#	include <sys/stat.h>			// for stat()
#	define stricmp					strcasecmp
#	define strnicmp					strncasecmp
#	define PLATFORM					"unix"
#endif

#include <vector>
#include <string>

#include "zlib.h"

#define STR2(s) #s
#define STR(s) STR2(s)

#define BUFFER_SIZE		(256<<20)
#define MAX_ITERATIONS	1			// number of passes to fully fill buffer, i.e. total processed data size will be up to (BUFFER_SIZE * MAX_ITERATIONS)
#define COMPRESS_LEVEL	9

#if _WIN32

#include <windows.h>

static HMODULE zlibDll = NULL;

static gzFile gzopen_imp(const char* filename, const char* params)
{
	if (zlibDll)
	{
		typedef gzFile (WINAPI *gzopen_f)(const char* filename, const char* params);
		static gzopen_f gzopen_ptr = NULL;
		if (gzopen_ptr == NULL)
		{
			gzopen_ptr = (gzopen_f)GetProcAddress(zlibDll, "gzopen");
//			assert(gzopen_ptr);
		}
		return gzopen_ptr(filename, params);
	}
	else
	{
		return gzopen(filename, params);
	}
}

static int gzwrite_imp(gzFile file, voidpc buf, unsigned len)
{
	if (zlibDll)
	{
		typedef int (WINAPI *gzwrite_f)(gzFile file, voidpc buf, unsigned len);
		static gzwrite_f gzwrite_ptr = NULL;
		if (gzwrite_ptr == NULL)
		{
			gzwrite_ptr = (gzwrite_f)GetProcAddress(zlibDll, "gzwrite");
//			assert(gzwrite_ptr);
		}
		return gzwrite_ptr(file, buf, len);
	}
	else
	{
		return gzwrite(file, buf, len);
	}
}

static int gzclose_imp(gzFile file)
{
	if (zlibDll)
	{
		typedef int (WINAPI *gzclose_f)(gzFile file);
		static gzclose_f gzclose_ptr = NULL;
		if (gzclose_ptr == NULL)
		{
			gzclose_ptr = (gzclose_f)GetProcAddress(zlibDll, "gzclose");
//			assert(gzclose_ptr);
		}
		return gzclose_ptr(file);
	}
	else
	{
		return gzclose(file);
	}
}

// Hook gzip functions
#define gzopen gzopen_imp
#define gzwrite gzwrite_imp
#define gzclose gzclose_imp

#endif // _WIN32

std::vector<std::string> fileList;
std::vector<std::string> fileExclude;

static bool IsFileExcluded(const char* filename)
{
	for (int i = 0; i < fileExclude.size(); i++)
	{
		if (!stricmp(filename, fileExclude[i].c_str()))
			return true;
	}
	return false;
}

static bool ScanDirectory(const char *dir, bool recurse = true, int baseDirLen = -1)
{
	char Path[1024];
	bool res = true;
//	printf("Scan %s\n", dir);
	if (baseDirLen < 0)
		baseDirLen = strlen(dir) + 1;

#if _WIN32
	sprintf(Path, "%s/*.*", dir);
	_finddatai64_t found;
	intptr_t hFind = _findfirsti64(Path, &found);
	if (hFind == -1) return true;
	do
	{
		if (found.name[0] == '.') continue;			// "." or ".."
		sprintf(Path, "%s/%s", dir, found.name);
		if (IsFileExcluded(Path + baseDirLen)) continue;
		// directory -> recurse
		if (found.attrib & _A_SUBDIR)
		{
			if (recurse)
				res = ScanDirectory(Path, recurse, baseDirLen);
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
		if (IsFileExcluded(Path + baseDirLen)) continue;
		// directory -> recurse
		// note: using 'stat64' here because 'stat' ignores large files
		struct stat64 buf;
		if (stat64(Path, &buf) < 0) continue;			// or break?
		if (S_ISDIR(buf.st_mode))
		{
			if (recurse)
				res = ScanDirectory(Path, recurse, baseDirLen);
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
	usage:
		printf(
			"Usage: test [options] <directory>\n"
			"Options:\n"
			"  --level=[0-9]     set compression level, default 9\n"
			"  --exclude=<dir>   exclude specified directory from tests\n"
#if _WIN32
			"  --dll=<file>      use external WINAPI zlib dll\n"
#endif
			"  --compact         use compact output\n"
			"  --delete          erase compressed file after completion\n"
		);
		return 1;
	}

	// parse command line
	const char* dirName = NULL;
	char level = '9';
	bool compactOutput = false;
	bool eraseCompressedFile = false;

	for (int i = 1; i < argc; i++)
	{
		const char* arg = argv[i];
		if (arg[0] == '-' && arg[1] == '-')
		{
			// option
			arg += 2; // skip "--"
			if (!strnicmp(arg, "level=", 6))
			{
				if (!(level >= '0' && level <= '9')) goto usage;
				level = arg[6];
			}
			else if (!strnicmp(arg, "exclude=", 8))
			{
				fileExclude.push_back(arg+8);
			}
			else if (!stricmp(arg, "compact"))
			{
				compactOutput = true;
			}
			else if (!stricmp(arg, "delete"))
			{
				eraseCompressedFile = true;
			}
#if _WIN32
			else if (!strnicmp(arg, "dll=", 4))
			{
				if (zlibDll != NULL) goto usage;
				zlibDll = LoadLibrary(arg+4);
				if (zlibDll == NULL)
				{
					printf("Error: unable to load zlib.dll %s\n", arg+4);
					exit(1);
				}
			}
#endif // _WIN32
			else
			{
				goto usage;
			}
		}
		else
		{
			if (dirName) goto usage;
			dirName = arg;
		}
	}

	if (!dirName)
	{
		printf("Error: directory name was not specified\n");
		exit(1);
	}

	// prepare data for compression
	ScanDirectory(dirName);
	if (fileList.size() == 0)
	{
		printf("Error: the specified location has no files\n");
		exit(1);
	}
//	printf("%d files\n", fileList.size());

	clock_t clocks = 0;

	// open compressed stream
	char initString[4] = "wb";
	const char* compressedFile = "compressed-" STR(VERSION) "-" PLATFORM ".gz";
	initString[2] = level;
	gzFile gz = gzopen(compressedFile, initString);
	int iteration = 0;
	int totalDataSize = 0;
	// perform compression
	while (FillBuffer() && iteration < MAX_ITERATIONS)
	{
		clock_t clock_a = clock();
		gzwrite(gz, buffer, bytesInBuffer);
		clocks += clock() - clock_a;
		iteration++;
		totalDataSize += bytesInBuffer;
	}
	// close compressed stream
	gzclose(gz);

	// determine size of compressed data
	FILE* f = fopen(compressedFile, "rb");
	fseek(f, 0, SEEK_END);
	int compressedSize = ftell(f);
	fclose(f);

	// erase compressed file
	if (eraseCompressedFile)
	{
		remove(compressedFile);
	}

	// print results
	const char* method = STR(VERSION);
#if _WIN32
	if (zlibDll) method = "DLL";
#endif
	float time = clocks / (float)CLOCKS_PER_SEC;
	float originalSizeMb = totalDataSize / double(1<<20);
	if (!compactOutput)
	{
		printf("Compressed %.1f Mb of data by method %s with level %c (%s)\n", originalSizeMb, method, level, dirName);
	}
	else
	{
		printf("%6s:%c   Data: %.1f Mb   ", method, level, originalSizeMb);
	}
	printf("Time: %-5.1f s   Size: %d bytes   Speed: %5.2f Mb/s   Ratio: %.2f\n",
		time, compressedSize, totalDataSize / double(1<<20) / time, (double)totalDataSize / compressedSize);

	return 0;
}
