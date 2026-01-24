#include <signal.h> // Signal handling
#include <stdio.h>  // Standard input/output definitions
#include <stdlib.h> // Standard library
#include <string.h> // String handling functions
#include <unistd.h> // For read/write in a more robust server environment

#include "data_structures.h"
#include "logging.h"
#include "complete.h"
#include "resolve.h"
#include "hover.h"
#include "signature.h"
#include "tcp.h"
#include "obbr.h"
#include "lsp.h"
#include "utilities.h"
#include "rhelp.h"
#include "chunk.h"
#include "../common.h"

#ifdef WIN32
// Include for _setmode and _O_BINARY
#include <fcntl.h>
#include <io.h>
#endif

/*
 * Global variables (declared in global_vars.h)
 */

LibList *inst_libs;    // Pointer to first package data
LibList *loaded_libs;  // Pointer to loaded library
char *glbnv_buffer;    // Global environment buffer
char tmpdir[256];      // Temporary directory
int auto_obbr;         // Auto object browser flag
char localtmpdir[256]; // Local temporary directory
int r_running;         // Indicates whether R is running

typedef struct active_request_ {
    char id[16];
    struct active_request_ *next;
} ActiveRequest;

static ActiveRequest *actv_req;

static void add_active_request(const char *id) {
    ActiveRequest *ar = calloc(1, sizeof(ActiveRequest));
    strncpy(ar->id, id, 15);
    ar->next = actv_req;
    actv_req = ar;
}

static void rm_active_request(const char *id) {
    ActiveRequest *ar = actv_req;
    if (ar == NULL)
        return;
    if (strcmp(ar->id, id) == 0) {
        actv_req = ar->next;
        free(ar);
        return;
    }
    ActiveRequest *prev = NULL;
    while (ar && strcmp(ar->id, id) != 0) {
        prev = ar;
        ar = ar->next;
    }
    if (ar == NULL || prev == NULL)
        return;
    prev->next = ar->next;
    free(ar);
}

static int is_request_active(const char *id) {
    ActiveRequest *ar = actv_req;
    while (ar) {
        if (strcmp(ar->id, id) == 0)
            return 1;
        ar = ar->next;
    }
    return 0;
}

void print_listTree(ListStatus *root, FILE *f) {
    if (root != NULL) {
        fprintf(f, "%d :: %s\n", root->status, root->key);
        print_listTree(root->left, f);
        print_listTree(root->right, f);
    }
}

static void log_rns_info(void) {
    LibList *lib = loaded_libs;
    while (lib) {
        if (lib->pkg && lib->pkg->name)
            Log("INFO: %s {%s}", lib->pkg->name, lib->pkg->fname);
        else if (lib->pkg)
            Log("INFO pkg: %p", (void *)lib->pkg);
        else
            Log("INFO: %p", (void *)lib);
        lib = lib->next;
    }
}

// --- LSP Communication Helper ---

/**
 * @brief Sends a JSON response with the necessary LSP headers (Content-Length
 * and Content-Type).
 * * @param content_length The length of the JSON payload in bytes.
 * @param json_payload The JSON string to send.
 */
void send_ls_response(const char *req_id, const char *json_payload) {
#ifdef Debug_NRS
    Log("\x1b[33mSEND_LS_RESPONSE\x1b[0m (%zu bytes):", strlen(json_payload));
    if (strlen(json_payload) > 380) {
        char begin[360] = {0};
        char end[16] = {0};
        memcpy(begin, json_payload, 359);
        memcpy(end, json_payload + strlen(json_payload) - 15, 15);
        Log("%s [...] %s\n", begin, end);
    } else {
        Log("%s\n", json_payload);
    }
#endif
    if (req_id) {
        int is_active = is_request_active(req_id);
        if (is_active) {
            rm_active_request(req_id);
        } else {
            return;
        }
    }

    fprintf(stdout, "Content-Length: %zu\r\n\r\n", strlen(json_payload));
    fprintf(stdout, "%s", json_payload);
    fflush(stdout);
}

void send_null(const char *req_id) {
    char res[128];
    snprintf(res, 127, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":null}",
             req_id);
    send_ls_response(req_id, res);
}

