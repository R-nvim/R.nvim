#include <R.h>
#include <Rdefines.h>
#include "common.h"

typedef struct pattern {
    char *ptrn;   // pattern, not including the backslash
    int len;      // pattern length
    int type;     // type of replacement
    char *before; // insert before the replacement
    char *after;  // insert after the replacement
} pattern_t;

/* Types:

   0: \cmd                          -> newstr
   1: \cmd{s}                       -> <s>
   2: \cmd{s1}{s2}                  -> <s1>
   3: \cmd{s1}{s2}                  -> <s2>
   4: \cmd{s}{}                     -> ""
   5: \cmd[optional-argument]{s}    -> <s>
   6: \href{s1}{s2}                 -> 's2' <s1> // curly single quotes
   7: \ifelse{{html|latex}{s1}{s2}} -> s2
   8: \code{\link{s}}               -> <s>
   9: \item{s1}{s2}                 -> `s1`: s2 || \n - s1

*/

// Optimized by frequency in titles and description of objects in default R
// packages : \code (1814), \R (220), \emph (97), sQuote (76), \eqn (59),
// \dQuote (41), \link (30), \pkg (29) etc...
// We use hexadecimal codes to print Unicode characters because some
// compilers report invalid code if we use non-ascii strings (see
// https://github.com/R-nvim/R.nvim/issues/378#issuecomment-2758009615).
static struct pattern rd[] = {
    // Order optimized for default R 4.2.2 packages
    {"code", 4, 8, "`", "`"},
    {"R", 1, 0, "*R*", "\000"},
    {"emph", 4, 1, "*", "*"},
    {"eqn", 3, 1, "*", "*"},
    {"sQuote", 6, 1, "\xe2\x80\x98", "\xe2\x80\x99"},
    {"dQuote", 6, 1, "\xe2\x80\x9c", "\xe2\x80\x9d"},
    {"pkg", 3, 1, "\000", "\000"},
    {"linkS4class", 11, 1, "\000", "\000"},
    {"link", 4, 5, "\xe2\x80\x98", "\xe2\x80\x99"},
    {"item{", 5, 9, "\x14  \xe2\x80\xa2 ", "\x14"},
    {"item ", 5, 0, "\x14  \xe2\x80\xa2 ", "\000"},
    {"itemize", 7, 1, "\x14", "\x14"},
    {"item", 4, 1, "\x14  \xe2\x80\xa2 ", "\000"},
    {"dots", 4, 0, "...", "\000"},
    {"bold", 4, 1, "**", "**"},
    {"file", 4, 1, "\xe2\x80\x98", "\xe2\x80\x99"},
    {"option", 6, 1, "\000", "\000"},
    {"command", 7, 1, "`", "`"},
    {"mu", 2, 0, "\xce\xbc", "\000"},
    {"ifelse", 6, 7, NULL, NULL},
    {"samp", 4, 1, "`", "`"},
    {"env", 3, 1, "\000", "\000"},
    {"describe", 8, 1, "\x14", "\x14"},
    {"Sigma", 5, 0, "\xce\xa3", "\000"},

    // Common in some other packages
    {"if{html}", 8, 4, NULL, NULL},
    {"figure", 6, 2, "\000", "\000"},
    {"href", 4, 6, NULL, NULL},
    {"preformatted", 12, 1, "\x14```\x14", "```\x14"},

