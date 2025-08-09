#' Display PNG image in terminal using Kitty graphics protocol
#'
#' Displays a PNG image file in the terminal using the Kitty graphics protocol.
#' Adapted from https://codeberg.org/djvanderlaan/kitty.r
#'
#' @param filename Character string. Path to PNG file to display
#' @return Invisibly returns NULL
#' @noRd
png2terminal <- function(filename) {
  d <- base64enc::base64encode(filename, 4096L)
  for (i in seq_along(d)) {
    cat(paste0("\033_Ga=T,f=100,m=1;", d[i], "\033\\"))
  }
  cat("\033_Ga=T,f=100,m=0\033\\")
  cat("\n")
  invisible(NULL)
}

#' Check if terminal supports image display
#'
#' Checks if the current terminal supports displaying images
#' using various terminal graphics protocols.
#'
#' @return Logical. TRUE if terminal supports images, FALSE otherwise
#' @noRd
has_terminal_img_support <- function() {
  Sys.getenv("TERM_PROGRAM") %in%
    c("Ghostty", "WarpTerminal", "WezTerm") ||
    nzchar(Sys.getenv("KONSOLE_VERSION")) ||
    Sys.getenv("TERM") %in% c("xterm-kitty", "st-256color", "wayst")
}

#' Get plot dimensions for terminal display
#'
#' Determines appropriate plot dimensions based on terminal size
#' and provided width/height parameters.
#'
#' @param width Integer. Plot width in pixels (optional)
#' @param height Integer. Plot height in pixels (optional)
#' @return List with width and height components
#' @noRd
get_plot_dimensions <- function(width, height) {
  if (!is.null(width) && !is.null(height)) {
    return(list(width = width, height = height))
  }

  term_size <- system2("stty", "size", stdout = TRUE, stderr = FALSE)
  if (length(term_size) > 0L && !is.na(term_size)) {
    dims <- as.numeric(strsplit(term_size, " ", fixed = TRUE)[[1L]])
    if (length(dims) == 2L) {
      term_rows <- dims[1L]
      term_cols <- dims[2L]
      char_width <- 12L
      char_height <- 24L
      if (is.null(width)) {
        width <- as.integer(term_cols * char_width)
      }
      if (is.null(height)) {
        height <- as.integer(term_rows * char_height * 0.7)
      }
    }
  }

  if (is.null(width)) {
    width <- 800L
  }
  if (is.null(height)) {
    height <- 600L
  }

  list(width = width, height = height)
}

#' Create PNG file from plot expression
#'
#' Executes a plot expression and saves the result as a PNG file.
#'
#' @param expr Expression. Plot expression to evaluate
#' @param png_file Character string. Output PNG file path
#' @param width Integer. Plot width in pixels
#' @param height Integer. Plot height in pixels
#' @param dpi Integer. Resolution in dots per inch
#' @return Invisibly returns NULL
#' @noRd
create_plot_png <- function(expr, png_file, width, height, dpi) {
  current_dev <- dev.cur()
  png(png_file, width = width, height = height, res = dpi * 1.5)
  par(cex = 1.2, cex.axis = 1.2, cex.lab = 1.2, cex.main = 1.2)
  png_dev <- dev.cur()

  on.exit(
    {
      if (dev.cur() == png_dev && png_dev != 1L) {
        dev.off()
      }
    },
    add = TRUE
  )

  force(expr)

  on.exit(NULL)

  if (dev.cur() == png_dev && png_dev != 1L) {
    dev.off()
  }
}


#' Setup terminal plotting functionality
#'
#' Configures terminal plotting by overriding base plot functions when
#' nvimcom.terminal_plot option is enabled. Called from nvimcom.R .onAttach.
#'
#' @return Invisibly returns NULL
#' @noRd
setup_terminal_plotting <- function() {
  if (!interactive()) {
    return(invisible(NULL))
  }

  if (getOption("nvimcom.terminal_plot", FALSE)) {
    plot <- function(...) {
      show_plot_in_terminal(base::plot(...))
    }

    assign("plot", plot, envir = .GlobalEnv)

    if (requireNamespace("ggplot2", quietly = TRUE)) {
      .ggplot2_print <- getS3method("print", "ggplot")
      assign(
        "print.ggplot",
        function(x, ...) {
          show_plot_in_terminal(.ggplot2_print(x, ...))
        },
        envir = globalenv()
      )
    } else {
      cat("DEBUG: ggplot2 not available\n")
    }
  } else {
    cat(
      "DEBUG: Terminal plotting not enabled (interactive:",
      interactive(),
      ", option:",
      getOption("nvimcom.terminal_plot", FALSE),
      ")\n"
    )
  }
}

#' Display plot in terminal
#'
#' Creates and displays a plot in the terminal using graphics protocols.
#'
#' @param expr Expression. Plot expression to evaluate and display
#' @param width Integer. Plot width in pixels (optional)
#' @param height Integer. Plot height in pixels (optional)
#' @param dpi Integer. Resolution in dots per inch (default 100)
#' @return Invisibly returns NULL
#' @noRd
show_plot_in_terminal <- function(
  expr,
  width = NULL,
  height = NULL,
  dpi = 100L
) {
  if (!has_terminal_img_support()) {
    return(invisible(NULL))
  }

  dims <- get_plot_dimensions(width, height)
  width <- dims[["width"]]
  height <- dims[["height"]]

  png_file <- tempfile(fileext = ".png")
  create_plot_png(expr, png_file, width, height, dpi)
  png2terminal(png_file)
}
