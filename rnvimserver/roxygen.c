#include <stdlib.h>
#include <string.h>

#include "roxygen.h"
#include "logging.h"
#include "lsp.h"
#include "../nvimcom/src/common.h"
#include "utilities.h"

// clang-format off
static const char *roxygen_tags[] = {
    "S3method", "aliases", "author", "backref", "concept", "describeIn",
    "description", "details", "docType", "encoding", "eval", "evalRd",
    "example", "examples", "export", "exportClass", "exportMethod",
    "exportPattern", "family", "field", "format", "import",
    "importClassesFrom", "importFrom", "importMethodsFrom", "include",
    "includeRmd", "inherit", "inheritDotParams", "inheritParams",
    "inheritSection", "keywords", "md", "method", "name", "noMd", "noRd",
    "note", "order", "param", "rawNamespace", "rawRd", "rdname", "references",
    "return", "section", "seealso", "slot", "source", "template",
    "templateVar", "title", "usage", "useDynLib", NULL
};
// clang-format on

static char *roxygen_menu;
static size_t nchars = 0;

void complete_roxygen(const char *params) {
    char *id = strstr(params, "\"orig_id\":");
    char *base = strstr(params, "\"base\":\"");
    cut_json_int(&id, 10);
    cut_json_str(&base, 8);

    Log("complete_roxygen: %s, '%s'", id ? id : "", base ? base : "");

    const char **s;

    if (!roxygen_menu) {
        s = roxygen_tags;
        while (*s != NULL) {
            nchars += strlen(*s) + 32;
            s++;
        }
        roxygen_menu = (char *)calloc(nchars, sizeof(char));
    }

    memset(roxygen_menu, 0, nchars * sizeof(char));
    char *p = roxygen_menu;
    s = roxygen_tags;
    while (*s != NULL) {
        if (!base || fuzzy_find(*s, base)) {
            p = str_cat(p, "{\"label\":\"@");
            p = str_cat(p, *s);
            p = str_cat(p, "\",\"kind\":14},");
        }
        s++;
    }
    send_menu_items(roxygen_menu, id);
}
