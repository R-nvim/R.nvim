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

/**
 * @brief Reads the entire contents of a specified file into a buffer.
 *
 * This function opens the file specified by the filename and reads its entire
 * content into a dynamically allocated buffer. It ensures that the file is read
 * in binary mode to preserve the data format. This function is typically used
 * to load files containing data relevant to the R.nvim plugin, such as
 * completion lists or configuration data.
 *
 * @param fn The name of the file to be read.
 * @param verbose Flag to indicate whether to print error messages. If set to a
 * non-zero value, error messages are printed to stderr.
 * @return Returns a pointer to a buffer containing the file's content if
 * successful. Returns NULL if the file cannot be opened or in case of a read
 * error.
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
