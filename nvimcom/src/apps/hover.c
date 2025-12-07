#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hover.h"
#include "global_vars.h"
#include "logging.h"
#include "lsp.h"
#include "utilities.h"
#include "tcp.h"
#include "../common.h"

static char *hov_buf;
static size_t hov_buf_sz = 4096;

static int get_info(const char *s) {
    Log("get_info: %s", s);
    int i;
    size_t nsz;
    const char *f[7];
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

    // Avoid buffer overflow if the information is bigger than
    // hov_buf.
    char *p = hov_buf;
    nsz = strlen(f[4]) + strlen(f[5]) + strlen(f[6]) + 1024 + (p - hov_buf);
    if (hov_buf_sz < nsz)
        p = grow_buffer(&hov_buf, &hov_buf_sz, nsz - hov_buf_sz + 32768);

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
        return 1;
    }
    return 0;
}

static void send_result(const char *req_id, const char *doc) {
    if (!doc || strlen(doc) == 0) {
        send_null(req_id);
        return;
    }

    const char *fmt =
        "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"contents\":\"%s\"}}";

    char *fdoc = (char *)calloc(strlen(doc) + 1, sizeof(char));
    format(doc, fdoc, ' ', '\x14');
    char *edoc = esc_json(fdoc);
    size_t len = sizeof(char) * (strlen(edoc) + 256);
    char *res = (char *)malloc(len);
    snprintf(res, len - 1, fmt, req_id, edoc);

    send_ls_response(req_id, res);
    free(fdoc);
    free(edoc);
    free(res);
}

void send_hover_doc(const char *hid, const char *hdoc) {
    send_result(hid, hdoc);
}

// Seek object in loaded libraries
static void seek_in_libs(const char *id, const char *word) {
    PkgData *pd = pkgList;
    while (pd) {
        if (pd->objls) {
            const char *s = seek_word(pd->objls, word);
            if (s) {
                if (is_function(s)) {
                    get_info(s);
                    send_result(id, hov_buf);
                    return;
                }
            }
        }
        pd = pd->next;
    }
    send_null(id);
}

void hov_seek(const char *id, const char *word) { seek_in_libs(id, word); }

void hover(const char *params) {
    Log("hover: %s", params);

    char *id = strstr(params, "\"orig_id\":");
    char *word = strstr(params, "\"word\":\"");
    char *fobj = strstr(params, "\"fobj\":\"");

    cut_json_int(&id, 10);
    cut_json_str(&word, 8);
    cut_json_str(&fobj, 8);

    if (!hov_buf) {
        hov_buf = (char *)malloc(hov_buf_sz);
    }
    memset(hov_buf, 0, hov_buf_sz);

    // First search the .GlobalEnv
    if (glbnv_buffer) {
        const char *s = seek_word(glbnv_buffer, word);
        if (s) {
            if (is_function(s)) {
                get_info(s);
                send_result(id, hov_buf);
            } else {
                char buffer[128];
                snprintf(buffer, 127, "nvimcom:::hover_summary('%s', %s)", id,
                         word);
                nvimcom_eval(buffer);
            }
            return;
        }
    }

    char *pkg = NULL;
    if (strstr(word, "::")) {
        pkg = word;
        word = strstr(word, "::");
        *word = '\0';
        word += 2;
    }

    PkgData *pd = pkgList;
    while (pd) {
        if (pd->objls) {
            if (pkg && strcmp(pkg, pd->name) != 0) {
                pd = pd->next;
                continue;
            }
            const char *s = seek_word(pd->objls, word);
            if (s) {
                if (is_function(s)) {
                    if (r_running && fobj) {
                        // If the function display information on the relevant
                        // method
                        char cmd[128];
                        snprintf(
                            cmd, 127,
                            "nvimcom:::sighover_method('%s', '%s', '%s', 'h')",
                            id, word, fobj);
                        nvimcom_eval(cmd);
                    } else {
                        get_info(s);
                        send_result(id, hov_buf);
                    }
                } else if (r_running) {
                    char buffer[128];
                    snprintf(buffer, 127, "nvimcom:::hover_summary('%s', %s)",
                             id, word);
                    nvimcom_eval(buffer);
                }
                return;
            }
        }
        pd = pd->next;
    }

    send_null(id);
    return;
}
