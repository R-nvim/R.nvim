#include <ctype.h>     // Character type functions
#include <dirent.h>    // Directory entry
#include <signal.h>    // Signal handling
#include <stdarg.h>    // Variable argument functions
#include <stdio.h>     // Standard input/output definitions
#include <stdlib.h>    // Standard library
#include <string.h>    // String handling functions
#include <sys/stat.h>  // Data returned by the stat() function
#include <sys/types.h> // Data types
#include <unistd.h>    // POSIX operating system API
#ifdef WIN32
#include <inttypes.h>
#include <process.h>
#include <time.h>
#include <winsock2.h>
#include <windows.h>
HWND NvimHwnd = NULL;
HWND RConsole = NULL;
#define bzero(b, len) (memset((b), '\0', (len)), (void)0)
#ifdef _WIN64
#define PRI_SIZET PRIu64
#else
#define PRI_SIZET PRIu32
#endif
#else
#include <netdb.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <sys/socket.h>
#define PRI_SIZET "zu"
#endif

#include "data_structures.h"
#include "logging.h"
#include "utilities.h"
#include "../common.h"

static char strL[8];        // String for last element prefix in tree view
static char strT[8];        // String for tree element prefix in tree view
static int OpenDF;          // Flag for open data frames in tree view
static int OpenLS;          // Flag for open lists in tree view
static int nvimcom_is_utf8; // Flag for UTF-8 encoding
static int allnames; // Flag for showing all names, including starting with '.'

static char compl_cb[64];      // Completion callback buffer
static char resolve_cb[64];    // Completion info buffer
static char compldir[256];     // Directory for completion files
static char tmpdir[256];       // Temporary directory
static char localtmpdir[256];  // Local temporary directory
static char liblist[576];      // Library list buffer
static char globenv[576];      // Global environment buffer
static int auto_obbr;          // Auto object browser flag
static size_t glbnv_buffer_sz; // Global environment buffer size
static char *glbnv_buffer;     // Global environment buffer
static char *compl_buffer;     // Completion buffer
static char *finalbuffer;      // Final buffer for message processing
static unsigned long compl_buffer_size = 163840; // Completion buffer size
static unsigned long fb_size = 1024;             // Final buffer size
static int building_objls; // Flag for building compl lists
static int more_to_build;  // Flag for more lists to build

void compl2ob(void);                // Convert completion list to Object Browser
void lib2ob(void);                  // Convert Library to object browser
void update_inst_libs(void);        // Update installed libraries
void update_pkg_list(char *libnms); // Update package list
void update_glblenv_buffer(char *g); // Update global environment buffer
static void build_objls(void);       // Build list of objects for completion
static void finish_bol(void);        // Finish building of lists
void complete(const char *id, char *base, char *funcnm, char *dtfrm,
              char *funargs); // Perform completion

LibPath *libpaths; // Pointer to first library path

InstLibs *instlibs; // Pointer to first installed library

static ListStatus *listTree; // Root node of the list status tree

PkgData *pkgList;    // Pointer to first package data
static int nLibObjs; // Number of library objects

static int r_conn;          // R connection status flag
static char VimSecret[128]; // Secret for communication with Vim
static int VimSecretLen;    // Length of Vim secret

#ifdef WIN32
static int Tid; // Thread ID
#else
static pthread_t Tid; // Thread ID
#endif
struct sockaddr_in servaddr; // Server address structure
static int sockfd;           // socket file descriptor
static int connfd;           // Connection file descriptor

static void
HandleSigTerm(__attribute__((unused)) int s) // Signal handler for SIGTERM
{
    exit(0);
}

static void RegisterPort(int bindportn) // Function to register port number to R
{
    // Register the port:
    printf("lua require('r.run').set_rns_port('%d')\n", bindportn);
    fflush(stdout);
}

static void ParseMsg(char *b) // Parse the message from R
{
#ifdef Debug_NRS
    if (strlen(b) > 500)
        Log("ParseMsg(): strlen(b) = %" PRI_SIZET "", strlen(b));
    else
        Log("ParseMsg():\n%s", b);
#endif

    if (*b == '+') {
        b++;
        switch (*b) {
        case 'G':
            b++;
            update_glblenv_buffer(b);
            if (auto_obbr)  // Update the Object Browser after sending the
                            // message to R.nvim to
                compl2ob(); // avoid unnecessary delays in auto completion
            break;
        case 'L':
            b++;
            update_pkg_list(b);
            build_objls();
            if (auto_obbr)
                lib2ob();
            break;
        case 'A': // strtok doesn't work here because "base" might be empty.
            b++;
            char *dtfrm;
            char *id = b;
            char *base = id;
            while (*base != ';')
                base++;
            *base = 0;
            base++;
            char *fnm = base;
            while (*fnm != ';')
                fnm++;
            *fnm = 0;
            fnm++;
            dtfrm = fnm;
            while (*dtfrm != 0 && *dtfrm != ';')
                dtfrm++;
            *dtfrm = 0;
            dtfrm++;
            b = dtfrm;
            while (*b != 0 && *b != '\n')
                b++;
            *b = 0;
            if (*dtfrm == '#')
                complete(id, base, fnm, NULL, NULL);
            else
                complete(id, base, fnm, dtfrm, NULL);
            break;
        case 'F': // strtok doesn't work here because "base" might be empty.
            b++;
            char *args;
            char *cid = b;
            char *bse = cid;
            while (*bse != ';')
                bse++;
            *bse = 0;
            bse++;
            char *fun = bse;
            while (*fun != ';')
                fun++;
            *fun = 0;
            fun++;
            args = fun;
            while (*args != 0 && *args != ';')
                args++;
            *args = 0;
            args++;
            b = args;
            while (*b != 0 && *b != '\n')
                b++;
            *b = 0;
            complete(cid, bse, fun, NULL, args);
            break;
        }
        return;
    }

    // Send the command to R.nvim
    printf("\x11%" PRI_SIZET "\x11%s\n", strlen(b), b);
    fflush(stdout);
}

/**
 * @brief Initializes the socket for the server.
 *
 * This function creates a socket for the server and performs necessary
 * initializations. On Windows, it also initializes Winsock. The function
 * exits the program if socket creation fails.
 *
 * @note For Windows, WSAStartup is called to start the Winsock API.
 */
static void initialize_socket(void) {
    Log("initialize_socket()");
#ifdef WIN32
    WSADATA d;
    int wr = WSAStartup(MAKEWORD(2, 2), &d);
    if (wr != 0) {
        fprintf(stderr, "WSAStartup failed: %d\n", wr);
        fflush(stderr);
        WSACleanup();
        exit(1);
    }
#endif
    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd == -1) {
        fprintf(stderr, "socket creation failed...\n");
        fflush(stderr);
        exit(1);
    }
}

#define PORT_START 10101
#define PORT_END 10199
/**
 * @brief Binds the server socket to an available port.
 *
 * This function initializes the server address structure and attempts to bind
 * the server socket to an available port starting from 10101 up to 10199.
 * It registers the port number for R to connect. The function exits the
 * program if it fails to bind the socket to any of the ports in the specified
 * range.
 */
