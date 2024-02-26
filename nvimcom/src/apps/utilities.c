#include "utilities.h"
#include <stdlib.h>
#include <string.h>

/**
 * Compares two ASCII strings in a case-insensitive manner.
 * @param a First string.
 * @param b Second string.
 * @return An integer less than, equal to, or greater than zero if a is found,
 *         respectively, to be less than, to match, or be greater than b.
 */
int ascii_ic_cmp(const char *a, const char *b) {
    int d;
    unsigned x, y;
    while (*a && *b) {
        x = (unsigned char)*a;
        y = (unsigned char)*b;
        if (x <= 'Z')
            x += 32;
        if (y <= 'Z')
            y += 32;
        d = x - y;
        if (d != 0)
            return d;
        a++;
        b++;
    }
    return 0;
}

/**
 * Grows a buffer to a new size.
 * @param b Pointer to the buffer.
 * @param sz Size of the buffer.
 * @param inc Amount to increase.
 * @return Pointer to the resized buffer.
 */
char *grow_buffer(char **b, unsigned long *sz, unsigned long inc) {
    *sz += inc;
    char *tmp = calloc(*sz, sizeof(char));
    strcpy(tmp, *b);
    free(*b);
    *b = tmp;
    return tmp;
}

/**
 * Replaces all instances of a specified character in a string with another
 * character.
 * @param s The string to be modified.
 * @param find The character to find and replace.
 * @param replace The character to replace with.
 */
void replace_char(char *s, char find, char replace) {
    while (*s != '\0') {
        if (*s == find)
            *s = replace;
        s++;
    }
}

/**
 * Checks if the string `b` can be found through string `a`.
 * @param a The string to be checked.
 * @param b The substring to look for at the start of `a`.
 * @return 1 if `b` is at the start of `a`, 0 otherwise.
 */
int fuzzy_find(const char *a, const char *b) {
    while (*b && *a) {
        while (*a && *a != *b)
            a++;
        a++;
        b++;
    }
    return *b == '\0';
}
