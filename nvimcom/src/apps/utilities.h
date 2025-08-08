#ifndef UTILITIES_H
#define UTILITIES_H

#ifdef WIN32
#include <inttypes.h>
#define bzero(b, len) (memset((b), '\0', (len)), (void)0)
#ifdef _WIN64
#define PRI_SIZET PRIu64
#else
#define PRI_SIZET PRIu32
#endif
#else
#define PRI_SIZET "zu"
#endif

char *grow_buffer(char **b, unsigned long *sz, unsigned long inc);
void replace_char(char *s, char find, char replace);

#endif
