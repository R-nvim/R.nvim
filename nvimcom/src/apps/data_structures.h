#ifndef DATA_STRUCTURES_H
#define DATA_STRUCTURES_H

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
    char *title;   // The package short description
    char *descr;   // The package description
    char *alias;   // A copy of the alias_ file
    char *objls;   // A copy of the objls_ file
    char *args;    // A copy of the args_ file
    char *srcref;  // A copy of the srcref_ file (source references)
    int nobjs;     // Number of objects in objls
} PkgData;

typedef struct lib_data_ {
    PkgData *pkg;
    struct lib_data_ *next;
} LibList;

void set_max_depth(int m);
int get_list_status(const char *s, int stt);
void toggle_list_status(char *s);
void init_lib_list(void);                  // Initialize the list of libraries
void update_loaded_libs(char *libnms);     // Update the list of libraries
void update_glblenv_buffer(const char *g); // Update global environment buffer
void load_cached_data(void); // Build list of objects for completion
void finish_updating_loaded_libs(int has_new_lib);
void init_ds_vars(void);
void change_all(int stt);

#endif
