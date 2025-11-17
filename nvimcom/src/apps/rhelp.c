#include <stdlib.h>
#include <string.h>

#include "rhelp.h"
#include "logging.h"
#include "lsp.h"
#include "../common.h"
#include "utilities.h"

// clang-format off
static const char *rhelp_keywords[] = {
    "Alpha", "Beta", "CRANpkg", "Chi", "Delta", "Epsilon", "Eta", "Gamma",
    "Iota", "Kappa", "Lambda", "Mu", "Nu", "Omega", "Omicron", "Phi", "Pi",
    "Psi", "R", "RdOpts", "Rdversion", "Rho", "S3method", "S4method", "Sexpr",
    "Sigma", "Tau", "Theta", "Upsilon", "Xi", "Zeta", "abbr", "acronym",
    "alias", "alpha", "arguments", "author", "beta", "bold", "chi", "cite",
    "code", "command", "concept", "cr", "dQuote", "delta", "deqn", "describe",
    "description", "details", "dfn", "docType", "doi", "dontdiff", "dontrun",
    "dontshow", "donttest", "dots", "email", "emph", "enc", "encoding",
    "enumerate", "env", "epsilon", "eqn", "eta", "examples", "figure", "file",
    "format", "gamma", "ge", "href", "if", "ifelse", "iota", "item", "itemize",
    "kappa", "kbd", "keyword", "lambda", "ldots", "le", "link", "linkS4class",
    "method", "mu", "name", "newcommand", "note", "nu", "omega", "omicron",
    "option", "out", "packageAuthor", "packageDESCRIPTION",
    "packageDescription", "packageIndices", "packageMaintainer",
    "packageTitle", "phi", "pi", "pkg", "preformatted", "psi", "references",
    "renewcommand", "rho", "sQuote", "samp", "section", "seealso", "sigma",
    "source", "special", "sspace", "strong", "subsection", "synopsis", "tab",
    "tabular", "tau", "testonly", "theta", "title", "upsilon", "url", "usage",
    "value", "var", "verb", "xi", "zeta", NULL
};
// clang-format on

static char *rhelp_menu;
static size_t nchars = 0;

void complete_rhelp(const char *params) {
    char *id = strstr(params, "\"orig_id\":");
    char *base = strstr(params, "\"base\":\"");
    cut_json_int(&id, 10);
    cut_json_str(&base, 8);

    Log("complete_rhelp: %s, '%s'", id, base);

    const char **s;

    if (!rhelp_menu) {
        s = rhelp_keywords;
        while (*s != NULL) {
            nchars += strlen(*s) + 32;
            s++;
        }
        rhelp_menu = (char *)calloc(nchars, sizeof(char));
    }

    memset(rhelp_menu, 0, nchars * sizeof(char));
    char *p = rhelp_menu;
    s = rhelp_keywords;
    while (*s != NULL) {
        if (!base || fuzzy_find(*s, base)) {
            p = str_cat(p, "{\"label\":\"\\\\");
            p = str_cat(p, *s);
            p = str_cat(p, "\",\"kind\":14},");
        }
        s++;
    }
    send_menu_items(rhelp_menu, id);
}