    // The rest
    {"alpha", 5, 0, "\xce\xb1", "\000"},
    {"beta", 4, 0, "\xce\xb2", "\000"},
    {"Delta", 5, 0, "\xce\x94", "\000"},
    {"delta", 5, 0, "\xce\xb4", "\000"},
    {"epsilon", 7, 0, "\xce\xb5", "\000"},
    {"zeta", 4, 0, "\xce\xb6", "\000"},
    {"theta", 5, 0, "\xce\xb8", "\000"},
    {"iota", 4, 0, "\xce\xb9", "\000"},
    {"kappa", 5, 0, "\xce\xba", "\000"},
    {"eta", 3, 0, "\xce\xb7", "\000"},
    {"gamma", 5, 0, "\xce\xb3", "\000"},
    {"lambda", 6, 0, "\xce\xbb", "\000"},
    {"nu", 2, 0, "\xce\xbd", "\000"},
    {"xi", 2, 0, "\xce\xbe", "\000"},
    {"omega", 5, 0, "\xcf\x89", "\000"},
    {"Omega", 5, 0, "\xce\xa9", "\000"},
    {"pi", 2, 0, "\xcf\x80", "\000"},
    {"phi", 3, 0, "\xcf\x86", "\000"},
    {"chi", 3, 0, "\xcf\x87", "\000"},
    {"psi", 3, 0, "\xcf\x88", "\000"},
    {"tau", 3, 0, "\xcf\x84", "\000"},
    {"upsilon", 7, 0, "\xcf\x85", "\000"},
    {"rho", 3, 0, "\xcf\x81", "\000"},
    {"sigma", 5, 0, "\xcf\x83", "\000"},
    {"log", 3, 0, "log", "\000"},
    {"le", 2, 0, "\xe2\x89\xa4", "\000"},
    {"ge", 2, 0, "\xe2\x89\xa5", "\000"},
    {"ll", 2, 0, "\xe2\x89\xaa", "\000"},
    {"gg", 2, 0, "\xe2\x89\xab", "\000"},
    {"infty", 5, 0, "\xe2\x88\x9e", "\000"},
    {"tabular", 7, 3, "\x14", "\x14"},
    {"tab", 3, 0, "\t", "\000"},
    {"cr", 2, 0, "\x14", "\000"},
    {"sqrt", 4, 1, "*\xe2\x88\x9a", "*"},
    {"strong", 6, 1, "**", "**"},
    {"email", 5, 1, "\000", "\000"},
    {"acronym", 7, 1, "\000", "\000"},
    {"var", 3, 1, "\000", "\000"},
    {"special", 7, 1, "\000", "\000"},
    {"deqn", 4, 1, "*", "*"},
    {"cite", 4, 1, "\000", "\000"},
    {"url", 3, 1, "\000", "\000"},
    {"ldots", 5, 0, "\xe2\x80\xa6", "\000"},
    {"verb", 4, 1, "`", "`"},
    {"out", 3, 1, "\000", "\000"},
    {"examples", 8, 1, "\x14```r\x14", "```\x14"},
    {NULL, 0, 0, NULL, NULL}};

// Insert `s` at position `p`
static char *insert_str(char *p, const char *s) {
    while (*s) {
        *p = *s;
        p++;
        s++;
    }
    return p;
}

// Consider that there is an opening bracket just before `p` and find the
// matching closing brace. There is no check for escaped brackets.
static int find_matching_sqrbrckt(const char *p) {
    int n = 1;
    int i = 0;
    while (n > 0 && p[i]) {
        if (p[i] == '[')
            n++;
        else if (p[i] == ']')
            n--;
        i++;
    }
    i--;
    return i;
}

// Consider that there is an opening curly brace just before `p` and find the
// matching closing brace. There is no check for escaped braces.
static int find_matching_bracket(const char *p) {
    int n = 1;
    int i = 0;
    while (n > 0 && p[i]) {
        if (p[i] == '{')
            n++;
        else if (p[i] == '}')
            n--;
        i++;
    }
    i--;
    return i;
}

