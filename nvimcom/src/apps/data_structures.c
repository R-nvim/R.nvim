#include <unistd.h> // POSIX operating system API
#include <dirent.h> // Directory entry
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "global_vars.h"
#include "utilities.h"
#include "../common.h"
#include "logging.h"
#include "data_structures.h"
#include "tcp.h"

static int building_objls;     // Flag for building compl lists
static int more_to_build;      // Flag for more lists to build
static LibPath *libpaths;      // Pointer to first library path
static size_t glbnv_buffer_sz; // Global environment buffer size
static ListStatus *listTree;   // Root node of the list status tree
static int max_depth = 2;      // Max list depth in nvimcom

void set_max_depth(int m) { max_depth = m; }

static void change_all_stt(ListStatus *root, int stt) {
    if (root != NULL) {
        // Open all but libraries
        if (!(stt == 1 && root->key[strlen(root->key) - 1] == ':'))
            root->status = stt;
        change_all_stt(root->left, stt);
        change_all_stt(root->right, stt);
    }
}

/**
 * @brief Change the status of all lists in the Object Browser.
   This function is called after the user types `<LocalLeader>r-` or
 `<LocalLeader>r=`.
 * @param stt New status (1 = open; 2 = closed).
 */
void change_all(int stt) { change_all_stt(listTree, stt); }

/**
 * @brief Copy a string, skipping consecutive spaces.
 *
 * This function takes an input string and produces an output string where
 * consecutive spaces are reduced to a single space. The output string is
 * null-terminated. The function does not modify the input string.
 *
 * @param input The input string with potential consecutive spaces.
 * @param output The output buffer where the trimmed string will be stored.
 *               This buffer should be large enough to hold the result.
 */
static void skip_consecutive_spaces(const char *input, char *output) {
    int i = 0, j = 0;
    while (input[i] != '\0') {
        output[j++] = input[i];
        if (input[i] == ' ') {
            // Skip over additional consecutive spaces
            while (input[i + 1] == ' ') {
                i++;
            }
        }
        i++;
    }
    output[j] = '\0'; // Null-terminate the output string
}

static int read_field_data(char *s, int i) {
    while (s[i]) {
        if (s[i] == '\n' && s[i + 1] == ' ') {
            s[i] = ' ';
            i++;
            while (s[i] == ' ')
                i++;
        }
        if (s[i] == '\n') {
            s[i] = 0;
            break;
        }
        i++;
    }
    return i;
}

/**
 * @brief Parses the DESCRIPTION file of an R package to extract metadata.
 *
 * This function reads the DESCRIPTION file of an R package and extracts key
 * metadata, including the Title and Description fields. It is used to provide
 * more detailed information about R packages in the Neovim environment,
 * particularly for features like auto-completion and package management within
 * the R.nvim plugin. The parsed information is used to update the data
 * structures that represent installed R libraries.
 *
 * @param descr Pointer to a string containing the contents of a DESCRIPTION
 * file.
 * @param fnm The name of the R package whose DESCRIPTION file is being parsed.
 */
static void parse_descr(char *descr, const char *fnm) {
    int i = 0;
    int dlen = strlen(descr);
    char *title, *description;
    title = NULL;
    description = NULL;
    InstLibs *lib, *ptr, *prev;
    while (i < dlen) {
        if ((i == 0 || descr[i - 1] == '\n' || descr[i - 1] == 0) &&
            str_here(descr + i, "Title: ")) {
            i += 7;
            title = descr + i;
            i = read_field_data(descr, i);
            descr[i] = 0;
        }
        if ((i == 0 || descr[i - 1] == '\n' || descr[i - 1] == 0) &&
            str_here(descr + i, "Description: ")) {
            i += 13;
            description = descr + i;
            i = read_field_data(descr, i);
            descr[i] = 0;
        }
        i++;
    }
    if (title && description) {
        if (instlibs == NULL) {
            instlibs = calloc(1, sizeof(InstLibs));
            lib = instlibs;
        } else {
            lib = calloc(1, sizeof(InstLibs));
            if (ascii_ic_cmp(instlibs->name, fnm) > 0) {
                lib->next = instlibs;
                instlibs = lib;
            } else {
                ptr = instlibs;
                prev = NULL;
                while (ptr && ascii_ic_cmp(fnm, ptr->name) > 0) {
                    prev = ptr;
                    ptr = ptr->next;
                }
                if (prev)
                    prev->next = lib;
                lib->next = ptr;
            }
        }
        lib->name = calloc(strlen(fnm) + 1, sizeof(char));
        strcpy(lib->name, fnm);
        lib->title = calloc(strlen(title) + 1, sizeof(char));
        skip_consecutive_spaces(title, lib->title);
        lib->descr = calloc(strlen(description) + 1, sizeof(char));
        lib->si = 1;
        if (lib->descr != NULL) {
            skip_consecutive_spaces(description, lib->descr);
        }
        replace_char(lib->title, '\'', '\x13');
        replace_char(lib->descr, '\'', '\x13');
    } else {
        if (title)
            fprintf(stderr, "Failed to get Description from %s. ", fnm);
        else
            fprintf(stderr, "Failed to get Title from %s. ", fnm);
        fflush(stderr);
    }
}

