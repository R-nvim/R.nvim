#include <string.h>

#include "rhelp.h"
#include "logging.h"
#include "lsp.h"
#include "../common.h"
#include "utilities.h"

#define N_RHELP_KEYS 119
static const char *rhelp_keywords[N_RHELP_KEYS] = {
    "Alpha",        "Beta",       "Chi",         "Delta",        "Epsilon",
    "Eta",          "Gamma",      "Iota",        "Kappa",        "Lambda",
    "Mu",           "Nu",         "Omega",       "Omicron",      "Phi",
    "Pi",           "Psi",        "R",           "Rdversion",    "Rho",
    "S4method",     "Sexpr",      "Sigma",       "Tau",          "Theta",
    "Upsilon",      "Xi",         "Zeta",        "acronym",      "alias",
    "alpha",        "arguments",  "author",      "beta",         "bold",
    "chi",          "cite",       "code",        "command",      "concept",
    "cr",           "dQuote",     "delta",       "deqn",         "describe",
    "description",  "details",    "dfn",         "docType",      "dontrun",
    "dontshow",     "donttest",   "dots",        "email",        "emph",
    "encoding",     "enumerate",  "env",         "epsilon",      "eqn",
    "eta",          "examples",   "file",        "format",       "gamma",
    "ge",           "href",       "iota",        "item",         "itemize",
    "kappa",        "kbd",        "keyword",     "lambda",       "ldots",
    "le",           "link",       "linkS4class", "method",       "mu",
    "name",         "newcommand", "note",        "nu",           "omega",
    "omicron",      "option",     "phi",         "pi",           "pkg",
    "preformatted", "psi",        "references",  "renewcommand", "rho",
    "sQuote",       "samp",       "section",     "seealso",      "sigma",
    "source",       "special",    "strong",      "subsection",   "synopsis",
    "tab",          "tabular",    "tau",         "testonly",     "theta",
    "title",        "upsilon",    "url",         "usage",        "value",
    "var",          "verb",       "xi",          "zeta",
};

void complete_rhelp(const char *params) {
    char *id = strstr(params, "\"orig_id\":");
    cut_json_int(&id, 10);
    Log("complete_rhelp: %s", id);
    char rhelp_menu[4096] = {0};
    char *p = rhelp_menu;
    for (int i = 0; i < N_RHELP_KEYS; i++) {
        p = str_cat(p, "{\"label\":\"\\\\");
        p = str_cat(p, rhelp_keywords[i]);
        p = str_cat(p, "\",\"kind\":14},");
    }
    send_menu_items(rhelp_menu, id);
}
