#include <stdlib.h>
#include <stdio.h>
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

// TODO: remove excess of text from all functions documentation.

/**
 * @brief Reads the entire contents of a specified file into a buffer.
 * @param fn The name of the file to be read.
 * @param verbose Flag to indicate whether to print error messages.
 * @return Returns a pointer to a buffer containing the file's or NULL.
 */
char *read_file(const char *fn, int verbose) {
    FILE *f = fopen(fn, "rb");
    if (!f) {
        if (verbose) {
            fprintf(stderr, "Error opening '%s'", fn);
            fflush(stderr);
        }
        return NULL;
    }
    fseek(f, 0L, SEEK_END);
    long sz = ftell(f);
    if (sz == 0) {
        // List of objects is empty. Perhaps no object was created yet.
        // The args_datasets files is empty
        fclose(f);
        return calloc(1, sizeof(char));
    }

    char *b = calloc(1, sz + 1);
    if (!b) {
        fclose(f);
        fputs("Error allocating memory\n", stderr);
        fflush(stderr);
        return NULL;
    }

    rewind(f);
    if (1 != fread(b, sz, 1, f)) {
        fclose(f);
        free(b);
        fprintf(stderr, "Error reading '%s'\n", fn);
        fflush(stderr);
        return NULL;
    }
    fclose(f);
    return b;
}

// Function to escape a string for JSON
char *esc_json(const char *input) {
    if (input == NULL) {
        return NULL;
    }

    size_t ilen = strlen(input);
    // Allocate enough memory for the escaped string (worst case: all chars
    // escaped) Plus 1 for null terminator
    char *b = (char *)malloc(ilen * 6 + 1);
    if (b == NULL) {
        return NULL;
    }

    size_t j = 0;
    for (size_t i = 0; i < ilen; i++) {
        char c = input[i];
        switch (c) {
        case '\x14':
            b[j++] = '\\';
            b[j++] = 'n';
            break;
        case '\x13':
            b[j++] = '\'';
            break;
        case '\x12':
            b[j++] = '\\';
            b[j++] = '\\';
            break;
        case '"':
            b[j++] = '\\';
            b[j++] = '"';
            break;
        case '\\':
            b[j++] = '\\';
            b[j++] = '\\';
            break;
        case '\n':
            b[j++] = '\\';
            b[j++] = 'n';
            break;
        case '\r':
            b[j++] = '\\';
            b[j++] = 'r';
            break;
        case '\t':
            b[j++] = '\\';
            b[j++] = 't';
            break;
        case '\b':
            b[j++] = '\\';
            b[j++] = 'b';
            break;
        case '\f':
            b[j++] = '\\';
            b[j++] = 'f';
            break;
        default:
            b[j++] = c;
            break;
        }
    }
    b[j] = '\0';
    return b;
}