static void bind_to_port(void) {
    Log("bind_to_port()");

    bzero(&servaddr, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = htonl(INADDR_ANY);

    int res = 1;
    for (int port = PORT_START; port <= PORT_END; port++) {
        servaddr.sin_port = htons(port);
        res = bind(sockfd, (struct sockaddr *)&servaddr, sizeof(servaddr));
        if (res == 0) {
            RegisterPort(port);
            Log("bind_to_port: Bind succeeded on port %d", port);
            break;
        }
    }
    if (res != 0) {
        fprintf(stderr, "Failed to bind any port in the range %d-%d\n",
                PORT_START, PORT_END);
        fflush(stderr);
#ifdef WIN32
        WSACleanup();
#endif /* ifdef WIN32 */
        exit(2);
    }
}

/**
 * @brief Sets the server to listen for incoming connections.
 *
 * This function sets the server to listen on the socket for incoming
 * connections. It configures the socket to allow up to 5 pending connection
 * requests in the queue. The function exits the program if it fails to set
 * the socket to listen state.
 */
static void listening_for_connections(void) {
    Log("listening_for_connections()");

    if ((listen(sockfd, 5)) != 0) {
        fprintf(stderr, "Listen failed...\n");
        fflush(stderr);
        exit(3);
    }
}

/**
 * @brief Accepts an incoming connection on the listening socket.
 *
 * This function waits for and accepts the first incoming connection request
 * on the listening socket. It stores the connection file descriptor in
 * 'connfd' and sets the 'r_conn' flag to indicate a successful connection.
 * The function exits the program if it fails to accept a connection.
 */
static void accept_connection(void) {
    Log("accept_connection()");
#ifdef WIN32
    int len;
#else
    socklen_t len;
#endif
    struct sockaddr_in cli;

    len = sizeof(cli);
    connfd = accept(sockfd, (struct sockaddr *)&cli, &len);
    if (connfd < 0) {
        fprintf(stderr, "server accept failed...\n");
        fflush(stderr);
        exit(4);
    }
    r_conn = 1;
}

/**
 * @brief Initializes listening for incoming connections.
 *
 * This function is responsible for the entire process of setting up the
 * server to listen for and accept incoming connections. It calls a series of
 * functions to initialize the socket, bind it to a port, set it to listen
 * for connections, and then accept an incoming connection.
 *
 * @note A previous version of this function was adapted from
 * https://www.geeksforgeeks.org/socket-programming-in-cc-handling-multiple-clients-on-server-without-multi-threading/
 */
static void
setup_server_socket(void) // Initialise listening for incoming connections
{
    Log("setup_server_socket()");
    initialize_socket();
    bind_to_port();
    listening_for_connections();
    accept_connection();
}

static void get_whole_msg(char *b) // Get the whole message from the socket
{
    Log("get_whole_msg()");
    char *p;
    char tmp[1];
    int msg_size;

    if (strstr(b, VimSecret) != b) {
        fprintf(stderr, "Strange string received {%s}: \"%s\"\n", VimSecret, b);
        fflush(stderr);
        return;
    }
    p = b + VimSecretLen;

    // Get the message size
    p[9] = 0;
    msg_size = atoi(p);
    p += 10;

    // Allocate enough memory to the final buffer
    if (finalbuffer) {
        memset(finalbuffer, 0, fb_size);
        if (msg_size > fb_size)
            finalbuffer =
                grow_buffer(&finalbuffer, &fb_size, msg_size - fb_size + 1024);
    } else {
        if (msg_size > fb_size)
            fb_size = msg_size + 1024;
        finalbuffer = calloc(fb_size, sizeof(char));
    }

    p = finalbuffer;
    for (;;) {
        if ((recv(connfd, tmp, 1, 0) == 1))
            *p = *tmp;
        else
            break;
        if (*p == '\x11')
            break;
        p++;
    }
    *p = 0;

    // FIXME: Delete this check when the code proved to be reliable
    if (strlen(finalbuffer) != msg_size) {
        fprintf(stderr, "Divergent TCP message size: %" PRI_SIZET " x %d\n",
                strlen(p), msg_size);
        fflush(stderr);
    }

    ParseMsg(finalbuffer);
}

#ifdef WIN32
static void
receive_msg(void *arg) // Thread function to receive messages on Windows
#else
static void *receive_msg(void *v) // Thread function to receive messages on Unix
#endif
{
    size_t blen = VimSecretLen + 9;
    char b[32];
    size_t rlen;

    for (;;) {
        bzero(b, 32);
        rlen = recv(connfd, b, blen, 0);
        if (rlen == blen) {
            Log("TCP in (message header): %s", b);
            get_whole_msg(b);
        } else {
            r_conn = 0;
#ifdef WIN32
            closesocket(sockfd);
            WSACleanup();
#else
            close(sockfd);
#endif
            if (rlen != -1 && rlen != 0) {
                fprintf(stderr, "TCP socket -1: restarting...\n");
                fprintf(stderr,
                        "Wrong TCP data length: %" PRI_SIZET " x %" PRI_SIZET
                        "\n",
                        blen, rlen);
                fflush(stderr);
            }
            break;
        }
    }
#ifndef WIN32
    return NULL;
#endif
}

void send_to_nvimcom(
    char *msg) // Function to send messages to R (nvimcom package)
{
    Log("TCP out: %s", msg);
    if (connfd) {
        size_t len = strlen(msg);
        if (send(connfd, msg, len, 0) != (ssize_t)len) {
            fprintf(stderr, "Partial/failed write.\n");
            fflush(stderr);
            return;
        }
    } else {
        fprintf(stderr, "nvimcom is not connected");
        fflush(stderr);
    }
}

#ifdef WIN32
static void SendToRConsole(char *aString) {
    if (!RConsole) {
        fprintf(stderr, "R Console window ID not defined [SendToRConsole]\n");
        fflush(stderr);
        return;
    }

    // The application (such as NeovimQt) might not define $WINDOWID
    if (!NvimHwnd)
        NvimHwnd = GetForegroundWindow();

    char msg[1024];
    snprintf(msg, 1023, "C%s%s", getenv("RNVIM_ID"), aString);
    send_to_nvimcom(msg);
    Sleep(0.02);

    // Necessary to force RConsole to actually process the line
    PostMessage(RConsole, WM_NULL, 0, 0);
}

static void RClearConsole() {
    if (!RConsole) {
        fprintf(stderr, "R Console window ID not defined [RClearConsole]\n");
        fflush(stderr);
        return;
    }

    SetForegroundWindow(RConsole);
    keybd_event(VK_CONTROL, 0, 0, 0);
    keybd_event(VkKeyScan('L'), 0, KEYEVENTF_EXTENDEDKEY | 0, 0);
    Sleep(0.05);
    keybd_event(VkKeyScan('L'), 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, 0);
    keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0);
    Sleep(0.05);
    PostMessage(RConsole, WM_NULL, 0, 0);
}

static void SaveWinPos(char *cachedir) {
    if (!RConsole) {
        fprintf(stderr, "R Console window ID not defined [SaveWinPos]\n");
        fflush(stderr);
        return;
    }

    RECT rcR, rcV;
    if (!GetWindowRect(RConsole, &rcR)) {
        fprintf(stderr, "Could not get R Console position\n");
        fflush(stderr);
        return;
    }

    if (!GetWindowRect(NvimHwnd, &rcV)) {
        fprintf(stderr, "Could not get Neovim position\n");
        fflush(stderr);
        return;
    }

    rcR.right = rcR.right - rcR.left;
    rcR.bottom = rcR.bottom - rcR.top;
    rcV.right = rcV.right - rcV.left;
    rcV.bottom = rcV.bottom - rcV.top;

    char fname[1032];
    snprintf(fname, 1031, "%s/win_pos", cachedir);
    FILE *f = fopen(fname, "w");
    if (f == NULL) {
        fprintf(stderr, "Could not write to '%s'\n", fname);
        fflush(stderr);
        return;
    }
    fprintf(f, "%ld\n%ld\n%ld\n%ld\n%ld\n%ld\n%ld\n%ld\n", rcR.left, rcR.top,
            rcR.right, rcR.bottom, rcV.left, rcV.top, rcV.right, rcV.bottom);
    fclose(f);
}

static void ArrangeWindows(char *cachedir) {
    if (!RConsole) {
        fprintf(stderr, "R Console window ID not defined [ArrangeWindows]\n");
        fflush(stderr);
        return;
    }

    char fname[1032];
    snprintf(fname, 1031, "%s/win_pos", cachedir);
    FILE *f = fopen(fname, "r");
    if (f == NULL) {
        fprintf(stderr, "Could not read '%s'\n", fname);
        fflush(stderr);
        return;
    }

    RECT rcR, rcV;
    char b[32];
    if ((fgets(b, 31, f))) {
        rcR.left = atol(b);
    } else {
        fprintf(stderr, "Error reading R left position\n");
        fflush(stderr);
        fclose(f);
        return;
    }
    if ((fgets(b, 31, f))) {
        rcR.top = atol(b);
    } else {
        fprintf(stderr, "Error reading R top position\n");
        fflush(stderr);
        fclose(f);
        return;
    }
    if ((fgets(b, 31, f))) {
        rcR.right = atol(b);
    } else {
        fprintf(stderr, "Error reading R right position\n");
        fflush(stderr);
        fclose(f);
        return;
    }
    if ((fgets(b, 31, f))) {
        rcR.bottom = atol(b);
    } else {
        fprintf(stderr, "Error reading R bottom position\n");
        fflush(stderr);
        fclose(f);
        return;
    }
    if ((fgets(b, 31, f))) {
        rcV.left = atol(b);
    } else {
        fprintf(stderr, "Error reading Neovim left position\n");
        fflush(stderr);
        fclose(f);
        return;
    }
    if ((fgets(b, 31, f))) {
        rcV.top = atol(b);
    } else {
        fprintf(stderr, "Error reading Neovim top position\n");
        fflush(stderr);
        fclose(f);
        return;
    }
    if ((fgets(b, 31, f))) {
        rcV.right = atol(b);
    } else {
        fprintf(stderr, "Error reading Neovim right position\n");
        fflush(stderr);
        fclose(f);
        return;
    }
    if ((fgets(b, 31, f))) {
        rcV.bottom = atol(b);
    } else {
        fprintf(stderr, "Error reading Neovim bottom position\n");
        fflush(stderr);
        fclose(f);
        return;
    }

    if (rcR.left > 0 && rcR.top > 0 && rcR.right > 0 && rcR.bottom > 0 &&
        rcR.right > rcR.left && rcR.bottom > rcR.top) {
        if (!SetWindowPos(RConsole, HWND_TOP, rcR.left, rcR.top, rcR.right,
                          rcR.bottom, 0)) {
            fprintf(stderr, "Error positioning RConsole window\n");
            fflush(stderr);
            fclose(f);
            return;
        }
    }

    if (rcV.left > 0 && rcV.top > 0 && rcV.right > 0 && rcV.bottom > 0 &&
        rcV.right > rcV.left && rcV.bottom > rcV.top) {
        if (!SetWindowPos(NvimHwnd, HWND_TOP, rcV.left, rcV.top, rcV.right,
                          rcV.bottom, 0)) {
            fprintf(stderr, "Error positioning Neovim window\n");
            fflush(stderr);
        }
    }

    SetForegroundWindow(NvimHwnd);
    fclose(f);
}

