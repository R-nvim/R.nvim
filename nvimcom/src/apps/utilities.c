#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "utilities.h"
#include "logging.h"

/**
 * Grows a buffer to a new size.
 * @param b Pointer to the buffer.
 * @param sz Size of the buffer.
 * @param inc Amount to increase.
 * @return Pointer to the resized buffer.
 */
char *grow_buffer(char **b, size_t *sz, size_t inc) {
    Log("\x1b[31mgrow_buffer\x1b[0m: %zu, %zu", *sz, inc);
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

// Advance the pointer to the value and NULL terminate the string
void cut_json_int(char **str, unsigned len) {
    if (*str == NULL)
        return;
    char *p = *str + len;
    *str = p;
    while (*p >= '0' && *p <= '9')
        p++;
    *p = '\0';
}

// Advance the pointer to the value and NULL terminate the string
void cut_json_str(char **str, unsigned len) {
    if (*str == NULL)
        return;
    char *p = *str + len;
    *str = p;
    while (*p != '"')
        p++;
    *p = '\0';
}

// Advance the pointer to the opening bracket and NULL terminate the string
// after the closing bracket
void cut_json_bkt(char **str, unsigned len) {
    char *p = *str + len;
    *str = p;
    size_t j = 1;
    int n_braces = 1;
    while (n_braces > 0 && p[j]) {
        if (p[j] == '{')
            n_braces++;
        else if (p[j] == '}')
            n_braces--;
        j++;
    }
    p[j] = '\0';
}

char *seek_word(char *objls, const char *wrd) {
    char *s = objls;
    while (*s != 0) {
        if (strcmp(s, wrd) == 0) {
            return s;
        }
        while (*s != '\n')
            s++;
        s++;
    }
    return NULL;
}

/**
 * Checks if the string `b` can be found through string `a`.
 * @param a The string to be checked.
 * @param b The substring to look for at the start of `a`.
 * @return 1 if `b` can be found through `a`, 0 otherwise.
 */
int fuzzy_find(const char *a, const char *b) {
    int i = 0;
    int j = 0;
    while (a[i] && b[j]) {
        if (a[i] == b[j]) {
            if (b[j] == '$' || b[j] == '@') {
                for (int k = 0; k <= j; k++)
                    if (a[k] != b[k])
                        return 0;
            }
            i++;
            j++;
        } else {
            while (a[i] && a[i] != b[j])
                i++;
        }
    }
    if (b[j] == '\0')
        return i;
    else
        return 0;
}

int is_function(const char *obj) {
    while (*obj)
        obj++;
    obj++;
    if (*obj == 'F') {
        return 1;
    } else {
        return 0;
    }
}
