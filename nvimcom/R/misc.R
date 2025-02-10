# Function called by R if options(editor = nvim.edit).
# R.nvim sets this option during nvimcom loading.
nvim.edit <- function(name, file, title) {
    if (file != "")
        stop("Feature not implemented. Use nvim to edit files.")
    if (is.null(name))
        stop("Feature not implemented. Use nvim to create R objects from scratch.")

    editf <- paste0(Sys.getenv("RNVIM_TMPDIR"), "/edit_", Sys.getenv("RNVIM_ID"), "_", round(runif(1, min = 100, max = 999)))
    waitf <- paste0(editf, "_wait")
    unlink(editf)
    writeLines(text = "Waiting...", con = waitf)

    sink(editf)
    dput(name)
    sink()

    .C(nvimcom_msg_to_nvim,
       paste0("lua require('r.edit').obj('", editf, "')"))

    while (file.exists(waitf))
        Sys.sleep(1)
    x <- eval(parse(editf))
    unlink(waitf)
    unlink(editf)
    x
}

# Substitute for utils::vi
vi <- function(name = NULL, file = "") {
    nvim.edit(name, file)
}

#' Function called by R.nvim when the user wants to source a line of code and
#' capture its output in a new Vim tab (default key binding `o`)
#' @param s A string representing the line of code to be source.
#' @param nm The name of the buffer to be created in the Vim tab.
nvim_capture_source_output <- function(s, nm) {
    o <- capture.output(base::source(s, echo = TRUE), file = NULL)
    o <- paste0(o, collapse = "\x14")
    o <- gsub("'", "\x13", o)
    .C(nvimcom_msg_to_nvim, paste0("lua require('r.edit').get_output('", nm, "', '", o, "')"))
}

#' Function called by R.nvim when the user wants to run the command `dput()`
#' over the word under cursor and see its output in a new Vim tab.
#' @param oname The name of the object under cursor.
#' @param howto How to show the output (never included when called by R.nvim).
nvim_dput <- function(oname, howto = "tabnew") {
    o <- capture.output(eval(parse(text = paste0("dput(", oname, ")"))))
    o <- paste0(o, collapse = "\x14")
    o <- gsub("'", "\x13", o)
    .C(nvimcom_msg_to_nvim,
       paste0("lua require('r.run').show_obj('", howto, "', '", oname, "', 'r', '", o, "')"))
}

#' Function called by R.nvim when the user wants to see a `data.frame` or
#' `matrix` (default key bindings: `\rv`, `\vs`, `\vv`, and `\rh`).
#' @param oname The name of the object (`data.frame` or `matrix`).
#' @param fenc File encoding to be used.
#' @param nrows How many lines to show.
#' @param R_df_viewer R function to be called to show the `data.frame`.
#' @param save_fun R function to be called to save the CSV file.
nvim_viewobj <- function(oname, fenc = "", nrows = -1, R_df_viewer = NULL, save_fun = NULL) {
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
            .C(nvimcom_msg_to_nvim,
               paste0("lua require('r.log').warn('", '"', oname, '"', " not found in .GlobalEnv')"))
            return(invisible(NULL))
        }
    }
    if (is.data.frame(o) || is.matrix(o)) {
        if (nrows < 0)
            nrows <- ceiling(10000 / ncol(o))
        if (nrows != 0 && nrows < nrow(o)) {
          o <- o[1:nrows, ]
        }
        if (!is.null(R_df_viewer)) {
            cmd <- gsub("'", "\x13", R_df_viewer)
            .C(nvimcom_msg_to_nvim,
               paste0("lua vim.schedule(function() require('r.send').cmd('", cmd, "') end)"))
            return(invisible(NULL))
        }
        if (is.null(save_fun)) {
            if (getOption("nvimcom.delim") == "\t") {
                txt <- capture.output(write.table(o, sep = "\t", row.names = FALSE, quote = FALSE,
                                                  fileEncoding = fenc))
            } else {
                txt <- capture.output(write.table(o, sep = getOption("nvimcom.delim"), row.names = FALSE,
                                                  fileEncoding = fenc))
            }
            txt <- paste0(txt, collapse = "\x14")
            txt <- gsub("'", "\x13", txt)
        } else {
            txt <- save_fun(o, oname)
            if (is.null(txt))
                txt <- oname
        }
        .C(nvimcom_msg_to_nvim,
           paste0("lua require('r.edit').view_df('", oname, "', '", txt, "')"))
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
    base::source(getOption("nvimcom.source.path"), ...,
        print.eval = print.eval, spaced = spaced)
}

#' Call base::source.
#' This function is sent to R Console when the user press `\ss`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.selection <- function(..., local = parent.frame()) Rnvim.source(..., local = local)

#' Call base::source.
#' This function is sent to R Console when the user press `\pp`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.paragraph <- function(..., local = parent.frame()) Rnvim.source(..., local = local)