void send_empty(const char *req_id) {
    char res[128];
    snprintf(res, 127,
             "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":"
             "{\"isIncomplete\":false,\"items\":[]}}",
             req_id);
    send_ls_response(req_id, res);
}

void send_cmd_to_nvim(const char *cmd) {
    size_t len = strlen(cmd);
    char *esccmd = (char *)malloc(sizeof(char) * len * 2 + 1);
    if (!esccmd)
        return;

    size_t j = 0;
    for (size_t i = 0; i < len; i++) {
        if (cmd[i] == '"') {
            esccmd[j] = '\\';
            j++;
        }
        esccmd[j] = cmd[i];
        j++;
    }
    esccmd[j] = 0;
    char *exeCmd = (char *)malloc(sizeof(char) * (124 + strlen(esccmd)));
    if (exeCmd) {
        sprintf(exeCmd,
                "{ \"jsonrpc\": \"2.0\", \"method\": \"client/exeRnvimCmd\", "
                "\"params\": {\"command\": \"%s\"}}",
                esccmd);
        send_ls_response(NULL, exeCmd);
        free(exeCmd);
    }
    free(esccmd);
}

void send_menu_items(char *compl_items, const char *req_id) {
    if (strlen(compl_items) == 0) {
        send_empty(req_id);
        return;
    }
    const char *fmt = "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{"
                      "\"isIncomplete\":false,\"items\":[%s]}}";

    size_t len = strlen(compl_items);

    // remove last superfluous comma to avoid json error:
    if (len > 3 && compl_items[len - 1] == ',') {
        compl_items[len - 1] = '\0';
    }
    char *res = (char *)malloc(sizeof(char) * len + 128);
    sprintf(res, fmt, req_id, compl_items);
    send_ls_response(req_id, res);
    free(res);
}

// Signal handler for SIGTERM
static void handle_sigterm(__attribute__((unused)) int s) { exit(0); }

// --- LSP Request Handlers ---

/**
 * @brief Handles the 'initialize' request (LSP Handshake).
 * * @param request_id The ID from the client's request.
 */
static void handle_initialize(const char *request_id) {
    // Finish immediately with SIGTERM
    signal(SIGTERM, handle_sigterm);

    // initialize global variables;
    strncpy(tmpdir, getenv("RNVIM_TMPDIR"), 255);
    set_doc_width(getenv("R_LS_DOC_WIDTH"));
    if (getenv("RNVIM_LOCAL_TMPDIR")) {
        strncpy(localtmpdir, getenv("RNVIM_LOCAL_TMPDIR"), 255);
    } else {
        strncpy(localtmpdir, getenv("RNVIM_TMPDIR"), 255);
    }
    set_max_depth(atoi(getenv("RNVIM_MAX_DEPTH")));

    init_cmp();
    init_obbr_vars();
    init_ds_vars();
    init_lib_list();

    char res[1024] = {0};
    char *p = res;
    p = str_cat(p, "{\"jsonrpc\":\"2.0\",\"id\":");
    p = str_cat(p, request_id);
    p = str_cat(p, ",\"result\":{\"capabilities\":{");

    char *disable = getenv("R_LS_DISABLE");
    int has_cpblt = 0;
    if (!disable || strstr(disable, "hover") == NULL) {
        p = str_cat(p, "\"hoverProvider\":true");
        has_cpblt = 1;
    }
    if (!disable || strstr(disable, "signature") == NULL) {
        if (has_cpblt)
            p = str_cat(p, ",");
        p = str_cat(p, "\"signatureHelpProvider\":{\"triggerCharacters\":[\"("
                       "\",\",\"]}");
        has_cpblt = 1;
    }
    if (!disable || strstr(disable, "completion") == NULL) {
        if (has_cpblt)
            p = str_cat(p, ",");
        p = str_cat(p, "\"completionProvider\":{\"resolveProvider\":true,"
                       "\"triggerCharacters\":[\".\",\" "
                       "\",\":\",\"(\",\"$\",\"\\\\\"]}");
        has_cpblt = 1;
    }
    if (!disable || strstr(disable, "definition") == NULL) {
        if (has_cpblt)
            p = str_cat(p, ",");
        p = str_cat(p, "\"definitionProvider\":true");
        has_cpblt = 1;
    }
    if (!disable || strstr(disable, "documentSymbol") == NULL) {
        if (has_cpblt)
            p = str_cat(p, ",");
        p = str_cat(p, "\"documentSymbolProvider\":true");
        has_cpblt = 1;
    }
    if (!disable || strstr(disable, "references") == NULL) {
        if (has_cpblt)
            p = str_cat(p, ",");
        p = str_cat(p, "\"referencesProvider\":true");
        has_cpblt = 1;
    }
    if (!disable || strstr(disable, "implementation") == NULL) {
        if (has_cpblt)
            p = str_cat(p, ",");
        p = str_cat(p, "\"implementationProvider\":true");
        has_cpblt = 1;
    }

    str_cat(p, "}}}");

    // "\"allCommitCharacters\":[\" \",\"\n\",\",\"]}}}}";

    send_ls_response(request_id, res);
}

