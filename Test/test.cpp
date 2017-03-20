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

// Defines controlling size of compressed data
#define BUFFER_SIZE		(256<<20)
#define MAX_ITERATIONS	1			// number of passes to fully fill buffer, i.e. total processed data size will be up to (BUFFER_SIZE * MAX_ITERATIONS)

#if _WIN32
#define USE_DLL 1
#endif

#define STR2(s) #s
#define STR(s) STR2(s)

#if USE_DLL

#include <windows.h>				// for DLL stuff

static HMODULE zlibDll = NULL;
static bool bWinapiCalls = false;

// Make a wrappers for zlib functions allowing to call statically-linked function, or cdecl or winapi dll function.
// This macro receives argument list twice - with and without type specifiers.
#define DECLARE_WRAPPER(type, name, prototype, args)\
static type name##_imp prototype					\
{													\
	if (zlibDll)									\
	{												\
		typedef type (*name##_f) prototype;			\
		typedef type (WINAPI *name##_fw) prototype;	\
		static name##_f func_ptr = NULL;			\
		if (func_ptr == NULL)						\
		{											\
			func_ptr = (name##_f)GetProcAddress(zlibDll, STR(name)); \
		}											\
		return bWinapiCalls ? ((name##_fw)func_ptr) args : func_ptr args; \
	}												\
	else											\
	{												\
		return name args;							\
	}												\
}

DECLARE_WRAPPER(gzFile, gzopen, (const char* filename, const char* params), (filename, params))
DECLARE_WRAPPER(int, gzwrite, (gzFile file, voidpc buf, unsigned len), (file, buf, len))
DECLARE_WRAPPER(int, gzread, (gzFile file, voidp buf, unsigned len), (file, buf, len))
DECLARE_WRAPPER(int, gzclose, (gzFile file), (file))
DECLARE_WRAPPER(int, compress2, (Bytef *dest, uLongf *destLen, const Bytef *source, uLong sourceLen, int level), (dest, destLen, source, sourceLen, level));
DECLARE_WRAPPER(int, uncompress, (Bytef *dest, uLongf *destLen, const Bytef *source, uLong sourceLen), (dest, destLen, source, sourceLen));

// Hook gzip functions
#define gzopen  gzopen_imp
#define gzwrite gzwrite_imp
#define gzread  gzread_imp
#define gzclose gzclose_imp
#define compress2 compress2_imp
#define uncompress uncompress_imp

#endif // USE_DLL

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

#if USE_DLL
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

static unsigned char compressedBuffer[BUFFER_SIZE+16384];

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
#if USE_DLL
			"  --dll=<file>      use external WINAPI zlib dll\n"
#endif
			"  --compact         use compact output\n"
			"  --memory          use in-memory compression instead of gzip\n"
			"  --verify          decompress generated file for testing\n"
			"  --delete          erase compressed file after completion\n"
		);
		return 1;
	}

	// parse command line
	const char* dirName = NULL;
	int level = 9;
	bool compactOutput = false;
	bool unpackFile = false;
	bool eraseCompressedFile = false;
	bool inMemoryCompression = false;

#if USE_DLL
	const char* dllName = NULL;
#endif

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
				level = arg[6] - '0';
			}
			else if (!strnicmp(arg, "exclude=", 8))
			{
				fileExclude.push_back(arg+8);
			}
			else if (!stricmp(arg, "compact"))
			{
				compactOutput = true;
			}
			else if (!stricmp(arg, "verify"))
			{
				unpackFile = true;
			}
			else if (!stricmp(arg, "delete"))
			{
				eraseCompressedFile = true;
			}
			else if (!stricmp(arg, "memory"))
			{
				inMemoryCompression = true;
			}
#if USE_DLL
			else if (!strnicmp(arg, "dll=", 4))
			{
				if (zlibDll != NULL) goto usage;
				dllName = arg+4;
				zlibDll = LoadLibrary(dllName);
				if (zlibDll == NULL)
				{
					printf("Error: unable to load zlib.dll %s\n", dllName);
					exit(1);
				}
			}
#endif // USE_DLL
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

#if USE_DLL
	if (zlibDll)
	{
		typedef unsigned (*zlibCompileFlags_f)();
		zlibCompileFlags_f zlibCompileFlags_ptr = (zlibCompileFlags_f)GetProcAddress(zlibDll, "zlibCompileFlags");
		unsigned zlibFlags = zlibCompileFlags_ptr();
		bWinapiCalls = (zlibFlags & 0x400) != 0;
	}
#endif // USE_DLL

	clock_t clocks = 0;
	clock_t unpackClocks = 0;

	// open compressed stream
	const char* compressedFile = "compressed-" STR(VERSION) "-" PLATFORM ".gz";
	gzFile gz = NULL;
	if (!inMemoryCompression)
	{
		char initString[4] = "wb";
		initString[2] = level + '0';
		gz = gzopen(compressedFile, initString);
	}

	int iteration = 0;
	int totalDataSize = 0;
	int totalCompressedSize = 0;

	// perform compression
	while (FillBuffer() && iteration < MAX_ITERATIONS)
	{
		if (!inMemoryCompression)
		{
			clock_t clock_a = clock();
			gzwrite(gz, buffer, bytesInBuffer);
			clocks += clock() - clock_a;
		}
		else
		{
			clock_t clock_a = clock();
			unsigned long compressedSize = sizeof(compressedBuffer);
			int result;
			result = compress2(compressedBuffer, &compressedSize, buffer, bytesInBuffer, level);
			if (result != Z_OK)
			{
				printf("   Compress ERROR %d\n", result);
				exit(1);
			}
			clocks += clock() - clock_a;
			totalCompressedSize += compressedSize;

			if (unpackFile)
			{
				clock_t clock_a = clock();
				unsigned long unpackedSize = BUFFER_SIZE;
				result = uncompress(buffer, &unpackedSize, compressedBuffer, compressedSize);
				if (result != Z_OK)
				{
					printf("   Unpack ERROR %d\n", result);
					exit(1);
				}
				unpackClocks += clock() - clock_a;
			}
		}
		iteration++;
		totalDataSize += bytesInBuffer;
	}

	// close compressed stream
	if (!inMemoryCompression)
	{
		gzclose(gz);
	}

	// determine size of compressed data
	if (!inMemoryCompression)
	{
		FILE* f = fopen(compressedFile, "rb");
		fseek(f, 0, SEEK_END);
		totalCompressedSize = ftell(f);
		fclose(f);
	}

	// print results
	const char* method = STR(VERSION);
#if USE_DLL
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
	printf("Time: %-5.1f s   Size: %d bytes   Speed: %5.2f Mb/s   Ratio: %.2f",
		time, totalCompressedSize, totalDataSize / double(1<<20) / time, (double)totalDataSize / totalCompressedSize);

	if (unpackFile && !inMemoryCompression)
	{
		gz = gzopen(compressedFile, "rb");
		clock_t clock_a = clock();

		int result;
		for (int unpSize = 0; unpSize < totalDataSize; /* nothing */)
		{
			result = gzread(gz, buffer, BUFFER_SIZE);
			if (result < 0)
			{
			unpack_error:
				printf("   Unpack ERROR %d\n", result);
				exit(1);
			}
			unpSize += result;
		}

		result = gzclose(gz);
		if (result != Z_OK) goto unpack_error;

		unpackClocks += clock() - clock_a;
	}

	if (unpackFile)
	{
		time = unpackClocks / (float)CLOCKS_PER_SEC;
		printf("   Unpack: %5.2f Mb/s", totalDataSize / double(1<<20) / time);
	}

#if USE_DLL
	if (zlibDll) printf("  (%s)", dllName);
#endif

	printf("\n");

	// erase compressed file
	if (eraseCompressedFile)
	{
		remove(compressedFile);
	}

	return 0;
}
