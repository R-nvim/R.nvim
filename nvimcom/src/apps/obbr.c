#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "global_vars.h"
#include "logging.h"
#include "../common.h"
#include "obbr.h"

static int nLibObjs;        // Number of library objects
static int nvimcom_is_utf8; // Flag for UTF-8 encoding
static char strL[8];        // String for last element prefix in tree view
static char strT[8];        // String for tree element prefix in tree view
static int OpenDF;          // Flag for open data frames in tree view
static int OpenLS;          // Flag for open lists in tree view
static char liblist[576];   // Library list buffer
static char globenv[576];   // Global environment buffer
static int allnames; // Flag for showing all names, including starting with '.'

void init_obbr_vars(void) {
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
    if (getenv("RNVIM_OPENDF"))
        OpenDF = 1;
    else
        OpenDF = 0;
    if (getenv("RNVIM_OPENLS"))
        OpenLS = 1;
    else
        OpenLS = 0;

    snprintf(liblist, 575, "%s/liblist_%s", localtmpdir, getenv("RNVIM_ID"));
    snprintf(globenv, 575, "%s/globenv_%s", localtmpdir, getenv("RNVIM_ID"));

    if (getenv("RNVIM_OBJBR_ALLNAMES"))
        allnames = 1;
    else
        allnames = 0;
}

/**
 * @brief Make a copy of a string, replacing special bytes with the
 * represented characters.
 *
 * @param o Original string.
 * @param d Destination buffer.
 * @param sz String size.
 */
static void copy_str_to_ob(const char *o, char *d, int sz) {
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
