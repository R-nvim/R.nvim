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

static void nvimcom_eval(const char *cmd) {
    char buf[1024];
    snprintf(buf, 1023, "E%s%s", getenv("RNVIM_ID"), cmd);
    send_to_nvimcom(buf);
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

static void resolve_lib_name(const char *req_id, const char *lbl,
                             const char *cls) {
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
            send_item_doc(b, req_id, lbl, "9", cls);
            free(b);
            break;
        }
        il = il->next;
    }
}

static void resolve_arg_item(const char *rid, const char *knd, const char *cls,
                             const char *itm, char *pkg, char *fnm) {

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
                                                send_item_doc(b, rid, itm, knd,
                                                              cls);
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
static void resolve(const char *rid, const char *knd, const char *cls,
                    const char *wrd, const char *pkg) {

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

            if (f[1][0] == 'F' && str_here(f[4], ">not_checked<")) {
                snprintf(
                    compl_buffer, 1024,
                    "nvimcom:::nvim.GlobalEnv.fun.args('%s', '%s', '%s', '%s')",
                    rid, wrd, knd, cls);
                nvimcom_eval(compl_buffer);
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
            if (f[1][0] == 'F') {
                char *b = format_usage(f[0], f[4]);
                str_cat(p, b);
                free(b);
            }
            send_item_doc(compl_buffer, rid, wrd, knd, cls);
            return;
        }
        while (*s != '\n')
            s++;
        s++;
    }
}

void handle_resolve(const char *req_id, char *params) {
    Log("resolve_json: %s\n%s", req_id, params);

    char *doc = strstr(params, "\"documentation\":{");
    char *env = strstr(params, "\"env\":\"");
    char *lbl = strstr(params, "\"label\":\"");
    char *cls = strstr(params, "\"cls\":\"");
    char *knd = strstr(params, "\"kind\":");

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

    if (!cls)
        return;

    cut_json_str(&env, 7);
    cut_json_str(&cls, 7);
    cut_json_str(&lbl, 9);
    cut_json_int(&knd, 7);

    Log("resolve_json: '%s', '%s', '%c', '%s'", env, lbl, *cls, knd);

    if (env && strcmp(env, ".GlobalEnv") == 0) {
        if (*cls == 'a') {
            return;
        } else if (*cls == 'f' || *cls == 'b' || *cls == 't' || *cls == 'n') {
            char buffer[512];
            sprintf(
                buffer,
                "nvimcom:::nvim.get.summary('%s', '%s', '%s', '%s', %s, '%s')",
                req_id, knd, cls, lbl, lbl, env);
            nvimcom_eval(buffer);

        } else if (*cls == 'F') {
            char buffer[512];
            sprintf(buffer,
                    "nvimcom:::nvim.GlobalEnv.fun.args('%s', '%s', '%s', '%s')",
                    req_id, lbl, knd, cls);
            nvimcom_eval(buffer);
        } else {
            char buffer[512];
            sprintf(buffer,
                    "nvimcom:::nvim.min.info('%s', %s, '%s', '%s', '%s', '%s')",
                    req_id, lbl, lbl, env, knd, cls);
            nvimcom_eval(buffer);
        }
        return;
    }

    if (*cls == 'c') {
        char buffer[512];
        sprintf(
            buffer,
            "nvimcom:::nvim.get.summary('%s', '%s', '%s', '%s', %s$%s, '%s')",
            req_id, knd, cls, lbl, env, lbl, env);
        nvimcom_eval(buffer);
    } else if (*cls == 'a') {
        // Delete " = "
        char *p = lbl;
        while (*p) {
            if (*p == ' ') {
                *p = '\0';
                break;
            }
            p++;
        }

        // Split "library:function"
        char *func = strstr(env, ":");
        if (func) {
            *func = 0;
            func++;
        }
        resolve_arg_item(req_id, knd, cls, lbl, env, func);
    } else if (*cls == 'L') {
        resolve_lib_name(req_id, lbl, cls);
    } else if (strstr(lbl, "$") != NULL &&
               (*cls == 'f' || *cls == 'b' || *cls == 't' || *cls == 'n')) {
        char buffer[512];
        sprintf(buffer,
                "nvimcom:::nvim.get.summary('%s', '%s', '%s', '%s', %s, '%s')",
                req_id, knd, cls, lbl, lbl, env);
        nvimcom_eval(buffer);
    } else {
        resolve(req_id, knd, cls, lbl, env);
    }
}
