// Compare original and optimized C code

#define COMPARE_MATCHES
#include "deflate-debug.c"

/* Prevent error when "longest_match" declared as "extern" but appears "static" */
#undef local
#define local

/* Include our match algorithm */
#include "../Sources/match.h"