static void rd_md(char **o1, char **o2) {
    char *p1 = *o1;
    char *p2 = *o2;
    char *p3, *p2a, *p2b;
    p2++;
    int i = 0;
    while (rd[i].ptrn) {
        // Count number of patterns:
        // fprintf(stderr, "%d: %s\n", i, rd[i].ptrn);
        if (str_here(p2, rd[i].ptrn)) {
            switch (rd[i].type) {
            case 0: // \cmd -> new
                p2 += rd[i].len;
                p1 = insert_str(p1, rd[i].before);
                *o1 = p1;
                *o2 = p2;
                return;
            case 1: // \cmd{string} -> <string>
                p2 += rd[i].len + 1;
                p3 = p2 + find_matching_bracket(p2);
                *p3 = 0;
                p1 = insert_str(p1, rd[i].before);
                p1 = insert_str(p1, p2);
                p1 = insert_str(p1, rd[i].after);
                p2 = p3 + 1;
                *o1 = p1;
                *o2 = p2;
                return;
            case 2: // \cmd{string1}{string2} -> <string1>
                p2 += rd[i].len + 1;
                p3 = p2 + find_matching_bracket(p2);
                *p3 = 0;
                p1 = insert_str(p1, rd[i].before);
                p1 = insert_str(p1, p2);
                p1 = insert_str(p1, rd[i].after);
                p2 = p3 + 1;
                if (*p2 == '{') {
                    p2++;
                    p2 = p2 + find_matching_bracket(p2);
                }
                p2++;
                *o1 = p1;
                *o2 = p2;
                return;
            case 3: // \cmd{string1}{string2} -> <string2>
                p2 += rd[i].len + 1;
                p2 = p2 + find_matching_bracket(p2) + 1;
                if (*p2 == '{') {
                    p2++;
                    p3 = p2 + find_matching_bracket(p2);
                    *p3 = 0;
                    p1 = insert_str(p1, rd[i].before);
                    p1 = insert_str(p1, p2);
                    p1 = insert_str(p1, rd[i].after);
                    p2 = p3 + 1;
                }
                *o1 = p1;
                *o2 = p2;
                return;
            case 4: // if{html}{string} -> ""
                p2 += rd[i].len + 1;
                p2 = p2 + find_matching_bracket(p2) + 1;
                *o1 = p1;
                *o2 = p2;
                return;
            case 5: // \cmd[optional-argument]{string} -> <string>
                p2 += rd[i].len;
                if (*p2 == '[') {
                    p2++;
                    p2 = p2 + find_matching_sqrbrckt(p2) + 1;
                }
                if (*p2 == '{') {
                    p2++;
                    p3 = p2 + find_matching_bracket(p2);
                    *p3 = 0;
                    p1 = insert_str(p1, rd[i].before);
                    p1 = insert_str(p1, p2);
                    p1 = insert_str(p1, rd[i].after);
                    p2 = p3 + 1;
                }
                *o1 = p1;
                *o2 = p2;
                return;
            case 6: // \href{string1}{string2} -> 'string2' <string1>
                p2 += rd[i].len + 1;
                p2a = p2;
                p2a = p2a + find_matching_bracket(p2a);
                *p2a = 0;
                p2b = p2a + 2;
                p3 = p2b + find_matching_bracket(p2b);
                *p3 = 0;
                p1 = insert_str(p1, "\xe2\x80\x98");
                p1 = insert_str(p1, p2b);
                p1 = insert_str(p1, "\xe2\x80\x99 <");
                p1 = insert_str(p1, p2);
                p1 = insert_str(p1, ">");
                p2 = p3 + 1;
                *o1 = p1;
                *o2 = p2;
            case 7: // \ifelse{{html|latex}{string1}{string2}} -> string2
                p2 += rd[i].len + 1;
                if (*p2 == '{') {
                    p2++;
                    char type = 0;
                    if (str_here(p2, "html") || str_here(p2, "latex"))
                        type = 'o';
                    p2 = p2 + find_matching_bracket(p2) + 1;
                    if (*p2 == '{') {
                        p2++;
                        if (type == 'o') {
                            p2 = p2 + find_matching_bracket(p2) + 2;
                            p3 = p2 + find_matching_bracket(p2);
                            *p3 = 0;
                            p1 = insert_str(p1, p2);
                            p2 = p3 + 2;
                        }
                    }
                }
                if (p2[0] && p2[1] && p2[0] == '{' && p2[1] == '}') {
                    p2 += 2; // ifelse resulting from \sspace
                }
                *o1 = p1;
                *o2 = p2;
                return;
            case 8: // \code{\link{string}} -> <string> /* remove \link{}
                p2 += rd[i].len + 1;
                p1 = insert_str(p1, rd[i].before);
                p3 = p2 + find_matching_bracket(p2);
                while (*p2 && p2 != p3) {
                    if (str_here(p2, "\\link{")) {
                        p2 += 6;
                        p2a = p2 + find_matching_bracket(p2);
                        while (p2 != p2a) {
                            *p1 = *p2;
                            p1++;
                            p2++;
                        }
                        p2++;
                        while (p2 != p3) {
                            *p1 = *p2;
                            p1++;
                            p2++;
                        }
                    } else {
                        *p1 = *p2;
                        p1++;
                        p2++;
                    }
                }
                p1 = insert_str(p1, rd[i].after);
                p2 = p3 + 1;
                *o1 = p1;
                *o2 = p2;
                return;
            case 9: // \item{string1}{string2} -> 'string1': string2
                p2 += rd[i].len;
                p2a = p2;
                p2a = p2a + find_matching_bracket(p2a);
                *p2a = 0;
                p2b = p2a + 1;
                if (*p2b == '{') {
                    // \item from \arguments section
                    p2b++;
                    p3 = p2b + find_matching_bracket(p2b);
                    *p3 = 0;
                    p1 = insert_str(p1, "`");
                    p1 = insert_str(p1, p2);
                    p1 = insert_str(p1, "`: ");
                    p1 = insert_str(p1, p2b);
                } else {
                    // \item from \itemize
                    p3 = p2 + find_matching_bracket(p2);
                    *p3 = 0;
                    p1 = insert_str(p1, rd[i].before);
                    p1 = insert_str(p1, p2);
                    p1 = insert_str(p1, rd[i].after);
                }
                p2 = p3 + 1;
                *o1 = p1;
                *o2 = p2;
                return;
            }
        }
        i++;
    }
    *p1 = '\\';
    p1++;
    *o1 = p1;
    *o2 = p2;
}

