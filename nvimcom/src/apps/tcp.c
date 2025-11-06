#include <stdio.h>  // Standard input/output definitions
#include <stdlib.h> // Standard library
#include <string.h> // String handling functions

#ifdef __FreeBSD__
#include <netinet/in.h> // BSD network library
#endif

#include <unistd.h> // POSIX operating system API
#ifdef WIN32
#include <inttypes.h>
#include <process.h>
#include <time.h>
#include <winsock2.h>
#include <windows.h>
#else
#include <netdb.h>
#include <pthread.h>
#include <sys/socket.h>
#endif

#include "global_vars.h"
#include "logging.h"
#include "utilities.h"
#include "complete.h"
#include "hover.h"
#include "obbr.h"
#include "tcp.h"
#include "lsp.h"

#ifdef WIN32
static HANDLE Tid; // Identifier of thread running TCP connection loop.
#else
static pthread_t Tid; // Thread ID
#endif

struct sockaddr_in servaddr;         // Server address structure
static int sockfd;                   // socket file descriptor
static int connfd;                   // Connection file descriptor
static unsigned long fb_size = 1024; // Final buffer size
static int r_conn;                   // R connection status flag
static char *VimSecret;              // Secret for communication with Vim
static int VimSecretLen;             // Length of Vim secret
static char *finalbuffer;            // Final buffer for message processing

// Parse the message from R
static void ParseMsg(char *b) {
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
        case 'C':
            b++;
            complete(b);
            break;
        case 'R':
            b++;
            const char *rid = strtok(b, "|");
            const char *lbl = strtok(NULL, "|");
            const char *knd = strtok(NULL, "|");
            const char *cls = strtok(NULL, "|");
            const char *doc = strtok(NULL, "|");
            send_item_doc(doc, rid, lbl, knd, cls);
            break;
        case 'H':
            b++;
            const char *hid = strtok(b, "|");
            const char *hdoc = strtok(NULL, "|");
            send_hover_doc(hid, hdoc);
            break;
        case 'D': // set max_depth of lists in the completion data
            b++;
            set_max_depth(atoi(b));
            break;
        }
        return;
    }

    // Send the command to R.nvim
    char *cmd = (char *)malloc(sizeof(char) * strlen(b) + 1);
    if (cmd) {
        strcpy(cmd, b);
        send_cmd_to_nvim(b);
        free(cmd);
    }
}

static void RegisterPort(int bindportn) // Function to register port number to R
{
    // Register the port:
    char pcmd[128];
    sprintf(pcmd, "require('r.run').set_rns_port('%d')", bindportn);
    send_cmd_to_nvim(pcmd);
}

/**
 * @brief Initializes the socket for the server.
 *
 * @note For Windows, WSAStartup is called to start the Winsock API.
 */
static void initialize_socket(void) {
    if (!VimSecret) {
        if (!getenv("RNVIM_SECRET")) {
            fprintf(stderr, "RNVIM_SECRET not found\n");
            fflush(stderr);
            exit(1);
        }
        VimSecretLen = strlen(getenv("RNVIM_SECRET"));
        VimSecret = malloc(VimSecretLen + 1);
        strcpy(VimSecret, getenv("RNVIM_SECRET"));
    }

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
 * @note A previous version of this function was adapted from
 * https://www.geeksforgeeks.org/socket-programming-in-cc-handling-multiple-clients-on-server-without-multi-threading/
 */
static void setup_server_socket(void) {
    Log("setup_server_socket()");
    initialize_socket();
    bind_to_port();
    listening_for_connections();
    accept_connection();
}

// Get the whole message from the socket
static void get_whole_msg(char *b) {
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
// Thread function to receive messages on Windows
static DWORD WINAPI receive_msg(__attribute__((unused)) void *arg)
#else
// Thread function to receive messages on Unix
static void *receive_msg(void *v)
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
            sockfd = -1;
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
#ifdef WIN32
    return 0;
#else
    return NULL;
#endif
}

// Function to send messages to R (nvimcom package)
void send_to_nvimcom(char *msg) {
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

void nvimcom_eval(const char *cmd) {
    char buf[1024];
    snprintf(buf, 1023, "E%s%s", getenv("RNVIM_ID"), cmd);
    send_to_nvimcom(buf);
}

// Start server and listen for connections
void start_server(void) {
    setup_server_socket();

    // Receive messages from TCP and output them to stdout
#ifdef WIN32
    DWORD ti;
    Tid = CreateThread(NULL, 0, receive_msg, NULL, 0, &ti);
#else
    pthread_create(&Tid, NULL, receive_msg, NULL);
#endif
}

// Close the TCP connection and cancel the server thread.
// Called during rnvimserver shutdown.
void stop_server(void) {
#ifdef WIN32
    closesocket(sockfd);
    WSACleanup();
    TerminateThread(Tid, 0);
    CloseHandle(Tid);
#else
    if (sockfd > 0)
        close(sockfd);
    if (Tid) {
        pthread_cancel(Tid);
        pthread_join(Tid, NULL);
    }
#endif
}
