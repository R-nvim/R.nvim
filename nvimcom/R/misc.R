# Function called by R if options(editor = nvim.edit).
# R.nvim sets this option during nvimcom loading.
nvim.edit <- function(name, file, title) {
    if (file != "") {
        stop("Feature not implemented. Use nvim to edit files.")
    }
    if (is.null(name)) {
        stop("Feature not implemented. Use nvim to create R objects from scratch.")
    }

    editf <- paste0(
        Sys.getenv("RNVIM_TMPDIR"),
        "/edit_",
        Sys.getenv("RNVIM_ID"),
        "_",
        round(runif(1, min = 100, max = 999))
    )
    waitf <- paste0(editf, "_wait")
    unlink(editf)
    writeLines(text = "Waiting...", con = waitf)

    sink(editf)
    dput(name)
    sink()

    .C(nvimcom_msg_to_nvim, paste0("require('r.edit').obj('", editf, "')"))

    while (file.exists(waitf)) {
        Sys.sleep(1)
    }
    x <- eval(parse(editf))
    unlink(waitf)
    unlink(editf)
    x
}

# Substitute for utils::vi
vi <- function(name = NULL, file = "") {
    nvim.edit(name, file)
}

#' Function called by R.nvim when the user wants to run the command `dput()`
#' over the word under cursor and see its output in a new Vim tab.
#' @param oname The name of the object under cursor.
#' @param howto How to show the output (never included when called by R.nvim).
nvim_dput <- function(oname, howto = "tabnew") {
    o <- capture.output(eval(parse(text = paste0("dput(", oname, ")"))))
    o <- gsub("\\\\", "\x12", o)
    o <- gsub("'", "\x13", o)
    o <- paste0(o, collapse = "\x14")
    .C(
        nvimcom_msg_to_nvim,
        paste0(
            "require('r.run').show_obj('",
            howto,
            "', '",
            oname,
            "', 'r', '",
            o,
            "')"
        )
    )
}

#' Function called by R.nvim when the user wants to see a `data.frame` or
#' `matrix` (default key bindings: `\rv`, `\vs`, `\vv`, and `\rh`).
#' @param oname The name of the object (`data.frame` or `matrix`).
#' @param fenc File encoding to be used.
#' @param nrows How many lines to show.
#' @param R_df_viewer R function to be called to show the `data.frame`.
#' @param save_fun R function to be called to save the CSV file.
nvim_viewobj <- function(
    oname,
    fenc = "",
    nrows = -1,
    R_df_viewer = NULL,
    save_fun = NULL
) {
    if (is.data.frame(oname) || is.matrix(oname)) {
        # Only when the rkeyword includes "::"
        o <- oname
        oname <- sub("::", "_", deparse(substitute(oname)))
    } else {
        oname_split <- unlist(strsplit(oname, "$", fixed = TRUE))
        oname_split <- unlist(strsplit(oname_split, "[[", fixed = TRUE))
        oname_split <- unlist(strsplit(oname_split, "]]", fixed = TRUE))
        ok <- try(o <- get(oname_split[[1]], envir = .GlobalEnv), silent = TRUE)
        if (length(oname_split) > 1) {
            for (i in 2:length(oname_split)) {
                oname_integer <- suppressWarnings(o <- as.integer(oname_split[[i]]))
                if (is.na(oname_integer)) {
                    ok <- try(o <- ok[[oname_split[[i]]]], silent = TRUE)
                } else {
                    ok <- try(o <- ok[[oname_integer]], silent = TRUE)
                }
            }
        }
        if (inherits(ok, "try-error")) {
            .C(
                nvimcom_msg_to_nvim,
                paste0(
                    "require('r.log').warn('",
                    '"',
                    oname,
                    '"',
                    " not found in .GlobalEnv')"
                )
            )
            return(invisible(NULL))
        }
    }
    if (is.data.frame(o) || is.matrix(o)) {
        if (nrows < 0) {
            nrows <- ceiling(10000 / ncol(o))
        }
        if (nrows != 0 && nrows < nrow(o)) {
            o <- o[1:nrows, ]
        }
        if (!is.null(R_df_viewer)) {
            cmd <- gsub("'", "\x13", R_df_viewer)
            .C(
                nvimcom_msg_to_nvim,
                paste0(
                    "vim.schedule(function() require('r.send').cmd('",
                    cmd,
                    "') end)"
                )
            )
            return(invisible(NULL))
        }
        if (is.null(save_fun)) {
            if (getOption("nvimcom.delim") == "\t") {
                txt <- capture.output(write.table(
                    o,
                    sep = "\t",
                    row.names = FALSE,
                    quote = FALSE,
                    fileEncoding = fenc
                ))
                oname <- paste0(oname, ".tsv")
            } else {
                txt <- capture.output(write.table(
                    o,
                    sep = getOption("nvimcom.delim"),
                    row.names = FALSE,
                    fileEncoding = fenc
                ))
                if (getOption("nvimcom.delim") == ",") {
                    oname <- paste0(oname, ".csv")
                }
            }
            txt <- gsub("\\\\", "\x12", txt)
            txt <- gsub("'", "\x13", txt)
            txt <- paste0(txt, collapse = "\x14")
        } else {
            txt <- save_fun(o, oname)
            if (is.null(txt)) txt <- oname
        }
        .C(
            nvimcom_msg_to_nvim,
            paste0("require('r.edit').view_df('", oname, "', '", txt, "')")
        )
    } else {
        nvim_dput(oname)
    }
    return(invisible(NULL))
}

