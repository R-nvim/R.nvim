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
