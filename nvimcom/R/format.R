check_formatfun <- function() {
  if (length(find.package("styler", quiet = TRUE, verbose = FALSE)) == 0) {
    .C(nvimcom_msg_to_nvim,
      "lua require('r.log').warn('You have to install styler in order to run :RFormat')")
    return(FALSE)
  }
  return(TRUE)
}

#' Format R file.
#' Sent to nvimcom through rnvimserver by R.nvim when the user runs the
#' `RFormat` command.
#' @param fname File name of buffer to be formatted.
#' @param wco Text width, based on Vim option 'textwidth'.
#' @param sw Vim option 'shiftwidth'.
nvim_format_file <- function(fname, wco, sw) {
  if (!check_formatfun()) {
    return(invisible(NULL))
  }

  sq <- getOption("styler.quiet")
  options(styler.quiet = TRUE)
  ok <- try(styler::style_file(fname, indent_by = sw))
  options(styler.quiet = sq)
  if (inherits(ok, "try-error")) {
    .C(nvimcom_msg_to_nvim,
      "lua require('r.log').warn('Error trying to execute the function styler::style_file()')")
    return(invisible(NULL))
  }

  .C(nvimcom_msg_to_nvim, "lua require('r.edit').reload()")
  return(invisible(NULL))
}

#' Format R code.
#' Sent to nvimcom through rnvimserver by R.nvim when the user runs the
#' `RFormat` command.
#' @param l1 First line of selection. R.nvim needs the information to know
#' what lines to replace.
#' @param l2 Last line of selection. R.nvim needs the information to know
#' what lines to replace.
#' @param wco Text width, based on Vim option 'textwidth'.
#' @param sw Vim option 'shiftwidth'.
#' @param txt Text to be formatted.
nvim_format_txt <- function(l1, l2, wco, sw, txt) {
  if (!check_formatfun()) {
    return(invisible(NULL))
  }

  txt <- strsplit(gsub("\x13", "'", txt), "\x14")[[1]]
  ok <- try(styler::style_text(txt, indent_by = sw))
  if (inherits(ok, "try-error")) {
    .C(nvimcom_msg_to_nvim,
      "lua require('r.log').warn('Error trying to execute the function styler::style_text()')")
    return(invisible(NULL))
  }
  txt <- gsub("'", "\x13", paste0(ok, collapse = "\x14"))

  .C(nvimcom_msg_to_nvim,
    paste0("lua require('r.edit').finish_code_formatting(", l1, ", ", l2, ", '", txt, "')"))
  return(invisible(NULL))
}
