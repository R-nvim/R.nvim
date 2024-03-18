#ifndef COMPLETE_H
#define COMPLETE_H
void resolve(const char *wrd, const char *pkg);
void get_alias(char **pkg, char **fun);
void resolve_arg_item(char *pkg, char *fnm, char *itm);
void complete(const char *id, char *base, char *funcnm, char *dtfrm,
              char *funargs); // Perform completion
void init_compl_vars(void);
#endif
