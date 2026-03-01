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
#include "resolve.h"
#include "hover.h"
#include "signature.h"
#include "obbr.h"
#include "tcp.h"
#include "lsp.h"

#ifdef WIN32
static HANDLE Tid; // Identifier of thread running TCP connection loop.
#else
static pthread_t Tid; // Thread ID
#endif

struct sockaddr_in servaddr;  // Server address structure
static int sockfd;            // socket file descriptor
static int connfd;            // Connection file descriptor
static size_t fb_size = 1024; // Final buffer size
static int r_conn;            // R connection status flag
static char *VimSecret;       // Secret for communication with Vim
static int VimSecretLen;      // Length of Vim secret
static char *finalbuffer;     // Final buffer for message processing

// Parse the message from R
static void ParseMsg(char *b) {
#ifdef Debug_NRS
    if (strlen(b) > 2000)
        Log("\x1b[32mTCP_in\x1b[0m, strlen = %zu", strlen(b));
    else
        Log("\x1b[32mTCP in\x1b[0m: %s", b);
#endif

    if (*b == '+') {
        char code;
        char *id;
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
            update_loaded_libs(b);
            if (auto_obbr)
                lib2ob();
            break;
        case 'C':
            b++;
            complete(b);
            break;
        case 'R':
        case 'H':
        case 's':
        case 'h':
            code = *b;
            b++;
            id = b;
            b = strstr(b, "|");
            *b = '\0';
            if (code == 'R') {
                send_item_doc(id, ++b);
            } else if (code == 'H') {
                send_hover_doc(id, ++b);
            } else if (code == 's') {
                sig_seek(id, ++b);
            } else if (code == 'h') {
                hov_seek(id, ++b);
            }
            break;
        case 'S':
            b++;
            id = b;
            b = strstr(b, "|");
            *b = 0;
            b++;
            const char *wrd = b;
            b = strstr(b, "|");
            *b = 0;
            glbnv_signature(id, wrd, ++b);
            break;
        case 'D': // set max_depth of lists in the completion data
            b++;
            set_max_depth(atoi(b));
            break;
        case 'd': // single definition result from R
            b++;
            char *def_id = b;
            b = strstr(b, "|");
            if (b) {
                *b = '\0';
                b++;
                char *def_file = b;
                b = strstr(b, "|");
                if (b) {
                    *b = '\0';
                    b++;
                    char *def_line = b;
                    b = strstr(b, "|");
                    if (b) {
                        *b = '\0';
                        char *def_col = b + 1;
                        // Convert line from 1-indexed (R) to 0-indexed (LSP)
                        int line = atoi(def_line) - 1;
                        int col = atoi(def_col);
                        // Build LSP Location response
                        const char *fmt =
                            "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":"
                            "{\"uri\":\"file://%s\",\"range\":{\"start\":"
                            "{\"line\":%d,\"character\":%d},\"end\":"
                            "{\"line\":%d,\"character\":%d}}}}";
                        size_t len = strlen(def_file) + strlen(def_id) + 256;
                        char *res = (char *)malloc(len);
                        snprintf(res, len - 1, fmt, def_id, def_file, line, col,
                                 line, col);
                        send_ls_response(def_id, res);
                        free(res);
                    }
                }
            }
            break;
        case 'm': // multiple definition results from R
            // Format: +m<req_id>|<count>|<file1>|<line1>|<col1>|<file2>|...
            b++;
            char *multi_id = b;
            b = strstr(b, "|");
            if (b) {
                *b = '\0';
                b++;
                int count = atoi(b);
                b = strstr(b, "|");
                if (b && count > 0) {
                    b++;
                    // Build Location[] response
                    size_t result_size = 4096;
                    char *result = (char *)malloc(result_size);
                    char *p = result;
                    p += snprintf(p, result_size,
                                  "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":[",
                                  multi_id);

                    for (int i = 0; i < count; i++) {
                        char *m_file = b;
                        b = strstr(b, "|");
                        if (!b)
                            break;
                        *b = '\0';
                        b++;

                        char *m_line_str = b;
                        b = strstr(b, "|");
                        if (!b)
                            break;
                        *b = '\0';
                        b++;

                        char *m_col_str = b;
                        char *next = strstr(b, "|");
                        if (next) {
                            *next = '\0';
                            b = next + 1;
                        }

                        int m_line =
                            atoi(m_line_str) - 1; // 1-indexed to 0-indexed
                        int m_col = atoi(m_col_str);

                        if (i > 0) {
                            p += snprintf(p, result_size - (p - result), ",");
                        }
                        p += snprintf(
                            p, result_size - (p - result),
                            "{\"uri\":\"file://%s\",\"range\":{\"start\":"
                            "{\"line\":%d,\"character\":%d},\"end\":"
                            "{\"line\":%d,\"character\":%d}}}",
                            m_file, m_line, m_col, m_line, m_col);
                    }

                    p += snprintf(p, result_size - (p - result), "]}");
                    send_ls_response(multi_id, result);
                    free(result);
                }
            }
            break;
        case 'N':
            b++;
            send_null(b);
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

// Function to register port number to R
static void RegisterPort(int bindportn) {
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
    size_t msg_size;

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

    if (strlen(finalbuffer) != msg_size) {
        fprintf(stderr, "Divergent TCP message size: %zu x %zu\n", strlen(p),
                msg_size);
        fflush(stderr);
    }

    r_running = 1;
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
                fprintf(stderr, "Wrong TCP data length: %zu x %zu\n", blen,
                        rlen);
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
    Log("\x1b[35mTCP out\x1b[0m: %s", msg);
    if (connfd && r_conn) {
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