void Windows_setup() // Setup Windows-specific configurations
{
    // Set the value of NvimHwnd
    if (getenv("WINDOWID")) {
#ifdef _WIN64
        NvimHwnd = (HWND)atoll(getenv("WINDOWID"));
#else
        NvimHwnd = (HWND)atol(getenv("WINDOWID"));
#endif
    } else {
        // The application (such as NeovimQt) might not define $WINDOWID
        NvimHwnd = FindWindow(NULL, "Neovim");
        if (!NvimHwnd) {
            NvimHwnd = FindWindow(NULL, "nvim");
            if (!NvimHwnd) {
                fprintf(stderr, "\"Neovim\" window not found\n");
                fflush(stderr);
            }
        }
    }
}
#endif

void start_server(void) // Start server and listen for connections
{
    // Finish immediately with SIGTERM
    signal(SIGTERM, HandleSigTerm);

    setup_server_socket();

    // Receive messages from TCP and output them to stdout
#ifdef WIN32
    Tid = _beginthread(receive_msg, 0, NULL);
#else
    pthread_create(&Tid, NULL, receive_msg, NULL);
#endif
}

/**
 * @brief Count the number of separator characters in a given buffer.
 *
 * This function scans a buffer and counts the number of occurrences of
 * the separator character '\006'. It is primarily used to parse and validate
 * data structure representations received from R. The function also checks if
 * the size of the buffer is 1, indicating an empty package with no exported
 * objects. In case of an unexpected number of separators, it logs an error,
 * frees the buffer, and returns NULL.
 *
 * @param b1 Pointer to the buffer to be scanned.
 * @param size Pointer to an integer where the size of the buffer will be
 * stored.
 * @return Returns the original buffer if the count of separators is as
 * expected. Returns NULL in case of an error or if the count is not as
 * expected.
 */
char *count_sep(char *b1, int *size) {
    *size = strlen(b1);
    // Some packages do not export any objects.
    if (*size == 1)
        return b1;

    char *s = b1;
    int n = 0;
    while (*s) {
        if (*s == '\006')
            n++;
        if (*s == '\n') {
            if (n == 7) {
                n = 0;
            } else {
                char b[64];
                s++;
                strncpy(b, s, 16);
                fprintf(stderr, "Number of separators: %d (%s)\n", n, b);
                fflush(stderr);
                free(b1);
                return NULL;
            }
        }
        s++;
    }
    return b1;
}

/**
 * @brief Reads the entire contents of a specified file into a buffer.
 *
 * This function opens the file specified by the filename and reads its entire
 * content into a dynamically allocated buffer. It ensures that the file is read
 * in binary mode to preserve the data format. This function is typically used
 * to load files containing data relevant to the R.nvim plugin, such as
 * completion lists or configuration data.
 *
 * @param fn The name of the file to be read.
 * @param verbose Flag to indicate whether to print error messages. If set to a
 * non-zero value, error messages are printed to stderr.
 * @return Returns a pointer to a buffer containing the file's content if
 * successful. Returns NULL if the file cannot be opened or in case of a read
 * error.
 */
char *read_file(const char *fn, int verbose) {
    Log("read_file: %s", fn);
    FILE *f = fopen(fn, "rb");
    if (!f) {
        if (verbose) {
            fprintf(stderr, "Error opening '%s'", fn);
            fflush(stderr);
        }
        return NULL;
    }
    fseek(f, 0L, SEEK_END);
    long sz = ftell(f);
    rewind(f);
    if (sz == 0) {
        // List of objects is empty. Perhaps no object was created yet.
        fclose(f);
        return NULL;
    }

    char *buffer = calloc(1, sz + 1);
    if (!buffer) {
        fclose(f);
        fputs("Error allocating memory\n", stderr);
        fflush(stderr);
        return NULL;
    }

    if (1 != fread(buffer, sz, 1, f)) {
        fclose(f);
        free(buffer);
        fprintf(stderr, "Error reading '%s'\n", fn);
        fflush(stderr);
        return NULL;
    }
    fclose(f);
    return buffer;
}

/**
 * @brief Validates and prepares the buffer containing completion data.
 *
 * This function processes a buffer that is expected to contain data for auto
 * completion, ensuring that there are exactly 7 '\006' separators between
 * newline characters. It modifies the buffer in place, replacing certain
 * control characters with their corresponding representations and ensuring the
 * data is correctly formatted for subsequent processing. The function is part
 * of the handling for auto completion data in the R.nvim plugin, facilitating
 * the communication and data exchange between Neovim and R.
 *
 * @param buffer Pointer to the buffer containing auto completion data.
 * @param size Pointer to an integer representing the size of the buffer.
 * @return Returns a pointer to the processed buffer if the validation is
 * successful. Returns NULL if the buffer does not meet the expected format or
 * validation fails.
 */
void *check_omils_buffer(char *buffer, int *size) {
    // Ensure that there are exactly 7 \006 between new line characters
    buffer = count_sep(buffer, size);

    if (!buffer)
        return NULL;

    if (buffer) {
        char *p = buffer;
        while (*p) {
            if (*p == '\006')
                *p = 0;
            // if (*p == '\'')
            //     *p = '\x13';
            p++;
        }
    }
    return buffer;
}

/**
 * @brief Reads the contents of an auto completion list file into a buffer.
 *
 * This function opens and reads the specified auto completion file (typically
 * named 'objls_'). It allocates memory for the buffer and loads the file
 * contents into it. The buffer is used to store completion items (like function
 * names and variables) available in R packages for use in auto completion in
 * Neovim. If the file is empty, it indicates that no completion items are
 * available or the file is yet to be populated.
 *
 * @param fn The name of the file to be read.
 * @param size A pointer to an integer where the size of the read data will be
 * stored.
 * @return Returns a pointer to a buffer containing the file contents if
 * successful. Returns NULL if the file cannot be opened, is empty, or in case
 * of a read error.
 */
char *read_objls_file(const char *fn, int *size) {
    char *buffer = read_file(fn, 1);
    if (!buffer)
        return NULL;

    return check_omils_buffer(buffer, size);
}

char *read_alias_file(const char *nm) {
    char fnm[512];
    snprintf(fnm, 511, "%s/alias_%s", compldir, nm);
    char *buffer = read_file(fnm, 1);
    if (!buffer)
        return NULL;
    char *p = buffer;
    while (*p) {
        if (*p == '\x09')
            *p = 0;
        p++;
    }
    return buffer;
}

char *read_args_file(const char *nm) {
    char fnm[512];
    snprintf(fnm, 511, "%s/args_%s", compldir, nm);
    char *buffer = read_file(fnm, 1);
    if (!buffer)
        return NULL;
    char *p = buffer;
    while (*p) {
        if (*p == '\006')
            *p = 0;
        p++;
    }
    return buffer;
}

char *get_pkg_descr(const char *pkgnm) {
    Log("get_pkg_descr(%s)", pkgnm);
    InstLibs *il = instlibs;
    while (il) {
        if (strcmp(il->name, pkgnm) == 0) {
            char *s = malloc((strlen(il->title) + 1) * sizeof(char));
            strcpy(s, il->title);
            return s;
        }
        il = il->next;
    }
    return NULL;
}

