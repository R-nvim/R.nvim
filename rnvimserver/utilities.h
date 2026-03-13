#ifndef UTILITIES_H
#define UTILITIES_H

#include <inttypes.h>
#include <stddef.h>
#ifdef WIN32
#define bzero(b, len) (memset((b), '\0', (len)), (void)0)
#endif

char *grow_buffer(char **b, size_t *sz, size_t inc);
void replace_char(char *s, char find, char replace);
char *read_file(const char *fn, int verbose);
char *esc_json(const char *input);
void cut_json_int(char **str, unsigned len);
void cut_json_str(char **str, unsigned len);
void cut_json_bkt(char **str, unsigned len);
char *seek_word(char *objls, const char *wrd);
int fuzzy_find(const char *a, const char *b);
int is_function(const char *obj);

#endif
