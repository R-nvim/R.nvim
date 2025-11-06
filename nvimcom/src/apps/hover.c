#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hover.h"
#include "global_vars.h"
#include "logging.h"
#include "lsp.h"
#include "utilities.h"
#include "../common.h"

static void get_info(const char *s, char *p) {
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
    // compl_buffer.
    nsz =
        strlen(f[4]) + strlen(f[5]) + strlen(f[6]) + 1024 + (p - compl_buffer);
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
        char *b = format_usage(f[0], f[4], 1);
        str_cat(p, b);
        free(b);
    }
}

static void send_result(const char *req_id, const char *doc) {
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

// FIXME: finish implementation
void hover(const char *params) {
    Log("hover: %s", params);

    char *id = strstr(params, "\"orig_id\":");
    char *word = strstr(params, "\"word\":\"");
    char *fobj = strstr(params, "\"fobj\":\"");
    char *fnm = strstr(params, "\"fnm\":\"");

    cut_json_int(&id, 10);
    cut_json_str(&word, 8);
    cut_json_str(&fobj, 8);
    cut_json_str(&fnm, 7);

    Log("hover: %s, '%s', '%s', '%s'", id, word, fobj, fnm);

    char *p;
    memset(compl_buffer, 0, compl_buffer_size);
    p = compl_buffer;

    if (fobj) {
        // The word is a function
        PkgData *pd = pkgList;
        const char *s = NULL;
        while (pd) {
            if (pd->objls) {
                s = seek_word(pd->objls, word);
                if (s) {
                    get_info(s, p);
                    send_result(id, compl_buffer);
                    Log("HOVER RESULT:\n%s\n", compl_buffer);
                    return;
                }
            }
            pd = pd->next;
        }
    } else if (fnm) {
        // The word is a function argument
    } else {
        // Anything else. Start searching the .GlobalEnv
    }
}