#' Call base::source.
#' @param ... Further arguments passed to base::source.
#' @param print.eval See base::source.
#' @param spaced See base::source.
Rnvim.source <- function(..., print.eval = TRUE, spaced = FALSE) {
    base::source(
        getOption("nvimcom.source.path"),
        ...,
        print.eval = print.eval,
        spaced = spaced
    )
}

#' Call base::source.
#' This function is sent to R Console when the user press `\ss`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.selection <- function(..., local = parent.frame()) {
    Rnvim.source(..., local = local)
}

#' Call base::source.
#' This function is sent to R Console when the user press `\pp`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.paragraph <- function(..., local = parent.frame()) {
    Rnvim.source(..., local = local)
}

#' Call base::source.
#' This function is sent to R Console when the user press `\bb`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.block <- function(..., local = parent.frame()) {
    Rnvim.source(..., local = local)
}

#' Call base::source.
#' This function is sent to R Console when the user press `\ff`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.function <- function(..., local = parent.frame()) {
    Rnvim.source(..., local = local)
}

#' Call base::source.
#' This function is sent to R Console when the user press `\cc`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.chunk <- function(..., local = parent.frame()) {
    Rnvim.source(..., local = local)
}

#' Source a temporary copy of an R file and, finally, delete it.
#' This function is sent to R Console when the user press `\aa`, `\ae`, or `\ao`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
source.and.clean <- function(f, print.eval = TRUE, spaced = FALSE, ...) {
    on.exit(unlink(f))
    base::source(f, print.eval = print.eval, spaced = spaced, ...)
}

#' Returns the output of command to be inserted by R.nvim.
#' The function is called when the user runs the command `:Rinsert`.
#' @param cmd Command to be executed.
#' @param howto How R.nvim should insert the result.
nvim_insert <- function(cmd, howto = "tabnew") {
    try(o <- capture.output(cmd))
    if (inherits(o, "try-error")) {
        .C(
            nvimcom_msg_to_nvim,
            paste0(
                "require('r.log').warn('Error trying to execute the command \"",
                cmd,
                "\"')"
            )
        )
    } else {
        o <- gsub("\\\\", "\x12", o)
        o <- gsub("'", "\x13", o)
        o <- paste0(o, collapse = "\x14")
        .C(
            nvimcom_msg_to_nvim,
            paste0("require('r.edit').finish_inserting('", howto, "', '", o, "')")
        )
    }
    return(invisible(NULL))
}

#' List arguments of a function
#' This function is sent to R Console by R.nvim when the user press `\ra` over
#' an R object.
#' @param ff The object under cursor.
nvim.list.args <- function(ff) {
    saved.warn <- getOption("warn")
    options(warn = -1)
    on.exit(options(warn = saved.warn))
    mm <- try(methods(ff), silent = TRUE)
    if (class(mm)[1] == "MethodsFunction" && length(mm) > 0) {
        for (i in seq_along(mm)) {
            if (exists(mm[i])) {
                cat(ff, "[method ", mm[i], "]:\n", sep = "")
                print(args(mm[i]))
                cat("\n")
            }
        }
        return(invisible(NULL))
    }
    print(args(ff))
}

#' Plot an object.
#' This function is sent to R Console by R.nvim when the user press `\rg` over
#' an R object.
#' @param x The object under cursor.
nvim.plot <- function(x) {
    xname <- deparse(substitute(x))
    if (inherits(x, "numeric") || inherits(x, "integer")) {
        oldpar <- par(no.readonly = TRUE)
        par(mfrow = c(2, 1))
        hist(
            x,
            col = "lightgray",
            main = paste("Histogram of", xname),
            xlab = xname
        )
        boxplot(
            x,
            main = paste("Boxplot of", xname),
            col = "lightgray",
            horizontal = TRUE
        )
        par(oldpar)
    } else {
        plot(x)
    }
}

#' Output the names of an object.
#' This function is sent to R Console by R.nvim when the user press `\rn` over
#' an R object.
#' @param x The object under cursor.
nvim.names <- function(x) {
    if (isS4(x)) {
        slotNames(x)
    } else if (inherits(x, 'S7_object')) {
        names(attributes(x))
    } else {
        names(x)
    }
}

#' Get the class of object.
#' @param x R object.
nvim.getclass <- function(x) {
    if (missing(x) || length(charToRaw(x)) == 0) {
        return("#E#")
    }

    if (x == "#c#") {
        return("character")
    } else if (x == "#n#") {
        return("numeric")
    }

    if (!exists(x, where = .GlobalEnv)) {
        return("#E#")
    }

    saved.warn <- getOption("warn")
    options(warn = -1)
    on.exit(options(warn = saved.warn))
    tr <- try(cls <- class(get(x, envir = .GlobalEnv)), silent = TRUE)
    if (inherits(tr, "try-error")) {
        return("#E#")
    }

    return(cls)
}

update_params <- function(fname) {
    if (
        getOption("nvimcom.set_params") == "no" ||
            (getOption("nvimcom.set_params") == "no_override" &&
                exists("params", envir = .GlobalEnv))
    ) {
        return(invisible(NULL))
    }
    if (fname == "DeleteOldParams") {
        if (exists("params", envir = .GlobalEnv)) {
            rm(params, envir = .GlobalEnv)
        }
    } else {
        if (!require(knitr, quietly = TRUE)) {
            stop("Please, install the 'knitr' package.")
        }
        flines <- readLines(fname)
        params <- knitr::knit_params(flines)
        assign(
            "params",
            lapply(params, \(x) x$value),
            envir = .GlobalEnv
        )
    }
    .C(nvimcom_task)
    return(invisible(NULL))
}
