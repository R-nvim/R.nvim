#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "nvimcom.h"
#include "rd2md.h"

static const R_CMethodDef CEntries[] = {
    {"nvimcom_Stop", (DL_FUNC) &nvimcom_Stop, 0},
    {"nvimcom_task", (DL_FUNC) &nvimcom_task, 0},
    {"nvimcom_msg_to_nvim", (DL_FUNC) &nvimcom_msg_to_nvim, 1},
    {NULL, NULL, 0}
};

static const R_CallMethodDef CallEntries[] = {
    {"nvimcom_Start", (DL_FUNC) &nvimcom_Start, 9},
    {"rd2md", (DL_FUNC) &rd2md, 1},
    {"get_section", (DL_FUNC) &get_section, 1},
    {"fmt_txt", (DL_FUNC) &fmt_txt, 3},
    {"fmt_usage", (DL_FUNC) &fmt_usage, 2},
    {NULL, NULL, 0}
};

void attribute_visible
R_init_nvimcom(DllInfo *info)
{
    R_registerRoutines(info, CEntries, CallEntries, NULL, NULL);
    R_useDynamicSymbols(info, FALSE);
    R_forceSymbols(info, TRUE);
}