/**
 * @brief Update the list of installed libraries.
 * This function is called on rnvimserver startup and before completion of
 * library names.
 */
void update_inst_libs(void) {
    Log("update_inst_libs()");
    DIR *d;
    struct dirent *dir;
    char fname[512];
    char *descr;
    InstLibs *il;
    int r;
    int n = 0;

    LibPath *lp = libpaths;
    while (lp) {
        d = opendir(lp->path);
        if (d) {
            while ((dir = readdir(d)) != NULL) {
#ifdef _DIRENT_HAVE_D_TYPE
                if (dir->d_name[0] != '.' && dir->d_type == DT_DIR)
#else
                if (dir->d_name[0] != '.')
#endif
                {
                    il = instlibs;
                    r = 0;
                    while (il) {
                        if (strcmp(il->name, dir->d_name) == 0) {
                            il->si = 1;
                            r = 1; // Repeated library
                            break;
                        }
                        il = il->next;
                    }
                    if (r)
                        continue;

                    snprintf(fname, 511, "%s/%s/DESCRIPTION", lp->path,
                             dir->d_name);
                    descr = read_file(fname, 0);
                    if (descr) {
                        n++;
                        parse_descr(descr, dir->d_name);
                        free(descr);
                    }
                }
            }
            closedir(d);
        }
        lp = lp->next;
    }
    Log("%d new libs found", n);

    // New libraries found. Overwrite ~/.cache/R.nvim/inst_libs
    if (n) {
        char fname[1032];
        snprintf(fname, 1031, "%s/inst_libs", compldir);
        FILE *f = fopen(fname, "w");
        if (f == NULL) {
            fprintf(stderr, "Could not write to '%s'\n", fname);
            fflush(stderr);
        } else {
            il = instlibs;
            while (il) {
                if (il->si)
                    fprintf(f, "%s\006%s\006%s\n", il->name, il->title,
                            il->descr);
                il = il->next;
            }
            fclose(f);
        }
    }
}

static void pkg_delete(PkgData *pd) {
    free(pd->name);
    free(pd->version);
    free(pd->fname);
    if (pd->descr)
        free(pd->descr);
    if (pd->objls)
        free(pd->objls);
    if (pd->args)
        free(pd->args);
    if (pd->alias)
        free(pd->alias);
    free(pd);
}

static PkgData *get_pkg(const char *nm) {
    if (!pkgList)
        return NULL;

    PkgData *pd = pkgList;
    do {
        if (strcmp(pd->name, nm) == 0)
            return pd;
        pd = pd->next;
    } while (pd);

    return NULL;
}

static char *get_pkg_descr(const char *pkgnm) {
    Log("get_pkg_descr(%s)", pkgnm);
    InstLibs *il = instlibs;
    while (il) {
        if (strcmp(il->name, pkgnm) == 0) {
            char *s = malloc((strlen(il->title) + 1) * sizeof(char));
            strcpy(s, il->title);
            return s;
        }
        il = il->next;
    }
    return NULL;
}

