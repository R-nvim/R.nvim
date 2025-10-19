#ifndef COMPLETE_H
#define COMPLETE_H
// void get_alias(char **pkg, char **fun);
void resolve(char *args);
void resolve_arg_item(char *args);
void complete(char *base, char *funcnm, char *dtfrm, char *funargs);
void complete_rhelp(void);
void complete_rmd_chunk(void);
void complete_quarto_block(void);
#endif
