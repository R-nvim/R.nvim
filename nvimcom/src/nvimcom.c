#include <R.h> /* to include Rconfig.h */
#include <Rdefines.h>
#include <Rinternals.h>
#include <R_ext/Parse.h>
#ifndef WIN32
#define HAVE_SYS_SELECT_H
#include <R_ext/eventloop.h>
#endif

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>

#ifdef __FreeBSD__
#include <netinet/in.h>
#endif

#include <unistd.h>

#ifdef WIN32
#include <process.h>
#include <winsock2.h>
#ifdef _WIN64
#include <inttypes.h>
#endif
#else
#include <arpa/inet.h> // inet_addr()
#include <netdb.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <sys/socket.h>
#endif

#ifndef WIN32
// Needed to know what is the prompt
#include <Rinterface.h>
#define R_INTERFACE_PTRS 1
extern int (*ptr_R_ReadConsole)(const char *, unsigned char *, int, int);
static int (*save_ptr_R_ReadConsole)(const char *, unsigned char *, int, int);
static int debugging;           // Is debugging a function now?
LibExtern SEXP R_SrcfileSymbol; // R internal variable defined in Defn.h.
static void SrcrefInfo(void);
#endif

static int debug_r; // Should detect when `browser()` is running and start
                    // debugging mode?
#include "common.h"

static int initialized = 0; // TCP client successfully connected to the server.

static int verbose = 0;  // 1: version number; 2: initial information; 3: TCP in
                         // and out; 4: more verbose; 5: really verbose.
static int allnames = 0; // Show hidden objects in auto completion and
                         // Object Browser?
static int nlibs = 0;    // Number of loaded libraries.

static char rns_port[16]; // rnvimserver port.
static char nvimsecr[32]; // Random string used to increase the safety of TCP
                          // communication.

static char *glbnvbuf1;   // Temporary buffer used to store the list of
                          // .GlobalEnv objects.
static char *glbnvbuf2;   // Temporary buffer used to store the list of
                          // .GlobalEnv objects.
static char *send_ge_buf; // Temporary buffer used to store the list of
                          // .GlobalEnv objects.

static unsigned long lastglbnvbsz;         // Previous size of glbnvbuf2.
static unsigned long glbnvbufsize = 32768; // Current size of glbnvbuf2.

static size_t tcp_header_len; // Length of nvimsecr + 9. Stored in a
                              // variable to avoid repeatedly calling
                              // strlen().

static double timelimit =
    100.0; // Maximum acceptable time to build list of .GlobalEnv objects
static int sizelimit = 1000000; // Maximum acceptable size of string
                                // representing .GlobalEnv (list of objects)
static int maxdepth = 12; // How many levels to parse in lists and S4 objects
// when building list of objects for auto-completion. The value decreases if
// the listing is too slow.
static int curdepth = 0; // Current level of the list or S4 object being parsed
                         // for auto-completion.
static int autoglbenv = 0; // Should the list of objects in .GlobalEnv be
// automatically updated after each top level command is executed? It will
// always be 2 if cmp-r is installed; otherwise, it will be 1 if the Object
// Browser is open.

static char tmpdir[512]; // The environment variable RNVIM_TMPDIR.
static int setwidth = 0; // Set the option width after each command is executed
static int oldcolwd = 0; // Last set width.

#ifdef WIN32
static int r_is_busy = 1; // Is R executing a top level command? R memory will
// become corrupted and R will crash afterwards if we execute a function that
// creates R objects while R is busy.
#else
static int fired = 0; // Do we have commands waiting to be executed?
static int ifd;       // input file descriptor
static int ofd;       // output file descriptor
static InputHandler *ih;
static char flag_eval[512]; // Do we have an R expression to evaluate?
static int flag_glbenv = 0; // Do we have to list objects from .GlobalEnv?
static int flag_debug = 0;  // Do we need to get file name and line information
                            // of debugging function?
#endif

/**
 * @typedef lib_info_
 * @brief Structure with name and version number of a library.
 *
 * The complete information of libraries is stored in its `objls_`, `alias_`,
 * and `args_` files in the R.nvim cache directory. The rnvimserver only needs
 * the name and version number of the library to read the corresponding files.
 *
 */
typedef struct lib_info_ {
    char *name;
    char *version;
    unsigned long strlen;
    struct lib_info_ *next;
} LibInfo;

static LibInfo *libList; // Linked list of loaded libraries information (names
                         // and version numbers).

static void nvimcom_checklibs(void);
static void send_to_nvim(char *msg);
static void nvimcom_eval_expr(const char *buf);

#ifdef WIN32
SOCKET sfd; // File descriptor of socket used in the TCP connection with the
            // rnvimserver.
static HANDLE tid; // Identifier of thread running TCP connection loop.
extern void Rconsolecmd(char *cmd); // Defined in R: src/gnuwin32/rui.c.
#else
static int sfd = -1;  // File descriptor of socket used in the TCP connection
                      // with the rnvimserver.
static pthread_t tid; // Identifier of thread running TCP connection loop.
#endif

static void escape_str(char *s) {
    while (*s) {
        if (*s == '\n') // It would prematurely send the string
            *s = ' ';
        if (*s == '\x5c') // Backslash is misinterpreted by Lua
            *s = '\x12';
        if (*s == '\'') // Single quote prematurely finishes strings
            *s = '\x13';
        s++;
    }
}

SEXP fmt_txt(SEXP txt, SEXP delim, SEXP nl) {
    const char *s = CHAR(STRING_ELT(txt, 0));
    const char *d = CHAR(STRING_ELT(delim, 0));
    const char *n = CHAR(STRING_ELT(nl, 0));
    char *b = calloc(strlen(s) + 1, sizeof(char));
    format(s, b, d[0], n[0]);
    SEXP ans = R_NilValue;
    PROTECT(ans = NEW_CHARACTER(1));
    SET_STRING_ELT(ans, 0, mkChar(b));
    UNPROTECT(1);
    free(b);
    return ans;
}