static void pre_rd_md(char **b1, char **b2, char *maxp) {
    char *p1 = *b1;
    char *p2 = *b2;

    while (*p2) {
        if (p1 >= maxp) {
            REprintf("p1 >= maxp [%p %p]\n", (void *)p1, (void *)maxp);
            break;
        }
        if (*p2 == '\\') {
            rd_md(&p1, &p2);
        } else {
            *p1 = *p2;
            p1++;
            p2++;
        }
    }
    *p1 = 0;
}

SEXP rd2md(SEXP txt) {
    if (Rf_isNull(txt))
        return R_NilValue;

    const char *s = CHAR(STRING_ELT(txt, 0));

    // \R is the only command that expands for more characters than the
    // command itself: from two (\R) to three (*R*), but string2 might be much
    // longer than string1 in \href{string1}{string2}. We decrease the risk of
    // overwriting text by creating buffers with extra room and prefixing the
    // string with empty spaces:
    unsigned long maxp = strlen(s) + 999;

    char *a = calloc(maxp + 1, sizeof(char));
    char *b = calloc(maxp + 1, sizeof(char));
    strcpy(b, s);

    // Run four times to convert nested \commands.

    char *p1 = a;
    char *p2 = b;
    pre_rd_md(&p1, &p2, a + maxp);

    p1 = b;
    p2 = a;
    pre_rd_md(&p1, &p2, b + maxp);

    p1 = a;
    p2 = b;
    pre_rd_md(&p1, &p2, a + maxp);

    p1 = b;
    p2 = a;
    pre_rd_md(&p1, &p2, b + maxp);

    // Final cleanup for nvimcom/R.nvim:
    // - Replace \n with \x14 within pre-formatted code to restore them during
    // auto completion.
    // - Replace \n with empty space to avoid problems transmitting strings to
    // Lua.
    p1 = a;
    p2 = b;
    // Skip leading empty spaces:
    while (*p1 && (*p1 == ' ' || *p1 == '\n' || *p1 == '\t' || *p1 == '\r'))
        p1++;
    while (*p1) {
        if (p1[0] && p1[1] && p1[2] && p1[0] == '`' && p1[1] == '`' &&
            p1[2] == '`') {
            *p2 = *p1;
            p2++;
            p1++;
            *p2 = *p1;
            p2++;
            p1++;
            *p2 = *p1;
            p2++;
            p1++;
            while (p1[0] && p1[1] && p1[2] &&
                   !(p1[0] == '`' && p1[1] == '`' && p1[2] == '`')) {
                if (*p1 == '\n')
                    *p1 = '\x14';
                *p2 = *p1;
                p2++;
                p1++;
            }
        } else {
            if (p1[0] == ' ' && p1[1] == '`' && p1[2] == '`' &&
                ((p1[3] >= 'a' && p1[3] <= 'z') ||
                 (p1[3] >= 'A' && p1[3] <= 'Z'))) {
                *p2 = ' ';
                p2++;
                *p2 = '"';
                p2++;
                p1 += 3;
            }
            if (*p1 == '\n' || *p1 == '\r')
                *p1 = ' ';
            if (*p1 == ' ') {
                *p2 = ' ';
                p2++;
                p1++;
                // - Skip the second and following spaces
                while (*p1 && (*p1 == ' ' || *p1 == '\n'))
                    p1++;
            } else {
                *p2 = *p1;
                p2++;
                p1++;
            }
        }
    }
    *p2 = 0;

    // Delete trailing spaces
    p2--;
    while (*p2 && (*p2 == ' ' || *p2 == '\x14')) {
        *p2 = 0;
        p2--;
    }

    // - Replace single quotes to avoid problems when sending the string as a
    // Lua dictionary
    p2 = b;
    while (*p2) {
        if (*p2 == '\'')
            *p2 = '\x13';
        p2++;
    }

    SEXP ans;
    PROTECT(ans = NEW_CHARACTER(1));
    SET_STRING_ELT(ans, 0, mkChar(b));
    UNPROTECT(1);
    free(a);
    free(b);
    return ans;
}

