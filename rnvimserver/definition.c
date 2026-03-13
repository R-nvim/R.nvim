#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "definition.h"
#include "global_vars.h"
#include "logging.h"
#include "lsp.h"
#include "utilities.h"
#include "tcp.h"

/**
 * @brief Search a package's srcref buffer for a symbol and extract
 * file path, line, and column.
 *
 * The srcref buffer has the format (with \0 as separator, converted from \006):
 *   funcname\0filepath\0line\0col\n
 *
 * @param srcref The srcref buffer.
 * @param symbol The symbol name to find.
 * @param file Output: pointer to file path string within the buffer.
 * @param line Output: line number (1-indexed from R).
 * @param col Output: column number.
 * @return 1 if found, 0 otherwise.
 */
static int seek_srcref(const char *srcref, const char *symbol,
                       const char **file, int *line, int *col) {
    const char *s = srcref;
    while (*s) {
        if (strcmp(s, symbol) == 0) {
            while (*s)
                s++;
            s++;
            *file = s;
            while (*s)
                s++;
            s++;
            *line = atoi(s);
            while (*s)
                s++;
            s++;
            *col = atoi(s);
            return 1;
        }
        while (*s != '\n')
            s++;
        s++;
    }
    return 0;
}

static void send_definition_location(const char *req_id, const char *filepath,
                                     int line, int col) {
    const char *fmt = "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":"
                      "{\"uri\":\"file://%s\",\"range\":{\"start\":"
                      "{\"line\":%d,\"character\":%d},\"end\":"
                      "{\"line\":%d,\"character\":%d}}}}";

    size_t len = strlen(filepath) + strlen(req_id) + 256;
    char *res = (char *)malloc(len);
    int lsp_line = line - 1;
    if (lsp_line < 0)
        lsp_line = 0;
    snprintf(res, len - 1, fmt, req_id, filepath, lsp_line, col, lsp_line, col);
    send_ls_response(req_id, res);
    free(res);
}

/**
 * @brief Try to resolve a symbol's definition from a package's cached data.
 *
 * If the srcref cache has a hit, sends the location directly.
 * If the srcref cache was built but has no entry, falls back to R with the
 * specific package name (fast single-namespace lookup).
 * If no srcref cache exists, falls back to R with the specific package name.
 *
 * @return 1 if handled (response sent or R fallback dispatched), 0 otherwise.
 */
static int try_resolve(const char *id, const char *symbol, const char *pkg_name,
                       PkgData *pkg) {
    const char *file;
    int line, col;

    if (pkg->srcref && seek_srcref(pkg->srcref, symbol, &file, &line, &col)) {
        send_definition_location(id, file, line, col);
        return 1;
    }
    if (r_running) {
        char cmd[512];
        snprintf(cmd, 511, "nvimcom:::send_definition('%s', '%s', '%s')", id,
                 pkg_name, symbol);
        nvimcom_eval(cmd);
        return 1;
    }
    send_null(id);
    return 1;
}

void definition(const char *params) {
    Log("definition: %s", params);

    char *id = strstr(params, "\"orig_id\":");
    char *symbol = strstr(params, "\"symbol\":\"");
    char *pkg = strstr(params, "\"pkg\":\"");

    cut_json_int(&id, 10);
    cut_json_str(&symbol, 10);
    cut_json_str(&pkg, 7);

    if (!id || !symbol || !*symbol) {
        if (id)
            send_null(id);
        return;
    }

    if (pkg && *pkg) {
        LibList *lib = inst_libs;
        while (lib) {
            if (strcmp(lib->pkg->name, pkg) == 0) {
                try_resolve(id, symbol, pkg, lib->pkg);
                return;
            }
            lib = lib->next;
        }
        if (r_running) {
            char cmd[512];
            snprintf(cmd, 511, "nvimcom:::send_definition('%s', '%s', '%s')",
                     id, pkg, symbol);
            nvimcom_eval(cmd);
            return;
        }
        send_null(id);
        return;
    }

    LibList *lib = loaded_libs;
    while (lib) {
        if (lib->pkg->objls) {
            const char *s = seek_word(lib->pkg->objls, symbol);
            if (s) {
                try_resolve(id, symbol, lib->pkg->name, lib->pkg);
                return;
            }
        }
        lib = lib->next;
    }

    // Not in loaded_libs — search inst_libs
    lib = inst_libs;
    while (lib) {
        if (lib->pkg->objls) {
            const char *s = seek_word(lib->pkg->objls, symbol);
            if (s) {
                try_resolve(id, symbol, lib->pkg->name, lib->pkg);
                return;
            }
        }
        lib = lib->next;
    }

    // Not found — full R search as last resort
    if (r_running) {
        char cmd[512];
        snprintf(cmd, 511, "nvimcom:::send_definition('%s', '', '%s')", id,
                 symbol);
        nvimcom_eval(cmd);
        return;
    }

    send_null(id);
}