SEXP fmt_usage(SEXP fnm, SEXP args) {
    const char *f = CHAR(STRING_ELT(fnm, 0));
    const char *a = CHAR(STRING_ELT(args, 0));
    char *b = format_usage(f, a);
    SEXP ans = R_NilValue;
    PROTECT(ans = NEW_CHARACTER(1));
    SET_STRING_ELT(ans, 0, mkChar(b));
    UNPROTECT(1);
    free(b);
    return ans;
}

/**
 * @brief Replace buffers used to store auto-completion information with
 * bigger ones.
 *
 * @return Pointer to the NULL terminating byte of glbnvbuf2.
 */
static char *nvimcom_grow_buffers(void) {
    lastglbnvbsz = glbnvbufsize;
    glbnvbufsize += 32768;

    char *tmp = (char *)calloc(glbnvbufsize, sizeof(char));
    strcpy(tmp, glbnvbuf1);
    free(glbnvbuf1);
    glbnvbuf1 = tmp;

    tmp = (char *)calloc(glbnvbufsize, sizeof(char));
    strcpy(tmp, glbnvbuf2);
    free(glbnvbuf2);
    glbnvbuf2 = tmp;

    tmp = (char *)calloc(glbnvbufsize + 64, sizeof(char));
    free(send_ge_buf);
    send_ge_buf = tmp;

    return (glbnvbuf2 + strlen(glbnvbuf2));
}

/**
 * @brief Send string to rnvimserver.
 *
 * The function sends a string to rnvimserver through the TCP connection
 * established at `nvimcom_Start()`.
 *
 * @param msg The message to be sent.
 */
static void send_to_nvim(char *msg) {
    if (sfd == -1)
        return;

    size_t sent;
    char b[64];
    size_t len;

    if (verbose > 2) {
        if (strlen(msg) < 128)
#ifdef WIN32
            REprintf("send_to_nvim [%lld] {%s}: %s\n", sfd, nvimsecr, msg);
#else
            REprintf("send_to_nvim [%d] {%s}: %s\n", sfd, nvimsecr, msg);
#endif
    }

    len = strlen(msg);

    /*
       TCP message format:
         RNVIM_SECRET : Prefix RNVIM_SECRET to msg to increase security
         000000000    : Size of message in 9 digits
         msg          : The message
         \x11         : Final byte

       Notes:

       - The string is terminated by a final \x11 byte which hopefully is never
         used in any R code. It would be slower to escape special characters.

       - The time to save the file at /dev/shm is bigger than the time to send
         the buffer through a TCP connection.

       - When the msg is very big, it's faster to send the final message in
         three pieces than to call snprintf() to assemble everything in a
         single string.
    */

    // Send the header
    snprintf(b, 63, "%s%09zu", nvimsecr, len);
    sent = send(sfd, b, tcp_header_len, 0);
    if (sent != tcp_header_len) {
        if (sent == -1)
            REprintf("Error sending message header to R.nvim: -1\n");
        else
            REprintf("Error sending message header to R.nvim: %zu x %zu\n",
                     tcp_header_len, sent);
#ifdef WIN32
        closesocket(sfd);
        WSACleanup();
#else
        close(sfd);
#endif
        sfd = -1;
        strcpy(rns_port, "0");
        return;
    }

    // based on code found on php source
    // Send the message
    char *pCur = msg;
    char *pEnd = msg + len;
    int loop = 0;
    while (pCur < pEnd) {
        sent = send(sfd, pCur, pEnd - pCur, 0);
        if (sent >= 0) {
            pCur += sent;
        } else if (sent == -1) {
            REprintf("Error sending message to R.nvim: %zu x %zu\n", len,
                     pCur - msg);
            return;
        }
        loop++;
        if (loop == 100) {
            // The goal here is to avoid infinite loop.
            // TODO: Maybe delete this check because php code does not have
            // something similar
            REprintf("Too many attempts to send message to R.nvim: %zu x %zu\n",
                     len, sent);
            return;
        }
    }

    // End the message with \x11
    sent = send(sfd, "\x11", 1, 0);
    if (sent != 1)
        REprintf("Error sending final byte to R.nvim: 1 x %zu\n", sent);
}

/**
 * @brief Function called by R code to send message to rnvimserver.
 *
 * @param cmd The message to be sent.
 */
void nvimcom_msg_to_nvim(char **cmd) { send_to_nvim(*cmd); }

/**
 * @brief Escape single quotes.
 *
 * We use single quotes to define strings to be sent to Neovim. Consequently,
 * single quotes within such strings must be escaped to avoid Lua errors
 * when evaluating the string.
 *
 * @param buf Original string.
 * @param buf2 Destination buffer of the new string with escaped quotes.
 * @param bsize Size limit of destination buffer.
 */
static void nvimcom_squo(const char *buf, char *buf2, int bsize) {
    int i = 0, j = 0;
    while (j < bsize) {
        if (buf[i] == '\'') {
            buf2[j] = '\\';
            j++;
            buf2[j] = '\'';
        } else if (buf[i] == 0) {
            buf2[j] = 0;
            break;
        } else {
            buf2[j] = buf[i];
        }
        i++;
        j++;
    }
}

/**
 * @brief Quote strings with backticks.
 *
 * The names of R objects that are invalid to be inserted directly in the
 * console must be quoted with backticks.
 *
 * @param b1 Name to be quoted.
 * @param b2 Destination buffer to the quoted name.
 */
static void nvimcom_backtick(const char *b1, char *b2) {
    int i = 0, j = 0;
    while (i < 511 && b1[i] != '$' && b1[i] != '@' && b1[i] != 0) {
        if (b1[i] == '[' && b1[i + 1] == '[') {
            b2[j] = '[';
            i++;
            j++;
            b2[j] = '[';
            i++;
            j++;
        } else {
            b2[j] = '`';
            j++;
        }
        while (i < 511 && b1[i] != '$' && b1[i] != '@' && b1[i] != '[' &&
               b1[i] != 0) {
            b2[j] = b1[i];
            i++;
            j++;
        }
        if (b1[i - 1] != ']') {
            b2[j] = '`';
            j++;
        }
        if (b1[i] == 0)
            break;
        if (b1[i] != '[') {
            b2[j] = b1[i];
            i++;
            j++;
        }
    }
    b2[j] = 0;
}

