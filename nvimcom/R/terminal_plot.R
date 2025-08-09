# Display PNG image in terminal using Kitty graphics protocol
# Adapted from https://codeberg.org/djvanderlaan/kitty.r
png2terminal <- function(filename) {
  d <- base64enc::base64encode(filename, 4096L)
  for (i in seq_along(d)) {
    cat(paste0("\033_Ga=T,f=100,m=1;", d[i], "\033\\"))
  }
  cat("\033_Ga=T,f=100,m=0\033\\")
  cat("\n")
  invisible(NULL)
}

show_plot_in_terminal <- function(
  expr,
  width = NULL,
  height = NULL,
  dpi = 100L
) {
  # Check terminal support first
  has_terminal_img_support <- (Sys.getenv(
    "TERM_PROGRAM"
  ) %in%
    c("Ghostty", "WarpTerminal", "WezTerm") ||
    nzchar(Sys.getenv("KONSOLE_VERSION")) ||
    Sys.getenv("TERM") %in% c("xterm-kitty", "st-256color", "wayst"))

  if (!has_terminal_img_support) {
    return(invisible(NULL))
  }

  # Get terminal dimensions if width/height not specified
  if (is.null(width) || is.null(height)) {
    term_size <- system2("stty", "size", stdout = TRUE, stderr = FALSE)
    if (length(term_size) > 0L && !is.na(term_size)) {
      dims <- as.numeric(strsplit(term_size, " ")[[1L]])
      if (length(dims) == 2L) {
        term_rows <- dims[1L]
        term_cols <- dims[2L]
        # pixels per character
        char_width <- 12L
        # pixels per character line
        char_height <- 24L
        if (is.null(width)) {
          width <- as.integer(term_cols * char_width)
        }
        if (is.null(height)) height <- as.integer(term_rows * char_height * 0.7)
      }
    }

    if (is.null(width)) {
      width <- 800L
    }
    if (is.null(height)) height <- 600L
  }

  png_file <- tempfile(fileext = ".png")

  current_dev <- dev.cur()

  png(png_file, width = width, height = height, res = dpi * 1.5)

  par(cex = 1.2, cex.axis = 1.2, cex.lab = 1.2, cex.main = 1.2)

  png_dev <- dev.cur()

  # Ensure we close the PNG device even if there's an error
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

  png2terminal(png_file)
}

# Setup terminal plotting - called from nvimcom.R .onAttach
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