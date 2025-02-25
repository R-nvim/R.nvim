#include <stdio.h>  // Standard input/output definitions
#include <stdlib.h> // Standard library
#include <string.h> // String handling functions

#include <inttypes.h>
#include <process.h>
#include <time.h>
#include <winsock2.h>
#include <windows.h>

#include "tcp.h"
#include "rgui.h"

HWND NvimHwnd = NULL;
HWND RConsole = NULL;

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

static void RClearConsole(void) {
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

void Windows_setup(void) // Setup Windows-specific configurations
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

void parse_rgui_msg(char *msg) {
    switch (*msg) {
    case '1': // Check if R is running
        if (PostMessage(RConsole, WM_NULL, 0, 0)) {
            fprintf(stderr, "R was already started\n");
            fflush(stderr);
        } else {
            printf("lua require('r.rgui').clean_and_start()\n");
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
}