/**
 * @brief Creates a new LibInfo structure to store the name and version
 * number of a library
 *
 * @param nm Name of the library.
 * @param vrsn Version number of the library.
 * @return Pointer to the new LibInfo structure.
 */
static LibInfo *nvimcom_lib_info_new(const char *nm, const char *vrsn) {
    LibInfo *pi = calloc(1, sizeof(LibInfo));
    pi->name = malloc((strlen(nm) + 1) * sizeof(char));
    strcpy(pi->name, nm);
    pi->version = malloc((strlen(vrsn) + 1) * sizeof(char));
    strcpy(pi->version, vrsn);
    pi->strlen = strlen(pi->name) + strlen(pi->version) + 2;
    return pi;
}

/**
 * @brief Adds a new LibInfo structure to libList, the linked list of loaded
 * libraries.
 *
 * @param nm The name of the library
 * @param vrsn The version number of the library
 */
static void nvimcom_lib_info_add(const char *nm, const char *vrsn) {
    LibInfo *pi = nvimcom_lib_info_new(nm, vrsn);
    if (libList) {
        pi->next = libList;
        libList = pi;
    } else {
        libList = pi;
    }
}

/**
 * @brief Returns a pointer to information on an library.
 *
 * @param nm Name of the library.
 * @return Pointer to a LibInfo structure with information on the library
 * `nm`.
 */
static LibInfo *nvimcom_get_lib(const char *nm) {
    if (!libList)
        return NULL;

    LibInfo *pi = libList;
    do {
        if (strcmp(pi->name, nm) == 0)
            return pi;
        pi = pi->next;
    } while (pi);

    return NULL;
}

/**
 * @brief This function adds a line with information for
 * auto-completion.
 *
 * @param x Object whose information is to be generated.
 *
 * @param xname The name of the object.
 *
 * @param curenv Current "environment" of object x. If x is an element of a list
 * or S4 object, `curenv` will be the representation of the parent structure.
 * Example: for `x` in `alist$aS4obj@x`, `curenv` will be `alist$aS4obj@`.
 *
 * @param p A pointer to the current NULL byte terminating the glbnvbuf2
 * buffer.
 *
 * @param depth Current number of levels in lists and S4 objects.
 *
 * @return The pointer p updated after the insertion of the new line.
 */
