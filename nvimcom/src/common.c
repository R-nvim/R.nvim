#include <stdlib.h> // Standard library
#include <stdio.h>  // Standard input/output definitions
#include <string.h> // String handling functions

#include "common.h"

static int doc_width = 58;

/**
 * Checks if the string `b` is at the start of string `a`.
 * @param a The string to be checked.
 * @param b The substring to look for at the start of `a`.
 * @return 1 if `b` is at the start of `a`, 0 otherwise.
 */
int str_here(const char *a, const char *b) {
    while (*b && *a) {
        if (*a != *b)
            return 0;
        a++;
        b++;
    }
    return *b == '\0';
}

/**
 * @brief Concatenate two strings.
 *
 * @param dest Destination buffer.
 * @param src String to be appended to `dest`.
 * @return Pointer to the new NULL terminating byte of `dest`.
 */
char *str_cat(char *dest, const char *src) {
    while (*dest)
        dest++;
    while ((*dest++ = *src++))
        ;
    return --dest;
}

/**
 * @brief Insert line breaks at appropriate places to ensure a specified text
 * width.
 *
 * @param orig Original buffer.
 * @param dest Destination buffer.
 * @param delim Character that separate words (usually a space).
 * @param nl Character to insert as new line (usually this is a \n, but we use
 * \x14 because a \n split strings sent to stdout).
 */
void format(const char *orig, char *dest, char delim, char nl) {
    size_t sz = strlen(orig);
    size_t i = 0, n = 0, s = 0;
    while (orig[i] && i < sz) {
        if (orig[i] == delim)
            s = i;
        dest[i] = orig[i];
        if (n == doc_width && s > 0) {
            dest[s] = nl;
            n = i - s;
            s = 0;
        }
        i++;
        n++;
    }
    dest[i] = 0;
}

/**
 * @brief Format the usage section of completion documentation.
 *
 * @param fnm Function name.
 * @param args The arguments as a string.
 * @return The formatted text (which must be freed after used).
 */
char *format_usage(const char *fnm, const char *args) {
    size_t sz = strlen(fnm) + 64 + (3 * strlen(args));
    char *b = calloc(sz, sizeof(char));
    char *f = calloc(sz, sizeof(char));
    snprintf(b, sz - 1, "%s(", fnm);
    size_t i = strlen(b);
    size_t j = 0;
    while (args[j]) {
        if (args[j] == '\x04') {
            b[i] = ' ';
            i++;
            b[i] = '=';
            i++;
            b[i] = ' ';
        } else if (args[j] == '\x05') {
            if (args[j + 1]) {
                b[i] = ',';
                i++;
                b[i] = '\x02';
            }
        } else {
            b[i] = args[j];
        }
        i++;
        j++;
    }
    str_cat(b, ")");
    format(b, f, '\x02', '\x03');
    strcpy(b, "\x14\x14---\x14```r\x14");
    i = 0;
    j = strlen(b);
    while (f[i]) {
        if (f[i] == '\x03') {
            b[j] = '\x14';
            j++;
            b[j] = ' ';
            j++;
            b[j] = ' ';
        } else if (f[i] == '\x02') {
            b[j] = ' ';
        } else {
            b[j] = f[i];
        }
        i++;
        j++;
    }
    str_cat(b, "\x14```\x14");
    free(f);
    return b;
}

void set_doc_width(const char *width) {
    if (!width)
        return;
    int w = atoi(width);
    if (w > 0)
        doc_width = w;
}

int get_doc_width(void) { return doc_width; }
