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

/*
 * Global variables (declared in global_vars.h)
 */

InstLibs *instlibs;    // Pointer to first installed library
PkgData *pkgList;      // Pointer to first package data
char *glbnv_buffer;    // Global environment buffer
char tmpdir[256];      // Temporary directory
int auto_obbr;         // Auto object browser flag
char localtmpdir[256]; // Local temporary directory

void print_listTree(ListStatus *root, FILE *f) {
    if (root != NULL) {
        fprintf(f, "%d :: %s\n", root->status, root->key);
        print_listTree(root->left, f);
        print_listTree(root->right, f);
    }
}

static void send_rns_info(void) {
    PkgData *pkg = pkgList;

    int ln = 9;
    int lv = 5;
    char fmt[64];
    while (pkg) {
        if (strlen(pkg->name) > ln)
            ln = strlen(pkg->name);
        if (strlen(pkg->version) > lv)
            lv = strlen(pkg->version);
        pkg = pkg->next;
    }
    sprintf(fmt, " [%%d, %%d, %%d, %%4d] %%%ds %%%ds %%s\x14", ln, lv);

    printf("lua require('r.server').echo_rns_info('doc_width: %d.\x14Loaded "
           "packages:\x14",
           get_doc_width());
    pkg = pkgList;
    while (pkg) {
        printf(fmt, pkg->to_build, pkg->built, pkg->loaded, pkg->nobjs,
               pkg->name, pkg->version, pkg->descr);
        pkg = pkg->next;
    }
    printf("')\n");
    fflush(stdout);
}

// --- LSP Communication Helper ---

/**
 * @brief Sends a JSON response with the necessary LSP headers (Content-Length
 * and Content-Type).
 * * @param content_length The length of the JSON payload in bytes.
 * @param json_payload The JSON string to send.
 */
void send_ls_response(const char *json_payload) {
#ifdef Debug_NRS
    Log("\x1b[33mSEND_LS_RESPONSE\x1b[0m (%" PRI_SIZET " bytes):",
        strlen(json_payload));
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
    fprintf(stdout, "Content-Length: %" PRI_SIZET "\r\n\r\n",
            strlen(json_payload));
    fprintf(stdout, "%s", json_payload);
    fflush(stdout);
}

void send_null(const char *req_id) {
    char res[128];
    snprintf(res, 127, "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":null}",
             req_id);
    send_ls_response(res);
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
        send_ls_response(exeCmd);
        free(exeCmd);
    }
    free(esccmd);
}

void send_menu_items(char *compl_items, const char *req_id) {
    if (strlen(compl_items) == 0) {
        send_null(req_id);
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
    send_ls_response(res);
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

    update_inst_libs();
    update_pkg_list(NULL);

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
                       "\",\":\",\"(\",\"@\",\"$\",\"\\\\\"]}");
    }

    str_cat(p, "}}}");

    // "\"allCommitCharacters\":[\" \",\"\n\",\",\"]}}}}";

    send_ls_response(res);
}

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
        } else if (*code == 'N') {
            char *id = strstr(params, "\"orig_id\":");
            cut_json_int(&id, 10);
            send_null(id);
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
            finished_building_objls();
            break;
        case '2':
            send_rns_info();
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

        if (sscanf(header, "Content-Length: %" PRI_SIZET, &content_length) !=
            1) {
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
                fprintf(stderr,
                        "wrong content length: %" PRI_SIZET " x %" PRI_SIZET,
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
            cut_json_int(&id, 5);

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
            } else if (strcmp(method, "initialize") == 0) {
                handle_initialize(id);
            } else if (strcmp(method, "initialized") == 0) {
                build_objls();
            } else if (strcmp(method, "$/cancelRequest") == 0) {
                Log("method not implemented: $/cancelRequest");
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
    lsp_loop();
    return 0;
}
