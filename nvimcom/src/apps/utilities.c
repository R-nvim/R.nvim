#include <stdlib.h>
#include <string.h>

#include "utilities.h"

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
