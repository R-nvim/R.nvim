#include <unistd.h> // POSIX operating system API
#include <dirent.h> // Directory entry
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "global_vars.h"
#include "utilities.h"
#include "logging.h"
#include "data_structures.h"
#include "tcp.h"
#include "lsp.h"

static size_t glbnv_buffer_sz; // Global environment buffer size
static ListStatus *listTree;   // Root node of the list status tree
static int max_depth = 2;      // Max list depth in nvimcom
static char *cmp_dir;          // Directory for completion files
static char *lib_names;        // List of loaded libraries

void set_max_depth(int m) { max_depth = m; }

/**
 * Compares two ASCII strings in a case-insensitive manner.
 * @param a First string.
 * @param b Second string.
 * @return An integer less than, equal to, or greater than zero
 *         respectively, to be less than, to match, or be greater than b.
 */
static int ascii_ic_cmp(const char *a, const char *b) {
    while (*a && *b) {
        unsigned x = (unsigned char)*a;
        unsigned y = (unsigned char)*b;
        if (x <= 'Z')
            x += 32;
        if (y <= 'Z')
            y += 32;
        int d = x - y;
        if (d != 0)
            return d;
        a++;
        b++;
    }
    return 0;
}

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

static void delete_pkg(PkgData *pd) {
    free(pd->name);
    free(pd->version);
    free(pd->fname);
    if (pd->objls)
        free(pd->objls);
    if (pd->args)
        free(pd->args);
    if (pd->title) // free title, descr and alias
        free(pd->title);
    free(pd);
}

static PkgData *get_pkg(const char *nm) {
    // Log("get_pkg: '%s'", nm);
    if (!inst_libs)
        return NULL;

    LibList *lib = inst_libs;
    do {
        if (strcmp(lib->pkg->name, nm) == 0)
            return lib->pkg;
        lib = lib->next;
    } while (lib);

    return NULL;
}

/**
 * @brief Count the number of separator characters in a given buffer.
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

    const char *s0 = b1;
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
 * @param buffer Pointer to the buffer containing auto completion data.
 * @param size Pointer to an integer representing the size of the buffer.
 * @return Returns a pointer to the processed buffer.
 */
static char *check_omils_buffer(char *b, int *size) {
    // Ensure that there are exactly 7 \006 between new line characters
    b = count_sep(b, size);

    if (!b)
        return NULL;

    char *p = b;
    while (*p) {
        if (*p == '\006')
            *p = 0;
        p++;
    }
    return b;
}

/**
 * @brief Reads the contents of an auto completion list file into a buffer.
 * @param fn The name of the file to be read.
 * @param size A pointer to an integer where the size of the read data will be
 * stored.
 * @return Returns a pointer to a buffer containing the file contents.
 */
static char *read_objls_file(const char *fn, int *size) {
    char *b = read_file(fn, 1);
    if (!b)
        return NULL;

    return check_omils_buffer(b, size);
}

static void *read_alias_file(PkgData *pd) {
    char fnm[512];
    snprintf(fnm, 511, "%s/alias_%s", cmp_dir, pd->name);
    char *b = read_file(fnm, 1);
    if (!b)
        return NULL;
    pd->title = b;
    char *p = b;
    while (*p != '\006')
        p++;
    *p = '\0';
    p++;
    pd->descr = p;
    while (*p != '\n')
        p++;
    *p = '\0';
    p++;
    pd->alias = p;
    while (*p) {
        if (*p == '\006')
            *p = 0;
        p++;
    }
    return b;
}

static char *read_args_file(const char *nm) {
    char fnm[512];
    snprintf(fnm, 511, "%s/args_%s", cmp_dir, nm);
    char *b = read_file(fnm, 1);
    if (!b)
        return NULL;
    char *p = b;
    while (*p) {
        if (*p == '\006')
            *p = 0;
        p++;
    }
    return b;
}

