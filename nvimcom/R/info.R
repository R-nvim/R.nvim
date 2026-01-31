format_text <- function(txt) {
    txt <- .Call(fmt_txt, txt[1])
    txt
}

get_methods <- function(funcname) {
    ow <- getOption("warn")
    options(warn = -1)
    tmp <- capture.output(methods(funcname))
    options(warn = ow)
    sm <- gsub("*", "", as.character(tmp))
    sm
}

#' Return the method name of a S3 function
sighover_method <- function(req_id, funcname, firstobj, sh) {
    if (exists(funcname) && !is.null(fobj <- get0(firstobj, envir = .GlobalEnv))) {
        sm <- get_methods(funcname)
        mthd <- paste0(funcname, ".", class(fobj))
        if (sum(mthd %in% sm) > 0) {
            mthd <- mthd[mthd %in% sm]
            .C(nvimcom_msg_to_nvim, paste0("+", sh, req_id, "|", mthd[1]))
            return(invisible(NULL))
        }
    }
    .C(nvimcom_msg_to_nvim, paste0("+", sh, req_id, "|", funcname))
}


#' Output the arguments of a function as extra information to be shown during
#' auto-completion.
#' Called by rnvimserver when the user selects a function created in the
#' .GlobalEnv environment in the completion menu.
#' menu.
#' @param req_id ID of language server's request.
#' @param funcname Name of function selected in the completion menu.
resolve_fun_args <- function(req_id, funcname) {
    txt <- nvim.args(funcname)
    # txt <- gsub("\\\\", "\\\\\\\\", txt)
    txt <- .Call(fmt_usage, funcname, txt)
    txt <- paste0("function [.GlobalEnv]", txt)
    .C(
        nvimcom_msg_to_nvim,
        paste0("+R", req_id, "|", txt)
    )
    return(invisible(NULL))
}

#' Output the minimal information on an object during auto-completion.
#' @param req_id ID of language server's request.
#' @param obj Object selected in the completion menu.
#' @param prnt Parent environment
resolve_min_info <- function(req_id, obj, prnt) {
    isnull <- try(is.null(obj), silent = TRUE)
    if (class(isnull)[1] != "logical") {
        return(invisible(NULL))
    }
    if (isnull[1]) {
        return(invisible(NULL))
    }

    txt <- paste0(class(obj)[1], " [", prnt, "]")
    objlbl <- attr(obj, "label", exact = TRUE)
    if (!is.null(objlbl) && is.character(objlbl)) {
        txt <- append(
            txt,
            c("", paste0("**", format_text(objlbl), "**"))
        )
    }
    if (is.data.frame(obj)) {
        txt <- append(txt, paste0("dim: ", nrow(obj), " x ", ncol(obj)))
    } else if (is.list(obj)) {
        txt <- append(txt, paste0("number of elements: ", length(obj)))
    }

    txt <- gsub("'", "\x13", txt)
    txt <- paste0(txt, collapse = "\x14")

    .C(
        nvimcom_msg_to_nvim,
        paste0("+R", req_id, "|", txt)
    )
    return(invisible(NULL))
}

get_summary <- function(obj, prnt) {
    isnull <- try(is.null(obj), silent = TRUE)
    if (class(isnull)[1] != "logical") {
        return(invisible(NULL))
    }
    if (isnull[1]) {
        return(invisible(NULL))
    }

    owd <- getOption("width")
    width <- as.integer(Sys.getenv("R_LS_DOC_WIDTH"))
    if (is.na(width)) {
        width <- 58
    }
    options(width = width)
    txt <- paste0(class(obj)[1], " (`", prnt, "`)")
    objlbl <- attr(obj, "label", exact = TRUE)
    if (!is.null(objlbl) && is.character(objlbl)) {
        objlbl <- format_text(objlbl)
        objlbl <- fix_string(objlbl)
        txt <- append(txt, c("", objlbl))
    }

    sm <- get_methods(summary)
    has_summary <- sum(paste0("summary.", class(obj)) %in% sm) > 0
    out <- NULL
    if (is.numeric(obj) || is.logical(obj) || has_summary) {
        out <- try(capture.output(print(summary(obj))), silent = TRUE)
    } else {
        out <- try(capture.output(utils::str(obj)), silent = TRUE)
    }
    if (length(out) > 30) {
        out <- out[1:30]
        out <- append(out, "- - - truncated - - -")
    }
    if (!is.null(out)) {
        txt <- append(txt, c("", "---", "```rout"))
        txt <- append(txt, out)
        txt <- append(txt, "```")
    }
    options(width = owd)

    txt <- gsub("'", "\x13", txt)
    txt <- paste0(txt, collapse = "\x14")
    txt
}

#' Output the summary as extra information on an object during auto-completion.
#' @param req_id ID of language server's request.
#' @param obj Object selected in the completion menu.
#' @param prnt Parent environment
resolve_summary <- function(req_id, obj, prnt) {
    txt <- get_summary(obj, prnt)
    .C(nvimcom_msg_to_nvim, paste0("+R", req_id, "|", txt))
    return(invisible(NULL))
}

hover_summary <- function(req_id, obj) {
    txt <- get_summary(obj, ".GlobalEnv")
    .C(nvimcom_msg_to_nvim, paste0("+H", req_id, "|", txt))
    return(invisible(NULL))
}

