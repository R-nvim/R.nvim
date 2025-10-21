#ifndef COMPLETE_H
#define COMPLETE_H
// void get_alias(char **pkg, char **fun);
void resolve(char *args);
void resolve_arg_item(char *args);
void complete(char *args);
void complete_rmd_chunk(const char *req_id);
void complete_quarto_block(const char *req_id);
#endif
