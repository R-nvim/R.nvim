#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "chunk.h"
#include "logging.h"
#include "lsp.h"
#include "utilities.h"
#include "../common.h"

typedef struct chunkitem_ {
    char *label;
    char *descr;
    struct chunkitem_ *next;
} ChunkItem;

static ChunkItem *broot;
static ChunkItem *croot;
static char *cbuffer;

static void get_chunk_items(const char *fname, ChunkItem **root) {
    char *b1 = read_file(fname, 1);
    if (!b1)
        return;
    char *p = b1;
    while (*p) {
        if (*p == '\n')
            *p = '\x02';
        p++;
    }
    char *b2 = esc_json(b1);
    free(b1);
    while (*b2) {
        ChunkItem *item = (ChunkItem *)calloc(1, sizeof(ChunkItem));
        if (!item)
            break;
        item->next = *root;
        *root = item;
        item->label = b2;
        while (*b2 != '|')
            b2++;
        *b2 = 0;
        b2++;
        item->descr = b2;
        while (*b2 != '\x02')
            b2++;
        *b2 = 0;
        b2++;
    }
    if (!cbuffer)
        cbuffer = (char *)calloc(100000, sizeof(char));
}

static void fill_compl_buffer(const char *base, ChunkItem *root) {
    char *p = cbuffer;
    *p = '\0';
    ChunkItem *c = root;
    while (c) {
        if (!base || strstr(c->label, base)) {
            p = str_cat(p, "{\"label\":\"");
            p = str_cat(p, c->label);
            p = str_cat(p, "\",\"kind\":5,\"documentation\":{\"kind\":"
                           "\"markdown\",\"value\":\"");
            p = str_cat(p, c->descr);
            p = str_cat(p, "\"}},");
        }
        c = c->next;
    }
    *p = '\0';
}

void complete_chunk_opts(char t, const char *params) {
    Log("complete_chunk [%c] params: '%s'", t, params);
    char *id = strstr(params, "\"orig_id\":");
    char *base = strstr(params, "\"base\":\"");
    cut_json_int(&id, 10);
    cut_json_str(&base, 8);
    Log("complete_chunk [%s]: '%s'", id, base);

    char fname[128];

    if (t == 'C') {
        if (!croot) {
            snprintf(fname, 127, "%s/resources/rmd_chunk_options",
                     getenv("RNVIM_HOME"));
            get_chunk_items(fname, &croot);
        }
        fill_compl_buffer(base, croot);
    } else {
        if (!broot) {
            snprintf(fname, 127, "%s/quarto_block_items",
                     getenv("RNVIM_COMPLDIR"));
            get_chunk_items(fname, &broot);
        }
        fill_compl_buffer(base, broot);
    }

    send_menu_items(cbuffer, id);
}