static PkgData *new_pkg_data(const char *nm, const char *vrsn) {
    char buf[1024];

    PkgData *pd = calloc(1, sizeof(PkgData));
    pd->name = malloc((strlen(nm) + 1) * sizeof(char));
    strcpy(pd->name, nm);
    pd->version = malloc((strlen(vrsn) + 1) * sizeof(char));
    strcpy(pd->version, vrsn);
    pd->descr = get_pkg_descr(pd->name);
    pd->loaded = 1;

    snprintf(buf, 1023, "%s/objls_%s_%s", compldir, nm, vrsn);
    pd->fname = malloc((strlen(buf) + 1) * sizeof(char));
    strcpy(pd->fname, buf);

    // Check if objls_ exist
    pd->built = 1;
    if (access(buf, F_OK) != 0) {
        pd->built = 0;
    }
    return pd;
}

static void add_pkg(const char *nm, const char *vrsn) {
    PkgData *tmp = pkgList;
    pkgList = new_pkg_data(nm, vrsn);
    pkgList->next = tmp;
}

void update_pkg_list(char *libnms) {
    Log("update_pkg_list()");
    char buf[512];
    char *s, *nm, *vrsn;
    PkgData *pkg;

    // Consider that all packages were unloaded
    pkg = pkgList;
    while (pkg) {
        pkg->loaded = 0;
        pkg = pkg->next;
    }

    if (libnms) {
        // called by nvimcom
        Log("update_pkg_list != NULL");
        while (*libnms) {
            nm = libnms;
            while (*libnms != '\003')
                libnms++;
            *libnms = 0;
            libnms++;
            vrsn = libnms;
            while (*libnms != '\004')
                libnms++;
            *libnms = 0;
            libnms++;
            if (*libnms == '\n') // this was the last package
                libnms++;

            if (strstr(nm, " ") || strstr(vrsn, " ")) {
                break;
            }

            pkg = get_pkg(nm);
            if (pkg)
                pkg->loaded = 1;
            else
                add_pkg(nm, vrsn);
        }
    } else {
        // Called during the initialization with libnames_ created by
        // R/before_rns.R to enable completion for functions loaded with the
        // `library()` and `require()` commands in the file being edited.
        char lbnm[128];
        Log("update_pkg_list == NULL");

        snprintf(buf, 511, "%s/libnames_%s", tmpdir, getenv("RNVIM_ID"));
        FILE *flib = fopen(buf, "r");
        if (!flib) {
            fprintf(stderr, "Failed to open \"%s\"\n", buf);
            fflush(stderr);
            return;
        }

        while ((s = fgets(lbnm, 127, flib))) {
            while (*s != '_')
                s++;
            *s = 0;
            s++;
            vrsn = s;
            while (*s != '\n')
                s++;
            *s = 0;

            pkg = get_pkg(lbnm);
            if (pkg)
                pkg->loaded = 1;
            else
                add_pkg(lbnm, vrsn);
        }
        fclose(flib);
    }

    // No command run yet
    if (!pkgList)
        return;

    // Delete data from unloaded packages to ensure that reloaded packages go
    // to the bottom of the Object Browser list
    pkg = pkgList;
    if (pkg->loaded == 0) {
        pkgList = pkg->next;
        pkg_delete(pkg);
    } else {
        PkgData *prev = pkg;
        pkg = pkg->next;
        while (pkg) {
            if (pkg->loaded == 0) {
                prev->next = pkg->next;
                pkg_delete(pkg);
                pkg = prev->next;
            } else {
                prev = pkg;
                pkg = prev->next;
            }
        }
    }
}

/**
 * @brief Count the number of separator characters in a given buffer.
 *
 * This function scans a buffer and counts the number of occurrences of
 * the separator character '\006'. It is primarily used to parse and validate
 * data structure representations received from R. The function also checks if
 * the size of the buffer is 1, indicating an empty package with no exported
 * objects. In case of an unexpected number of separators, it logs an error,
 * frees the buffer, and returns NULL.
 *
 * @param b1 Pointer to the buffer to be scanned.
 * @param size Pointer to an integer where the size of the buffer will be
 * stored.
 * @return Returns the original buffer if the count of separators is as
 * expected. Returns NULL in case of an error or if the count is not as
 * expected.
 */
