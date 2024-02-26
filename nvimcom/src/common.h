#ifndef COMMON_H
#define COMMON_H

char *str_cat(char *dest, const char *src);
int str_here(const char *string, const char *substring);
void format(const char *orig, char *dest, char delim, char nl);
char *format_usage(const char *fnm, const char *args);

#endif // COMMON_H