SEXP get_section(SEXP rtxt, SEXP rsec) {
    if (Rf_isNull(rtxt) || Rf_isNull(rsec))
        return R_NilValue;

    const char *str = CHAR(STRING_ELT(rtxt, 0));
    const char *sec = CHAR(STRING_ELT(rsec, 0));

    char *a = calloc(sizeof(char), (strlen(str) + 1));
    char *b = malloc(sizeof(char) * (strlen(str) + 1));
    strcpy(b, str);
    char *s = a;
    char *p = b;
    char *e;
    while (*p) {
        if (*p == '\\') {
            p++;
            if (str_here(p, sec)) {
                p = p + strlen(sec) + 1;
                while (*p == '\n' || *p == '\r' || *p == ' ' || *p == '\t')
                    p++;
                e = p + find_matching_bracket(p);
                *e = 0;
                e--;
                while (*e &&
                       (*e == '\n' || *e == '\r' || *e == ' ' || *e == '\t')) {
                    *e = 0;
                    e--;
                }
                while (*p) {
                    *s = *p;
                    s++;
                    p++;
                }
                *s = 0;
            }
        }
        p++;
    }

    SEXP ans = R_NilValue;
    if (*a) {
        PROTECT(ans = NEW_CHARACTER(1));
        SET_STRING_ELT(ans, 0, mkChar(a));
        UNPROTECT(1);
        ans = rd2md(ans);
    }
    free(a);
    free(b);
    return ans;
}