static char *nvimcom_glbnv_line(SEXP *x, const char *xname, const char *curenv,
                                char *p, int depth) {
    if (depth > maxdepth)
        return p;

    if (depth > curdepth)
        curdepth = depth;

    int xgroup = 0; // 1 = function, 2 = data.frame, 3 = list, 4 = s4
    char ebuf[64];
    int len = 0;
    SEXP txt, lablab;
    SEXP sn = R_NilValue;
    char buf[576];
    char bbuf[512];

    if ((strlen(glbnvbuf2 + lastglbnvbsz)) > 31744)
        p = nvimcom_grow_buffers();

    p = str_cat(p, curenv);
    snprintf(ebuf, 63, "%s", xname);
    escape_str(ebuf);
    p = str_cat(p, ebuf);

    if (Rf_isLogical(*x)) {
        p = str_cat(p, "\006%\006");
    } else if (Rf_isNumeric(*x)) {
        p = str_cat(p, "\006{\006");
    } else if (Rf_isFactor(*x)) {
        p = str_cat(p, "\006!\006");
    } else if (Rf_isValidString(*x)) {
        p = str_cat(p, "\006~\006");
    } else if (Rf_isFunction(*x)) {
        p = str_cat(p, "\006(\006");
        xgroup = 1;
    } else if (Rf_isFrame(*x)) {
        p = str_cat(p, "\006$\006");
        xgroup = 2;
    } else if (Rf_isNewList(*x)) {
        p = str_cat(p, "\006[\006");
        xgroup = 3;
    } else if (Rf_isS4(*x)) {
        p = str_cat(p, "\006<\006");
        xgroup = 4;
    } else if (Rf_isEnvironment(*x)) {
        p = str_cat(p, "\006:\006");
    } else if (TYPEOF(*x) == PROMSXP) {
        p = str_cat(p, "\006&\006");
    } else {
        p = str_cat(p, "\006*\006");
    }

    // Specific class of object, if any
    PROTECT(txt = getAttrib(*x, R_ClassSymbol));
    if (!isNull(txt)) {
        p = str_cat(p, CHAR(STRING_ELT(txt, 0)));
    }
    UNPROTECT(1);

    p = str_cat(p, "\006.GlobalEnv\006");

    if (xgroup == 1) {
        /* It would be necessary to port args2buff() from src/main/deparse.c to
           here but it's too big. So, it's better to call nvimcom:::nvim.args()
           during auto completion. FORMALS() may return an object that will
           later crash R:
           https://github.com/jalvesaq/Nvim-R/issues/543#issuecomment-748981771
         */
        p = str_cat(p, ">not_checked<");
    }

    // Add label
    PROTECT(lablab = allocVector(STRSXP, 1));
    SET_STRING_ELT(lablab, 0, mkChar("label"));
    PROTECT(txt = getAttrib(*x, lablab));
    if (length(txt) > 0) {
        if (Rf_isValidString(txt)) {
            snprintf(buf, 159, "\006\006%s", CHAR(STRING_ELT(txt, 0)));
            escape_str(buf);
            p = str_cat(p, buf);
        } else {
            p = str_cat(p, "\006\006Error: label is not a valid string.");
        }
    } else {
        p = str_cat(p, "\006\006");
    }
    UNPROTECT(2);

    // Add the object length
    if (xgroup == 2) {
        snprintf(buf, 127, " [%d, %d]", length(Rf_GetRowNames(*x)), length(*x));
        p = str_cat(p, buf);
    } else if (xgroup == 3) {
        snprintf(buf, 127, " [%d]", length(*x));
        p = str_cat(p, buf);
    } else if (xgroup == 4) {
        SEXP cmdSexp, cmdexpr;
        ParseStatus status;
        snprintf(buf, 575, "%s%s", curenv, xname);
        nvimcom_backtick(buf, bbuf);
        snprintf(buf, 575, "slotNames(%s)", bbuf);
        PROTECT(cmdSexp = allocVector(STRSXP, 1));
        SET_STRING_ELT(cmdSexp, 0, mkChar(buf));
        PROTECT(cmdexpr = R_ParseVector(cmdSexp, -1, &status, R_NilValue));
        if (status == PARSE_OK) {
            int er = 0;
            PROTECT(sn = R_tryEval(VECTOR_ELT(cmdexpr, 0), R_GlobalEnv, &er));
            if (er)
                REprintf("nvimcom error executing command: slotNames(%s%s)\n",
                         curenv, xname);
            else
                len = length(sn);
            UNPROTECT(1);
        } else {
            REprintf("nvimcom error: invalid value in slotNames(%s%s)\n",
                     curenv, xname);
        }
        UNPROTECT(2);
        snprintf(buf, 127, " [%d]", len);
        p = str_cat(p, buf);
    }

    // finish the line
    p = str_cat(p, "\006\n");

    if (xgroup > 1) {
        char newenv[576];
        SEXP elmt = R_NilValue;
        const char *ename;

        if (xgroup == 4) {
            snprintf(newenv, 575, "%s%s@", curenv, xname);
            if (len > 0) {
                for (int i = 0; i < len; i++) {
                    ename = CHAR(STRING_ELT(sn, i));
                    PROTECT(elmt = R_do_slot(*x, Rf_install(ename)));
                    p = nvimcom_glbnv_line(&elmt, ename, newenv, p, depth + 1);
                    UNPROTECT(1);
                }
            }
        } else {
            SEXP listNames;
            snprintf(newenv, 575, "%s%s$", curenv, xname);
            PROTECT(listNames = getAttrib(*x, R_NamesSymbol));
            len = length(listNames);
            if (len == 0) { /* Empty list? */
                int len1 = length(*x);
                if (len1 > 0) { /* List without names */
                    len1 -= 1;
                    if (newenv[strlen(newenv) - 1] == '$')
                        newenv[strlen(newenv) - 1] = 0; // Delete trailing '$'
                    for (int i = 0; i < len1; i++) {
                        snprintf(ebuf, 63, "[[%d]]", i + 1);
                        elmt = VECTOR_ELT(*x, i);
                        p = nvimcom_glbnv_line(&elmt, ebuf, newenv, p,
                                               depth + 1);
                    }
                    snprintf(ebuf, 63, "[[%d]]", len1 + 1);
                    PROTECT(elmt = VECTOR_ELT(*x, len1));
                    p = nvimcom_glbnv_line(&elmt, ebuf, newenv, p, depth + 1);
                    UNPROTECT(1);
                }
            } else { /* Named list */
                SEXP eexp;
                len -= 1;
                for (int i = 0; i < len; i++) {
                    PROTECT(eexp = STRING_ELT(listNames, i));
                    ename = CHAR(eexp);
                    UNPROTECT(1);
                    if (ename[0] == 0) {
                        snprintf(ebuf, 63, "[[%d]]", i + 1);
                        ename = ebuf;
                    }
                    PROTECT(elmt = VECTOR_ELT(*x, i));
                    p = nvimcom_glbnv_line(&elmt, ename, newenv, p, depth + 1);
                    UNPROTECT(1);
                }
                ename = CHAR(STRING_ELT(listNames, len));
                if (ename[0] == 0) {
                    snprintf(ebuf, 63, "[[%d]]", len + 1);
                    ename = ebuf;
                }
                PROTECT(elmt = VECTOR_ELT(*x, len));
                p = nvimcom_glbnv_line(&elmt, ename, newenv, p, depth + 1);
                UNPROTECT(1);
            }
            UNPROTECT(1); /* listNames */
        }
    }
    return p;
}

/**
 * @brief Send to R.nvim the string containing the list of objects in
 * .GlobalEnv.
 */
static void send_glb_env(void) {
    clock_t t1;

    t1 = clock();

    strcpy(send_ge_buf, "+G");
    strcat(send_ge_buf, glbnvbuf2);
    send_to_nvim(send_ge_buf);

    if (verbose > 3)
        REprintf("Time to send message to R.nvim: %f\n",
                 1000 * ((double)clock() - t1) / CLOCKS_PER_SEC);

    char *tmp = glbnvbuf1;
    glbnvbuf1 = glbnvbuf2;
    glbnvbuf2 = tmp;
}

/**
 * @brief Generate a list of objects in .GlobalEnv and store it in the
 * glbnvbuf2 buffer. The string stored in glbnvbuf2 represents a file with the
 * same format of the `objls_` files in R.nvim's cache directory.
 */