// Forward declarations
static void send_definition_result(const char *params);
static void send_document_symbols_result(const char *params);
static void send_references_result(const char *params);
static void send_implementation_result(const char *params);

static void handle_exe_cmd(const char *params) {
    Log("handle_exe_cmd: %s\n", params);
    char *code = strstr(params, "\"code\":\"") + 8;
    char *p;
    switch (*code) {
    case 'C':
        code++;
        if (*code == 'H') {
            complete_rhelp(params);
        } else if (*code == '@') {
            complete_fig_tbl(params);
        } else {
            complete_chunk_opts(*code, params);
        }
        break;
    case 'H':
        hover(params);
        break;
    case 'S':
        signature(params);
        break;
    case 'E':
        cut_json_str(&code, 1);
        send_empty(code);
        break;
    case 'N':
        cut_json_str(&code, 1);
        send_null(code);
        break;
    case 'D': // Definition result from Lua
        send_definition_result(params);
        break;
    case 'Y': // Document symbols result from Lua
        send_document_symbols_result(params);
        break;
    case 'R': // References result from Lua
        send_references_result(params);
        break;
    case 'I': // Implementation result from Lua
        send_implementation_result(params);
        break;
    case '1': // Start TCP server and wait nvimcom connection
        start_server();
        break;
    case '2': // Send message
        cut_json_str(&code, 1);
        send_to_nvimcom(code);
        break;
    case '3':
        code++;
        switch (*code) {
        case '1': // Update GlobalEnv
            auto_obbr = 1;
            compl2ob();
            break;
        case '2': // Update Libraries
            auto_obbr = 1;
            lib2ob();
            break;
        case '3': // Open/Close list
            p = strstr(params, "\"key\":\"");
            cut_json_str(&p, 7);
            toggle_list_status(p);
            code++;
            if (*code == 'G')
                compl2ob();
            else
                lib2ob();
            break;
        case '4': // Close/Open all
            code++;
            if (*code == 'O')
                change_all(1);
            else
                change_all(0);
            code++;
            if (*code == 'G')
                compl2ob();
            else
                lib2ob();
            break;
        }
        break;
    case '4': // Miscellaneous commands
        code++;
        switch (*code) {
        case '1':
            finish_updating_loaded_libs(1);
            break;
        case '2':
            log_rns_info();
            break;
        case '3':
            update_glblenv_buffer("");
            if (auto_obbr)
                compl2ob();
            break;
        }
        break;
    case '5':
        complete(params);
        break;
    case '9': // R no longer running
        update_glblenv_buffer("");
        if (auto_obbr)
            compl2ob();
        r_running = 0;
        break;
    default:
        fprintf(stderr, "Unknown command received: %s\n", code);
        fflush(stderr);
        break;
    }
}

/**
 * @brief Handles 'exit' and 'shutdown' notifications.
 */
static void handle_exit(const char *method) {
    Log("Received \"%s\" notification. Shutting down.\n", method);
    exit(0);
}

static void handle_completion(const char *id, const char *params) {
    char *position = strstr(params, "\"position\":{") + 11;
    if (!position) {
        fprintf(stderr, "Error in textDocument/completion: missing "
                        "`position` field\n");
        fflush(stderr);
        return;
    }
    char *line = strstr(position, "\"line\":");
    char *col = strstr(position, "\"character\":");
    cut_json_int(&line, 7);
    cut_json_int(&col, 12);
    char compl_command[128];
    snprintf(compl_command, 127, "require('r.lsp').complete(%s, %s, %s)", id,
             line, col);
    send_cmd_to_nvim(compl_command);
}

