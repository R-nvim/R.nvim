#' Command sent to R console after `\rp`.
#' @param object Object under cursor.
#' @param firstobj If `object` is a function, the first function parameter.
nvim.print <- function(object, firstobj) {
    # detect if object is a function with namespace prefix
    exp <- parse(text = object, keep.source = FALSE)[[1L]]
    has_ns <- is.call(exp)
    if (has_ns && deparse(exp[[1L]], nlines = 1L) %in% c("::", ":::")) {
        ns <- asNamespace(exp[[2L]])
        object <- deparse(exp[[3L]])
    } else {
        # use the default 'where' for 'exists()'
        ns <- -1L
    }

    if (!exists(object, ns))
        warning("object '", object, "' not found")
    if (!missing(firstobj)) {
        objclass <- nvim.getclass(firstobj)
        if (objclass[1] != "#E#" && objclass[1] != "") {
            saved.warn <- getOption("warn")
            options(warn = -1)
            on.exit(options(warn = saved.warn))

            # `utils::methods()` only search in the search list, which means
            # only packages that have been loaded are considered. In order to
            # accept specified namespace, we need to set `mlen` here
            if (has_ns) {
                mlen <- 1L
            } else {
                mlen <- try(length(methods(object)), silent = TRUE)
            }

            if (class(mlen)[1] == "integer" && mlen > 0) {
                for (cls in objclass) {
                    if (exists(paste0(object, ".", cls), ns)) {
                        .newobj <- get(paste0(object, ".", cls), ns)
                        message("Note: Printing ", object, ".", cls)
                        break
                    }
                }
            }
        }
    }
    # make sure only search current calling environment
    if (!exists(".newobj", inherits = FALSE))
        .newobj <- get(object, ns)
    print(.newobj)
}