static void nvimcom_globalenv_list(void) {
    if (verbose > 4)
        REprintf("nvimcom_globalenv_list()\n");
    const char *varName;
    SEXP envVarsSEXP, varSEXP;

    if (tmpdir[0] == 0)
        return;

    double tm = clock();

    memset(glbnvbuf2, 0, glbnvbufsize);
    char *p = glbnvbuf2;

    curdepth = 0;

    PROTECT(envVarsSEXP = R_lsInternal(R_GlobalEnv, allnames));
    for (int i = 0; i < Rf_length(envVarsSEXP); i++) {
        varName = CHAR(STRING_ELT(envVarsSEXP, i));
        if (R_BindingIsActive(Rf_install(varName), R_GlobalEnv)) {
            // See: https://github.com/jalvesaq/Nvim-R/issues/686
            PROTECT(varSEXP = R_ActiveBindingFunction(Rf_install(varName),
                                                      R_GlobalEnv));
        } else {
            PROTECT(varSEXP = Rf_findVar(Rf_install(varName), R_GlobalEnv));
        }
        if (varSEXP != R_UnboundValue) {
            // should never be unbound
            p = nvimcom_glbnv_line(&varSEXP, varName, "", p, 0);
        } else {
            REprintf("nvimcom_globalenv_list: Unexpected R_UnboundValue.\n");
        }
        UNPROTECT(1);
    }
    UNPROTECT(1);

    size_t len1 = strlen(glbnvbuf1);
    size_t len2 = strlen(glbnvbuf2);
    int changed = len1 != len2;
    if (verbose > 4)
        REprintf("globalenv_list(0) len1 = %zu, len2 = %zu\n", len1, len2);
    if (!changed) {
        for (int i = 0; i < len1; i++) {
            if (glbnvbuf1[i] != glbnvbuf2[i]) {
                changed = 1;
                break;
            }
        }
    }

    if (changed)
        send_glb_env();

    double tmdiff = 1000 * ((double)clock() - tm) / CLOCKS_PER_SEC;
    if (tmdiff > timelimit || strlen(glbnvbuf1) > sizelimit) {
        maxdepth = curdepth - 1;
        char b[16];
        snprintf(b, 15, "+D%d", maxdepth);
        send_to_nvim(b);
        if (verbose)
            REprintf(
                "nvimcom:\n"
                "    Time to build list of objects: %g ms (max_time = %g ms)\n"
                "    List size: %zu bytes (max_size = %d bytes)\n"
                "    New max_depth: %d\n",
                tmdiff, timelimit, strlen(glbnvbuf1), sizelimit, maxdepth);
    }
}

/**
 * @brief Evaluate an R expression.
 *
 * @param buf The expression to be evaluated.
 */
static void nvimcom_eval_expr(const char *buf) {
    if (verbose > 3)
        Rprintf("nvimcom_eval_expr: '%s'\n", buf);

    char rep[128];

    SEXP cmdSexp, cmdexpr, ans;
    ParseStatus status;
    int er = 0;

    PROTECT(cmdSexp = allocVector(STRSXP, 1));
    SET_STRING_ELT(cmdSexp, 0, mkChar(buf));
    PROTECT(cmdexpr = R_ParseVector(cmdSexp, -1, &status, R_NilValue));

    char buf2[80];
    nvimcom_squo(buf, buf2, 80);
    if (status == PARSE_OK) {
        /* Only the first command will be executed if the expression includes
         * a semicolon. */
        PROTECT(ans = R_tryEval(VECTOR_ELT(cmdexpr, 0), R_GlobalEnv, &er));
        if (er && verbose > 1) {
            strcpy(rep, "lua require('r.log').warn('Error running: ");
            strncat(rep, buf2, 80);
            strcat(rep, "')");
            send_to_nvim(rep);
        }
        UNPROTECT(1);
    } else {
        if (verbose > 1) {
            strcpy(rep, "lua require('r.log').warn('Invalid command: ");
            strncat(rep, buf2, 80);
            strcat(rep, "')");
            send_to_nvim(rep);
        }
    }
    UNPROTECT(2);
}

/**
 * @brief Send the names and version numbers of currently loaded libraries to
 * R.nvim.
 */
static void send_libnames(void) {
    LibInfo *lib;
    unsigned long totalsz = 9;
    char *libbuf;
    lib = libList;
    do {
        totalsz += lib->strlen;
        lib = lib->next;
    } while (lib);

    libbuf = malloc(totalsz + 1);

    libbuf[0] = 0;
    str_cat(libbuf, "+L");
    lib = libList;
    do {
        str_cat(libbuf, lib->name);
        str_cat(libbuf, "\003");
        str_cat(libbuf, lib->version);
        str_cat(libbuf, "\004");
        lib = lib->next;
    } while (lib);
    libbuf[totalsz] = 0;
    send_to_nvim(libbuf);
    free(libbuf);
}

/**
 * @brief Count how many libraries are loaded in R's workspace. If the number
 * differs from the previous count, add new libraries to LibInfo structure.
 */
static void nvimcom_checklibs(void) {
    SEXP a;

    PROTECT(a = eval(lang1(install("search")), R_GlobalEnv));

    int newnlibs = Rf_length(a);
    if (nlibs == newnlibs)
        return;

    SEXP l, cmdSexp, cmdexpr, ans;
    const char *libname;
    char *libn;
    char buf[128];
    ParseStatus status;
    int er = 0;
    LibInfo *lib;

    nlibs = newnlibs;

    for (int i = 0; i < newnlibs; i++) {
        PROTECT(l = STRING_ELT(a, i));
        libname = CHAR(l);
        libn = strstr(libname, "package:");
        if (libn != NULL) {
            libn = strstr(libn, ":");
            libn++;
            lib = nvimcom_get_lib(libn);
            if (!lib) {
                snprintf(buf, 127, "utils::packageDescription('%s')$Version",
                         libn);
                PROTECT(cmdSexp = allocVector(STRSXP, 1));
                SET_STRING_ELT(cmdSexp, 0, mkChar(buf));
                PROTECT(cmdexpr =
                            R_ParseVector(cmdSexp, -1, &status, R_NilValue));
                if (status != PARSE_OK) {
                    REprintf("nvimcom error parsing: %s\n", buf);
                } else {
                    PROTECT(ans = R_tryEval(VECTOR_ELT(cmdexpr, 0), R_GlobalEnv,
                                            &er));
                    if (er) {
                        REprintf("nvimcom error executing: %s\n", buf);
                    } else {
                        nvimcom_lib_info_add(libn, CHAR(STRING_ELT(ans, 0)));
                    }
                    UNPROTECT(1);
                }
                UNPROTECT(2);
            }
        }
        UNPROTECT(1);
    }
    UNPROTECT(1);

    send_libnames();
    return;
}

/**
 * @brief Function registered to be called by R after completing each top-level
 * task. See R documentation on addTaskCallback.
 */
