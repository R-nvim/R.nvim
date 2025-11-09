#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "signature.h"
#include "global_vars.h"
#include "logging.h"
#include "lsp.h"
#include "tcp.h"
#include "utilities.h"
#include "../common.h"

static int get_info(const char *s, char *p) {
    int i;
    unsigned long nsz;
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

    if (f[1][0] == 'F') {
        char *b = format_usage(f[0], f[4], 0);
        str_cat(p, b);
        free(b);
        return 1;
    } else {
        return 0;
    }
}

static void send_result(const char *req_id, const char *doc) {
    if (!doc || strlen(doc) == 0) {
        send_null(req_id);
        return;
    }

    const char *fmt =
        "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"activeSignature\":0,"
        "\"signatures\":[{\"label\":\"%s\"}]}}";

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

void glbnv_signature(const char *req_id, const char *word, const char *args) {
    if (!args || strlen(args) == 0) {
        send_null(req_id);
        return;
    }

    char *b = format_usage(word, args, 0);
    send_result(req_id, b);
    free(b);
}

void signature(const char *params) {
    Log("signature: %s", params);

    char *id = strstr(params, "\"orig_id\":");
    char *word = strstr(params, "\"word\":\"");

    cut_json_int(&id, 10);
    cut_json_str(&word, 8);

    if (!word) {
        send_null(id);
        return;
    }

    char *p;
    memset(cmp_buf, 0, cmp_buf_size);
    p = cmp_buf;
    const char *s = NULL;

    // The word is a function
    // Seek the function in .GlobalEnv
    if (glbnv_buffer) {
        s = seek_word(glbnv_buffer, word);
        if (s) {
            char cmd[128];
            snprintf(cmd, 127, "nvimcom:::signature('%s', '%s')", id, word);
            nvimcom_eval(cmd);
            return;
        }
    }

    // Seek the function in loaded libraries
    PkgData *pd = pkgList;
    while (pd) {
        if (pd->objls) {
            s = seek_word(pd->objls, word);
            if (s) {
                int is_function = get_info(s, p);
                if (is_function)
                    send_result(id, cmp_buf);
                return;
            }
        }
        pd = pd->next;
    }
    send_null(id);
}
