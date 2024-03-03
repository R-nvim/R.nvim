#ifndef UTILITIES_H
#define UTILITIES_H

char *grow_buffer(char **b, unsigned long *sz, unsigned long inc);
void replace_char(char *s, char find, char replace);
int fuzzy_find(const char *a, const char *b);
int ascii_ic_cmp(const char *a, const char *b);

#endif // UTILITIES_H