static char *count_sep(char *b1, int *size) {
    *size = strlen(b1);
    // Some packages do not export any objects.
    if (*size == 1)
        return b1;

    char *s0 = b1;
    char *s1 = b1;
    int n = 0;
    while (*s1) {
        if (*s1 == '\006')
            n++;
        if (*s1 == '\n') {
            if (n == 7) {
                n = 0;
                s0 = s1;
                s0++;
            } else {
                char b[64];
                strncpy(b, s0, 63);
                fprintf(stderr, "Number of separators: %d (%s)\n", n, b);
                fflush(stderr);
                free(b1);
                *size = 0;
                return NULL;
            }
        }
        s1++;
    }
    return b1;
}

/**
 * @brief Validates and prepares the buffer containing completion data.
 *
 * This function processes a buffer that is expected to contain data for auto
 * completion, ensuring that there are exactly 7 '\006' separators between
 * newline characters. It modifies the buffer in place, replacing certain
 * control characters with their corresponding representations and ensuring the
 * data is correctly formatted for subsequent processing. The function is part
 * of the handling for auto completion data in the R.nvim plugin, facilitating
 * the communication and data exchange between Neovim and R.
 *
 * @param buffer Pointer to the buffer containing auto completion data.
 * @param size Pointer to an integer representing the size of the buffer.
 * @return Returns a pointer to the processed buffer if the validation is
 * successful. Returns NULL if the buffer does not meet the expected format or
 * validation fails.
 */
static char *check_omils_buffer(char *buffer, int *size) {
    // Ensure that there are exactly 7 \006 between new line characters
    buffer = count_sep(buffer, size);

    if (!buffer)
        return NULL;

    if (buffer) {
        char *p = buffer;
        while (*p) {
            if (*p == '\006')
                *p = 0;
            // if (*p == '\'')
            //     *p = '\x13';
            p++;
        }
    }
    return buffer;
}

/**
 * @brief Updates the buffer containing the global environment data from R.
 *
 * This function is responsible for updating the global environment buffer
 * with new data received from R. It ensures the buffer is appropriately sized
 * and formatted for further processing. The global environment buffer contains
 * data about the R global environment, such as variables and functions, which
 * are used for features like auto-completion in Neovim. The function also
 * triggers a refresh of related UI components if necessary.
 *
 * @param g A string containing the new global environment data.
 */
void update_glblenv_buffer(char *g) {
    Log("update_glblenv_buffer()");
    int glbnv_size = strlen(g);

    if (glbnv_buffer) {
        if ((glbnv_size + 2) > glbnv_buffer_sz) {
            free(glbnv_buffer);
            glbnv_buffer_sz = glbnv_size + 4096;
            glbnv_buffer = calloc(glbnv_buffer_sz, sizeof(char));
        }
    } else {
        glbnv_buffer_sz = glbnv_size + 4096;
        glbnv_buffer = calloc(glbnv_buffer_sz, sizeof(char));
    }

    memcpy(glbnv_buffer, g, glbnv_size);
    glbnv_buffer[glbnv_size] = 0;

    if (check_omils_buffer(glbnv_buffer, &glbnv_size) == NULL) {
        glbnv_buffer_sz = 0;
        glbnv_buffer = NULL;
        return;
    }
}

static ListStatus *search(ListStatus *root, const char *s) {
    ListStatus *node = root;
    int cmp = strcmp(node->key, s);
    while (node && cmp != 0) {
        if (cmp > 0)
            node = node->right;
        else
            node = node->left;
        if (node)
            cmp = strcmp(node->key, s);
    }
    if (cmp == 0)
        return node;
    else
        return NULL;
}

static ListStatus *new_ListStatus(const char *s, int stt) {
    ListStatus *p;
    p = calloc(1, sizeof(ListStatus));
    p->key = malloc((strlen(s) + 1) * sizeof(char));
    strcpy(p->key, s);
    p->status = stt;
    return p;
}

static ListStatus *insert(ListStatus *root, const char *s, int stt) {
    if (!root)
        return new_ListStatus(s, stt);
    int cmp = strcmp(root->key, s);
    if (cmp > 0)
        root->right = insert(root->right, s, stt);
    else
        root->left = insert(root->left, s, stt);
    return root;
}

