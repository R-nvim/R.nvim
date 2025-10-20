#include <signal.h> // Signal handling
#include <stdio.h>  // Standard input/output definitions
#include <stdlib.h> // Standard library
#include <string.h> // String handling functions
#include <unistd.h> // For read/write in a more robust server environment

#include "data_structures.h"
#include "logging.h"
#include "complete.h"
#include "tcp.h"
#include "obbr.h"
#include "lsp.h"
#include "utilities.h"
#include "../common.h"

/*
 * Global variables (declared in global_vars.h)
 */

InstLibs *instlibs;                       // Pointer to first installed library
PkgData *pkgList;                         // Pointer to first package data
char *compl_buffer;                       // Completion buffer
char *glbnv_buffer;                       // Global environment buffer
char compldir[256];                       // Directory for completion files
char tmpdir[256];                         // Temporary directory
int auto_obbr;                            // Auto object browser flag
unsigned long compl_buffer_size = 163840; // Completion buffer size
char localtmpdir[256];                    // Local temporary directory
char request_id[16] = {0};

// Signal handler for SIGTERM
static void handle_sigterm(__attribute__((unused)) int s) { exit(0); }

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

static void init_global_vars(void) {
    strncpy(compldir, getenv("RNVIM_COMPLDIR"), 255);
    strncpy(tmpdir, getenv("RNVIM_TMPDIR"), 255);

    if (getenv("RNVIM_LOCAL_TMPDIR")) {
        strncpy(localtmpdir, getenv("RNVIM_LOCAL_TMPDIR"), 255);
    } else {
        strncpy(localtmpdir, getenv("RNVIM_TMPDIR"), 255);
    }
    set_max_depth(atoi(getenv("RNVIM_MAX_DEPTH")));

    compl_buffer = calloc(compl_buffer_size, sizeof(char));
}

/*
 * @desc: used before stdin_loop() in main() to initialize the server.
 */
static void init(void) {
#ifdef Debug_NRS
    init_logging();
#endif

    // Finish immediately with SIGTERM
    signal(SIGTERM, handle_sigterm);

    init_global_vars();
    init_obbr_vars();
    init_ds_vars();

    update_inst_libs();
    update_pkg_list(NULL);
    build_objls();

    send_cmd_to_nvim("vim.g.R_Nvim_status = 3");
    Log("init() finished");
}

// --- LSP Communication Helper ---

/**
 * @brief Sends a JSON response with the necessary LSP headers (Content-Length
 * and Content-Type).
 * * @param content_length The length of the JSON payload in bytes.
 * @param json_payload The JSON string to send.
 */
void send_ls_response(const char *json_payload) {
    Log("SEND_LS_RESPONSE:\n%s\n", json_payload);
    // 1. Send Content-Length header
    fprintf(stdout, "Content-Length: %zu\r\n\r\n", strlen(json_payload));

    // 2. Send Content-Type header (optional, but good practice)
    // fprintf(stdout, "Content-Type: application/json\r\n");

    // 3. Send the mandatory two newline characters to end the headers
    // fprintf(stdout, "\r\n");

    // 4. Send the JSON payload
    fprintf(stdout, "%s", json_payload);

    // Flush the standard output buffer to ensure the message is sent
    // immediately
    fflush(stdout);
}