void nvimcom_task(void) {
    if (verbose > 4)
        REprintf("nvimcom_task()\n");
#ifdef WIN32
    r_is_busy = 0;
#endif
    if (rns_port[0] != 0) {
        nvimcom_checklibs();
        if (autoglbenv)
            nvimcom_globalenv_list();
    }
    if (setwidth && getenv("COLUMNS")) {
        int columns = atoi(getenv("COLUMNS"));
        if (columns > 0 && columns != oldcolwd) {
            oldcolwd = columns;

            /* From R-exts: Evaluating R expressions from C */
            SEXP s, t;
            PROTECT(t = s = allocList(2));
            SET_TYPEOF(s, LANGSXP);
            SETCAR(t, install("options"));
            t = CDR(t);
            SETCAR(t, ScalarInteger((int)columns));
            SET_TAG(t, install("width"));
            eval(s, R_GlobalEnv);
            UNPROTECT(1);

            if (verbose > 2)
                Rprintf("nvimcom: width = %d columns\n", columns);
        }
    }
}

#ifndef WIN32
/**
 * @brief Executed by R when idle.
 *
 * @param unused Unused parameter.
 */
static void nvimcom_exec(__attribute__((unused)) void *nothing) {
    if (*flag_eval) {
        nvimcom_eval_expr(flag_eval);
        *flag_eval = 0;
    }
    if (flag_glbenv) {
        nvimcom_globalenv_list();
        flag_glbenv = 0;
    }
    if (flag_debug) {
        SrcrefInfo();
        flag_debug = 0;
    }
}

/**
 * @brief Check if there is anything in the pipe that we use to register that
 * there are commands to be evaluated. R only executes this function when it
 * can safely execute our commands. This functionality is not available on
 * Windows.
 *
 * @param unused Unused parameter.
 */
static void nvimcom_uih(__attribute__((unused)) void *data) {
    /* Code adapted from CarbonEL.
     * Thanks to Simon Urbanek for the suggestion on r-devel mailing list. */
    if (verbose > 4)
        REprintf("nvimcom_uih()\n");
    char buf[16];
    if (read(ifd, buf, 1) < 1)
        REprintf("nvimcom error: read < 1\n");
    R_ToplevelExec(nvimcom_exec, NULL);
    fired = 0;
}

/**
 * @brief Put a single byte in a pipe to register that we have commands
 * waiting to be executed. R will crash if we execute commands while it is
 * busy with other tasks.
 */
static void nvimcom_fire(void) {
    if (verbose > 4)
        REprintf("nvimcom_fire()\n");
    if (fired)
        return;
    fired = 1;
    char buf[16];
    *buf = 0;
    if (write(ofd, buf, 1) <= 0)
        REprintf("nvimcom error: write <= 0\n");
}

/**
 * @brief Read an R's internal variable to get file name and line number of
 * function currently being debugged.
 */
static void SrcrefInfo(void) {
    // Adapted from SrcrefPrompt(), at src/main/eval.c
    if (debugging == 0) {
        send_to_nvim("lua require('r.debug').stop()");
        return;
    }

    /* If we have a valid R_Srcref, use it */
    if (R_Srcref && R_Srcref != R_NilValue) {
        SEXP filename = R_GetSrcFilename(R_Srcref);
        if (isString(filename) && length(filename)) {
            size_t slen = strlen(CHAR(STRING_ELT(filename, 0)));
            char *buf = calloc(sizeof(char), (2 * slen + 56));
            char *buf2 = calloc(sizeof(char), (2 * slen + 56));
            snprintf(buf, 2 * slen + 1, "%s",
                    CHAR(STRING_ELT(filename, 0)));
            nvimcom_squo(buf, buf2, 2 * slen + 32);
            snprintf(buf, 2 * slen + 55,
                    "lua require('r.debug').jump('%s', %d)", buf2,
                    asInteger(R_Srcref));
            send_to_nvim(buf);
            free(buf);
            free(buf2);
        }
    }
}

/**
 * @brief This function is called by R to process user input. The function
 * monitor R input and checks if we are within the `browser()` function before
 * passing the data to the R function that really process the input.
 *
 * @param prompt R prompt
 * @param buf Command inserted in the R console
 * @param len Length of command in bytes
 * @param addtohistory Should the command be included in `.Rhistory`?
 * @return The return value is defined and used by R.
 */
static int nvimcom_read_console(const char *prompt, unsigned char *buf, int len,
                                int addtohistory) {
    if (debugging == 1) {
        if (prompt[0] != 'B')
            debugging = 0;
        flag_debug = 1;
        nvimcom_fire();
    } else {
        if (prompt[0] == 'B' && prompt[1] == 'r' && prompt[2] == 'o' &&
            prompt[3] == 'w' && prompt[4] == 's' && prompt[5] == 'e' &&
            prompt[6] == '[') {
            debugging = 1;
            flag_debug = 1;
            nvimcom_fire();
        }
    }
    return save_ptr_R_ReadConsole(prompt, buf, len, addtohistory);
}
#endif

#ifdef WIN32
/**
 * @brief This function is called after the TCP connection with the rnvimserver
 * is established. Its goal is to pass to R.nvim information on the running R
 * instance.
 *
 * @param r_info Information on R (see `.onAttach()` at R/nvimcom.R)
 */
static void nvimcom_send_running_info(const char *r_info, const char *nvv) {
    char msg[2176];
    pid_t R_PID = getpid();

#ifdef _WIN64
    snprintf(msg, 2175,
             "lua require('r.run').set_nvimcom_info('%s', %" PRId64
             ", '%" PRId64 "', %s)",
             nvv, R_PID, (long long)GetForegroundWindow(), r_info);
#else
    snprintf(msg, 2175,
             "lua require('r.run').set_nvimcom_info('%s', %d, '%ld', %s)", nvv,
             R_PID, (long)GetForegroundWindow(), r_info);
#endif
    send_to_nvim(msg);
}
#endif

/**
 * @brief Parse messages received from rnvimserver
 *
 * @param buf The message though the TCP connection
 */
