#include <stdio.h>  // Standard input/output definitions
#include <stdlib.h> // Standard library
#include <string.h> // String handling functions

#include "logging.h"
#include "global_vars.h"
#include "utilities.h"
#include "../common.h"
#include "complete.h"
#include "lsp.h"

// The kind numbers are from vim.lsp.protocol.CompletionItemKind
static const char *kind_tbl[16][2] = {
    {"a", "6"},  //  function arg      Variable
    {"c", "5"},  //  data.frame column Field
    {"n", "12"}, //  numeric           Value
    {"f", "5"},  //  factor            Field
    {"t", "1"},  //  character         Text
    {"F", "3"},  //  function          Function
    {"d", "22"}, //  data.frame        Struct
    {"l", "22"}, //  list              Struct
    {"4", "7"},  //  S4                Class
    {"7", "7"},  //  S7                Class
    {"b", "2"},  //  logical           Method
    {"L", "9"},  //  library           Module
    {"C", "4"},  //  control           Constructor
    {"e", "8"},  //  environment       Interface
    {"p", "23"}, //  promise           Event
    {"o", "25"}, //  other             TypeParameter
};

static const char *get_kind(const char *cls) {
    for (size_t i = 0; i < 16; i++)
        if (*kind_tbl[i][0] == *cls)
            return kind_tbl[i][1];
    Log("get_kind: %s", cls);
    return kind_tbl[15][1];
}

/**
 * Checks if the string `b` can be found through string `a`.
 * @param a The string to be checked.
 * @param b The substring to look for at the start of `a`.
 * @return 1 if `b` can be found through `a`, 0 otherwise.
 */
static int fuzzy_find(const char *a, const char *b) {
    int i = 0;
    int j = 0;
    while (a[i] && b[j]) {
        while (a[i] && a[i] != b[j])
            i++;
        if (b[j] == '$' || b[j] == '@') {
            for (int k = 0; k <= j; k++)
                if (a[k] != b[k])
                    return 0;
        }
        if (a[i])
            i++;
        j++;
    }
    return b[j] == '\0';
}

static int count_twice(const char *b1, const char *b2, const char ch) {
    int n1 = 0;
    int n2 = 0;
    for (unsigned long i = 0; i < strlen(b1); i++)
        if (b1[i] == ch)
            n1++;
    for (unsigned long i = 0; i < strlen(b2); i++)
        if (b2[i] == ch)
            n2++;
    return n1 == n2;
}

static char *find_obj(char *objls, const char *dfbase) {
    while (*objls != 0) {
        if (str_here(objls, dfbase)) {
            return objls;
        } else {
            while (*objls != '\n')
                objls++;
            objls++;
        }
    }
    return NULL;
}

static char *get_df_cols(const char *dtfrm, const char *base, char *p) {
    size_t skip = strlen(dtfrm) + 1; // The data.frame name + "$"
    char dfbase[64];
    snprintf(dfbase, 63, "%s$%s", dtfrm, base);
    const char *s = NULL;

    if (glbnv_buffer)
        s = find_obj(glbnv_buffer, dfbase);

    if (!s) {
        PkgData *pd = pkgList;
        while (pd) {
            if (pd->objls) {
                s = find_obj(pd->objls, dfbase);
                if (s)
                    break;
            }
            pd = pd->next;
        }
    }

    if (!s)
        return p;

    while (*s && str_here(s, dfbase)) {
        // Avoid buffer overflow if the information is bigger than
        // compl_buffer.
        unsigned long nsz = strlen(s) + 1024 + (p - compl_buffer);
        if (compl_buffer_size < nsz)
            p = grow_buffer(&compl_buffer, &compl_buffer_size,
                            nsz - compl_buffer_size + 32768);

        p = str_cat(p, "{\"label\":\"");
        p = str_cat(p, s + skip);
        p = str_cat(p, "\",\"sortText\":\"_");
        p = str_cat(p, s + skip);
        p = str_cat(p, "\",\"cls\":\"c\",\"kind\":5,\"env\":\"");
        p = str_cat(p, dtfrm);
        p = str_cat(p, "\"},");

        while (*s != '\n')
            s++;
        s++;
    }
    return p;
}

