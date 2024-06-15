#ifndef DATA_STRUCTURES_H
#define DATA_STRUCTURES_H

// Structure for paths to libraries
typedef struct libpaths_ {
    char *path;             // Path to library
    struct libpaths_ *next; // Next path
} LibPath;

// Structure for installed libraries
typedef struct instlibs_ {
    char *name;             // Library name
    char *title;            // Library title
    char *descr;            // Library description
    int si;                 // Still installed flag
    struct instlibs_ *next; // Next installed library
} InstLibs;

// Structure for list or library open/close status in the Object Browser
typedef struct liststatus_ {
    char *key; // Name of the object or library. Library names are prefixed with
               // "package:"
    int status;                // 0: closed; 1: open
    struct liststatus_ *left;  // Left node
    struct liststatus_ *right; // Right node
} ListStatus;

// Structure for package data
typedef struct pkg_data_ {
    char *name;    // The package name
    char *version; // The package version number
    char *fname;   // Objls_ file name in the compldir
    char *descr;   // The package short description
    char *objls;   // A copy of the objls_ file
    char *alias;   // A copy of the alias_ file
    char *args;    // A copy of the args_ file
    int to_build;  // Flag to indicate if the name is sent to build list
    int built;     // Flag to indicate if objls_ found
    int loaded;    // Loaded flag in libnames_
    int nobjs;     // Number of objects in objls
    struct pkg_data_ *next; // Pointer to next package data
} PkgData;

void set_max_depth(int m);
int get_list_status(const char *s, int stt);
void toggle_list_status(char *s);
void update_inst_libs(void);
void update_pkg_list(char *libnms);  // Update package list
void update_glblenv_buffer(char *g); // Update global environment buffer
void build_objls(void);              // Build list of objects for completion
void finished_building_objls(void);
void init_ds_vars(void);
void change_all(int stt);

#endif
