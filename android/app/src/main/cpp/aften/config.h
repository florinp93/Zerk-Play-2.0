/* Hand-written for the Android build (Aften's CMake generates this upstream).
 * No SIMD (the x86 / AltiVec code isn't built) and no threading options set,
 * so threading.h falls back to NO_THREADS: one frame in, one frame out. */
#define HAVE_INTTYPES_H 1

/* Set by upstream's CMakeLists.txt; only bounds the thread count. */
#define MAX_NUM_THREADS 32

/* Only the x86 / PowerPC CPU-caps sources define this; nothing to restrict here. */
#define apply_simd_restrictions(simd) ((void) (simd))
