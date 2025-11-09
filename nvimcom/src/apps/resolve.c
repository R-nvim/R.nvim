#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "resolve.h"
#include "global_vars.h"
#include "logging.h"
#include "lsp.h"
#include "tcp.h"
#include "utilities.h"
#include "../common.h"

static struct {
    char id[16];
    char *item;
} last_item;

void send_item_doc(const char *req_id, const char *doc) {
    if (!doc || strlen(doc) == 0 || strcmp(last_item.id, req_id) != 0) {
        send_null(req_id);
        return;
    }

    const char *fmt =
        "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{%s,\"documentation\":{"
        "\"kind\":\"markdown\",\"value\":\"%s\"}}}";

    char *fdoc = (char *)calloc(strlen(doc) + 1, sizeof(char));
    format(doc, fdoc, ' ', '\x14');
    char *edoc = esc_json(fdoc);
    size_t len = sizeof(char) * (strlen(edoc) + 256);
    char *res = (char *)malloc(len);

    snprintf(res, len - 1, fmt, req_id, last_item.item, edoc);

    send_ls_response(res);

    free(fdoc);
    free(edoc);
    free(res);
}

static void get_alias(char **pkg, char **fun) {
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

static void resolve_lib_name(const char *req_id, const char *lbl) {
    Log("resolve_lib_name: %s, %s", req_id, lbl);

    if (!instlibs)
        return;

    InstLibs *il;

    il = instlibs;
    while (il) {
        if (strcmp(il->name, lbl) == 0) {
            char *b = (char *)malloc(
                sizeof(char) * (strlen(il->title) + strlen(il->descr) + 32));
            sprintf(b, "**%s**\x14\x14%s\x14", il->title, il->descr);
            send_item_doc(req_id, b);
            free(b);
            break;
        }
        il = il->next;
    }
}

static void resolve_arg_item(const char *rid, const char *itm, char *pkg,
                             char *fnm) {

    Log("resolve_arg_item: %s, %s, %s, %s", pkg, fnm, itm, rid);
    // Delete " = "
    char lbl[64];
    strncpy(lbl, itm, 63);
    char *a = lbl;
    while (*a) {
        if (*a == ' ') {
            *a = '\0';
            break;
        }
        a++;
    }

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
                                        if (str_here(s, lbl)) {
                                            s += strlen(lbl);
                                            if (*s == '\005' || *s == ',') {
                                                while (*s && *s != '\005')
                                                    s++;
                                                s++;
                                                char *b = calloc(strlen(s) + 2,
                                                                 sizeof(char));
                                                format(s, b, ' ', '\x14');
                                                send_item_doc(rid, b);
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
 * @desc: Return user_data of a specific item with function usage, title and
 * description to be displayed in the float window
 * @param args: List of arguments
 * */
static void resolve(const char *rid, const char *wrd, const char *pkg) {
    Log("resolve: %s, %s, %s", wrd, pkg, rid);
    int i;
    size_t nsz;
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

    memset(cmp_buf, 0, cmp_buf_size);
    char *p = cmp_buf;

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

            if (f[1][0] == 'F' && str_here(f[4], ">not_checked<")) {
                snprintf(cmp_buf, 1024,
                         "nvimcom:::resolve_fun_args('%s', '%s')", rid, wrd);
                nvimcom_eval(cmp_buf);
                return;
            }

            // Avoid buffer overflow if the information is bigger than
            // cmp_buf.
            nsz = strlen(f[4]) + strlen(f[5]) + strlen(f[6]) + 1024 +
                  (p - cmp_buf);
            if (cmp_buf_size < nsz)
                p = grow_buffer(&cmp_buf, &cmp_buf_size,
                                nsz - cmp_buf_size + 32768);

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
            if (f[1][0] == 'F') {
                char *b = format_usage(f[0], f[4], 1);
                str_cat(p, b);
                free(b);
            }
            send_item_doc(rid, cmp_buf);
            return;
        }
        while (*s != '\n')
            s++;
        s++;
    }
}

void handle_resolve(const char *req_id, char *params) {
    Log("handle_resolve: %s\n%s", req_id, params);

    const char *doc = strstr(params, "\"documentation\":{");
    if (doc) {
        cut_json_bkt(&params, 9);
        Log("%s", params);
        const char *fmt = "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":%s}";
        size_t len = sizeof(char) * (strlen(params) + 64);
        char *res = (char *)malloc(len);
        snprintf(res, len - 1, fmt, req_id, params);
        send_ls_response(res);
        free(res);
        return;
    }

    char *cls = strstr(params, "\"cls\":\"");
    if (!cls) {
        send_null(req_id);
        return;
    }

    char *item = strstr(params, "\"params\":{");
    char *env = strstr(params, "\"env\":\"");
    char *lbl = strstr(params, "\"label\":\"");

    // FIXME: bug if there is '}' in any of the params elements
    cut_json_bkt(&item, 9);
    if (last_item.item)
        free(last_item.item);
    strncpy(last_item.id, req_id, 15);
    last_item.item = (char *)malloc(1 + strlen(item) * sizeof(char));
    item++;                        // skip the opening bracket
    item[strlen(item) - 1] = '\0'; // delete the closing bracket
    strcpy(last_item.item, item);

    cut_json_str(&env, 7);
    cut_json_str(&lbl, 9);
    cut_json_str(&cls, 7);

    if (env && strcmp(env, ".GlobalEnv") == 0) {
        if (*cls == 'a') {
            return;
        } else if (*cls == 'f' || *cls == 'b' || *cls == 't' || *cls == 'n') {
            char buffer[512];
            sprintf(buffer, "nvimcom:::resolve_summary('%s', %s, '%s')", req_id,
                    lbl, env);
            nvimcom_eval(buffer);

        } else if (*cls == 'F') {
            char buffer[512];
            sprintf(buffer, "nvimcom:::resolve_fun_args('%s', '%s')", req_id,
                    lbl);
            nvimcom_eval(buffer);
        } else {
            char buffer[512];
            sprintf(buffer, "nvimcom:::resolve_min_info('%s', %s, '%s')",
                    req_id, lbl, env);
            nvimcom_eval(buffer);
        }
        return;
    }

    if (*cls == 'c') {
        char buffer[512];
        sprintf(buffer, "nvimcom:::resolve_summary('%s', %s$%s, '%s')", req_id,
                env, lbl, env);
        nvimcom_eval(buffer);
    } else if (*cls == 'a') {
        // Split "library:function"
        char *func = strstr(env, ":");
        if (func) {
            *func = 0;
            func++;
        }
        resolve_arg_item(req_id, lbl, env, func);
    } else if (*cls == 'L') {
        resolve_lib_name(req_id, lbl);
    } else if (strstr(lbl, "$") != NULL &&
               (*cls == 'f' || *cls == 'b' || *cls == 't' || *cls == 'n')) {
        char buffer[512];
        sprintf(buffer, "nvimcom:::resolve_summary('%s', %s, '%s')", req_id,
                lbl, env);
        nvimcom_eval(buffer);
    } else {
        resolve(req_id, lbl, env);
    }
}
