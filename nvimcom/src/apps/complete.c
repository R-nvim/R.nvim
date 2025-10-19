#include <stdio.h>  // Standard input/output definitions
#include <stdlib.h> // Standard library
#include <string.h> // String handling functions

#include "logging.h"
#include "global_vars.h"
#include "utilities.h"
#include "../common.h"
#include "tcp.h"
#include "complete.h"
#include "lsp.h"

const char *rhelp_menu;

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
        p = str_cat(p, "\",\"cls\":\"c\",\"env\":\"");
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
            p = str_cat(p, "\",\"cls\":\"");
            p = str_cat(p, f[1]);
            if (lib) {
                p = str_cat(p, "\",\"env\":\"");
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

void get_alias(char **pkg, char **fun) {
    char s[64];
    snprintf(s, 63, "%s\n", *fun);
    char *p;
    char *f;
    PkgData *pd = pkgList;
    if (**pkg != '#')
        while (pd && !str_here(pd->name, *pkg))
            pd = pd->next;
    while (pd) {
        if (pd->alias) {
            p = pd->alias;
            while (*p) {
                f = p;
                while (*f)
                    f++;
                f++;
                if (*f && str_here(f, s)) {
                    *pkg = pd->name;
                    *fun = p;
                    return;
                }
                p = f;
                while (*p && *p != '\n')
                    p++;
                p++;
            }
        }
        pd = pd->next;
    }
    *pkg = NULL;
}

void resolve_arg_item(char *args) {
    char *pkg = strtok(args, "|");
    char *fnm = strtok(NULL, "|");
    const char *itm = strtok(NULL, "|");
    const char *rid = strtok(NULL, "|");
    const char *knd = strtok(NULL, "|");
    Log("resolve_arg_item: %s, %s, %s, %s, %s", pkg, fnm, itm, rid, knd);
    get_alias(&pkg, &fnm);
    if (!pkg)
        return;
    PkgData *p = pkgList;
    while (p) {
        if (strcmp(p->name, pkg) == 0) {
            if (p->args) {
                char *s = p->args;
                while (*s) {
                    if (strcmp(s, fnm) == 0) {
                        while (*s)
                            s++;
                        while (*s != '\n') {
                            if (*s == 0) {
                                while (*s != '\005') {
                                    // Look for \0 or ' ' because some arguments
                                    // share the same documentation item.
                                    // Example: lm()
                                    if (*s == 0 || *s == ' ') {
                                        s++;
                                        if (str_here(s, itm)) {
                                            s += strlen(itm);
                                            if (*s == '\005' || *s == ',') {
                                                while (*s && *s != '\005')
                                                    s++;
                                                s++;
                                                char *b = calloc(strlen(s) + 2,
                                                                 sizeof(char));
                                                format(s, b, ' ', '\x14');
                                                send_item_doc(b, rid, itm, knd);
                                                free(b);
                                                return;
                                            }
                                        }
                                    }
                                    s++;
                                }
                            }
                            s++;
                        }
                        return;
                    } else {
                        while (*s != '\n')
                            s++;
                        s++;
                    }
                }
            }
            break;
        }
        p = p->next;
    }
}

/*
 * TODO: Candidate for completion_services.c
 *
 * @desc: Return user_data of a specific item with function usage, title and
 * description to be displayed in the float window
 * @param wrd:
 * @param pkg:
 * */
void resolve(char *args) {
    const char *wrd = strtok(args, "|");
    const char *pkg = strtok(NULL, "|");
    const char *rid = strtok(NULL, "|");
    const char *knd = strtok(NULL, "|");
    Log("resolve: %s, %s, %s, %s", wrd, pkg, rid, knd);
    int i;
    unsigned long nsz;
    const char *f[7];
    char *s;

    if (strcmp(pkg, ".GlobalEnv") == 0) {
        s = glbnv_buffer;
    } else {
        PkgData *pd = pkgList;
        while (pd) {
            if (strcmp(pkg, pd->name) == 0)
                break;
            else
                pd = pd->next;
        }

        if (pd == NULL)
            return;

        s = pd->objls;
    }

    memset(compl_buffer, 0, compl_buffer_size);
    char *p = compl_buffer;

    while (*s != 0) {
        if (strcmp(s, wrd) == 0) {
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

            if (f[1][0] == '(' && str_here(f[4], ">not_checked<")) {
                snprintf(compl_buffer, 1024,
                         "E%snvimcom:::nvim.GlobalEnv.fun.args(\"%s\")\n",
                         getenv("RNVIM_ID"), wrd);
                send_to_nvimcom(compl_buffer);
                return;
            }

            // Avoid buffer overflow if the information is bigger than
            // compl_buffer.
            nsz = strlen(f[4]) + strlen(f[5]) + strlen(f[6]) + 1024 +
                  (p - compl_buffer);
            if (compl_buffer_size < nsz)
                p = grow_buffer(&compl_buffer, &compl_buffer_size,
                                nsz - compl_buffer_size + 32768);

            size_t sz = strlen(f[5]) + strlen(f[6]) + 16;
            char *buffer = malloc(sz);
            p = str_cat(p, f[2]);
            p = str_cat(p, " `");
            p = str_cat(p, f[3]);
            p = str_cat(p, "::");
            p = str_cat(p, f[0]);
            p = str_cat(p, "`\x14\x14**");
            format(f[5], buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            p = str_cat(p, "**\x14\x14");
            format(f[6], buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            free(buffer);
            if (f[1][0] == '(') {
                char *b = format_usage(f[0], f[4]);
                p = str_cat(p, b);
                free(b);
            }
            send_item_doc(compl_buffer, rid, wrd, knd);
            return;
        }
        while (*s != '\n')
            s++;
        s++;
    }
}

/*
 * TODO: Candidate for completion_services.c
 *
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
                    if (*s == '(') { // Check if it's a function
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
                            p = str_cat(p, " = ");
                            if (*s == '\x04') {
                                p = str_cat(p, "\", \"def\":\"");
                                i = 0;
                                s++;
                                while (*s != '\x05' && i < 63) {
                                    a[i] = *s;
                                    i++;
                                    s++;
                                }
                                a[i] = 0;
                                p = str_cat(p, a);
                            }
                            p = str_cat(p, "\",\"cls\":\"a\",\"env\":\"");
                            p = str_cat(p, pd->name);
                            p = str_cat(p, "\x02");
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
    size_t sz = 1024;
    char *buffer = malloc(sz);

    il = instlibs;
    while (il) {
        unsigned long len = strlen(il->descr) + (p - compl_buffer) + 1024;
        if (compl_buffer_size < len)
            p = grow_buffer(&compl_buffer, &compl_buffer_size,
                            len - compl_buffer_size + 32768);

        if (str_here(il->name, base) && il->si) {
            if ((strlen(il->title) + strlen(il->descr)) > sz) {
                free(buffer);
                sz = strlen(il->title) + strlen(il->descr) + 1;
                buffer = malloc(sz);
            }

            p = str_cat(p, "{\"label\":\"");
            p = str_cat(p, il->name);
            p = str_cat(p, "\",\"cls\":\"l\",\"env\":\"**");
            format(il->title, buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            p = str_cat(p, "**\x14\x14");
            format(il->descr, buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            p = str_cat(p, "\x14\"},");
        }
        il = il->next;
    }
    free(buffer);
    // Delete the last comma
    p--;
    *p = '\0';
}

/*
 * TODO: Candidate for completion_services.c
 *
 * @desc:
 * @param id: Completion ID (integer incremented at each completion), possibily
 * used by cmp to abort outdated completion.
 * @param base: Keyword being completed.
 * @param funcnm: Function name when the keyword being completed is one of its
 * arguments.
 * @param dtfrm: Name of data.frame when the keyword being completed is an
 * argument of a function listed in either fun_data_1 or fun_data_2.
 * @param funargs Function arguments from a .GlobalEnv function.
 */
void complete(char *base, char *funcnm, char *dtfrm, char *funargs) {
    Log("complete(%s, %s, %s, %s)", base, funcnm, dtfrm, funargs);
    char *p;

    memset(compl_buffer, 0, compl_buffer_size);
    p = compl_buffer;

    // Get menu completion for installed libraries
    if (funcnm && *funcnm == '\004') {
        complete_instlibs(p, base);
        send_menu_items(compl_buffer);
        return;
    }

    if (funargs || funcnm) {
        if (funargs) {
            // Insert arguments of .GlobalEnv function
            p = str_cat(p, funargs);
        } else if (funcnm) {
            // Completion of arguments of a library's function
            p = complete_args(p, funcnm);

            // Add columns of a data.frame
            if (dtfrm) {
                p = get_df_cols(dtfrm, base, p);
            }
        }

        // base will be empty if completing only function arguments
        if (base[0] == 0) {
            p--;
            *p = '\0';
            send_menu_items(compl_buffer);
            return;
        }
    }

    // Finish filling the compl_buffer
    if (glbnv_buffer)
        p = parse_objls(glbnv_buffer, base, NULL, ".GlobalEnv", p);

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
    p--;
    *p = '\0';
    send_menu_items(compl_buffer);
}

void complete_rhelp(void) {
    Log("complete_rhelp");
    if (!rhelp_menu) {
        char fpath[128];
        snprintf(fpath, 127, "%s/resources/rhelp_keywords",
                 getenv("RNVIM_HOME"));
        Log("rnvim_home: >>>%s<<<", fpath);
        rhelp_menu = read_file(fpath, 1);
    }
    if (rhelp_menu)
        send_menu_items(rhelp_menu);
}

void complete_rmd_chunk(void) {}
void complete_quarto_block(void) {}