static void nvimcom_parse_received_msg(char *buf) {
    char *p;

    if (verbose > 3) {
        REprintf("nvimcom received: %s\n", buf);
    } else if (verbose > 2) {
        p = buf + strlen(getenv("RNVIM_ID")) + 1;
        REprintf("nvimcom Received: [%c] %s\n", buf[0], p);
    }

    switch (buf[0]) {
#ifdef WIN32
    case 'B':
        r_is_busy = 1;
        break;
#endif
    case 'A': // Object Browser started
        if (autoglbenv == 0)
            autoglbenv = 1;
#ifdef WIN32
        if (!r_is_busy)
            nvimcom_globalenv_list();
#else
        flag_glbenv = 1;
        nvimcom_fire();
#endif
        break;
    case 'N': // Object Browser closed
        if (autoglbenv == 1)
            autoglbenv = 0;
        break;
    case 'G':
#ifdef WIN32
        if (!r_is_busy)
            nvimcom_globalenv_list();
#else
        flag_glbenv = 1;
        nvimcom_fire();
#endif
        break;
#ifdef WIN32
    case 'C': // Send command to Rgui Console
        p = buf;
        p++;
        if (strstr(p, getenv("RNVIM_ID")) == p) {
            p += strlen(getenv("RNVIM_ID"));
            r_is_busy = 1;
            Rconsolecmd(p);
        }
        break;
#endif
    case 'L': // Evaluate lazy object
#ifdef WIN32
        if (r_is_busy)
            break;
#endif
        p = buf;
        p++;
        if (strstr(p, getenv("RNVIM_ID")) == p) {
            p += strlen(getenv("RNVIM_ID"));
#ifdef WIN32
            char flag_eval[512];
            snprintf(flag_eval, 510, "%s <- %s", p, p);
            nvimcom_eval_expr(flag_eval);
            *flag_eval = 0;
            nvimcom_globalenv_list();
#else
            snprintf(flag_eval, 510, "%s <- %s", p, p);
            flag_glbenv = 1;
            nvimcom_fire();
#endif
        }
        break;
    case 'E': // eval expression
    case 'R': // eval expression and update GlobalEnv list
        p = buf;
        if (*p == 'R')
#ifdef WIN32
            if (!r_is_busy)
                nvimcom_globalenv_list();
#else
            flag_glbenv = 1;
#endif
        p++;
        if (strstr(p, getenv("RNVIM_ID")) == p) {
            p += strlen(getenv("RNVIM_ID"));
#ifdef WIN32
            if (!r_is_busy)
                nvimcom_eval_expr(p);
#else
            strncpy(flag_eval, p, 510);
            nvimcom_fire();
#endif
        } else {
            REprintf("\nvimcom: received invalid RNVIM_ID.\n");
        }
        break;
    case 'D':
        p = buf;
        p++;
        maxdepth = atoi(p);
        if (verbose > 3)
            REprintf("New max_depth: %d\n", maxdepth);
#ifdef WIN32
        if (!r_is_busy)
            nvimcom_globalenv_list();
#else
        flag_glbenv = 1;
        nvimcom_fire();
#endif
        break;
    default: // do nothing
        REprintf("\nError [nvimcom]: Invalid message received: %s\n", buf);
        break;
    }
}

#ifdef WIN32
/**
 * @brief Loop to receive TCP messages from rnvimserver
 *
 * @param unused Unused parameter.
 */
static DWORD WINAPI client_loop_thread(__attribute__((unused)) void *arg)
#else
/**
 * @brief Loop to receive TCP messages from rnvimserver
 *
 * @param unused Unused parameter.
 */
static void *client_loop_thread(__attribute__((unused)) void *arg)
#endif
{
    size_t len;
    for (;;) {
        char buff[1024];
        memset(buff, '\0', sizeof(buff));
        len = recv(sfd, buff, sizeof(buff), 0);
#ifdef WIN32
        if (len == 0 || buff[0] == 0 || buff[0] == EOF ||
            strstr(buff, "QuitNow") == buff)
#else
        if (len == 0 || buff[0] == 0 || buff[0] == EOF)
#endif
        {
            if (len == 0)
                REprintf("Connection with R.nvim was lost\n");
            if (buff[0] == EOF)
                REprintf("client_loop_thread: buff[0] == EOF\n");
#ifdef WIN32
            closesocket(sfd);
            WSACleanup();
#else
            close(sfd);
            sfd = -1;
#endif
            break;
        }
        nvimcom_parse_received_msg(buff);
    }
#ifdef WIN32
    return 0;
#else
    return NULL;
#endif
}

/**
 * @brief Set variables that will control nvimcom behavior and establish a TCP
 * connection with rnvimserver in a new thread. This function is called when
 * nvimcom package is attached (See `.onAttach()` at R/nvimcom.R).
 *
 * @param vrb Verbosity level (`nvimcom.verbose` in ~/.Rprofile).
 *
 * @param anm Should names with starting with a dot be included in completion
 * lists? (`R_objbr_allnames` in init.vim).
 *
 * @param swd Should nvimcom set the option "width" after the execution of
 * each command? (`R_setwidth` in init.vim).
 *
 * @param age Should the list of objects in .GlobalEnv be automatically
 * updated? (`R_objbr_allnames` in init.vim)
 *
 * @param nvv nvimcom version
 *
 * @param rinfo Information on R to be passed to nvim.
 */