// Return the menu items for auto completion, but don't include function
// usage, and tittle and description of objects to avoid extremely large data
// transfer.
static char *parse_objls(const char *s, const char *base, const char *pkg,
                         const char *lib, char *p) {
    int i;
    unsigned long nsz;
    const char *f[7];

    while (*s != 0) {
        if (fuzzy_find(s, base)) {
            i = 0;
            while (i < 7) {
                f[i] = s;
                i++;
                while (*s != 0)
                    s++;
                s++;
            }
            while (*s != '\n' && *s != 0)
                s++;
            if (*s == '\n')
                s++;

            // Skip elements of lists unless the user is really looking for
            // them, and skip lists if the user is looking for one of its
            // elements.
            if (!count_twice(base, f[0], '@'))
                continue;
            if (!count_twice(base, f[0], '$'))
                continue;
            if (!count_twice(base, f[0], '['))
                continue;

            // Avoid buffer overflow if the information is bigger than
            // compl_buffer.
            nsz = 1024 + (p - compl_buffer);
            if (compl_buffer_size < nsz)
                p = grow_buffer(&compl_buffer, &compl_buffer_size,
                                nsz - compl_buffer_size + 32768);

            p = str_cat(p, "{\"label\":\"");
            if (pkg) {
                p = str_cat(p, pkg);
                p = str_cat(p, "::");
            }
            p = str_cat(p, f[0]);
            p = str_cat(p, "\",\"sortText\":\"");
            if (pkg) {
                p = str_cat(p, pkg);
                p = str_cat(p, "::");
            }
            p = str_cat(p, f[0]);
            p = str_cat(p, "\",\"cls\":\"");
            p = str_cat(p, f[1]);
            p = str_cat(p, "\",\"kind\":");
            p = str_cat(p, get_kind(f[1]));
            if (lib) {
                p = str_cat(p, ",\"env\":\"");
                p = str_cat(p, lib);
            }
            p = str_cat(p, "\"},");
            // big data will be truncated.
        } else {
            while (*s != '\n')
                s++;
            s++;
        }
    }
    return p;
}

/*
 * @desc:
 * @param p:
 * @param funcnm:
 * */
char *complete_args(char *p, char *funcnm) {
    // Check if function is "pkg::fun"
    char *pkg = NULL;
    if (strstr(funcnm, "::")) {
        pkg = funcnm;
        funcnm = strstr(funcnm, "::");
        *funcnm = 0;
        funcnm++;
        funcnm++;
    }

    PkgData *pd = pkgList;
    char a[64];
    int i;
    while (pd) {
        if (pd->objls && (pkg == NULL || (strcmp(pd->name, pkg) == 0))) {
            const char *s = pd->objls;
            while (*s != 0) {
                if (strcmp(s, funcnm) == 0) {
                    while (*s)
                        s++;
                    s++;
                    if (*s == 'F') { // Check if it's a function
                        i = 3;
                        while (i) {
                            s++;
                            if (*s == 0)
                                i--;
                        }
                        s++;
                        while (*s) {
                            i = 0;
                            p = str_cat(p, "{\"label\":\"");
                            while (*s != '\x05' && *s != '\x04' && i < 63) {
                                a[i] = *s;
                                i++;
                                s++;
                            }
                            a[i] = 0;
                            p = str_cat(p, a);
                            p = str_cat(p, " =\",\"sortText\":\"_");
                            p = str_cat(p, a);
                            p = str_cat(
                                p, "\",\"cls\":\"a\",\"kind\":6,\"env\":\"");
                            p = str_cat(p, pd->name);
                            p = str_cat(p, ":");
                            p = str_cat(p, funcnm);
                            p = str_cat(p, "\"},");
                            s++;
                        }
                        break;
                    } else {
                        while (*s != '\n')
                            s++;
                        s++;
                    }
                } else {
                    while (*s != '\n')
                        s++;
                    s++;
                }
            }
        }
        pd = pd->next;
    }
    return p;
}

