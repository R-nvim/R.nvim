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

static int get_info(const char *s, char *p) {
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
    // cmp_buf.
    nsz = strlen(f[4]) + strlen(f[5]) + strlen(f[6]) + 1024 + (p - cmp_buf);
    if (cmp_buf_size < nsz)
        p = grow_buffer(&cmp_buf, &cmp_buf_size, nsz - cmp_buf_size + 32768);

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

    send_ls_response(res);
    free(fdoc);
    free(edoc);
    free(res);
}

void send_hover_doc(const char *hid, const char *hdoc) {
    send_result(hid, hdoc);
}

void hover(const char *params) {
    Log("hover: %s", params);

    char *id = strstr(params, "\"orig_id\":");
    char *word = strstr(params, "\"word\":\"");

    // TODO: either use these two parameters or delete them
    char *fobj = strstr(params, "\"fobj\":\"");
    char *fnm = strstr(params, "\"fnm\":\"");

    cut_json_int(&id, 10);
    cut_json_str(&word, 8);
    cut_json_str(&fobj, 8);
    cut_json_str(&fnm, 7);

    if (!word) {
        send_null(id);
        return;
    }

    char *p;
    memset(cmp_buf, 0, cmp_buf_size);
    p = cmp_buf;

    // The word is a function
    PkgData *pd = pkgList;
    while (pd) {
        if (pd->objls) {
            const char *s = seek_word(pd->objls, word);
            if (s) {
                int is_function = get_info(s, p);
                if (is_function) {
                    send_result(id, cmp_buf);
                } else {
                    char buffer[512];
                    sprintf(buffer, "nvimcom:::hover_summary('%s', %s)", id,
                            word);
                    nvimcom_eval(buffer);
                }
                return;
            }
        }
        pd = pd->next;
    }

    // Anything else. Search the .GlobalEnv
    if (glbnv_buffer) {
        const char *s = seek_word(glbnv_buffer, word);
        if (s) {
            char buffer[512];
            sprintf(buffer, "nvimcom:::hover_summary('%s', %s)", id, word);
            nvimcom_eval(buffer);
            return;
        }
    }

    send_null(id);
}
