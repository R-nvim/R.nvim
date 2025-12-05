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

static char *sig_buf;
static size_t sig_buf_sz = 1024;

static int get_info(const char *s) {
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

    memset(sig_buf, 0, sig_buf_sz);
    char *p = sig_buf;

    // Avoid buffer overflow if the information is too lengthy.
    nsz = strlen(f[0]) + strlen(f[4]) + 512;
    nsz = nsz * 2;
    if (sig_buf_sz < nsz)
        p = grow_buffer(&sig_buf, &sig_buf_sz, nsz - sig_buf_sz);

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

    send_ls_response(req_id, res);
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

// Seek the function in loaded libraries
static void seek_in_libs(const char *id, const char *word) {
    PkgData *pd = pkgList;
    while (pd) {
        if (pd->objls) {
            const char *s = seek_word(pd->objls, word);
            if (s) {
                int is_function = get_info(s);
                if (is_function)
                    send_result(id, sig_buf);
                return;
            }
        }
        pd = pd->next;
    }
    send_null(id);
}

void sig_seek(const char *id, const char *word) { seek_in_libs(id, word); }

void signature(const char *params) {
    Log("signature: %s", params);

    char *id = strstr(params, "\"orig_id\":");
    char *word = strstr(params, "\"word\":\"");
    char *fobj = strstr(params, "\"fobj\":\"");

    cut_json_int(&id, 10);
    cut_json_str(&word, 8);
    cut_json_str(&fobj, 8);

    if (!sig_buf) {
        sig_buf = (char *)malloc(sig_buf_sz);
    }

    if (glbnv_buffer) {
        const char *s = seek_word(glbnv_buffer, word);
        if (s) {
            int is_function = get_info(s);
            if (is_function)
                send_result(id, sig_buf);
            return;
        }
        if (fobj) {
            // If the function is a generic one, show the signature of the
            // relevant method
            char cmd[128];
            snprintf(cmd, 127,
                     "nvimcom:::sighover_method('%s', '%s', '%s', 's')", id,
                     word, fobj);
            nvimcom_eval(cmd);
            return;
        }
    }

    seek_in_libs(id, word);
}