static void handle_hover(const char *id) {
    char h_cmd[128];
    snprintf(h_cmd, 127, "require('r.lsp').hover(%s)", id);
    send_cmd_to_nvim(h_cmd);
}

static void handle_signature(const char *id) {
    char h_cmd[128];
    snprintf(h_cmd, 127, "require('r.lsp').signature(%s)", id);
    send_cmd_to_nvim(h_cmd);
}

static void handle_definition(const char *id) {
    char d_cmd[128];
    snprintf(d_cmd, 127, "require('r.lsp').definition(%s)", id);
    send_cmd_to_nvim(d_cmd);
}

static void handle_document_symbols(const char *id) {
    char s_cmd[128];
    snprintf(s_cmd, 127, "require('r.lsp').document_symbols(%s)", id);
    send_cmd_to_nvim(s_cmd);
}

static void handle_references(const char *id) {
    char r_cmd[128];
    snprintf(r_cmd, 127, "require('r.lsp').references(%s)", id);
    send_cmd_to_nvim(r_cmd);
}

static void handle_implementation(const char *id) {
    char i_cmd[128];
    snprintf(i_cmd, 127, "require('r.lsp').implementation(%s)", id);
    send_cmd_to_nvim(i_cmd);
}

static void send_definition_result(const char *params) {
    // IMPORTANT: Search for ALL fields BEFORE calling cut_json_* functions,
    // because those functions NULL-terminate and modify the params string!
    char *id = strstr(params, "\"orig_id\":");
    char *locations = strstr(params, "\"locations\":");
    char *uri = strstr(params, "\"uri\":\"");
    char *line_field = strstr(params, "\"line\":");
    char *col_field = strstr(params, "\"col\":");

    if (!id) {
        return;
    }

    cut_json_int(&id, 10);

    if (locations) {
        // Format: "locations":[{file:"...",line:N,col:N},...]
        char *arr_start = strchr(locations, '[');
        char *arr_end = strrchr(locations, ']');
        if (!arr_start || !arr_end) {
            send_null(id);
            return;
        }

        size_t result_size = 4096;
        char *result = (char *)malloc(result_size);
        char *p = result;
        p += snprintf(p, result_size, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":[", id);

        char *loc = arr_start + 1;
        int first = 1;
        while (loc < arr_end) {
            char *obj_start = strchr(loc, '{');
            if (!obj_start || obj_start >= arr_end) break;

            char *obj_end = strchr(obj_start, '}');
            if (!obj_end || obj_end > arr_end) break;

            char *file = strstr(obj_start, "\"file\":\"");
            char *line = strstr(obj_start, "\"line\":");
            char *col = strstr(obj_start, "\"col\":");

            if (file && line && col && file < obj_end && line < obj_end && col < obj_end) {
                file += 8;
                char *file_end = strchr(file, '"');
                if (file_end && file_end < obj_end) {
                    size_t file_len = file_end - file;
                    char *file_str = (char *)malloc(file_len + 1);
                    strncpy(file_str, file, file_len);
                    file_str[file_len] = '\0';

                    line += 7;
                    col += 6;
                    int line_num = atoi(line);
                    int col_num = atoi(col);

                    if (!first) {
                        p += snprintf(p, result_size - (p - result), ",");
                    }
                    first = 0;

                    p += snprintf(p, result_size - (p - result),
                        "{\"uri\":\"file://%s\",\"range\":{\"start\":{\"line\":%d,\"character\":%d},"
                        "\"end\":{\"line\":%d,\"character\":%d}}}",
                        file_str, line_num, col_num, line_num, col_num);

                    free(file_str);
                }
            }

            loc = obj_end + 1;
        }

        p += snprintf(p, result_size - (p - result), "]}");
        send_ls_response(id, result);
        free(result);
    } else {
        // Single location: use the fields we already found
        if (!uri || !line_field || !col_field) {
            return;
        }

        cut_json_str(&uri, 7);
        cut_json_int(&line_field, 7);
        cut_json_int(&col_field, 6);

        // Build the LSP Location response
        const char *fmt =
            "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":"
            "{\"uri\":\"%s\",\"range\":{\"start\":{\"line\":%s,\"character\":%s},"
            "\"end\":{\"line\":%s,\"character\":%s}}}}";

        size_t len = strlen(uri) + strlen(id) + strlen(line_field) * 2 + strlen(col_field) * 2 + 256;
        char *res = (char *)malloc(len);
        snprintf(res, len - 1, fmt, id, uri, line_field, col_field, line_field, col_field);
        send_ls_response(id, res);
        free(res);
    }
}