#' Call base::source.
#' This function is sent to R Console when the user press `\bb`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.block <- function(..., local = parent.frame()) Rnvim.source(..., local = local)

#' Call base::source.
#' This function is sent to R Console when the user press `\ff`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.function <- function(..., local = parent.frame()) Rnvim.source(..., local = local)

#' Call base::source.
#' This function is sent to R Console when the user press `\cc`.
#' @param ... Further arguments passed to base::source.
#' @param local See base::source.
Rnvim.chunk <- function(..., local = parent.frame()) Rnvim.source(..., local = local)

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
        .C(nvimcom_msg_to_nvim,
           paste0("lua require('r.log').warn('Error trying to execute the command \"", cmd, "\"')"))
    } else {
        o <- gsub("\\\\", "\\\\\\\\", o)
        o <- gsub("'", "\\\\'", o)
        o <- paste0(o, collapse = "\x14")
        .C(nvimcom_msg_to_nvim,
           paste0("lua require('r.edit').finish_inserting('", howto, "', '", o, "')"))
    }
    return(invisible(NULL))
}

format_text <- function(txt, delim, nl) {
    txt <- .Call(fmt_txt, txt, delim, nl)
    txt
}

format_usage <- function(fnm, args) {
    txt <- .Call(fmt_usage, fnm, args)
    txt
}

#' Output the arguments of a function as extra information to be shown during
#' auto-completion.
#' Called by rnvimserver when the user selects a function created in the
#' .GlobalEnv environment in the completion menu.
#' menu.
#' @param funcname Name of function selected in the completion menu.
nvim.GlobalEnv.fun.args <- function(funcname) {
    txt <- nvim.args(funcname)
    # txt <- gsub("\\\\", "\\\\\\\\", txt)
    txt <- format_usage(funcname, txt)
    txt <- paste0("function [.GlobalEnv]", txt)
    .C(nvimcom_msg_to_nvim,
       paste0("lua ", Sys.getenv("RNVIM_RSLV_CB"), "('", txt, "')"))
    return(invisible(NULL))
}

#' Output the minimal information on an object during auto-completion.
#' @param obj Object selected in the completion menu.
#' @param prnt Parent environment
nvim.min.info <- function(obj, prnt) {
    isnull <- try(is.null(obj), silent = TRUE)
    if (class(isnull)[1] != "logical")
        return(invisible(NULL))
    if (isnull[1])
        return(invisible(NULL))

    txt <- paste0(class(obj)[1], " [", prnt, "]")
    objlbl <- attr(obj, "label")
    if (!is.null(objlbl))
        txt <- append(txt, c("", paste0("**", format_text(objlbl, " ", "\x14"), "**")))
    if (is.data.frame(obj)) {
        txt <- append(txt, paste0("dim: ", nrow(obj), " x ", ncol(obj)))
    } else if (is.list(obj)) {
        txt <- append(txt, paste0("number of elements: ", length(obj)))
    }

    txt <- gsub("'", "\x13", txt)
    txt <- paste0(txt, collapse = "\x14")

    .C(nvimcom_msg_to_nvim,
       paste0("lua ", Sys.getenv("RNVIM_RSLV_CB"), "('", txt, "')"))
    return(invisible(NULL))
}

#' Output the summary as extra information on an object during auto-completion.
#' @param obj Object selected in the completion menu.
#' @param prnt Parent environment
nvim.get.summary <- function(obj, prnt) {
    isnull <- try(is.null(obj), silent = TRUE)
    if (class(isnull)[1] != "logical")
        return(invisible(NULL))
    if (isnull[1])
        return(invisible(NULL))

    owd <- getOption("width")
    width <- as.integer(Sys.getenv("CMPR_DOC_WIDTH"))
    if (is.na(width)) {
        width <- 58
    }
    options(width = width)
    txt <- paste0(class(obj)[1], " [", prnt, "]")
    objlbl <- attr(obj, "label")
    if (!is.null(objlbl)) {
        objlbl <- format_text(objlbl, " ", "\x14")
        objlbl <- nvim.fix.string(objlbl)
        txt <- append(txt, c("", objlbl))
    }
    txt <- append(txt, "\x14\x14---\x14```rout")
    if (is.factor(obj) || is.numeric(obj) || is.logical(obj)) {
        sobj <- try(summary(obj), silent = TRUE)
        txt <- append(txt, capture.output(print(sobj)))
    } else {
        sobj <- try(capture.output(utils::str(obj)), silent = TRUE)
        txt <- append(txt, sobj)
    }
    txt <- append(txt, c("```", ""))
    options(width = owd)

    txt <- gsub("'", "\x13", txt)
    txt <- paste0(txt, collapse = "\x14")

    .C(nvimcom_msg_to_nvim,
       paste0("lua ", Sys.getenv("RNVIM_RSLV_CB"), "('", txt, "')"))
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
        hist(x, col = "lightgray", main = paste("Histogram of", xname), xlab = xname)
        boxplot(x, main = paste("Boxplot of", xname),
                col = "lightgray", horizontal = TRUE)
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
    } else {
        names(x)
    }
}

