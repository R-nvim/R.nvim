#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hover.h"
#include "logging.h"
#include "lsp.h"
#include "utilities.h"

// FIXME: implement
void handle_hover(const char *req_id, char *params) {
    Log("handle_hover: %s\n%s", req_id, params);

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

    Log("handle_hover: '%s', '%s', '%c', '%s'", env, lbl, *cls, knd);
}