static void send_document_symbols_result(const char *params) {
    char *id = strstr(params, "\"orig_id\":");
    char *symbols = strstr(params, "\"symbols\":");

    if (!id) {
        return;
    }

    cut_json_int(&id, 10);

    if (!symbols) {
        send_null(id);
        return;
    }

    // Find the symbols array
    char *arr_start = strchr(symbols, '[');
    char *arr_end = strrchr(symbols, ']');
    if (!arr_start || !arr_end) {
        send_null(id);
        return;
    }

    // Build the result - we'll pass through the symbols array as-is since Lua already formatted it correctly
    // The Lua code sends DocumentSymbol objects with all required fields
    size_t result_size = (arr_end - arr_start) + 256;
    char *result = (char *)malloc(result_size);

    // Extract just the array content
    size_t array_len = arr_end - arr_start + 1;
    char *array_content = (char *)malloc(array_len + 1);
    strncpy(array_content, arr_start, array_len);
    array_content[array_len] = '\0';

    snprintf(result, result_size, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":%s}", id, array_content);

    send_ls_response(id, result);
    free(array_content);
    free(result);
}

static void send_references_result(const char *params) {
    // IMPORTANT: Search for ALL fields BEFORE calling cut_json_* functions,
    // because those functions NULL-terminate and modify the params string!
    char *id = strstr(params, "\"orig_id\":");
    char *locations = strstr(params, "\"locations\":");
    char *uri = strstr(params, "\"uri\":\"");
    char *line_field = strstr(params, "\"line\":");
    char *col_field = strstr(params, "\"col\":");

    if (!id) {
        return;
    }

    cut_json_int(&id, 10);

    if (locations) {
        // Format: "locations":[{file:"...",line:N,col:N},...]
        char *arr_start = strchr(locations, '[');
        char *arr_end = strrchr(locations, ']');
        if (!arr_start || !arr_end) {
            send_null(id);
            return;
        }

        size_t result_size = 4096;
        char *result = (char *)malloc(result_size);
        char *p = result;
        p += snprintf(p, result_size, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":[", id);

        char *loc = arr_start + 1;
        int first = 1;
        while (loc < arr_end) {
            char *obj_start = strchr(loc, '{');
            if (!obj_start || obj_start >= arr_end) break;

            char *obj_end = strchr(obj_start, '}');
            if (!obj_end || obj_end > arr_end) break;

            char *file = strstr(obj_start, "\"file\":\"");
            char *line = strstr(obj_start, "\"line\":");
            char *col = strstr(obj_start, "\"col\":");

            if (file && line && col && file < obj_end && line < obj_end && col < obj_end) {
                file += 8;
                char *file_end = strchr(file, '"');
                if (file_end && file_end < obj_end) {
                    size_t file_len = file_end - file;
                    char *file_str = (char *)malloc(file_len + 1);
                    strncpy(file_str, file, file_len);
                    file_str[file_len] = '\0';

                    line += 7;
                    col += 6;
                    int line_num = atoi(line);
                    int col_num = atoi(col);

                    if (!first) {
                        p += snprintf(p, result_size - (p - result), ",");
                    }
                    first = 0;

                    p += snprintf(p, result_size - (p - result),
                        "{\"uri\":\"file://%s\",\"range\":{\"start\":{\"line\":%d,\"character\":%d},"
                        "\"end\":{\"line\":%d,\"character\":%d}}}",
                        file_str, line_num, col_num, line_num, col_num);

                    free(file_str);
                }
            }

            loc = obj_end + 1;
        }

        p += snprintf(p, result_size - (p - result), "]}");
        send_ls_response(id, result);
        free(result);
    } else {
        if (!uri || !line_field || !col_field) {
            return;
        }

        cut_json_str(&uri, 7);
        cut_json_int(&line_field, 7);
        cut_json_int(&col_field, 6);

        const char *fmt =
            "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":"
            "{\"uri\":\"%s\",\"range\":{\"start\":{\"line\":%s,\"character\":%s},"
            "\"end\":{\"line\":%s,\"character\":%s}}}}";

        size_t len = strlen(uri) + strlen(id) + strlen(line_field) * 2 + strlen(col_field) * 2 + 256;
        char *res = (char *)malloc(len);
        snprintf(res, len - 1, fmt, id, uri, line_field, col_field, line_field, col_field);
        send_ls_response(id, res);
        free(res);
    }
}

