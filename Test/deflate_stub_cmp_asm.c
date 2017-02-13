// Compare optimized C and Asm code

#define COMPARE_MATCHES
#define ASMV
#include "Zlib/deflate-debug.c"

/* Prevent error when "longest_match" declared as "extern" but appears "static" */
#undef local
#define local

/* Include our match algorithm */
#define longest_match longest_match_orig
#undef local
#define local
#include "../Sources/match.h"
