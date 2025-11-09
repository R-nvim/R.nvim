format_text <- function(txt) {
    txt <- .Call(fmt_txt, txt[1])
    txt
}

#' Return to rnvimserver the signature of a .GlobalEnv function
signature <- function(req_id, funcname) {
    args <- nvim.args(funcname)
    if (args == "") {
        .C(nvimcom_msg_to_nvim, paste0("+N", req_id))
    } else {
        .C(
            nvimcom_msg_to_nvim,
            paste0("+S", req_id, "|", funcname, "|", args)
        )
    }
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
    width <- as.integer(Sys.getenv("CMPR_DOC_WIDTH"))
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
    txt <- append(txt, c("* * *", "```rout"))
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