// Read the DESCRIPTION of all installed libraries
static void complete_instlibs(char *p, const char *base) {
    update_inst_libs();

    Log("instlibs = %p", (void *)instlibs);
    if (!instlibs)
        return;

    InstLibs *il;

    il = instlibs;
    while (il) {
        unsigned long len = strlen(il->descr) + (p - compl_buffer) + 1024;
        if (compl_buffer_size < len)
            p = grow_buffer(&compl_buffer, &compl_buffer_size,
                            len - compl_buffer_size + 32768);

        if (!base || (str_here(il->name, base) && il->si)) {
            p = str_cat(p, "{\"label\":\"");
            p = str_cat(p, il->name);
            p = str_cat(p, "\",\"cls\":\"L\",\"kind\":9},");
        }
        il = il->next;
    }
}

void complete(const char *params) {
    Log("complete: %s", params);
    char *id = strstr(params, "\"orig_id\":");
    char *base = strstr(params, "\"base\":\"");
    char *fnm = strstr(params, "\"fnm\":\"");
    char *df = strstr(params, "\"df\":\"");
    char *fargs = strstr(params, "\"fargs\":\"");
    cut_json_int(&id, 10);
    cut_json_str(&base, 8);
    cut_json_str(&fnm, 7);
    cut_json_str(&df, 6);
    cut_json_str(&fargs, 9);
    if (base && *base == ' ')
        base = NULL;

    Log("complete(%s, %s, %s, %s, %s)", id, base, fnm, df, fargs);

    char *p;
    memset(compl_buffer, 0, compl_buffer_size);
    p = compl_buffer;

    // Get menu completion for installed libraries
    if (fnm && *fnm == '#') {
        complete_instlibs(p, base);
        send_menu_items(compl_buffer, id);
        return;
    }

    if (fargs || fnm) {
        if (fargs) {
            replace_char(fargs, '\x13', '"');
            // Insert arguments of .GlobalEnv function
            p = str_cat(p, fargs);
        } else if (fnm) {
            // Completion of arguments of a library's function
            p = complete_args(p, fnm);

            // Add columns of a data.frame
            if (df) {
                p = get_df_cols(df, base, p);
            }
        }

        // base will be empty if completing only function arguments
        if (!base) {
            send_menu_items(compl_buffer, id);
            return;
        }
    }

    // Finish filling the compl_buffer
    if (glbnv_buffer && base)
        p = parse_objls(glbnv_buffer, base, NULL, ".GlobalEnv", p);

    if (base) {
        PkgData *pd = pkgList;
        // Check if base is "pkg::fun"
        char *pkg = NULL;
        if (strstr(base, "::")) {
            pkg = base;
            base = strstr(base, "::");
            *base = 0;
            base++;
            base++;
        }
        while (pd) {
            if (pd->objls && (pkg == NULL || (strcmp(pd->name, pkg) == 0)))
                p = parse_objls(pd->objls, base, pkg, pd->name, p);
            pd = pd->next;
        }
    }
    send_menu_items(compl_buffer, id);
}

void complete_fig_tbl(const char *params) {
    Log("complete_fig_tbl: %s", params);

    char *id = strstr(params, "\"orig_id\":");
    char *items = strstr(params, "\"items\":[{") + 9;

    cut_json_int(&id, 10);
    char *end_items = strstr(items, "}],");
    if (end_items) {
        end_items++;
    } else {
        end_items = strstr(items, "]}");
    }
    if (!end_items)
        return;
    *end_items = '\0';
    send_menu_items(items, id);
}