/**
 * @brief Get a list status (open or closed) in the Object Browser.
 *
 * @param s List name.
 * @param stt Initial status if the list isn't inserted yet.
 * @return The current status of the list.
 */
int get_list_status(const char *s, int stt) {
    ListStatus *p = search(listTree, s);
    if (p)
        return p->status;
    insert(listTree, s, stt);
    return stt;
}

/**
 * Description:
 * @param s:
 */
void toggle_list_status(char *s) {
    ListStatus *p = search(listTree, s);
    if (p) {

        // Count list levels
        char *t = s;
        int n = 0;
        while (*t) {
            if (*t == '$' || *t == '@')
                n++;
            t++;
        }
        // Check if the value of max_depth is high enough
        if (p->status == 0 && n >= max_depth) {
            max_depth++;
            char b[16];
            snprintf(b, 15, "D%d", n + 1);
            send_to_nvimcom(b);
        }

        p->status = !p->status;
    }
}

/**
 * @brief Reads the contents of an auto completion list file into a buffer.
 *
 * This function opens and reads the specified auto completion file (typically
 * named 'objls_'). It allocates memory for the buffer and loads the file
 * contents into it. The buffer is used to store completion items (like function
 * names and variables) available in R packages for use in auto completion in
 * Neovim. If the file is empty, it indicates that no completion items are
 * available or the file is yet to be populated.
 *
 * @param fn The name of the file to be read.
 * @param size A pointer to an integer where the size of the read data will be
 * stored.
 * @return Returns a pointer to a buffer containing the file contents if
 * successful. Returns NULL if the file cannot be opened, is empty, or in case
 * of a read error.
 */
static char *read_objls_file(const char *fn, int *size) {
    char *buffer = read_file(fn, 1);
    if (!buffer)
        return NULL;

    return check_omils_buffer(buffer, size);
}

static char *read_alias_file(const char *nm) {
    char fnm[512];
    snprintf(fnm, 511, "%s/alias_%s", compldir, nm);
    char *buffer = read_file(fnm, 1);
    if (!buffer)
        return NULL;
    char *p = buffer;
    while (*p) {
        if (*p == '\x09')
            *p = 0;
        p++;
    }
    return buffer;
}

static char *read_args_file(const char *nm) {
    char fnm[512];
    snprintf(fnm, 511, "%s/args_%s", compldir, nm);
    char *buffer = read_file(fnm, 1);
    if (!buffer)
        return NULL;
    char *p = buffer;
    while (*p) {
        if (*p == '\006')
            *p = 0;
        p++;
    }
    return buffer;
}

static void load_pkg_data(PkgData *pd) {
    int size;
    if (!pd->descr)
        pd->descr = get_pkg_descr(pd->name);
    pd->alias = read_alias_file(pd->name);
    pd->args = read_args_file(pd->name);
    if (!pd->objls) {
        pd->nobjs = 0;
        pd->objls = read_objls_file(pd->fname, &size);
        if (size > 2)
            for (int i = 0; i < size; i++)
                if (pd->objls[i] == '\n')
                    pd->nobjs++;
    }
}

// Send to R.nvim the command to read the list of libraries loaded in R
void build_objls(void) {
    Log("build_objls()");
    unsigned long nsz;

    if (building_objls) {
        more_to_build = 1;
        return;
    }
    building_objls = 1;

    memset(compl_buffer, 0, compl_buffer_size);
    char *p = compl_buffer;

    PkgData *pkg = pkgList;

    // It would be easier to call R once for each library, but we will build
    // all cache files at once to avoid the cost of starting R many times.
    int k = 0;
    while (pkg) {
        if (pkg->to_build == 0) {
            nsz = strlen(pkg->name) + 1024 + (p - compl_buffer);
            if (compl_buffer_size < nsz)
                p = grow_buffer(&compl_buffer, &compl_buffer_size,
                                nsz - compl_buffer_size + 32768);
            p = str_cat(p, "'");
            p = str_cat(p, pkg->name);
            p = str_cat(p, "', ");
            pkg->to_build = 1;
            k++;
        }
        pkg = pkg->next;
    }

    if (k > 0) {
        // Build all the objls_ files.
        printf("lua require('r.server').build_objls({%s})\n", compl_buffer);
        fflush(stdout);
    }
}

