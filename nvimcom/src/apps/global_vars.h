#ifndef GLOBAL_VARS_H
#define GLOBAL_VARS_H

#include <stddef.h>
#include "data_structures.h"

extern InstLibs *instlibs;              // Pointer to first installed library
extern PkgData *pkgList;                // Pointer to first package data
extern char *compl_buffer;              // Completion buffer
extern char *glbnv_buffer;              // Global environment buffer
extern char compldir[256];              // Directory for completion files
extern char localtmpdir[256];           // Local temporary directory
extern char tmpdir[256];                // Temporary directory
extern int auto_obbr;                   // Auto object browser flag
extern unsigned long compl_buffer_size; // Completion buffer size

#endif