void pkg_delete(PkgData *pd) {
    free(pd->name);
    free(pd->version);
    free(pd->fname);
    if (pd->descr)
        free(pd->descr);
    if (pd->objls)
        free(pd->objls);
    if (pd->args)
        free(pd->args);
    if (pd->alias)
        free(pd->alias);
    free(pd);
}

void load_pkg_data(PkgData *pd) {
    int size;
    if (!pd->descr)
        pd->descr = get_pkg_descr(pd->name);
    pd->objls = read_objls_file(pd->fname, &size);
    pd->alias = read_alias_file(pd->name);
    pd->args = read_args_file(pd->name);
    pd->nobjs = 0;
    if (pd->objls) {
        pd->loaded = 1;
        if (size > 2)
            for (int i = 0; i < size; i++)
                if (pd->objls[i] == '\n')
                    pd->nobjs++;
    }
}

PkgData *new_pkg_data(const char *nm, const char *vrsn) {
    char buf[1024];

    PkgData *pd = calloc(1, sizeof(PkgData));
    pd->name = malloc((strlen(nm) + 1) * sizeof(char));
    strcpy(pd->name, nm);
    pd->version = malloc((strlen(vrsn) + 1) * sizeof(char));
    strcpy(pd->version, vrsn);
    pd->descr = get_pkg_descr(pd->name);
    pd->loaded = 1;

    snprintf(buf, 1023, "%s/objls_%s_%s", compldir, nm, vrsn);
    pd->fname = malloc((strlen(buf) + 1) * sizeof(char));
    strcpy(pd->fname, buf);

    // Check if objls_ exist
    pd->built = 1;
    if (access(buf, F_OK) != 0) {
        pd->built = 0;
    }
    return pd;
}

PkgData *get_pkg(const char *nm) {
    if (!pkgList)
        return NULL;

    PkgData *pd = pkgList;
    do {
        if (strcmp(pd->name, nm) == 0)
            return pd;
        pd = pd->next;
    } while (pd);

    return NULL;
}

void add_pkg(const char *nm, const char *vrsn) {
    PkgData *tmp = pkgList;
    pkgList = new_pkg_data(nm, vrsn);
    pkgList->next = tmp;
}

int read_field_data(char *s, int i) {
    while (s[i]) {
        if (s[i] == '\n' && s[i + 1] == ' ') {
            s[i] = ' ';
            i++;
            while (s[i] == ' ')
                i++;
        }
        if (s[i] == '\n') {
            s[i] = 0;
            break;
        }
        i++;
    }
    return i;
}

/**
 * @brief Copy a string, skiping consecutive spaces.
 *
 * This function takes an input string and produces an output string where
 * consecutive spaces are reduced to a single space. The output string is
 * null-terminated. The function does not modify the input string.
 *
 * @param input The input string with potential consecutive spaces.
 * @param output The output buffer where the trimmed string will be stored.
 *               This buffer should be large enough to hold the result.
 */
void skip_consecutive_spaces(const char *input, char *output) {
    int i = 0, j = 0;
    while (input[i] != '\0') {
        output[j++] = input[i];
        if (input[i] == ' ') {
            // Skip over additional consecutive spaces
            while (input[i + 1] == ' ') {
                i++;
            }
        }
        i++;
    }
    output[j] = '\0'; // Null-terminate the output string
}

/**
 * @brief Parses the DESCRIPTION file of an R package to extract metadata.
 *
 * This function reads the DESCRIPTION file of an R package and extracts key
 * metadata, including the Title and Description fields. It is used to provide
 * more detailed information about R packages in the Neovim environment,
 * particularly for features like auto-completion and package management within
 * the R.nvim plugin. The parsed information is used to update the data
 * structures that represent installed R libraries.
 *
 * @param descr Pointer to a string containing the contents of a DESCRIPTION
 * file.
 * @param fnm The name of the R package whose DESCRIPTION file is being parsed.
 */
void parse_descr(char *descr, const char *fnm) {
    int i = 0;
    int dlen = strlen(descr);
    char *title, *description;
    title = NULL;
    description = NULL;
    InstLibs *lib, *ptr, *prev;
    while (i < dlen) {
        if ((i == 0 || descr[i - 1] == '\n' || descr[i - 1] == 0) &&
            str_here(descr + i, "Title: ")) {
            i += 7;
            title = descr + i;
            i = read_field_data(descr, i);
            descr[i] = 0;
        }
        if ((i == 0 || descr[i - 1] == '\n' || descr[i - 1] == 0) &&
            str_here(descr + i, "Description: ")) {
            i += 13;
            description = descr + i;
            i = read_field_data(descr, i);
            descr[i] = 0;
        }
        i++;
    }
    if (title && description) {
        if (instlibs == NULL) {
            instlibs = calloc(1, sizeof(InstLibs));
            lib = instlibs;
        } else {
            lib = calloc(1, sizeof(InstLibs));
            if (ascii_ic_cmp(instlibs->name, fnm) > 0) {
                lib->next = instlibs;
                instlibs = lib;
            } else {
                ptr = instlibs;
                prev = NULL;
                while (ptr && ascii_ic_cmp(fnm, ptr->name) > 0) {
                    prev = ptr;
                    ptr = ptr->next;
                }
                if (prev)
                    prev->next = lib;
                lib->next = ptr;
            }
        }
        lib->name = calloc(strlen(fnm) + 1, sizeof(char));
        strcpy(lib->name, fnm);
        lib->title = calloc(strlen(title) + 1, sizeof(char));
        skip_consecutive_spaces(title, lib->title);
        lib->descr = calloc(strlen(description) + 1, sizeof(char));
        lib->si = 1;
        if (lib->descr != NULL) {
            skip_consecutive_spaces(description, lib->descr);
        }
        replace_char(lib->title, '\'', '\x13');
        replace_char(lib->descr, '\'', '\x13');
    } else {
        if (title)
            fprintf(stderr, "Failed to get Description from %s. ", fnm);
        else
            fprintf(stderr, "Failed to get Title from %s. ", fnm);
        fflush(stderr);
    }
}