static void send_implementation_result(const char *params) {
    Log("[DEBUG C] send_implementation_result called\n");
    Log("[DEBUG C] Params: %s\n", params);

    // IMPORTANT: Search for ALL fields BEFORE calling cut_json_* functions,
    // because those functions NULL-terminate and modify the params string!
    char *id = strstr(params, "\"orig_id\":");
    char *locations = strstr(params, "\"locations\":");
    char *uri = strstr(params, "\"uri\":\"");
    char *line_field = strstr(params, "\"line\":");
    char *col_field = strstr(params, "\"col\":");

    if (!id) {
        Log("[DEBUG C] No orig_id found in params\n");
        return;
    }

    cut_json_int(&id, 10);
    Log("[DEBUG C] Request ID: %s\n", id);

    if (locations) {
        Log("[DEBUG C] Multiple locations found\n");
        // Format: "locations":[{file:"...",line:N,col:N},...]
        char *arr_start = strchr(locations, '[');
        char *arr_end = strrchr(locations, ']');
        if (!arr_start || !arr_end) {
            send_null(id);
            return;
        }

        size_t result_size = 4096;
        char *result = (char *)malloc(result_size);
        char *p = result;
        p += snprintf(p, result_size, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":[", id);

        char *loc = arr_start + 1;
        int first = 1;
        while (loc < arr_end) {
            char *obj_start = strchr(loc, '{');
            if (!obj_start || obj_start >= arr_end) break;

            char *obj_end = strchr(obj_start, '}');
            if (!obj_end || obj_end > arr_end) break;

            char *file = strstr(obj_start, "\"file\":\"");
            char *line = strstr(obj_start, "\"line\":");
            char *col = strstr(obj_start, "\"col\":");

            if (file && line && col && file < obj_end && line < obj_end && col < obj_end) {
                file += 8;
                char *file_end = strchr(file, '"');
                if (file_end && file_end < obj_end) {
                    size_t file_len = file_end - file;
                    char *file_str = (char *)malloc(file_len + 1);
                    strncpy(file_str, file, file_len);
                    file_str[file_len] = '\0';

                    line += 7;
                    col += 6;
                    int line_num = atoi(line);
                    int col_num = atoi(col);

                    if (!first) {
                        p += snprintf(p, result_size - (p - result), ",");
                    }
                    first = 0;

                    p += snprintf(p, result_size - (p - result),
                        "{\"uri\":\"file://%s\",\"range\":{\"start\":{\"line\":%d,\"character\":%d},"
                        "\"end\":{\"line\":%d,\"character\":%d}}}",
                        file_str, line_num, col_num, line_num, col_num);

                    free(file_str);
                }
            }

            loc = obj_end + 1;
        }

        p += snprintf(p, result_size - (p - result), "]}");
        Log("[DEBUG C] Sending implementation LSP response: %s\n", result);
        send_ls_response(id, result);
        free(result);
    } else {
        Log("[DEBUG C] Single location (not array)\n");
        if (!uri || !line_field || !col_field) {
            Log("[DEBUG C] Missing uri, line, or col field\n");
            return;
        }

        cut_json_str(&uri, 7);
        cut_json_int(&line_field, 7);
        cut_json_int(&col_field, 6);

        const char *fmt =
            "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":"
            "{\"uri\":\"%s\",\"range\":{\"start\":{\"line\":%s,\"character\":%s},"
            "\"end\":{\"line\":%s,\"character\":%s}}}}";

        size_t len = strlen(uri) + strlen(id) + strlen(line_field) * 2 + strlen(col_field) * 2 + 256;
        char *res = (char *)malloc(len);
        snprintf(res, len - 1, fmt, id, uri, line_field, col_field, line_field, col_field);
        Log("[DEBUG C] Sending single implementation response: %s\n", res);
        send_ls_response(id, res);
        free(res);
    }
}

