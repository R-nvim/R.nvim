#include <signal.h> // Signal handling
#include <stdio.h>  // Standard input/output definitions
#include <stdlib.h> // Standard library
#include <string.h> // String handling functions
#ifdef WIN32
#include "rgui.h"
#endif

#include "data_structures.h"
#include "logging.h"
#include "complete.h"
#include "tcp.h"
#include "obbr.h"
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

    init_global_vars();
    init_obbr_vars();
    init_compl_vars();
    init_ds_vars();

    update_inst_libs();
    update_pkg_list(NULL);
    build_objls();

    // Finish immediately with SIGTERM
    signal(SIGTERM, handle_sigterm);

    printf("lua vim.g.R_Nvim_status = 3\n");
    fflush(stdout);

    Log("init() finished");
}

/*
 * TODO: Candidate for message_handling.c
 *
 * @desc: Used in main() for continuous processing of stdin commands
 */
void stdin_loop(void) {
    char line[1024];
    char *msg;
    char t;
    memset(line, 0, 1024);

    while (fgets(line, 1023, stdin)) {

        for (unsigned int i = 0; i < strlen(line); i++)
            if (line[i] == '\n' || line[i] == '\r')
                line[i] = 0;
        Log("stdin: %s", line);
        msg = line;
        switch (*msg) {
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
        case '5':
            msg++;
            char *id = msg;
            while (*msg != '\003')
                msg++;
            *msg = 0;
            msg++;
            if (*msg == '\004') {
                msg++;
                complete(id, msg, "\004", NULL, NULL);
            } else if (*msg == '\005') {
                msg++;
                char *base = msg;
                while (*msg != '\005')
                    msg++;
                *msg = 0;
                msg++;
                complete(id, base, msg, NULL, NULL);
            } else {
                complete(id, msg, NULL, NULL, NULL);
            }
            break;
        case '6':
            msg++;
            char *wrd = msg;
            while (*msg != '\002')
                msg++;
            *msg = 0;
            msg++;
            if (strstr(wrd, "::"))
                wrd = strstr(wrd, "::") + 2;
            resolve(wrd, msg);
            break;
        case '7':
            msg++;
            char *p = msg;
            while (*msg != '\002')
                msg++;
            *msg = 0;
            msg++;
            char *f = msg;
            while (*msg != '\002')
                msg++;
            *msg = 0;
            msg++;
            char *itm = msg;
            get_alias(&p, &f);
            if (p)
                resolve_arg_item(p, f, itm);
            break;
#ifdef WIN32
        case '8':
            // Messages related with the Rgui on Windows
            msg++;
            parse_rgui_msg(msg);
            break;
#endif
        case '9': // Quit now
            stop_server();
            exit(0);
            break;
        default:
            fprintf(stderr, "Unknown command received: [%d] %s\n", line[0],
                    msg);
            fflush(stderr);
            break;
        }
        memset(line, 0, 1024);
    }
}

int main(int argc, char **argv) {
    init();
#ifdef WIN32
    Windows_setup();
#endif
    stdin_loop();
    return 0;
}
