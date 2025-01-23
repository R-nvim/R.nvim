#include <stdio.h>  // Standard input/output definitions
#include <stdlib.h> // Standard library
#include <string.h> // String handling functions

#include "logging.h"
#include "global_vars.h"
#include "utilities.h"
#include "../common.h"
#include "tcp.h"
#include "complete.h"

static char compl_cb[64];   // Completion callback buffer
static char resolve_cb[64]; // Completion info buffer

void init_compl_vars(void) {
    strncpy(compl_cb, getenv("RNVIM_COMPL_CB"), 63);
    strncpy(resolve_cb, getenv("RNVIM_RSLV_CB"), 63);
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
    unsigned long nsz;
    char dfbase[64];
    snprintf(dfbase, 63, "%s$%s", dtfrm, base);
    char *s = NULL;

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
        nsz = strlen(s) + 1024 + (p - compl_buffer);
        if (compl_buffer_size < nsz)
            p = grow_buffer(&compl_buffer, &compl_buffer_size,
                            nsz - compl_buffer_size + 32768);

        p = str_cat(p, "{label = '");
        p = str_cat(p, s + skip);
        p = str_cat(p, "', cls = 'c', env = '");
        p = str_cat(p, dtfrm);
        p = str_cat(p, "'}, ");

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
                         char *lib, char *p) {
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

            p = str_cat(p, "{label = '");
            if (pkg) {
                p = str_cat(p, pkg);
                p = str_cat(p, "::");
            }
            p = str_cat(p, f[0]);
            p = str_cat(p, "', cls = '");
            p = str_cat(p, f[1]);
            if (lib) {
                p = str_cat(p, "', env = '");
                p = str_cat(p, lib);
            }
            p = str_cat(p, "'}, ");
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
    char *s = malloc(strlen(*pkg) + strlen(*fun) + 3);
    sprintf(s, "%s\n", *fun);
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
                    free(s);
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
    free(s);
}

void resolve_arg_item(char *pkg, char *fnm, char *itm) {
    Log("resolve_arg_item: %s, %s, %s", pkg, fnm, itm);
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
                                    // Look for \0 or ' ' because some arguments share
                                    // the same documentation item. Example: lm()
                                    if (*s == 0 || *s == ' ') {
                                        s++;
                                        if (str_here(s, itm)) {
                                            s += strlen(itm);
                                            if (*s == '\005' || *s == ',') {
                                                while (*s && *s != '\005')
                                                    s++;
                                                s++;
                                                char *b =
                                                    calloc(strlen(s) + 2, sizeof(char));
                                                format(s, b, ' ', '\x14');
                                                printf("lua %s('%s')\n", resolve_cb, b);
                                                fflush(stdout);
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
                        printf("lua %s('')\n", resolve_cb);
                        fflush(stdout);
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
    printf("lua %s('')\n", resolve_cb);
    fflush(stdout);
}

/*
 * TODO: Candidate for completion_services.c
 *
 * @desc: Return user_data of a specific item with function usage, title and
 * description to be displayed in the float window
 * @param wrd:
 * @param pkg:
 * */
void resolve(const char *wrd, const char *pkg) {
    Log("resolve: %s, %s", wrd, pkg);
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
            printf("lua %s('%s')\n", resolve_cb, compl_buffer);
            fflush(stdout);
            return;
        }
        while (*s != '\n')
            s++;
        s++;
    }
    printf("lua %s('')\n", resolve_cb);
    fflush(stdout);
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
    char *s;
    char a[64];
    int i;
    while (pd) {
        if (pd->objls && (pkg == NULL || (pkg && strcmp(pd->name, pkg) == 0))) {
            s = pd->objls;
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
                            p = str_cat(p, "{label = '");
                            while (*s != '\x05' && *s != '\x04' && i < 63) {
                                a[i] = *s;
                                i++;
                                s++;
                            }
                            a[i] = 0;
                            p = str_cat(p, a);
                            p = str_cat(p, " = ");
                            if (*s == '\x04') {
                                p = str_cat(p, "', def = '");
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
                            p = str_cat(p, "', cls = 'a', env='");
                            p = str_cat(p, pd->name);
                            p = str_cat(p, "\x02");
                            p = str_cat(p, funcnm);
                            p = str_cat(p, "'},");
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
static char *complete_instlibs(char *p, const char *base) {
    update_inst_libs();

    Log("instlibs = %p", (void *)instlibs);
    if (!instlibs)
        return p;

    unsigned long len;
    InstLibs *il;
    size_t sz = 1024;
    char *buffer = malloc(sz);

    il = instlibs;
    while (il) {
        len = strlen(il->descr) + (p - compl_buffer) + 1024;
        if (compl_buffer_size < len)
            p = grow_buffer(&compl_buffer, &compl_buffer_size,
                            len - compl_buffer_size + 32768);

        if (str_here(il->name, base) && il->si) {
            if ((strlen(il->title) + strlen(il->descr)) > sz) {
                free(buffer);
                sz = strlen(il->title) + strlen(il->descr) + 1;
                buffer = malloc(sz);
            }

            p = str_cat(p, "{label = '");
            p = str_cat(p, il->name);
            p = str_cat(p, "', cls = 'l', env = '**");
            format(il->title, buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            p = str_cat(p, "**\x14\x14");
            format(il->descr, buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            p = str_cat(p, "\x14'},");
        }
        il = il->next;
    }
    free(buffer);
    return p;
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
void complete(const char *id, char *base, char *funcnm, char *dtfrm,
              char *funargs) {
    Log("complete(%s, %s, %s, %s, %s)", id, base, funcnm, dtfrm, funargs);
    char *p;

    memset(compl_buffer, 0, compl_buffer_size);
    p = compl_buffer;

    // Get menu completion for installed libraries
    if (funcnm && *funcnm == '\004') {
        p = complete_instlibs(p, base);
        printf("\x11%" PRI_SIZET "\x11"
               "lua %s(%s, {%s})\n",
               strlen(compl_cb) + strlen(id) + strlen(compl_buffer) + 10,
               compl_cb, id, compl_buffer);
        fflush(stdout);
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
            printf("\x11%" PRI_SIZET "\x11"
                   "lua %s(%s, {%s})\n",
                   strlen(compl_cb) + strlen(id) + strlen(compl_buffer) + 10,
                   compl_cb, id, compl_buffer);
            fflush(stdout);
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
        if (pd->objls && (pkg == NULL || (pkg && strcmp(pd->name, pkg) == 0)))
            p = parse_objls(pd->objls, base, pkg, pd->name, p);
        pd = pd->next;
    }

    printf("\x11%" PRI_SIZET "\x11"
           "lua %s(%s, {%s})\n",
           strlen(compl_cb) + strlen(id) + strlen(compl_buffer) + 10, compl_cb,
           id, compl_buffer);
    fflush(stdout);
}
