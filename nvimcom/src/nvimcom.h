#ifndef NVIMCOM_H
#define NVIMCOM_H

#include <Rdefines.h>

SEXP nvimcom_Start(SEXP vrb, SEXP anm, SEXP swd, SEXP age, SEXP imd, SEXP szl,
                   SEXP tml, SEXP nvv, SEXP rinfo);
void nvimcom_Stop(void);
void nvimcom_msg_to_nvim(char **cmd);
void nvimcom_task(void);
SEXP fmt_txt(SEXP txt, SEXP delim, SEXP nl);
SEXP fmt_usage(SEXP fnm, SEXP args);

#endif // NVIMCOM_H