// --- Main Server Loop ---

static void lsp_loop(void) {
    Log("LSP loop started.\n");

    // The main buffer to read the Content-Length header
    char header[128];
    // The main buffer for the JSON payload. Needs to be large enough for
    // typical messages.
    size_t clen = 6143;
    char *content = (char *)malloc(clen + 1);

    // Server loop: continuously read messages from stdin
    while (1) {
        size_t content_length = 0;
        // char *header_end = NULL;

        // 1. Read Content-Length Header
        // Read header line by line until we find Content-Length:
        if (fgets(header, 127, stdin) == NULL)
            break;

        if (sscanf(header, "Content-Length: %zu", &content_length) != 1) {
            // Error handling for missing/malformed header.
            // For a simple server, we might just continue or break.
            fprintf(stderr, "Malformed header: %s", header);
            fflush(stderr);
            continue;
        }
        if (content_length >= clen) {
            free(content);
            clen = content_length + 1024;
            content = (char *)malloc(clen + 1);
        }

        // 2. Consume the remaining headers until the blank line (\r\n\r\n)
        // We expect Content-Type: application/json\r\n and then \r\n
        do {
            if (fgets(header, 127, stdin) == NULL)
                break;
            // The blank line is just "\r\n" or "\n" depending on environment,
            // but we check for the line being effectively empty.
            if (header[0] == '\r' || header[0] == '\n')
                break;
        } while (1);

        // 3. Read the JSON payload
        if (content_length > 0) {
            size_t bytes_read = fread(content, 1, content_length, stdin);
            content[bytes_read] = '\0';
            if (bytes_read != content_length) {
                fprintf(stderr, "wrong content length: %zu x %zu",
                        content_length, bytes_read);
                fflush(stderr);
            }

            // JSON parsing
            Log("\x1b[36mJSON received\x1b[0m:\n%s\n", content);

            // Find the start position of all fields that we may need
            char *method = strstr(content, "\"method\":\"");
            char *id = strstr(content, "\"id\":");
            char *params = strstr(content, "\"params\":{");

            if (!method) {
                fprintf(stderr, "Error: method not defined\n");
                fflush(stderr);
                break;
            }

            cut_json_str(&method, 10);

            if (id) {
                cut_json_int(&id, 5);
                add_active_request(id);
            }

            // Route the request based on the method
            if (strcmp(method, "textDocument/completion") == 0) {
                handle_completion(id, params);
            } else if (strcmp(method, "exeRnvimCmd") == 0) {
                handle_exe_cmd(params);
            } else if (strcmp(method, "completionItem/resolve") == 0) {
                handle_resolve(id, params);
            } else if (strcmp(method, "textDocument/hover") == 0) {
                handle_hover(id);
            } else if (strcmp(method, "textDocument/signatureHelp") == 0) {
                handle_signature(id);
            } else if (strcmp(method, "textDocument/definition") == 0) {
                handle_definition(id);
            } else if (strcmp(method, "textDocument/documentSymbol") == 0) {
                handle_document_symbols(id);
            } else if (strcmp(method, "textDocument/references") == 0) {
                handle_references(id);
            } else if (strcmp(method, "textDocument/implementation") == 0) {
                handle_implementation(id);
            } else if (strcmp(method, "initialize") == 0) {
                handle_initialize(id);
            } else if (strcmp(method, "initialized") == 0) {
                load_cached_data();
            } else if (strcmp(method, "$/cancelRequest") == 0) {
                Log("\x1b[31;1mCANCEL %s", id);
                rm_active_request(id);
            } else if (strcmp(method, "exit") == 0 ||
                       strcmp(method, "shutdown") == 0) {
                handle_exit(method);
            } else {
                fprintf(stderr, "Unhandled method: %s\n", method);
                fflush(stderr);
            }
        }
    }
}

int main(int argc, char **argv) {
#ifdef WIN32
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
    _setmode(_fileno(stdin), _O_BINARY);
#endif
#ifdef Debug_NRS
    init_logging();
#endif
    lsp_loop();
    return 0;
}
