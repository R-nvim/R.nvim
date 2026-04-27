# R may break strings while sending them even if they are short
out <- function(x) {
    # R.nvim will wait for more input if the string doesn't end with "\x14"
    y <- paste0(x, "\x14\n")
    cat(y)
    flush(stdout())
}

setwd(Sys.getenv("RNVIM_COMPLDIR"))

# libPaths
libp <- unique(c(
    unlist(strsplit(Sys.getenv("R_LIBS_USER"), .Platform$path.sep)),
    .libPaths()
))

# Check R version
R_version <- paste0(version[c("major", "minor")], collapse = ".")

if (R_version < "4.1.0") {
    out("WARN: R.nvim requires R >= 4.1.0")
}

R_version <- sub("[0-9]$", "", R_version)

need_new_nvimcom <- ""

np <- find.package("nvimcom", quiet = TRUE, verbose = FALSE)
if (length(np) == 1) {
    nd <- utils::packageDescription("nvimcom")
    if (!grepl(paste0('^R ', R_version), nd$Built)) {
        need_new_nvimcom <- paste0(
            "R version mismatch: '",
            R_version,
            "' vs '",
            nd$Built,
            "'"
        )
    } else {
        if (nd$Version != needed_nvc_version) {
            need_new_nvimcom <- "nvimcom version mismatch"
            fi <- file.info(paste0(np, "/DESCRIPTION"))
            if (
                sum(grepl("uname", names(fi))) == 1 &&
                    Sys.getenv("USER") != "" &&
                    Sys.getenv("USER") != fi[["uname"]]
            ) {
                need_new_nvimcom <-
                    paste0(
                        need_new_nvimcom,
                        " (nvimcom ",
                        nd$Version,
                        " was installed in `",
                        np,
                        "` by \"",
                        fi[["uname"]],
                        "\")"
                    )
            }
        }
    }
} else {
    if (length(np) == 0) need_new_nvimcom <- "Nvimcom not installed"
}

if (need_new_nvimcom == "") {
    quit(save = "no")
}

# Build and install nvimcom if necessary
out(paste0("INFO: Why build nvimcom=", need_new_nvimcom))

# Check if any directory in libPaths is writable
ok <- FALSE
for (p in libp) {
    if (dir.exists(p) && file.access(p, mode = 2) == 0) ok <- TRUE
}
if (!ok) {
    out(paste0("LIBD: ", libp[1]))
    quit(save = "no", status = 71)
}

if (!ok) {
    out("WARN: No suitable directory found to install nvimcom")
    quit(save = "no", status = 65)
}

out("ECHO: Installing nvimcom...")
tools:::.install_packages(
    paste0("nvimcom_", needed_nvc_version, ".tar.gz"),
    no.q = TRUE
)

np <- find.package("nvimcom", quiet = TRUE, verbose = FALSE)
if (length(np) == 1) {
    nd <- utils::packageDescription("nvimcom")
    if (nd$Version != needed_nvc_version) {
        out("WARN: Failed to update nvimcom.")
        quit(save = "no", status = 63)
    }
} else {
    if (length(np) == 0) {
        if (dir.exists(paste0(libp[1], "/00LOCK-nvimcom"))) {
            out(paste0(
                'WARN: Failed to install nvimcom. Perhaps you should delete the directory "',
                libp[1],
                '/00LOCK-nvimcom"'
            ))
        } else {
            out("WARN: Failed to install nvimcom.")
        }
        quit(save = "no", status = 61)
    } else {
        out("WARN: More than one nvimcom versions installed.")
        quit(save = "no", status = 62)
    }
}
out("ECHO:  ")


# Save ~/.cache/R.nvim/nvimcom_info
np <- find.package("nvimcom", quiet = TRUE, verbose = FALSE)
if (length(np) == 1) {
    nd <- utils::packageDescription("nvimcom")
    nvimcom_info <- c(nd$Version, np, sub("R ([^;]*).*", "\\1", nd$Built))
    writeLines(
        nvimcom_info,
        paste0(Sys.getenv("RNVIM_COMPLDIR"), "/nvimcom_info")
    )
    quit(save = "no")
}

if (length(np) == 0) {
    out("WARN: nvimcom is not installed.")
    for (p in libp) {
        if (dir.exists(paste0(p, "/00LOCK-nvimcom"))) {
            out(paste0(
                'WARN: nvimcom is not installed. Perhaps you should delete the directory "',
                p,
                '/00LOCK-nvimcom"'
            ))
        }
    }
    quit(save = "no", status = 67)
}

if (length(np) > 1) {
    out(paste0(
        "WARN: nvimcom is installed in more than one directory: ",
        paste0(ip[grep("^nvimcom$", rownames(ip)), "LibPath"], collapse = ", ")
    ))
    quit(save = "no", status = 68)
}