// Called asynchronously and only if an objls_ file was actually built.
static void finish_bol(void) {
    Log("finish_bol()");

    char buf[1024];

    // Don't check the return value of run_R_code because some packages might
    // have been successfully built before R exiting with status > 0.

    // Check if all files were really built before trying to load them.
    PkgData *pkg = pkgList;
    while (pkg) {
        if (pkg->built == 0 && access(pkg->fname, F_OK) == 0)
            pkg->built = 1;
        if (pkg->built && !pkg->objls)
            load_pkg_data(pkg);
        pkg = pkg->next;
    }

    // Finally create a list of built objls_ because libnames_ might have
    // already changed and R.nvim would try to read objls_ files not built yet.
    snprintf(buf, 511, "%s/libs_in_rns_%s", localtmpdir, getenv("RNVIM_ID"));
    FILE *f = fopen(buf, "w");
    if (f) {
        PkgData *pkg = pkgList;
        while (pkg) {
            if (pkg->loaded && pkg->built && pkg->objls)
                fprintf(f, "%s_%s\n", pkg->name, pkg->version);
            pkg = pkg->next;
        }
        fclose(f);
    }

    // Message to Neovim: Update both syntax and Rhelp_list
    printf("lua require('r.server').update_Rhelp_list()\n");
    fflush(stdout);
}

// This function is called by lua/r/server.lua when R finishes building
// the completion data files.
void finished_building_objls(void) {
    finish_bol();
    building_objls = 0;

    // If this function was called while it was running, build the remaining
    // cache files before saving the list of libraries whose cache files were
    // built.
    if (more_to_build) {
        more_to_build = 0;
        build_objls();
    }
}

static void fill_inst_libs(void) {
    Log("fill_inst_libs");
    InstLibs *il = NULL;
    char fname[1032];
    snprintf(fname, 1031, "%s/inst_libs", compldir);
    char *b = read_file(fname, 0);
    if (!b)
        return;
    char *s = b;
    char *n, *t, *d;
    while (*s) {
        n = s;
        t = NULL;
        d = NULL;
        while (*s && *s != '\006')
            s++;
        if (*s && *s == '\006') {
            *s = 0;
            s++;
            if (*s) {
                t = s;
                while (*s && *s != '\006')
                    s++;
                if (*s && *s == '\006') {
                    *s = 0;
                    s++;
                    if (*s) {
                        d = s;
                        while (*s && *s != '\n')
                            s++;
                        if (*s && *s == '\n') {
                            *s = 0;
                            s++;
                        } else
                            break;
                    } else
                        break;
                } else
                    break;
            }
            if (d) {
                if (il) {
                    il->next = calloc(1, sizeof(InstLibs));
                    il = il->next;
                } else {
                    il = calloc(1, sizeof(InstLibs));
                }
                if (instlibs == NULL)
                    instlibs = il;
                il->name = malloc((strlen(n) + 1) * sizeof(char));
                strcpy(il->name, n);
                il->title = malloc((strlen(t) + 1) * sizeof(char));
                strcpy(il->title, t);
                il->descr = malloc((strlen(d) + 1) * sizeof(char));
                strcpy(il->descr, d);
            }
        }
    }
    free(b);
}

void init_ds_vars(void) {
    char fname[512];
    snprintf(fname, 511, "%s/libPaths", tmpdir);
    char *b = read_file(fname, 1);
#ifdef WIN32
    for (int i = 0; i < strlen(b); i++)
        if (b[i] == '\\')
            b[i] = '/';
#endif
    if (b) {
        libpaths = calloc(1, sizeof(LibPath));
        libpaths->path = b;
        LibPath *p = libpaths;
        while (*b) {
            if (*b == '\n') {
                while (*b == '\n' || *b == '\r') {
                    *b = 0;
                    b++;
                }
                if (*b) {
                    p->next = calloc(1, sizeof(LibPath));
                    p = p->next;
                    p->path = b;
                } else {
                    break;
                }
            }
            b++;
        }
    }

    // Fill immediately the list of installed libraries. Each entry still has
    // to be confirmed by listing the directories in .libPaths.
    fill_inst_libs();

    // List tree sentinel
    listTree = new_ListStatus("base:", 0);
}
