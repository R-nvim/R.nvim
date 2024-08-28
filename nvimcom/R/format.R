check_formatfun <- function() {
    if (is.null(getOption("nvimcom.formatfun"))) {
        if (length(find.package("styler", quiet = TRUE, verbose = FALSE)) > 0) {
           options(nvimcom.formatfun = "style_text")
        } else {
            if (length(find.package("formatR", quiet = TRUE, verbose = FALSE)) > 0) {
                options(nvimcom.formatfun = "tidy_source")
            } else {
                .C("nvimcom_msg_to_nvim",
                   "lua require('r').warn('You have to install either formatR or styler in order to run :Rformat')",
                   PACKAGE = "nvimcom")
                return(invisible(NULL))
            }
        }
    }
}

#' Format R file.
#' Sent to nvimcom through rnvimserver by R.nvim when the user runs the
#' `Rformat` command.
#' @param fname File name of buffer to be formatted.
#' @param wco Text width, based on Vim option 'textwidth'.
#' @param sw Vim option 'shiftwidth'.
nvim_format_file <- function(fname, wco, sw) {
    check_formatfun()
    if (getOption("nvimcom.formatfun") == "tidy_source") {
        ok <- formatR::tidy_file(fname, width.cutoff = wco, output = FALSE)
        if (inherits(ok, "try-error")) {
            .C("nvimcom_msg_to_nvim",
               "lua require('r').warn('Error trying to execute the function formatR::tidy_file()')",
               PACKAGE = "nvimcom")
            return(invisible(NULL))
        }
    } else if (getOption("nvimcom.formatfun") == "style_text") {
        ok <- try(styler::style_file(fname, indent_by = sw))
        if (inherits(ok, "try-error")) {
            .C("nvimcom_msg_to_nvim",
               "lua require('r').warn('Error trying to execute the function styler::style_file()')",
               PACKAGE = "nvimcom")
            return(invisible(NULL))
        }
    } else  {
        warning('Valid values for `nvimcom.formatfun` are "style_text" and "tidy_source"')
        return(invisible(NULL))
    }

    .C("nvimcom_msg_to_nvim",
       paste0("lua require('r.edit').reload()"),
       PACKAGE = "nvimcom")
    return(invisible(NULL))
}

#' Format R code.
#' Sent to nvimcom through rnvimserver by R.nvim when the user runs the
#' `Rformat` command.
#' @param l1 First line of selection. R.nvim needs the information to know
#' what lines to replace.
#' @param l2 Last line of selection. R.nvim needs the information to know
#' what lines to replace.
#' @param wco Text width, based on Vim option 'textwidth'.
#' @param sw Vim option 'shiftwidth'.
#' @param txt Text to be formatted.
nvim_format_txt <- function(l1, l2, wco, sw, txt) {
    check_formatfun()
    txt <- strsplit(gsub("\x13", "'", txt), "\x14")[[1]]
    if (getOption("nvimcom.formatfun") == "tidy_source") {
        ok <- formatR::tidy_source(text = txt, width.cutoff = wco, output = FALSE)
        if (inherits(ok, "try-error")) {
            .C("nvimcom_msg_to_nvim",
               "lua require('r').warn('Error trying to execute the function formatR::tidy_source()')",
               PACKAGE = "nvimcom")
            return(invisible(NULL))
        }
        txt <- gsub("'", "\x13", paste0(ok$text.tidy, collapse = "\x14"))
    } else if (getOption("nvimcom.formatfun") == "style_text") {
        ok <- try(styler::style_text(txt, indent_by = sw))
        if (inherits(ok, "try-error")) {
            .C("nvimcom_msg_to_nvim",
               "lua require('r').warn('Error trying to execute the function styler::style_text()')",
               PACKAGE = "nvimcom")
            return(invisible(NULL))
        }
        txt <- gsub("'", "\x13", paste0(ok, collapse = "\x14"))
    } else  {
        warning('Valid values for `nvimcom.formatfun` are "style_text" and "tidy_source"')
        return(invisible(NULL))
    }

    .C("nvimcom_msg_to_nvim",
       paste0("lua require('r.edit').finish_code_formatting(", l1, ", ", l2, ", '", txt, "')"),
       PACKAGE = "nvimcom")
    return(invisible(NULL))
}
