#ifndef COMMON_H
#define COMMON_H

char *str_cat(char *dest, const char *src);
int str_here(const char *string, const char *substring);
void format(const char *orig, char *dest, char delim, char nl);
char *format_usage(const char *fnm, const char *args);
void set_doc_width(const char *width);
int get_doc_width(void);

#endif // COMMON_H