static void load_pkg_data(PkgData *pd) {
    // Log("load_pkg_data(%s)", pd->name);
    int size;
    read_alias_file(pd);
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

static PkgData *new_pkg_data(const char *nm, const char *vrsn) {
    char buf[1024];

    PkgData *pd = calloc(1, sizeof(PkgData));
    pd->name = malloc((strlen(nm) + 1) * sizeof(char));
    strcpy(pd->name, nm);
    pd->version = malloc((strlen(vrsn) + 1) * sizeof(char));
    strcpy(pd->version, vrsn);

    snprintf(buf, 1023, "%s/objls_%s_%s", cmp_dir, nm, vrsn);
    pd->fname = malloc((strlen(buf) + 1) * sizeof(char));
    strcpy(pd->fname, buf);

    // Check if objls_ exist
    if (access(buf, F_OK) == 0) {
        load_pkg_data(pd);
    } else {
        fprintf(stderr, "Cache file '%s' not found\n", buf);
        fflush(stderr);
    }
    return pd;
}

static void add_pkg(const char *nm, const char *vrsn) {

    LibList *tmp = calloc(1, sizeof(LibList));
    tmp->pkg = new_pkg_data(nm, vrsn);

    if (!inst_libs || ascii_ic_cmp(tmp->pkg->name, inst_libs->pkg->name) < 0) {
        Log("add_pkg: \x1b[32m%s\x1b[0m -> %s", nm,
            inst_libs ? inst_libs->pkg->name : "\x1b[31mNULL\x1b[0m");
        tmp->next = inst_libs;
        inst_libs = tmp;
        return;
    }

    LibList *cur = inst_libs;
    while (cur->next &&
           ascii_ic_cmp(cur->next->pkg->name, tmp->pkg->name) < 0) {
        cur = cur->next;
    }

    Log("add_pkg: %s -> \x1b[35m%s\x1b[0m -> %s", cur->pkg->name, nm,
        cur->next ? cur->next->pkg->name : "\x1b[31mNULL\x1b[0m");
    tmp->next = cur->next;
    cur->next = tmp;
}

void load_cached_data(void) {
    DIR *d;
    const struct dirent *dir;
    char path[512];

    d = opendir(cmp_dir);
    if (!d)
        return;

    while ((dir = readdir(d)) != NULL) {
        if (strstr(dir->d_name, "objls_")) {
            strcpy(path, dir->d_name);
            const char *nm = path + 6;
            char *vr = path + 6;
            while (*vr != '_')
                vr++;
            *vr = '\0';
            vr++;
            PkgData *pkg = get_pkg(nm);
            if (pkg && strcmp(pkg->version, vr) != 0) {
                LibList *lib = inst_libs;
                LibList *prv = NULL;
                Log("New version of '%s': %s x %s", nm, pkg->version, vr);
                while (lib) {
                    if (strcmp(lib->pkg->name, nm) == 0) {
                        if (prv) {
                            prv->next = lib->next;
                        } else {
                            inst_libs->next = lib->next;
                        }
                        delete_pkg(pkg);
                        break;
                    }
                    prv = lib;
                    lib = lib->next;
                }
                pkg = NULL;
            }
            if (!pkg)
                add_pkg(nm, vr);
        }
    }
    closedir(d);
    // merge_sort(&inst_libs);
}

static void delete_lib_list(LibList *lib) {
    LibList *next;
    while (lib) {
        next = lib->next;
        free(lib);
        lib = next;
    }
}

void finish_updating_loaded_libs(int has_new_lib) {
    Log("finish_updating_loaded_libs");

    if (has_new_lib) {
        load_cached_data();
    }

    // Consider that all packages were unloaded
    delete_lib_list(loaded_libs);
    loaded_libs = NULL;

    char *msg = calloc(128 + strlen(lib_names), sizeof(char));
    sprintf(msg, "require('r.server').update_Rhelp_list('%s')", lib_names);

    char *p = lib_names;
    while (*p && *p != '\004') {
        const char *nm = p;
        while (*p != '\003')
            p++;
        *p = 0;
        p++;
        PkgData *pkg = get_pkg(nm);
        if (pkg) {
            LibList *tmp = calloc(1, sizeof(LibList));
            tmp->pkg = pkg;
            tmp->next = loaded_libs;
            loaded_libs = tmp;
        }
    }

    // Message to Neovim: Update Rhelp_list
    p = msg;
    while (*p) {
        if (*p == '\004' || *p == '\n')
            *p = ' ';
        p++;
    }
    send_cmd_to_nvim(msg);
    free(msg);
}

void update_loaded_libs(char *libnms) {
    Log("update_loaded_libs: '%s'", libnms);
    if (lib_names)
        free(lib_names);
    lib_names = malloc(sizeof(char) * strlen(libnms) + 1);
    strcpy(lib_names, libnms);

    // Check if we already have the required cache data
    while (*libnms && *libnms != '\004') {
        const char *nm = libnms;
        while (*libnms != '\003')
            libnms++;
        *libnms = 0;
        libnms++;
        const PkgData *pkg = get_pkg(nm);
        if (!pkg) {
            send_cmd_to_nvim("require('r.server').build_cache_files()");
            return;
        }
    }
    finish_updating_loaded_libs(0);
}

/**
 * @brief Prepare to update the list of loaded libraries. If R is not started
 * yet, the libraries in R_DEFAULT_PACKAGES are considered loaded.
 *
 * @param libnms Either the list of loaded libraries send by nvimcom or NULL
 * (when the function is called by Neovim before R is started)
 */
void init_lib_list(void) {
    Log("init_lib_list()");
    char buf[512];
    snprintf(buf, 511, "%s/libnames_%s", tmpdir, getenv("RNVIM_ID"));
    char *libnms = read_file(buf, 1);
    update_loaded_libs(libnms);
    free(libnms);
}

/**
 * @brief Updates the buffer containing the global environment data from R.
 * @param g A string containing the new global environment data.
 */
void update_glblenv_buffer(const char *g) {
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

void toggle_list_status(char *s) {
    ListStatus *p = search(listTree, s);
    if (p) {

        // Count list levels
        const char *t = s;
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

void init_ds_vars(void) {
    // List tree sentinel
    listTree = new_ListStatus("base:", 0);
    cmp_dir = malloc(sizeof(char) * strlen(getenv("RNVIM_COMPLDIR")) + 1);
    strcpy(cmp_dir, getenv("RNVIM_COMPLDIR"));
}