#' Send definition location for a symbol to Nvim
#' @param req_id ID of language server's request.
#' @param pkg Package name (empty string to search all loaded packages)
#' @param symbol Function or object name to find
send_definition <- function(req_id, pkg, symbol) {
    # Helper to send result back
    # Format: +d<req_id>|<file>|<line>|<col>
    send_result <- function(file, line, col) {
        msg <- sprintf("+d%s|%s|%d|%d", req_id, file, line, col)
        .C(nvimcom_msg_to_nvim, msg)
    }

    send_null <- function() {
        .C(nvimcom_msg_to_nvim, paste0("+N", req_id))
    }

    # Helper to get definition info for a function
    get_def_info <- function(fn, pkg_name) {
        sr <- getSrcref(fn)
        if (!is.null(sr)) {
            srcfile <- getSrcFilename(sr, full.names = TRUE)
            if (nzchar(srcfile) && file.exists(srcfile)) {
                return(list(file = srcfile, line = sr[1], col = sr[5]))
            }
        }
        # No source reference - deparse to temp file
        tmpfile <- file.path(tempdir(), paste0(pkg_name, "_", symbol, ".R"))

        # Check if cached file already exists
        if (!file.exists(tmpfile)) {
            header <- sprintf(
                "# %s::%s (no source available - deparsed)",
                pkg_name,
                symbol
            )
            body <- deparse(fn)
            writeLines(c(header, "", body), tmpfile)
        }

        return(list(file = tmpfile, line = 3, col = 0))
    }

    # Base R packages - skip when searching installed (they're always loaded)
    base_pkgs <- c(
        "base",
        "utils",
        "stats",
        "graphics",
        "grDevices",
        "datasets",
        "methods",
        "tools",
        "compiler",
        "parallel",
        "splines",
        "stats4",
        "tcltk",
        "grid"
    )

    # Helper to check if symbol is exported from a package
    is_exported <- function(pkg_name, sym) {
        sym %in% getNamespaceExports(pkg_name)
    }

    # Collect all matching functions
    matches <- list()
    match_pkgs <- character(0)

    if (nzchar(pkg)) {
        # Specific package requested - allow internal functions with :::
        tryCatch(
            {
                ns <- asNamespace(pkg)
                if (exists(symbol, envir = ns, inherits = FALSE)) {
                    fn <- get(symbol, envir = ns)
                    if (is.function(fn)) {
                        info <- get_def_info(fn, pkg)
                        matches[[length(matches) + 1]] <- info
                        match_pkgs <- c(match_pkgs, pkg)
                    }
                }
            },
            error = function(e) NULL
        )
    } else {
        # Search in loaded namespaces first (fast)
        # Only include EXPORTED functions
        for (p in loadedNamespaces()) {
            tryCatch(
                {
                    if (is_exported(p, symbol)) {
                        ns <- asNamespace(p)
                        fn <- get(symbol, envir = ns)
                        if (is.function(fn)) {
                            info <- get_def_info(fn, p)
                            matches[[length(matches) + 1]] <- info
                            match_pkgs <- c(match_pkgs, p)
                        }
                    }
                },
                error = function(e) NULL
            )
        }

        # Check if we found it in a non-base loaded package
        found_in_nonbase <- any(!match_pkgs %in% base_pkgs)

        # Search installed packages if:
        # - Nothing found, OR
        # - Only found in base R (user might want a different package)
        if (length(matches) == 0 || !found_in_nonbase) {
            installed <- .packages(all.available = TRUE)
            already_loaded <- loadedNamespaces()
            # Skip base packages (already checked via loadedNamespaces)
            installed <- setdiff(installed, base_pkgs)

            for (p in installed) {
                if (p %in% already_loaded) {
                    next
                }
                if (length(matches) >= 10) {
                    break
                } # Limit for speed
                tryCatch(
                    {
                        # Only check exported functions
                        ns <- suppressPackageStartupMessages(loadNamespace(p))
                        if (is_exported(p, symbol)) {
                            fn <- get(symbol, envir = ns)
                            if (is.function(fn)) {
                                info <- get_def_info(fn, p)
                                matches[[length(matches) + 1]] <- info
                                match_pkgs <- c(match_pkgs, p)
                            }
                        }
                    },
                    error = function(e) NULL
                )
            }
        }
    }

    if (length(matches) == 0) {
        send_null()
        return(invisible(NULL))
    }

    # Sort matches: base packages first, then alphabetically
    if (length(matches) > 1) {
        is_base <- match_pkgs %in% base_pkgs
        order_idx <- order(!is_base, match_pkgs) # TRUE (base) sorts before FALSE
        matches <- matches[order_idx]
        match_pkgs <- match_pkgs[order_idx]
    }

    if (length(matches) == 1) {
        # Single match - send directly
        info <- matches[[1]]
        send_result(info$file, info$line, info$col)
    } else {
        # Multiple matches - send all with +m code
        # Format: +m<req_id>|<count>|<file1>|<line1>|<col1>|<file2>|<line2>|<col2>|...
        parts <- c(sprintf("+m%s", req_id), as.character(length(matches)))
        for (m in matches) {
            parts <- c(parts, m$file, as.character(m$line), as.character(m$col))
        }
        msg <- paste(parts, collapse = "|")
        .C(nvimcom_msg_to_nvim, msg)
    }
    return(invisible(NULL))
}

get_method <- function(req_id, fnm, fstobj, wrd = NULL, lib = NULL, df = NULL) {
    fname <- fnm
    if (exists(fnm) && !is.null(fobj <- get0(fstobj, envir = .GlobalEnv))) {
        sm <- get_methods(fnm)
        mthd <- paste0(fnm, ".", class(fobj))
        if (sum(mthd %in% sm) > 0) {
            fname <- mthd[mthd %in% sm]
        }
    }
    msg <- sprintf('+C{"orig_id":%s,"fnm":"%s"', req_id, fname)
    if (!is.null(wrd)) {
        msg <- paste0(msg, ',"base":"', wrd, '"')
    }
    if (!is.null(df)) {
        msg <- paste0(msg, ',"df":"', df, '"')
    }
    .C(nvimcom_msg_to_nvim, paste0(msg, "}"))
}