#' Get the class of object.
#' @param x R object.
nvim.getclass <- function(x) {
    if (missing(x) || length(charToRaw(x)) == 0)
        return("#E#")

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
    if (inherits(tr, "try-error"))
        return("#E#")

    return(cls)
}

nvim.getmethod <- function(fname, objclass) {
    if (exists(fname, where = 1) && is.function(get(fname, pos = 1)) &&
        (isGeneric(fname) || isS3stdGeneric(fname))) {
        mtd <- rownames(attr(methods(fname), "info"))
        for (obc in objclass) {
            fnm <- paste0(fname, ".", obc)
            idx <- grep(paste0("^", fnm, "$"), mtd)
            if (length(idx) == 1) {
                fun <- NULL
                try(fun <- getS3method(fname, obc))
                if (is.function(fun)) {
                    frm <- formals(fun)
                    luatbl <- sapply(frm,
                                     function(x)
                                         if (length(x) == 0) {
                                             return("")
                                         } else {
                                             return(" = ")
                                         })
                    env <- paste0("#\x02", fnm)
                    clpstr <- paste0("', cls = 'a', env = '", env, "'}, {label = '")
                    luastr <- paste0(names(luatbl), unname(luatbl),
                                     collapse = clpstr)
                    luastr <- paste0("{label = '", luastr, "', cls = 'a', env = '", env, "'}")
                    return(luastr)
                }
            }
        }
    }
    return(fname)
}

#' Complete arguments of functions.
#' Called during nvim-cmp completion with cmp-r as source.
#' @param id Completion identification number.
#' @param rkeyword Name of function whose arguments are being completed.
#' @param argkey First characters of argument to be completed.
#' @param firstobj First parameter of function being completed.
#' @param lib Name of library preceding the function name
#' (example: `library::function`).
#' @param ldf Whether the function is in `R_fun_data_1` or not.
nvim_complete_args <- function(id, rkeyword, argkey, firstobj = "", lib = NULL, ldf = FALSE) {

    # Check if rkeyword is a .GlobalEnv function:
    if (length(grep(paste0("^", rkeyword, "$"), objects(.GlobalEnv))) == 1) {
        args <- nvim.args(rkeyword, txt = argkey)
        args <- gsub("\005$", "", args)
        argsl <- strsplit(args, "\005")[[1]]
        argsl <- sub("\004.*", "", argsl)
        args <- paste0("{label = '",
                       paste(argsl,
                             collapse = "', cls = 'a', env = '.GlobalEnv'}, {label = '"),
                       "', cls = 'a', env = '.GlobalEnv'}")
        msg <- paste0("+C", id, ";", argkey, ";", rkeyword, ";;", args)
        .C(nvimcom_msg_to_nvim, msg)
        return(invisible(NULL))
    }

    if (firstobj != "" && exists(firstobj, where = 1)) {
        # Completion of columns of data.frame
        if (ldf && is.data.frame(get(firstobj))) {
            if (is.null(lib)) {
                msg <- paste0("+C", id, ";", argkey, ";", rkeyword, ";", firstobj, ";")
            } else {
                msg <- paste0("+C", id, ";", argkey, ";", lib, "::", rkeyword, ";", firstobj, ";")
            }
            .C(nvimcom_msg_to_nvim, msg)
            return(invisible(NULL))
        }

        # Completion of method arguments
        objclass <- nvim.getclass(firstobj)
        if (objclass[1] != "#E#" && objclass[1] != "") {
            mthd <- nvim.getmethod(rkeyword, objclass)
            if (mthd != rkeyword) {
                msg <- paste0("+C", id, ";", argkey, ";;;", mthd, ", ")
                .C(nvimcom_msg_to_nvim, msg)
                return(invisible(NULL))
            }
        }
    }

    # Normal completion of arguments
    if (is.null(lib)) {
        msg <- paste0("+C", id, ";", argkey, ";", rkeyword, ";;")
    } else {
        msg <- paste0("+C", id, ";", argkey, ";", lib, "::", rkeyword, ";;")
    }
    .C(nvimcom_msg_to_nvim, msg)
    return(invisible(NULL))
}

update_params <- function(fname) {
    if (
        getOption("nvimcom.set_params") == "no" ||
          (
            getOption("nvimcom.set_params") == "no_override" &&
                exists("params", envir = .GlobalEnv)
          )
    ) {
      return(invisible(NULL))
    }
    if (fname == "DeleteOldParams") {
        if (exists("params", envir = .GlobalEnv)) {
            rm(params, envir = .GlobalEnv)
        }
    } else {
        if (!require(knitr, quietly = TRUE))
            stop("Please, install the 'knitr' package.")
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
