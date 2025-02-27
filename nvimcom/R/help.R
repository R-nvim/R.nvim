# Function called by R if options(pager = nvim.hmsg).
# R.nvim sets this option during nvimcom loading.
nvim.hmsg <- function(files, header, title, delete.file) {
    doc <- nvim.fix.string(paste(readLines(files[1]), collapse = "\x14"))
    ttl <- nvim.fix.string(title)
    .C(nvimcom_msg_to_nvim, paste0("lua require('r.doc').show('", ttl, "', '", doc, "')"))
    return(invisible(NULL))
}

#' Function called by R.nvim after `\rh` or `:Rhelp`.
#' R.nvim sends the command through the rnvimserver TCP connection to nvimcom
#' and R evaluates the command when idle.
#' @param topic The word under cursor when `\rh` was pressed.
#' @param w The width that lines should have in the formatted document.
#' @param firstobj The first argument of `topic`, if any. There will be a first
#' object if the user requests the documentation of `topic(firstobj)`.
#' @param package The name of the package, if any. There will be a package if
#' the user request the documentation from the Object Browser or the cursor is
#' over `package::topic`.
nvim.help <- function(topic, w, firstobj, package) {
    if (!missing(firstobj) && firstobj != "") {
        objclass <- nvim.getclass(firstobj)
        if (objclass[1] != "#E#" && objclass[1] != "") {
            saved.warn <- getOption("warn")
            options(warn = -1)
            on.exit(options(warn = saved.warn))
            mlen <- try(length(methods(topic)), silent = TRUE)
            if (class(mlen)[1] == "integer" && mlen > 0) {
                for (i in seq_along(objclass)) {
                    newtopic <- paste0(topic, ".", objclass[i])
                    if (length(utils::help(newtopic))) {
                        topic <- newtopic
                        break
                    }
                }
            }
        }
    }

    oldRdOp <- tools::Rd2txt_options()
    on.exit(tools::Rd2txt_options(oldRdOp))
    tools::Rd2txt_options(width = w)

    oldpager <- getOption("pager")
    on.exit(options(pager = oldpager), add = TRUE)
    options(pager = nvim.hmsg)

    warn <- function(msg) {
        .C(nvimcom_msg_to_nvim,
           paste0("lua require('r.log').warn('", as.character(msg), "')"))
    }

    if ("pkgload" %in% loadedNamespaces()) {
        ret <- try(pkgload::dev_help(topic), silent = TRUE)

        if (!inherits(ret, "try-error")) {
            suppressMessages(print(ret))
            return(invisible(NULL))
        } else if (!missing(package) && pkgload::is_dev_package(package)) {
            warn(ret)
            return(invisible(NULL))
        }
    }

    if ("devtools" %in% loadedNamespaces()) {
        ret <- suppressMessages(try(devtools::dev_help(topic), silent = TRUE))

        if (!inherits(ret, "try-error")) {
            return(invisible(NULL))
        } else if (!missing(package) && package %in% devtools::dev_packages()) {
            warn(ret)
            return(invisible(NULL))
        }
    }

    if (missing(package)) {
        h <- utils::help(topic, help_type = "text")
    } else {
        h <- utils::help(topic, package = as.character(package), help_type = "text")
    }

    if (length(h) == 0) {
        msg <- paste0('No documentation for "', topic, '" in loaded packages and libraries.')
        .C(nvimcom_msg_to_nvim, paste0("lua require('r.log').warn('", msg, "')"))
        return(invisible(NULL))
    }
    if (length(h) > 1) {
        if (missing(package)) {
            h <- sub("/help/.*", "", h)
            h <- sub(".*/", "", h)
            .C(nvimcom_msg_to_nvim,
               paste0("lua require('r.doc').choose_lib('", topic, "', {'", paste(h, collapse = "', '"), "'})"))
            return(invisible(NULL))
        } else {
            h <- h[grep(paste0("/", package, "/"), h)]
            if (length(h) == 0) {
                msg <- paste0("Package '", package, "' has no documentation for '", topic, "'")
                .C(nvimcom_msg_to_nvim, paste0("lua require('r.log').warn('", msg, "')"))
                return(invisible(NULL))
            }
        }
    }
    print(h)

    return(invisible(NULL))
}

#' Function called by R.nvim after `\re`.
#' @param The word under cursor. Should be a function.
nvim.example <- function(topic) {
    saved.warn <- getOption("warn")
    options(warn = -1)
    on.exit(options(warn = saved.warn))
    ret <- try(example(topic, give.lines = TRUE, character.only = TRUE,
                       package = NULL), silent = TRUE)
    if (inherits(ret, "try-error")) {
        .C(nvimcom_msg_to_nvim,
           paste0("lua require('r.log').warn('", as.character(ret), "')"))
    } else {
        if (is.character(ret)) {
            if (length(ret) > 0) {
                writeLines(ret, paste0(Sys.getenv("RNVIM_TMPDIR"), "/example.R"))
                .C(nvimcom_msg_to_nvim, "lua require('r.edit').open_example()")
            } else {
                .C(nvimcom_msg_to_nvim,
                   paste0("lua require('r.log').warn('There is no example for \"", topic, "\"')"))
            }
        } else {
            .C(nvimcom_msg_to_nvim,
               paste0("lua require('r.log').warn('There is no help for \"", topic, "\".')"))
        }
    }
    return(invisible(NULL))
}
