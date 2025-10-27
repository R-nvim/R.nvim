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

void resolve_arg_item(const char *rid, const char *knd, const char *itm,
                      char *pkg, char *fnm) {

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
 * @desc: Return user_data of a specific item with function usage, title and
 * description to be displayed in the float window
 * @param args: List of arguments
 * */
void resolve(const char *rid, const char *knd, const char *wrd,
             const char *pkg) {

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
                snprintf(compl_buffer, 1024,
                         "nvimcom:::nvim.GlobalEnv.fun.args(\"%s\")\n", wrd);
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

static void cut_json_int(char **str, unsigned len) {
    char *p = *str + len;
    *str = p + 1;
    *p = '\0';
    p++;
    while (*p >= '0' && *p <= '9')
        p++;
    *p = '\0';
}

static void cut_json_str(char **str, unsigned len) {
    if (*str == NULL)
        return;
    char *p = *str + len;
    *str = p + 1;
    *p = '\0';
    while (*p != '"')
        p++;
    *p = '\0';
}

// local fix_doc = function(txt)
//     -- The rnvimserver replaces ' with \019 and \n with \020. We have to
//     revert this: txt = string.gsub(txt, "\020", "\n") txt = string.gsub(txt,
//     "\019", "'") txt = string.gsub(txt, "\018", "\\") return txt
// end

// Simulate the fix_doc function
// Note: In C, we must manage the memory for the returned string!
void fix_doc(char *str) {
    while (*str) {
        if (*str == '\x12')
            *str = '\'';
        else if (*str == '\x13')
            *str = '"';
        else if (*str == '\x14')
            *str = '\n';
        str++;
    }
}

void resolve_json(const char *req_id, const char *json) {
    Log("resolve_json: %s\n%s", req_id, json);
    // {"env":"base","label":"read.dcf","cls":"F","kind":3}
    char *env = strstr(json, "\"env\":\"");
    char *lbl = strstr(json, "\"label\":\"");
    char *cls = strstr(json, "\"cls\":\"");
    char *knd = strstr(json, "\"kind\":");

    if (!cls)
        return;

    cut_json_str(&env, 6);
    cut_json_str(&cls, 6);
    cut_json_str(&lbl, 8);
    cut_json_int(&knd, 6);

    Log("resolve_json: %s | %s | %s | %s", env, lbl, cls, knd);

    if (strcmp(env, ".GlobalEnv") == 0) {
        if (*cls == 'a') {
            Log("RESOLVE A");

        } else if (*cls == 'f' || *cls == 'b' || *cls == 't' || *cls == 'n') {
            char buffer[512];
            sprintf(buffer,
                    "nvimcom:::nvim.get.summary('%s', '%s', '%s', %s, '%s')",
                    req_id, knd, lbl, lbl, env);
            nvimcom_eval(buffer);

        } else if (*cls == 'F') {
            char buffer[512];
            sprintf(buffer,
                    "nvimcom:::nvim.GlobalEnv.fun.args('%s', '%s', '%s')",
                    req_id, lbl, knd);
            nvimcom_eval(buffer);
        } else {
            char buffer[512];
            sprintf(buffer,
                    "nvimcom:::nvim.min.info('%s', %s, '%s', '%s', '%s')",
                    req_id, lbl, lbl, env, knd);
            nvimcom_eval(buffer);
        }
        return;
    }

    if (*cls == 'c') {
        char buffer[512];
        sprintf(buffer, "nvimcom:::nvim.get.summary('%s', %s$%s, '%s')", req_id,
                env, lbl, env);
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
        char *lib = env;
        char *func = lib;
        while (*func) {
            if (*func == ':') {
                *func = 0;
                func++;
            }
        }
        resolve_arg_item(req_id, knd, lbl, lib, func);

    } else if (*cls == 'L') {
        // Lua: print("value" .. fix_doc(itm_env)("\n") .. "kind" ..
        // vim.lsp.MarkupKind.Markdown) This line is complex due to the chained
        // function call `fix_doc(itm_env)("\n")` which looks like a Lua
        // closure. Assuming it's meant to print "value" + fix_doc result +
        // "kind" + a constant:

        // char *fixed_env = fix_doc(env);
        // // Note: Assuming a placeholder for vim.lsp.MarkupKind.Markdown
        // const char *MARKUP_KIND_MARKDOWN = "markdown";
        //
        // printf("value%skind%s\n", fixed_env, MARKUP_KIND_MARKDOWN);
        // free(fixed_env); // Free the memory from fix_doc
        //
        Log("RESOLVE L\n");

        // Lua: elseif itm_label:find("%$") and (itm_cls == "f" or itm_cls ==
        // "b" or itm_cls == "t" or itm_cls == "n") then
    } else if (strstr(lbl, "$") != NULL &&
               (*cls == 'f' || *cls == 'b' || *cls == 't' || *cls == 'n')) {
        char buffer[512];
        sprintf(buffer, "nvimcom:::nvim.get.summary('%s', %s, '%s')", req_id,
                lbl, env);
        nvimcom_eval(buffer);

        // Lua: else
    } else {
        resolve(req_id, knd, lbl, env);
    }
}