void update_inst_libs(void) {
    Log("update_inst_libs()");
    DIR *d;
    struct dirent *dir;
    char fname[512];
    char *descr;
    InstLibs *il;
    int r;
    int n = 0;

    LibPath *lp = libpaths;
    while (lp) {
        d = opendir(lp->path);
        if (d) {
            while ((dir = readdir(d)) != NULL) {
#ifdef _DIRENT_HAVE_D_TYPE
                if (dir->d_name[0] != '.' && dir->d_type == DT_DIR) {
#else
                if (dir->d_name[0] != '.') {
#endif
                    il = instlibs;
                    r = 0;
                    while (il) {
                        if (strcmp(il->name, dir->d_name) == 0) {
                            il->si = 1;
                            r = 1; // Repeated library
                            break;
                        }
                        il = il->next;
                    }
                    if (r)
                        continue;
                    snprintf(fname, 511, "%s/%s/DESCRIPTION", lp->path,
                             dir->d_name);
                    descr = read_file(fname, 1);
                    if (descr) {
                        n++;
                        parse_descr(descr, dir->d_name);
                        free(descr);
                    }
                }
            }
            closedir(d);
        }
        lp = lp->next;
    }

    // New libraries found. Overwrite ~/.cache/R.nvim/inst_libs
    if (n) {
        char fname[1032];
        snprintf(fname, 1031, "%s/inst_libs", compldir);
        FILE *f = fopen(fname, "w");
        if (f == NULL) {
            fprintf(stderr, "Could not write to '%s'\n", fname);
            fflush(stderr);
        } else {
            il = instlibs;
            while (il) {
                if (il->si)
                    fprintf(f, "%s\006%s\006%s\n", il->name, il->title,
                            il->descr);
                il = il->next;
            }
            fclose(f);
        }
    }
}

// Read the list of libraries loaded in R, and run another R instance to build
// the objls_, args_, and alias_ files in compldir.
static void build_objls(void) {
    Log("build_objls()");
    unsigned long nsz;

    if (building_objls) {
        more_to_build = 1;
        return;
    }
    building_objls = 1;

    memset(compl_buffer, 0, compl_buffer_size);
    char *p = compl_buffer;

    PkgData *pkg = pkgList;

    // It would be easier to call R once for each library, but we will build
    // all cache files at once to avoid the cost of starting R many times.
    int k = 0;
    while (pkg) {
        if (pkg->to_build == 0) {
            nsz = strlen(pkg->name) + 1024 + (p - compl_buffer);
            if (compl_buffer_size < nsz)
                p = grow_buffer(&compl_buffer, &compl_buffer_size,
                                nsz - compl_buffer_size + 32768);
            p = str_cat(p, "'");
            p = str_cat(p, pkg->name);
            p = str_cat(p, "', ");
            pkg->to_build = 1;
            k++;
        }
        pkg = pkg->next;
    }

    if (k > 0) {
        // Build all the objls_ files.
        printf("lua require('r.server').build_objls({%s})\n", compl_buffer);
        fflush(stdout);
    }
}

static void finished_building_objls(void) {
    finish_bol();
    building_objls = 0;

    // If this function was called while it was running, build the remaining
    // cache files before saving the list of libraries whose cache files were
    // built.
    if (more_to_build) {
        more_to_build = 0;
        build_objls();
    }
}

// Called asynchronously and only if an objls_ file was actually built.
static void finish_bol(void) {
    Log("finish_bol()");

    char buf[1024];

    // Don't check the return value of run_R_code because some packages might
    // have been successfully built before R exiting with status > 0.

    // Check if all files were really built before trying to load them.
    PkgData *pkg = pkgList;
    while (pkg) {
        if (pkg->built == 0 && access(pkg->fname, F_OK) == 0)
            pkg->built = 1;
        if (pkg->built && !pkg->objls)
            load_pkg_data(pkg);
        pkg = pkg->next;
    }

    // Finally create a list of built objls_ because libnames_ might have
    // already changed and R.nvim would try to read objls_ files not built yet.
    snprintf(buf, 511, "%s/libs_in_rns_%s", localtmpdir, getenv("RNVIM_ID"));
    FILE *f = fopen(buf, "w");
    if (f) {
        PkgData *pkg = pkgList;
        while (pkg) {
            if (pkg->loaded && pkg->built && pkg->objls)
                fprintf(f, "%s_%s\n", pkg->name, pkg->version);
            pkg = pkg->next;
        }
        fclose(f);
    }

    // Message to Neovim: Update both syntax and Rhelp_list
    printf("lua require('r.server').update_Rhelp_list()\n");
    fflush(stdout);
}

// Read the DESCRIPTION of all installed libraries
char *complete_instlibs(char *p, const char *base) {
    update_inst_libs();

    if (!instlibs)
        return p;

    unsigned long len;
    InstLibs *il;
    size_t sz = 1024;
    char *buffer = malloc(sz);

    il = instlibs;
    while (il) {
        len = strlen(il->descr) + (p - compl_buffer) + 1024;
        if (compl_buffer_size < len)
            p = grow_buffer(&compl_buffer, &compl_buffer_size,
                            len - compl_buffer_size + 32768);

        if (str_here(il->name, base) && il->si) {
            if ((strlen(il->title) + strlen(il->descr)) > sz) {
                free(buffer);
                sz = strlen(il->title) + strlen(il->descr) + 1;
                buffer = malloc(sz);
            }

            p = str_cat(p, "{label = '");
            p = str_cat(p, il->name);
            p = str_cat(p, "', cls = 'l', env = '**");
            format(il->title, buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            p = str_cat(p, "**\x14\x14");
            format(il->descr, buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            p = str_cat(p, "\x14'},");
        }
        il = il->next;
    }

    return p;
}

void update_pkg_list(char *libnms) {
    Log("update_pkg_list()");
    char buf[512];
    char *s, *nm, *vrsn;
    PkgData *pkg;

    // Consider that all packages were unloaded
    pkg = pkgList;
    while (pkg) {
        pkg->loaded = 0;
        pkg = pkg->next;
    }

    if (libnms) {
        // called by nvimcom
        Log("update_pkg_list != NULL");
        while (*libnms) {
            nm = libnms;
            while (*libnms != '\003')
                libnms++;
            *libnms = 0;
            libnms++;
            vrsn = libnms;
            while (*libnms != '\004')
                libnms++;
            *libnms = 0;
            libnms++;
            if (*libnms == '\n') // this was the last package
                libnms++;

            if (strstr(nm, " ") || strstr(vrsn, " ")) {
                break;
            }

            pkg = get_pkg(nm);
            if (pkg)
                pkg->loaded = 1;
            else
                add_pkg(nm, vrsn);
        }
    } else {
        // Called during the initialization with libnames_ created by
        // R/before_rns.R to highlight function from the `library()` and
        // `require()` commands present in the file being edited.
        char lbnm[128];
        Log("update_pkg_list == NULL");

        snprintf(buf, 511, "%s/libnames_%s", tmpdir, getenv("RNVIM_ID"));
        FILE *flib = fopen(buf, "r");
        if (!flib) {
            fprintf(stderr, "Failed to open \"%s\"\n", buf);
            fflush(stderr);
            return;
        }

        while ((s = fgets(lbnm, 127, flib))) {
            while (*s != '_')
                s++;
            *s = 0;
            s++;
            vrsn = s;
            while (*s != '\n')
                s++;
            *s = 0;

            pkg = get_pkg(lbnm);
            if (pkg)
                pkg->loaded = 1;
            else
                add_pkg(lbnm, vrsn);
        }
        fclose(flib);
    }

    // No command run yet
    if (!pkgList)
        return;

    // Delete data from unloaded packages to ensure that reloaded packages go
    // to the bottom of the Object Browser list
    pkg = pkgList;
    if (pkg->loaded == 0) {
        pkgList = pkg->next;
        pkg_delete(pkg);
    } else {
        PkgData *prev = pkg;
        pkg = pkg->next;
        while (pkg) {
            if (pkg->loaded == 0) {
                prev->next = pkg->next;
                pkg_delete(pkg);
                pkg = prev->next;
            } else {
                prev = pkg;
                pkg = prev->next;
            }
        }
    }
}

/**
 * TODO: Candidate for data_structures.c
 *
 * Description:
 * @param s:
 * @param stt:
 * @return
 */
int get_list_status(const char *s, int stt) {
    ListStatus *p = search(listTree, s);
    if (p)
        return p->status;
    insert(listTree, s, stt);
    return stt;
}

/**
 * TODO: Candidate for data_structures.c
 *
 * Description:
 * @param s:
 */
void toggle_list_status(const char *s) {
    ListStatus *p = search(listTree, s);
    if (p)
        p->status = !p->status;
}

/**
 * @brief Make a copy of a string, replacing special bytes with the
 * represented characters.
 *
 * @param o Original string.
 * @param d Destination buffer.
 * @param sz String size.
 */
void copy_str_to_ob(const char *o, char *d, int sz) {
    int i = 0;
    while (o[i] && i < sz) {
        if (o[i] == '\x13') {
            d[i] = '\'';
        } else if (o[i] == '\x12') {
            d[i] = '\\';
        } else {
            d[i] = o[i];
        }
        i++;
    }
    d[i] = 0;
}

static const char *write_ob_line(const char *p, const char *bs, char *prfx,
                                 int closeddf, FILE *fl) {
    char base1[128];
    char base2[128];
    char prefix[128];
    char newprfx[96];
    char nm[160];
    char descr[160];
    const char *f[7];
    const char *s;    // Diagnostic pointer
    const char *bsnm; // Name of object including its parent list, data.frame or
                      // S4 object
    int df;           // Is data.frame? If yes, start open unless closeddf = 1
    int i;
    int ne;

    nLibObjs--;

    bsnm = p;
    p += strlen(bs);

    i = 0;
    while (i < 7) {
        f[i] = p;
        i++;
        while (*p != 0)
            p++;
        p++;
    }
    while (*p != '\n' && *p != 0)
        p++;
    if (*p == '\n')
        p++;

    if (closeddf)
        df = 0;
    else if (f[1][0] == '$')
        df = OpenDF;
    else
        df = OpenLS;

    copy_str_to_ob(f[0], nm, 159);

    if (f[1][0] == '(')
        s = f[5];
    else
        s = f[6];
    if (s[0] == 0) {
        descr[0] = 0;
    } else {
        copy_str_to_ob(s, descr, 159);
    }

    if (!(bsnm[0] == '.' && allnames == 0))
        fprintf(fl, "   %s%c#%s\t%s\n", prfx, f[1][0], nm, descr);

    if (*p == 0)
        return p;

    if (f[1][0] == '[' || f[1][0] == '$' || f[1][0] == '<' || f[1][0] == ':') {
        s = f[6];
        s++;
        s++;
        s++; // Number of elements (list)
        if (f[1][0] == '$') {
            while (*s && *s != ' ')
                s++;
            s++; // Number of columns (data.frame)
        }
        ne = atoi(s);
        if (f[1][0] == '[' || f[1][0] == '$' || f[1][0] == ':') {
            snprintf(base1, 127, "%s$", bsnm);  // Named list
            snprintf(base2, 127, "%s[[", bsnm); // Unnamed list
        } else {
            snprintf(base1, 127, "%s@", bsnm); // S4 object
            snprintf(
                base2, 127, "%s[[",
                bsnm); // S4 object always have names but base2 must be defined
        }

        if (get_list_status(bsnm, df) == 0) {
            while (str_here(p, base1) || str_here(p, base2)) {
                while (*p != '\n')
                    p++;
                p++;
                nLibObjs--;
            }
            return p;
        }

        if (str_here(p, base1) == 0 && str_here(p, base2) == 0)
            return p;

        int len = strlen(prfx);
        if (nvimcom_is_utf8) {
            int j = 0, i = 0;
            while (i < len) {
                if (prfx[i] == '\xe2') {
                    i += 3;
                    if (prfx[i - 1] == '\x80' || prfx[i - 1] == '\x94') {
                        newprfx[j] = ' ';
                        j++;
                    } else {
                        newprfx[j] = '\xe2';
                        j++;
                        newprfx[j] = '\x94';
                        j++;
                        newprfx[j] = '\x82';
                        j++;
                    }
                } else {
                    newprfx[j] = prfx[i];
                    i++, j++;
                }
            }
            newprfx[j] = 0;
        } else {
            for (int i = 0; i < len; i++) {
                if (prfx[i] == '-' || prfx[i] == '`')
                    newprfx[i] = ' ';
                else
                    newprfx[i] = prfx[i];
            }
            newprfx[len] = 0;
        }

        // Check if the next list element really is there
        while (str_here(p, base1) || str_here(p, base2)) {
            // Check if this is the last element in the list
            s = p;
            while (*s != '\n')
                s++;
            s++;
            ne--;
            if (ne == 0) {
                snprintf(prefix, 112, "%s%s", newprfx, strL);
            } else {
                if (str_here(s, base1) || str_here(s, base2))
                    snprintf(prefix, 112, "%s%s", newprfx, strT);
                else
                    snprintf(prefix, 112, "%s%s", newprfx, strL);
            }

            if (*p) {
                if (str_here(p, base1))
                    p = write_ob_line(p, base1, prefix, 0, fl);
                else
                    p = write_ob_line(p, bsnm, prefix, 0, fl);
            }
        }
    }
    return p;
}

/**
 * @brief Updates the buffer containing the global environment data from R.
 *
 * This function is responsible for updating the global environment buffer
 * with new data received from R. It ensures the buffer is appropriately sized
 * and formatted for further processing. The global environment buffer contains
 * data about the R global environment, such as variables and functions, which
 * are used for features like auto-completion in Neovim. The function also
 * triggers a refresh of related UI components if necessary.
 *
 * @param g A string containing the new global environment data.
 */
void update_glblenv_buffer(char *g) {
    Log("update_glblenv_buffer()");
    int glbnv_size;

    if (glbnv_buffer) {
        if (strlen(g) > glbnv_buffer_sz) {
            free(glbnv_buffer);
            glbnv_buffer_sz = strlen(g) + 4096;
            glbnv_buffer = malloc(glbnv_buffer_sz * sizeof(char));
        }
    } else {
        glbnv_buffer_sz = strlen(g) + 4096;
        glbnv_buffer = malloc(glbnv_buffer_sz * sizeof(char));
    }
    strcpy(glbnv_buffer, g);
    if (check_omils_buffer(glbnv_buffer, &glbnv_size) == NULL)
        return;
}

void compl2ob(void) {
    Log("compl2ob()");
    FILE *f = fopen(globenv, "w");
    if (!f) {
        fprintf(stderr, "Error opening \"%s\" for writing\n", globenv);
        fflush(stderr);
        return;
    }

    fprintf(f, ".GlobalEnv | Libraries\n\n");

    if (glbnv_buffer) {
        const char *s = glbnv_buffer;
        while (*s)
            s = write_ob_line(s, "", "", 0, f);
    }

    fclose(f);
    if (auto_obbr) {
        fputs("lua require('r.browser').update_OB('GlobalEnv')\n", stdout);
        fflush(stdout);
    }
}

void lib2ob(void) {
    Log("lib2ob()");
    FILE *f = fopen(liblist, "w");
    if (!f) {
        fprintf(stderr, "Failed to open \"%s\"\n", liblist);
        fflush(stderr);
        return;
    }
    fprintf(f, "Libraries | .GlobalEnv\n\n");

    char lbnmc[512];
    PkgData *pkg;
    const char *p;
    int stt;

    pkg = pkgList;
    while (pkg) {
        if (pkg->loaded) {
            if (pkg->descr)
                fprintf(f, "   :#%s\t%s\n", pkg->name, pkg->descr);
            else
                fprintf(f, "   :#%s\t\n", pkg->name);
            snprintf(lbnmc, 511, "%s:", pkg->name);
            stt = get_list_status(lbnmc, 0);
            if (pkg->objls && pkg->nobjs > 0 && stt == 1) {
                p = pkg->objls;
                nLibObjs = pkg->nobjs - 1;
                while (*p) {
                    if (nLibObjs == 0)
                        p = write_ob_line(p, "", strL, 1, f);
                    else
                        p = write_ob_line(p, "", strT, 1, f);
                }
            }
        }
        pkg = pkg->next;
    }

    fclose(f);
    fputs("lua require('r.browser').update_OB('libraries')\n", stdout);
    fflush(stdout);
}

void change_all(ListStatus *root, int stt) {
    if (root != NULL) {
        // Open all but libraries
        if (!(stt == 1 && root->key[strlen(root->key) - 1] == ':'))
            root->status = stt;
        change_all(root->left, stt);
        change_all(root->right, stt);
    }
}

void print_listTree(ListStatus *root, FILE *f) {
    if (root != NULL) {
        fprintf(f, "%d :: %s\n", root->status, root->key);
        print_listTree(root->left, f);
        print_listTree(root->right, f);
    }
}

static void fill_inst_libs(void) {
    InstLibs *il = NULL;
    char fname[1032];
    snprintf(fname, 1031, "%s/inst_libs", compldir);
    char *b = read_file(fname, 0);
    if (!b)
        return;
    char *s = b;
    char *n, *t, *d;
    while (*s) {
        n = s;
        t = NULL;
        d = NULL;
        while (*s && *s != '\006')
            s++;
        if (*s && *s == '\006') {
            *s = 0;
            s++;
            if (*s) {
                t = s;
                while (*s && *s != '\006')
                    s++;
                if (*s && *s == '\006') {
                    *s = 0;
                    s++;
                    if (*s) {
                        d = s;
                        while (*s && *s != '\n')
                            s++;
                        if (*s && *s == '\n') {
                            *s = 0;
                            s++;
                        } else
                            break;
                    } else
                        break;
                } else
                    break;
            }
            if (d) {
                if (il) {
                    il->next = calloc(1, sizeof(InstLibs));
                    il = il->next;
                } else {
                    il = calloc(1, sizeof(InstLibs));
                }
                if (instlibs == NULL)
                    instlibs = il;
                il->name = malloc((strlen(n) + 1) * sizeof(char));
                strcpy(il->name, n);
                il->title = malloc((strlen(t) + 1) * sizeof(char));
                strcpy(il->title, t);
                il->descr = malloc((strlen(d) + 1) * sizeof(char));
                strcpy(il->descr, d);
            }
        }
    }
    free(b);
}

static void send_rns_info(void) {
    printf("lua require('r.server').echo_rns_info('CMPR_DOC_WIDTH: %s. Loaded "
           "packages:",
           getenv("CMPR_DOC_WIDTH"));
    PkgData *pkg = pkgList;
    while (pkg) {
        printf(" %s", pkg->name);
        pkg = pkg->next;
    }
    printf("')\n");
    fflush(stdout);
}

/*
 * TODO:: Candidate for server_init.c
 *
 * @desc: used before stdin_loop() in main() to initialize the server.
 */
static void init(void) {
#ifdef Debug_NRS
    time_t t;
    time(&t);
    FILE *f = fopen("/dev/shm/rnvimserver_log", "w");
    fprintf(f, "NSERVER LOG | %s\n\n", ctime(&t));
    fclose(f);
#endif

    char envstr[1024];

    envstr[0] = 0;
    if (getenv("LC_MESSAGES"))
        strcat(envstr, getenv("LC_MESSAGES"));
    if (getenv("LC_ALL"))
        strcat(envstr, getenv("LC_ALL"));
    if (getenv("LANG"))
        strcat(envstr, getenv("LANG"));
    int len = strlen(envstr);
    for (int i = 0; i < len; i++)
        envstr[i] = toupper(envstr[i]);
    if (strstr(envstr, "UTF-8") != NULL || strstr(envstr, "UTF8") != NULL) {
        nvimcom_is_utf8 = 1;
        strcpy(strL, "\xe2\x94\x94\xe2\x94\x80 ");
        strcpy(strT, "\xe2\x94\x9c\xe2\x94\x80 ");
    } else {
        nvimcom_is_utf8 = 0;
        strcpy(strL, "`- ");
        strcpy(strT, "|- ");
    }

    if (!getenv("RNVIM_SECRET")) {
        fprintf(stderr, "RNVIM_SECRET not found\n");
        fflush(stderr);
        exit(1);
    }
    strncpy(VimSecret, getenv("RNVIM_SECRET"), 127);
    VimSecretLen = strlen(VimSecret);

    strncpy(compl_cb, getenv("RNVIM_COMPL_CB"), 63);
    strncpy(resolve_cb, getenv("RNVIM_RSLV_CB"), 63);
    strncpy(compldir, getenv("RNVIM_COMPLDIR"), 255);
    strncpy(tmpdir, getenv("RNVIM_TMPDIR"), 255);
    if (getenv("RNVIM_LOCAL_TMPDIR")) {
        strncpy(localtmpdir, getenv("RNVIM_LOCAL_TMPDIR"), 255);
    } else {
        strncpy(localtmpdir, getenv("RNVIM_TMPDIR"), 255);
    }
    snprintf(liblist, 575, "%s/liblist_%s", localtmpdir, getenv("RNVIM_ID"));
    snprintf(globenv, 575, "%s/globenv_%s", localtmpdir, getenv("RNVIM_ID"));

    if (getenv("RNVIM_OPENDF"))
        OpenDF = 1;
    else
        OpenDF = 0;
    if (getenv("RNVIM_OPENLS"))
        OpenLS = 1;
    else
        OpenLS = 0;
    if (getenv("RNVIM_OBJBR_ALLNAMES"))
        allnames = 1;
    else
        allnames = 0;

    // Fill immediately the list of installed libraries. Each entry still has
    // to be confirmed by listing the directories in .libPaths.
    fill_inst_libs();

    // List tree sentinel
    listTree = new_ListStatus("base:", 0);

    compl_buffer = calloc(compl_buffer_size, sizeof(char));

    char fname[512];
    snprintf(fname, 511, "%s/libPaths", tmpdir);
    char *b = read_file(fname, 1);
#ifdef WIN32
    for (int i = 0; i < strlen(b); i++)
        if (b[i] == '\\')
            b[i] = '/';
#endif
    if (b) {
        libpaths = calloc(1, sizeof(LibPath));
        libpaths->path = b;
        LibPath *p = libpaths;
        while (*b) {
            if (*b == '\n') {
                while (*b == '\n' || *b == '\r') {
                    *b = 0;
                    b++;
                }
                if (*b) {
                    p->next = calloc(1, sizeof(LibPath));
                    p = p->next;
                    p->path = b;
                } else {
                    break;
                }
            }
            b++;
        }
    }
    update_inst_libs();
    update_pkg_list(NULL);
    build_objls();

    printf("lua vim.g.R_Nvim_status = 3\n");
    fflush(stdout);

    Log("init() finished");
}

int count_twice(const char *b1, const char *b2, const char ch) {
    int n1 = 0;
    int n2 = 0;
    for (unsigned long i = 0; i < strlen(b1); i++)
        if (b1[i] == ch)
            n1++;
    for (unsigned long i = 0; i < strlen(b2); i++)
        if (b2[i] == ch)
            n2++;
    return n1 == n2;
}

/*
 * TODO: Candidate for completion_services.c
 *
 * @desc: Return user_data of a specific item with function usage, title and
 * description to be displayed in the float window
 * @param wrd:
 * @param pkg:
 * */
void resolve(const char *wrd, const char *pkg) {
    Log("resolve: %s, %s", wrd, pkg);
    int i;
    unsigned long nsz;
    const char *f[7];
    char *s;

    if (strcmp(pkg, ".GlobalEnv") == 0) {
        s = glbnv_buffer;
    } else {
        PkgData *pd = pkgList;
        while (pd) {
            if (strcmp(pkg, pd->name) == 0)
                break;
            else
                pd = pd->next;
        }

        if (pd == NULL)
            return;

        s = pd->objls;
    }

    memset(compl_buffer, 0, compl_buffer_size);
    char *p = compl_buffer;

    while (*s != 0) {
        if (strcmp(s, wrd) == 0) {
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
            if (*s == '\n')
                s++;

            if (f[1][0] == '(' && str_here(f[4], ">not_checked<")) {
                snprintf(compl_buffer, 1024,
                         "E%snvimcom:::nvim.GlobalEnv.fun.args(\"%s\")\n",
                         getenv("RNVIM_ID"), wrd);
                send_to_nvimcom(compl_buffer);
                return;
            }

            // Avoid buffer overflow if the information is bigger than
            // compl_buffer.
            nsz = strlen(f[4]) + strlen(f[5]) + strlen(f[6]) + 1024 +
                  (p - compl_buffer);
            if (compl_buffer_size < nsz)
                p = grow_buffer(&compl_buffer, &compl_buffer_size,
                                nsz - compl_buffer_size + 32768);

            size_t sz = strlen(f[5]) + strlen(f[6]) + 16;
            char *buffer = malloc(sz);
            p = str_cat(p, f[2]);
            p = str_cat(p, " ");
            p = str_cat(p, f[3]);
            p = str_cat(p, "::");
            p = str_cat(p, f[0]);
            p = str_cat(p, "\x14\x14**");
            format(f[5], buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            p = str_cat(p, "**\x14\x14");
            format(f[6], buffer, ' ', '\x14');
            p = str_cat(p, buffer);
            free(buffer);
            if (f[1][0] == '(') {
                char *b = format_usage(f[0], f[4]);
                p = str_cat(p, b);
                free(b);
            }
            printf("lua %s('%s')\n", resolve_cb, compl_buffer);
            fflush(stdout);
            return;
        }
        while (*s != '\n')
            s++;
        s++;
    }
    printf("lua %s('')\n", resolve_cb);
    fflush(stdout);
}

char *find_obj(char *objls, const char *dfbase) {
    while (*objls != 0) {
        if (str_here(objls, dfbase)) {
            return objls;
        } else {
            while (*objls != '\n')
                objls++;
            objls++;
        }
    }
    return NULL;
}

char *get_df_cols(const char *dtfrm, const char *base, char *p) {
    size_t skip = strlen(dtfrm) + 1; // The data.frame name + "$"
    unsigned long nsz;
    char dfbase[64];
    snprintf(dfbase, 63, "%s$%s", dtfrm, base);
    char *s = NULL;

    if (glbnv_buffer)
        s = find_obj(glbnv_buffer, dfbase);

    if (!s) {
        PkgData *pd = pkgList;
        while (pd) {
            if (pd->objls) {
                s = find_obj(pd->objls, dfbase);
                if (s)
                    break;
            }
            pd = pd->next;
        }
    }

    if (!s)
        return p;

    while (*s && str_here(s, dfbase)) {
        // Avoid buffer overflow if the information is bigger than
        // compl_buffer.
        nsz = strlen(s) + 1024 + (p - compl_buffer);
        if (compl_buffer_size < nsz)
            p = grow_buffer(&compl_buffer, &compl_buffer_size,
                            nsz - compl_buffer_size + 32768);

        p = str_cat(p, "{label = '");
        p = str_cat(p, s + skip);
        p = str_cat(p, "', cls = 'c', env = '");
        p = str_cat(p, dtfrm);
        p = str_cat(p, "'}, ");

        while (*s != '\n')
            s++;
        s++;
    }

    return p;
}

// Return the menu items for auto completion, but don't include function
// usage, and tittle and description of objects because if the buffer becomes
// too big it will be truncated.
char *parse_objls(const char *s, const char *base, const char *pkg, char *lib,
                  char *p) {
    int i;
    unsigned long nsz;
    const char *f[7];

    while (*s != 0) {
        if (fuzzy_find(s, base)) {
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
            if (*s == '\n')
                s++;

            // Skip elements of lists unless the user is really looking for
            // them, and skip lists if the user is looking for one of its
            // elements.
            if (!count_twice(base, f[0], '@'))
                continue;
            if (!count_twice(base, f[0], '$'))
                continue;
            if (!count_twice(base, f[0], '['))
                continue;

            // Avoid buffer overflow if the information is bigger than
            // compl_buffer.
            nsz = 1024 + (p - compl_buffer);
            if (compl_buffer_size < nsz)
                p = grow_buffer(&compl_buffer, &compl_buffer_size,
                                nsz - compl_buffer_size + 32768);

            p = str_cat(p, "{label = '");
            if (pkg) {
                p = str_cat(p, pkg);
                p = str_cat(p, "::");
            }
            p = str_cat(p, f[0]);
            p = str_cat(p, "', cls = '");
            p = str_cat(p, f[1]);
            if (lib) {
                p = str_cat(p, "', env = '");
                p = str_cat(p, lib);
            }
            p = str_cat(p, "'}, ");
            // big data will be truncated.
        } else {
            while (*s != '\n')
                s++;
            s++;
        }
    }
    return p;
}

void get_alias(char **pkg, char **fun) {
    char *s = malloc(strlen(*pkg) + strlen(*fun) + 3);
    sprintf(s, "%s\n", *fun);
    char *p;
    char *f;
    PkgData *pd = pkgList;
    if (**pkg != '#')
        while (pd && !str_here(pd->name, *pkg))
            pd = pd->next;
    while (pd) {
        if (pd->alias) {
            p = pd->alias;
            while (*p) {
                f = p;
                while (*f)
                    f++;
                f++;
                if (*f && str_here(f, s)) {
                    *pkg = pd->name;
                    *fun = p;
                    return;
                }
                p = f;
                while (*p && *p != '\n')
                    p++;
                p++;
            }
        }
        pd = pd->next;
    }
    *pkg = NULL;
}

void resolve_arg_item(char *pkg, char *fnm, char *itm) {
    Log("resolve_arg_item: %s, %s, %s", pkg, fnm, itm);
    char item[128];
    snprintf(item, 127, "%s\005", itm);
    PkgData *p = pkgList;
    while (p) {
        if (strcmp(p->name, pkg) == 0) {
            if (p->args) {
                char *s = p->args;
                while (*s) {
                    if (strcmp(s, fnm) == 0) {
                        while (*s)
                            s++;
                        s++;
                        while (*s != '\n') {
                            if (str_here(s, item)) {
                                while (*s && *s != '\005')
                                    s++;
                                s++;
                                char *b = calloc(strlen(s) + 2, sizeof(char));
                                format(s, b, ' ', '\x14');
                                printf("lua %s('%s')\n", resolve_cb, b);
                                fflush(stdout);
                                free(b);
                                return;
                            }
                            s++;
                        }
                        printf("lua %s('')\n", resolve_cb);
                        fflush(stdout);
                        return;
                    } else {
                        while (*s != '\n')
                            s++;
                        s++;
                    }
                }
            }
            break;
        }
        p = p->next;
    }
    printf("lua %s('')\n", resolve_cb);
    fflush(stdout);
}

/*
 * TODO: Candidate for completion_services.c
 *
 * @desc:
 * @param p:
 * @param funcnm:
 * */
char *complete_args(char *p, char *funcnm) {
    // Check if function is "pkg::fun"
    char *pkg = NULL;
    if (strstr(funcnm, "::")) {
        pkg = funcnm;
        funcnm = strstr(funcnm, "::");
        *funcnm = 0;
        funcnm++;
        funcnm++;
    }

    PkgData *pd = pkgList;
    char *s;
    char a[64];
    int i;
    while (pd) {
        if (pd->objls && (pkg == NULL || (pkg && strcmp(pd->name, pkg) == 0))) {
            s = pd->objls;
            while (*s != 0) {
                if (strcmp(s, funcnm) == 0) {
                    i = 4;
                    while (i) {
                        s++;
                        if (*s == 0)
                            i--;
                    }
                    s++;
                    while (*s) {
                        i = 0;
                        p = str_cat(p, "{label = '");
                        while (*s != '\x05' && i < 63) {
                            if (*s == '\x04') {
                                a[i] = ' ';
                                i++;
                                a[i] = '=';
                                i++;
                                a[i] = ' ';
                                i++;
                                while (*s != '\x05')
                                    s++;
                            } else {
                                a[i] = *s;
                                i++;
                                s++;
                            }
                        }
                        a[i] = 0;
                        p = str_cat(p, a);
                        p = str_cat(p, "', cls = 'a', env='");
                        p = str_cat(p, pd->name);
                        p = str_cat(p, "\x02");
                        p = str_cat(p, funcnm);
                        p = str_cat(p, "'},");
                        s++;
                    }
                    break;
                } else {
                    while (*s != '\n')
                        s++;
                    s++;
                }
            }
        }
        pd = pd->next;
    }
    return p;
}

/*
 * TODO: Candidate for completion_services.c
 *
 * @desc:
 * @param id: Completion ID (integer incremented at each completion), possibily
 * used by cmp to abort outdated completion.
 * @param base: Keyword being completed.
 * @param funcnm: Function name when the keyword being completed is one of its
 * arguments.
 * @param dtfrm: Name of data.frame when the keyword being completed is an
 * argument of a function listed in either fun_data_1 or fun_data_2.
 * @param funargs Function arguments from a .GlobalEnv function.
 */
void complete(const char *id, char *base, char *funcnm, char *dtfrm,
              char *funargs) {
    Log("complete(%s, %s, %s, %s, %s)", id, base, funcnm, dtfrm, funargs);
    char *p;

    memset(compl_buffer, 0, compl_buffer_size);
    p = compl_buffer;

    // Get menu completion for installed libraries
    if (funcnm && *funcnm == '\004') {
        p = complete_instlibs(p, base);
        printf("\x11%" PRI_SIZET "\x11"
               "lua %s(%s, {%s})\n",
               strlen(compl_cb) + strlen(id) + strlen(compl_buffer) + 10,
               compl_cb, id, compl_buffer);
        fflush(stdout);
        return;
    }

    if (funargs || funcnm) {

        if (funargs) {
            // Insert arguments of .GlobalEnv function
            p = str_cat(p, funargs);
        } else if (funcnm) {
            // Completion of arguments of a library's function
            p = complete_args(p, funcnm);

            // Add columns of a data.frame
            if (dtfrm) {
                p = get_df_cols(dtfrm, base, p);
            }
        }

        // base will be empty if completing only function arguments
        if (base[0] == 0) {
            printf("\x11%" PRI_SIZET "\x11"
                   "lua %s(%s, {%s})\n",
                   strlen(compl_cb) + strlen(id) + strlen(compl_buffer) + 10,
                   compl_cb, id, compl_buffer);
            fflush(stdout);
            return;
        }
    }

    // Finish filling the compl_buffer
    if (glbnv_buffer)
        p = parse_objls(glbnv_buffer, base, NULL, ".GlobalEnv", p);

    PkgData *pd = pkgList;

    // Check if base is "pkg::fun"
    char *pkg = NULL;
    if (strstr(base, "::")) {
        pkg = base;
        base = strstr(base, "::");
        *base = 0;
        base++;
        base++;
    }

    while (pd) {
        if (pd->objls && (pkg == NULL || (pkg && strcmp(pd->name, pkg) == 0)))
            p = parse_objls(pd->objls, base, pkg, pd->name, p);
        pd = pd->next;
    }

    printf("\x11%" PRI_SIZET "\x11"
           "lua %s(%s, {%s})\n",
           strlen(compl_cb) + strlen(id) + strlen(compl_buffer) + 10, compl_cb,
           id, compl_buffer);
    fflush(stdout);
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
                    change_all(listTree, 1);
                else
                    change_all(listTree, 0);
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
            switch (*msg) {
            case '1': // Check if R is running
                if (PostMessage(RConsole, WM_NULL, 0, 0)) {
                    fprintf(stderr, "R was already started\n");
                    fflush(stderr);
                } else {
                    printf("lua require('r.windows').clean_and_start_Rgui()\n");
                    fflush(stdout);
                }
                break;
            case '3': // SendToRConsole
                msg++;
                SendToRConsole(msg);
                break;
            case '4': // SaveWinPos
                msg++;
                SaveWinPos(msg);
                break;
            case '5': // ArrangeWindows
                msg++;
                ArrangeWindows(msg);
                break;
            case '6':
                RClearConsole();
                break;
            case '7': // RaiseNvimWindow
                if (NvimHwnd)
                    SetForegroundWindow(NvimHwnd);
                break;
            }
            break;
#endif
        case '9': // Quit now
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