SEXP nvimcom_Start(SEXP vrb, SEXP anm, SEXP swd, SEXP age, SEXP imd, SEXP szl,
                   SEXP tml, SEXP dbg, SEXP nvv, SEXP rinfo) {
    verbose = *INTEGER(vrb);
    allnames = *INTEGER(anm);
    setwidth = *INTEGER(swd);
    autoglbenv = *INTEGER(age);
    maxdepth = *INTEGER(imd);
    sizelimit = *INTEGER(szl);
    timelimit = (double)*INTEGER(tml);
    debug_r = *INTEGER(dbg);

    if (getenv("RNVIM_TMPDIR")) {
        strncpy(tmpdir, getenv("RNVIM_TMPDIR"), 500);
        if (getenv("RNVIM_SECRET"))
            strncpy(nvimsecr, getenv("RNVIM_SECRET"), 31);
        else
            REprintf(
                "nvimcom: Environment variable RNVIM_SECRET is missing.\n");
    } else {
        if (verbose)
            REprintf("nvimcom: It seems that R was not started by Neovim. The "
                     "communication with R.nvim will not work.\n");
        tmpdir[0] = 0;
        SEXP ans;
        PROTECT(ans = NEW_LOGICAL(1));
        SET_LOGICAL_ELT(ans, 0, 0);
        UNPROTECT(1);
        return ans;
    }

    if (getenv("RNVIM_PORT"))
        strncpy(rns_port, getenv("RNVIM_PORT"), 15);

    set_doc_width(getenv("CMPR_DOC_WIDTH"));

    if (verbose > 0)
        REprintf("nvimcom %s loaded\n", CHAR(STRING_ELT(nvv, 0)));
    if (verbose > 1) {
        if (getenv("NVIM_IP_ADDRESS")) {
            REprintf("  NVIM_IP_ADDRESS: %s\n", getenv("NVIM_IP_ADDRESS"));
        }
        REprintf("  CMPR_DOC_WIDTH: %s\n", getenv("CMPR_DOC_WIDTH"));
        REprintf("  RNVIM_PORT: %s\n", rns_port);
        REprintf("  RNVIM_ID: %s\n", getenv("RNVIM_ID"));
        REprintf("  RNVIM_TMPDIR: %s\n", tmpdir);
        REprintf("  RNVIM_COMPLDIR: %s\n", getenv("RNVIM_COMPLDIR"));
        REprintf("  R info: %s\n\n", CHAR(STRING_ELT(rinfo, 0)));
    }

    tcp_header_len = strlen(nvimsecr) + 9;
    glbnvbuf1 = (char *)calloc(glbnvbufsize, sizeof(char));
    glbnvbuf2 = (char *)calloc(glbnvbufsize, sizeof(char));
    send_ge_buf = (char *)calloc(glbnvbufsize + 64, sizeof(char));
    if (!glbnvbuf1 || !glbnvbuf2 || !send_ge_buf)
        REprintf("nvimcom: Error allocating memory.\n");

#ifndef WIN32
    *flag_eval = 0;
    int fds[2];
    if (pipe(fds) == 0) {
        ifd = fds[0];
        ofd = fds[1];
        ih = addInputHandler(R_InputHandlers, ifd, &nvimcom_uih, 32);
    } else {
        REprintf("nvimcom error: pipe != 0\n");
        ih = NULL;
    }
#endif

    static int failure = 0;

    if (atoi(rns_port) > 0) {
        struct sockaddr_in servaddr;
#ifdef WIN32
        WSADATA d;
        int wr = WSAStartup(MAKEWORD(2, 2), &d);
        if (wr != 0) {
            REprintf("WSAStartup failed: %d\n", wr);
        }
#endif
        // socket create and verification
        sfd = socket(AF_INET, SOCK_STREAM, 0);
        if (sfd != -1) {
            memset(&servaddr, '\0', sizeof(servaddr));

            // assign IP, PORT
            servaddr.sin_family = AF_INET;
            if (getenv("NVIM_IP_ADDRESS"))
                servaddr.sin_addr.s_addr = inet_addr(getenv("NVIM_IP_ADDRESS"));
            else
                servaddr.sin_addr.s_addr = inet_addr("127.0.0.1");
            servaddr.sin_port = htons(atoi(rns_port));

            // connect the client socket to server socket
            if (connect(sfd, (struct sockaddr *)&servaddr, sizeof(servaddr)) ==
                0) {
#ifdef WIN32
                DWORD ti;
                tid = CreateThread(NULL, 0, client_loop_thread, NULL, 0, &ti);
                nvimcom_send_running_info(CHAR(STRING_ELT(rinfo, 0)),
                                          CHAR(STRING_ELT(nvv, 0)));
#else
                pthread_create(&tid, NULL, client_loop_thread, NULL);
                snprintf(flag_eval, 510, "nvimcom:::send_nvimcom_info('%d')",
                         getpid());
                nvimcom_fire();
#endif
            } else {
                REprintf("nvimcom: connection with the server failed (%s)\n",
                         rns_port);
                failure = 1;
            }
        } else {
            REprintf("nvimcom: socket creation failed (%d)\n", atoi(rns_port));
            failure = 1;
        }
    }

    if (failure == 0) {
        initialized = 1;
#ifdef WIN32
        r_is_busy = 0;
#else
        if (debug_r) {
            save_ptr_R_ReadConsole = ptr_R_ReadConsole;
            ptr_R_ReadConsole = nvimcom_read_console;
        }
#endif
        nvimcom_checklibs();
    }

    SEXP ans;
    PROTECT(ans = NEW_LOGICAL(1));
    if (initialized) {
        SET_LOGICAL_ELT(ans, 0, 1);
    } else {
        SET_LOGICAL_ELT(ans, 0, 0);
    }
    UNPROTECT(1);
    return ans;
}

/**
 * @brief Close the TCP connection with rnvimserver and do other cleanup.
 * This function is called by `.onUnload()` at R/nvimcom.R.
 */
void nvimcom_Stop(void) {
#ifndef WIN32
    if (ih) {
        removeInputHandler(&R_InputHandlers, ih);
        close(ifd);
        close(ofd);
    }
#endif

    if (initialized) {
#ifdef WIN32
        closesocket(sfd);
        WSACleanup();
        TerminateThread(tid, 0);
        CloseHandle(tid);
#else
        if (debug_r)
            ptr_R_ReadConsole = save_ptr_R_ReadConsole;
        close(sfd);
        pthread_cancel(tid);
        pthread_join(tid, NULL);
#endif

        LibInfo *lib = libList;
        LibInfo *tmp;
        while (lib) {
            tmp = lib->next;
            free(lib->name);
            free(lib);
            lib = tmp;
        }

        if (glbnvbuf1)
            free(glbnvbuf1);
        if (glbnvbuf2)
            free(glbnvbuf2);
        if (send_ge_buf)
            free(send_ge_buf);
        if (verbose)
            REprintf("nvimcom stopped\n");
    }
    initialized = 0;
}
