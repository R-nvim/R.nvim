#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h> // For va_list
#include <string.h>
#include <time.h>

#include "logging.h"

static char *fnm;

/**
 * @brief Logs a formatted message to a specified log file.
 * @param fmt Format string for the log message (printf-style).
 * @param ... Variable arguments providing data to format.
 * @note This function is conditionally compiled only if Debug_NRS is defined.
 */
__attribute__((format(printf, 1, 2))) void Log(const char *fmt, ...) {
#ifdef Debug_NRS
    va_list argptr;
    FILE *f = fopen(fnm, "a");
    if (!f)
        return;
    va_start(argptr, fmt);
    vfprintf(f, fmt, argptr);
    fprintf(f, "\n");
    va_end(argptr);
    fclose(f);
#endif
}

#ifdef Debug_NRS
void init_logging(void) {
#ifdef WIN32
    fnm = malloc((strlen(getenv("TMP")) + 16) * sizeof(char));
    sprintf(fnm, "%s/rnvimserver_log", getenv("TMP"));
#else
    fnm = malloc(sizeof(char) * 32);
    strcpy(fnm, "/dev/shm/rnvimserver_log");
#endif
    time_t t;
    time(&t);
    FILE *f = fopen(fnm, "w");
    if (!f)
        return;
    fprintf(f, "NSERVER LOG | %s\n\n", ctime(&t));
    fclose(f);
}
#endif