void send_cmd_to_nvim(const char *cmd) {
    Log("LSP: CMD before:\n%s\n", cmd);
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

// --- LSP Request Handlers ---

/**
 * @brief Handles the 'initialize' request (LSP Handshake).
 * * @param request_id The ID from the client's request.
 */
void handle_initialize(const char *request_id) {
    const char *fmt =
        "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"capabilities\":{"
        "\"textDocumentSync\": 0,"
        "\"hoverProvider\": 1,"
        "\"completionProvider\": {"
        "\"resolveProvider\": 1,"
        "\"triggerCharacters\": [\".\",\" \",\":\",\"(\",\"@\",\"$\"],"
        "\"allCommitCharacters\": [\" \", \"\n\", \";\", \",\"]}}}}";

    char res[1024];
    sprintf(res, fmt, request_id);
    send_ls_response(res);
}

void send_item_doc(const char *doc, const char *id, const char *label,
                   const char *kind) {
    const char *fmt =
        "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"label\":\"%s\",\"kind\":"
        "\"%s\",\"documentation\":{\"kind\":\"markdown\",\"value\":\"%s\"}}}";

    char *edoc = esc_json(doc);
    size_t len = strlen(edoc);
    char *res = (char *)malloc(sizeof(char) * len + 128);
    sprintf(res, fmt, request_id, label, kind, edoc);

    send_ls_response(res);
    free(res);
    free(edoc);
}

void send_menu_items(const char *compl_items, const char *req_id) {
    const char *fmt =
        "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"isIncomplete\":0,\"is_"
        "incomplete_forward\":0,\"is_incomplete_backward\":1,\"items\":[%s]}}";

    size_t len = strlen(compl_items);
    char *res = (char *)malloc(sizeof(char) * len + 128);
    sprintf(res, fmt, req_id, compl_items);
    send_ls_response(res);
    free(res);
}

void handle_exe_cmd(char *code) {
    Log("handle_exe_cmd: >>>%s<<<\n", code);
    char *msg;
    char t;
    msg = code;
    // TODO: use letters instead of number?
    switch (*msg) {
    case 'C':
        Log("Case C: %s", msg);
        msg++;
        if (*msg == 'H')
            complete_rhelp(++msg);
        else if (*msg == 'C')
            complete_rmd_chunk(++msg);
        else if (*msg == 'B')
            complete_quarto_block(++msg);
        break;
    case '1': // Start server and wait nvimcom connection
        start_server();
        break;
    case '2': // Send message
        msg++;
        send_to_nvimcom(msg);
        break;
    case '3':
        msg++;
        switch (*msg) {
        case '1': // Update GlobalEnv
            auto_obbr = 1;
            compl2ob();
            break;
        case '2': // Update Libraries
            auto_obbr = 1;
            lib2ob();
            break;
        case '3': // Open/Close list
            msg++;
            t = *msg;
            msg++;
            toggle_list_status(msg);
            if (t == 'G')
                compl2ob();
            else
                lib2ob();
            break;
        case '4': // Close/Open all
            msg++;
            if (*msg == 'O')
                change_all(1);
            else
                change_all(0);
            msg++;
            if (*msg == 'G')
                compl2ob();
            else
                lib2ob();
            break;
        }
        break;
    case '4': // Miscellaneous commands
        msg++;
        switch (*msg) {
        case '1':
            msg++;
            if (*msg)
                set_doc_width(msg);
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
        case '5':
            msg++;
            set_doc_width(msg);
            break;
        }
        break;
    case '5': // format: "id|Tword[|arg]"
        msg++;
        complete(msg);
        break;
    case '6':
        msg++;
        resolve(msg);
        break;
    case '7':
        msg++;
        resolve_arg_item(msg);
        break;
    case '9': // Quit now
        stop_server();
        exit(0);
        break;
    default:
        fprintf(stderr, "Unknown command received: [%d] %s\n", code[0], msg);
        fflush(stderr);
        break;
    }
}

/**
 * @brief Handles the 'exit' notification to shut down the server.
 */
void handle_exit(void) {
    Log("LSP: Received exit notification. Shutting down.\n");
    exit(0);
}

// --- Main Server Loop ---

void lsp_loop(void) {
    Log("LSP loop started.\n");

    // The main buffer to read the Content-Length header
    char header[128];
    // The main buffer for the JSON payload. Needs to be large enough for
    // typical messages.
    char content[8192];

    // Server loop: continuously read messages from stdin
    while (1) {
        long content_length = 0;
        // char *header_end = NULL;

        // 1. Read Content-Length Header
        // Read header line by line until we find Content-Length:
        if (fgets(header, sizeof(header), stdin) == NULL)
            break;

        if (sscanf(header, "Content-Length: %ld", &content_length) != 1) {
            // Error handling for missing/malformed header.
            // For a simple server, we might just continue or break.
            Log("LSP: Malformed header: %s", header);
            continue;
        }

        // 2. Consume the remaining headers until the blank line (\r\n\r\n)
        // We expect Content-Type: application/json\r\n and then \r\n
        do {
            if (fgets(header, sizeof(header), stdin) == NULL)
                break;
            // The blank line is just "\r\n" or "\n" depending on environment,
            // but we check for the line being effectively empty.
            if (header[0] == '\r' || header[0] == '\n')
                break;
        } while (1);

        // 3. Read the JSON payload
        if (content_length > 0 && content_length < sizeof(content)) {
            // Read exactly content_length bytes into the content buffer
            size_t bytes_read = fread(content, 1, content_length, stdin);
            content[bytes_read] = '\0'; // Null-terminate the JSON string

            // For debugging: print the raw request to stderr (Neovim log)
            Log("LSP: Received request (%zu bytes):\n%s\n", bytes_read,
                content);

            // --- Minimal JSON Parsing / Method Routing ---

            // Find the method and ID using simple string search (no real JSON
            // parsing)

            const char *method_start = strstr(content, "\"method\":\"");
            const char *id_start = strstr(content, "\"id\":");

            char method[100] = {0};

            if (method_start) {
                // Extract method name
                sscanf(method_start + 10, "%99[^\"]", method);
            }

            if (id_start) {
                // Extract request ID (assumes it's an integer for simplicity)
                sscanf(id_start + 5, "%15[^,}]", request_id);
            }

            // Route the request based on the method
            if (strcmp(method, "textDocument/completion") == 0) {
                char *position = strstr(content, "\"position\":{") + 11;
                if (!position)
                    continue;
                const char *line = strstr(position, "\"line\":");
                const char *col = strstr(position, "\"character\":");
                if (!line || !col)
                    continue;

                char line_str[16] = {0};
                char col_str[16] = {0};
                sscanf(line + 7, "%8[^,}]", line_str);
                sscanf(col + 12, "%8[^,}]", col_str);
                char compl_command[128];
                snprintf(compl_command, 127,
                         "require('r.lsp').complete('%s', %s, %s)", request_id,
                         line_str, col_str);
                send_cmd_to_nvim(compl_command);
            } else if (strcmp(method, "exeRnvimCmd") == 0) {
                char *code_start = strstr(content, "{\"code\":\"") + 9;
                for (int i = 0; i < 1024; i++) {
                    if (code_start[i] == '"') {
                        code_start[i] = '\0';
                        break;
                    }
                }
                handle_exe_cmd(code_start);
            } else if (strcmp(method, "completionItem/resolve") == 0) {
                char *params_start = strstr(content, "\"params\":{");
                if (!params_start)
                    continue;
                char *p = params_start + 9;
                size_t j = 1;
                int n_braces = 1;
                while (n_braces > 0 && j < 900) {
                    if (p[j] == '{')
                        n_braces++;
                    else if (p[j] == '}')
                        n_braces--;
                    j++;
                }
                p[j] = '\0';
                char compl_command[1024];
                snprintf(compl_command, 1024,
                         "require('r.lsp').resolve('%s', '%s')", request_id, p);
                send_cmd_to_nvim(compl_command);
            } else if (strcmp(method, "initialize") == 0) {
                handle_initialize(request_id);
            } else if (strcmp(method, "initialized") == 0) {
                init();
            } else if (strcmp(method, "exit") == 0) {
                handle_exit();
            } else {
                Log("LSP: Unhandled method: %s\n", method);
            }

        } else {
            Log("Error reading content or invalid length:\n%s\n%s", header,
                content);
        }
    }
}

int main(int argc, char **argv) {
    lsp_loop();
    // stdin_loop();
    return 0;
}
