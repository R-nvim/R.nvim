
# For building omnls files
#' @param x
nvim.fix.string <- function(x, edq = FALSE) {
    x <- gsub("\\\\", "\x12", x)
    x <- gsub("'", "\x13", x)
    x <- gsub("\n", "\\\\n", x)
    x <- gsub("\r", "\\\\r", x)
    x <- gsub("\t", "\\\\t", x)
    if (edq) {
        x <- gsub('"', '\x12"', x)
    }
    x
}

#' Get the list of arguments of a function
#' @param funcname Function name.
#' @param txt Begin of parameter name.
#' @param pkg Library name. If not NULL, restrict the search to `pkg`.
#' @param objclass Class of first argument of the function.
nvim.args <- function(funcname, txt = "", pkg = NULL, objclass = NULL) {
    # Adapted from: https://stat.ethz.ch/pipermail/ess-help/2011-March/006791.html
    if (!exists(funcname, where = 1))
        return("")
    frm <- NA
    funcmeth <- NA
    if (!is.null(objclass) && !nvim.grepl("[[:punct:]]", funcname)) {
        saved.warn <- getOption("warn")
        options(warn = -1)
        on.exit(options(warn = saved.warn))
        mlen <- try(length(methods(funcname)), silent = TRUE) # Still get warns
        if (class(mlen)[1] == "integer" && mlen > 0) {
            for (i in seq_along(objclass)) {
                funcmeth <- paste0(funcname, ".", objclass[i])
                if (existsFunction(funcmeth)) {
                    funcname <- funcmeth
                    frm <- formals(funcmeth)
                    break
                }
            }
        }
    }

    if (is.null(pkg)) {
        pkgname <- sub(".*:", "", find(funcname, mode = "function")[1])
    } else {
        pkgname <- pkg
    }

    if (is.na(frm[1])) {
        if (is.null(pkg)) {
            deffun <- paste0(funcname, ".default")
            if (existsFunction(deffun) && pkgname != ".GlobalEnv") {
                funcname <- deffun
                funcmeth <- deffun
            } else if (!existsFunction(funcname)) {
                return("")
            }
            if (is.primitive(get(funcname))) {
                a <- args(funcname)
                if (is.null(a))
                    return("")
                frm <- formals(a)
            } else {
                try(frm <- formals(get(funcname, envir = globalenv())), silent = TRUE)
                if (length(frm) == 1 && is.na(frm))
                    return("")
            }
        } else {
            idx <- grep(paste0(":", pkg, "$"), search())
            if (length(idx)) {
                ff <- "NULL"
                tr <- try(ff <- get(paste0(funcname, ".default"), pos = idx), silent = TRUE)
                if (inherits(tr, "try-error"))
                    ff <- get(funcname, pos = idx)
                if (is.primitive(ff)) {
                    a <- args(ff)
                    if (is.null(a))
                        return("")
                    frm <- formals(a)
                } else {
                    frm <- formals(ff)
                }
            } else {
                if (!isNamespaceLoaded(pkg))
                    loadNamespace(pkg)
                ff <- getAnywhere(funcname)
                idx <- grep(pkg, ff$where)
                if (length(idx))
                    frm <- formals(ff$objs[[idx]])
            }
        }
    }

    res <- NULL
    for (field in names(frm)) {
        type <- typeof(frm[[field]])
        if (type == "symbol") {
            res <- append(res, paste0(field, "\x05"))
        } else if (type == "character") {
            res <- append(res, paste0(field, "\x04\"",
                                      nvim.fix.string(frm[[field]], TRUE), "\"\x05"))
        } else if (type == "logical" || type == "double" || type == "integer") {
            res <- append(res, paste0(field, "\x04", as.character(frm[[field]]), "\x05"))
        } else if (type == "NULL") {
            res <- append(res, paste0(field, "\x04NULL\x05"))
        } else if (type == "language") {
            res <- append(res, paste0(field, "\x04",
                                      nvim.fix.string(deparse(frm[[field]])), "\x05"))
        } else if (type == "list") {
            res <- append(res, paste0(field, "\x04list()\x05"))
        } else {
            res <- append(res, paste0(field, "\x05"))
            warning("nvim.args: ", funcname, " [", field, "]", " (typeof = ", type, ")")
        }
    }

    res <- paste0(res, collapse = "")


    if (length(res) == 0 || (length(res) == 1 && res == "")) {
        res <- ""
    } else {
        if (is.null(pkg)) {
            info <- pkgname
            if (!is.na(funcmeth)) {
                if (info != "")
                    info <- paste0(info, ", ")
                info <- paste0(info, "function:", funcmeth, "()")
            }
            # TODO: Add the method name to the completion menu if (info != "")
        }
    }

    return(res)
}


#' Check if `pattern` is included in the vector `x`.
#' @param Pattern.
#' @param x Character vector.
nvim.grepl <- function(pattern, x) {
    res <- grep(pattern, x)
    if (length(res) == 0) {
        return(FALSE)
    } else {
        return(TRUE)
    }
}

#' Get object description from R documentation.
#' @param printenv Library name
#' @param x Object name
nvim.getInfo <- function(printenv, x) {
    if (is.null(NvimcomEnv$pkgdescr[[printenv]]))
        return("\006\006")

    info <- NULL
    als <- NvimcomEnv$pkgdescr[[printenv]]$alias[NvimcomEnv$pkgdescr[[printenv]]$alias[, "name"] == x, "alias"]
    try(info <- NvimcomEnv$pkgdescr[[printenv]]$descr[[als]], silent = TRUE)
    if (length(info) == 1)
        return(info)
    return("\006\006")
}

#' Make a single line of the `objls_` file with information for auto completion
#' of object names.
#' @param x R object
#' @param envir Current "environment" of object x. It will be
#' `package:libname`.
#' @param printenv The same as envir, but without the `package:` prefix.
#' @param curlevel Current number of levels in lists and S4 objects.
#' @param maxlevel Maximum number of levels in lists and S4 objects to parse,
#' with 0 meanin no limit.
nvim.cmpl.line <- function(x, envir, printenv, curlevel, maxlevel = 0) {
    # No support for names with apostrophes, such as magrittr::`n'est pas`
    if (nvim.grepl("'", x))
        return(invisible(NULL))

    if (curlevel == 0) {
        xx <- try(get(x, envir), silent = TRUE)
        if (inherits(xx, "try-error"))
            return(invisible(NULL))
    } else {
        x.clean <- gsub("$", "", x, fixed = TRUE)
        x.clean <- gsub("_", "", x.clean, fixed = TRUE)
        haspunct <- nvim.grepl("[[:punct:]]", x.clean)
        if (haspunct[1]) {
            ok <- nvim.grepl("[[:alnum:]]\\.[[:alnum:]]", x.clean)
            if (ok[1]) {
                haspunct  <- FALSE
                haspp <- nvim.grepl("[[:punct:]][[:punct:]]", x.clean)
                if (haspp[1]) haspunct <- TRUE
            }
        }

        # No support for names with spaces
        if (nvim.grepl(" ", x)) {
            haspunct <- TRUE
        }

        if (haspunct[1]) {
            xx <- NULL
        } else {
            xx <- try(eval(parse(text = x)), silent = TRUE)
            if (inherits(xx, "try-error")) {
                xx <- NULL
            }
        }
    }

    if (is.null(xx)) {
        x.class <- ""
        x.group <- "*"
    } else {
        if (x == "break" || x == "next" || x == "for" || x == "if" || x == "repeat" || x == "while") {
            x.group <- ";"
            x.class <- "flow-control"
        } else {
            x.class <- class(xx)[1]
            if (is.function(xx)) {
                x.group <- "f"
            } else if (is.numeric(xx)) {
                x.group <- "{"
            } else if (is.factor(xx)) {
                x.group <- "!"
            } else if (is.character(xx)) {
                x.group <- "~"
            } else if (is.logical(xx)) {
                x.group <- "%"
            } else if (is.data.frame(xx)) {
                x.group <- "$"
            } else if (is.list(xx)) {
                x.group <- "["
            } else if (is.environment(xx)) {
                x.group <- ":"
            } else {
                x.group <- "*"
            }
        }
    }

    n <- nvim.fix.string(x)

    if (curlevel == maxlevel || maxlevel == 0) {
        if (x.group == "f") {
            if (curlevel == 0) {
                if (nvim.grepl("GlobalEnv", printenv)) {
                    cat(n, "\006(\006function\006", printenv, "\006",
                        nvim.args(x), "\n", sep = "")
                } else {
                    info <- nvim.getInfo(printenv, x)
                    cat(n, "\006(\006function\006", printenv, "\006",
                        nvim.args(x, pkg = printenv), info, "\006\n", sep = "")
                }
            } else {
                # some libraries have functions as list elements
                cat(n, "\006(\006function\006", printenv,
                    "\006\006\006\006\n", sep = "")
            }
        } else {
            if (is.list(xx) || is.environment(xx)) {
                if (curlevel == 0) {
                    info <- nvim.getInfo(printenv, x)
                    if (is.data.frame(xx)) {
                        cat(n, "\006", x.group, "\006", x.class, "\006", printenv,
                            "\006[", nrow(xx), ", ", ncol(xx), "]", info, "\006\n", sep = "")
                    } else if (is.list(xx)) {
                        cat(n, "\006", x.group, "\006", x.class, "\006", printenv,
                            "\006", length(xx), info, "\006\n", sep = "")
                    } else {
                        cat(n, "\006", x.group, "\006", x.class, "\006", printenv,
                            "\006[]", info, "\006\n", sep = "")
                    }
                } else {
                    cat(n, "\006", x.group, "\006", x.class, "\006", printenv,
                        "\006[]\006\006\006\n", sep = "")
                }
            } else {
                info <- nvim.getInfo(printenv, x)
                if (info == "\006\006") {
                    xattr <- try(attr(xx, "label"), silent = TRUE)
                    if (!inherits(xattr, "try-error") && !is.null(xattr) && length(xattr) == 1)
                        info <- paste0("\006\006", nvim.fix.string(.Call(rd2md, xattr)))
                }
                cat(n, "\006", x.group, "\006", x.class, "\006", printenv,
                    "\006[]", info, "\006\n", sep = "")
            }
        }
    }

    if ((is.list(xx) || is.environment(xx)) && curlevel <= maxlevel) {
        obj.names <- names(xx)
        curlevel <- curlevel + 1
        xxl <- length(xx)
        if (!is.null(xxl) && xxl > 0) {
            for (k in obj.names) {
                nvim.cmpl.line(paste0(x, "$", k), envir, printenv, curlevel, maxlevel)
            }
        }
    } else if (isS4(xx) && curlevel <= maxlevel) {
        obj.names <- slotNames(xx)
        curlevel <- curlevel + 1
        xxl <- length(xx)
        if (!is.null(xxl) && xxl > 0) {
            for (k in obj.names) {
                nvim.cmpl.line(paste0(x, "@", k), envir, printenv, curlevel, maxlevel)
            }
        }
    }
}

#' Store descriptions of all functions from a library in a internal
#' environment.
#' @param pkg Library name.
GetFunDescription <- function(pkg) {
    pd <- packageDescription(pkg)
    pth <- attr(pd, "file")
    pth <- sub("Meta/package.rds", "help/", pth)
    idx <- paste0(pth, "aliases.rds")

    # Development packages might not have any written documentation yet
    if (!file.exists(idx) || !file.info(idx)$size)
        return(NULL)

    als <- readRDS(idx)
    als <- cbind(unname(als), names(als))
    colnames(als) <- c("alias", "name")
    write.table(als, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE,
                file = paste0(Sys.getenv("RNVIM_COMPLDIR"), "/alias_", pkg))

    if (!file.exists(paste0(pth, pkg, ".rdx")))
        return(NULL)
    pkgRdDB <- tools:::fetchRdDB(paste0(pth, pkg))
    NvimcomEnv$pkgRdDB[[pkg]] <- pkgRdDB

    GetDescr <- function(x) {
        tags <- tools:::RdTags(x)
        x[which(!(tags %in% c(c("\\title", "\\name", "\\description"))))] <-  NULL
        x <- paste0(x, collapse = "")
        ttl <- .Call(get_section, x, "title")
        dsc <- .Call(get_section, x, "description")
        ttl <- nvim.fix.string(ttl)
        dsc <- nvim.fix.string(dsc)
        x <- paste0("\006", ttl, "\006", dsc)
        x
    }
    NvimcomEnv$pkgdescr[[pkg]] <- list("descr" = sapply(pkgRdDB, GetDescr),
                                       "alias" = als)
}

#' @param x
filter.objlist <- function(x) {
    x[!grepl("^[\\[\\(\\{:-@%/=+\\$<>\\|~\\*&!\\^\\-]", x) & !startsWith(x, ".__")]
}

get_arg_doc_list <- function(fun, pkg) {
    rdo <- NULL
    try(rdo <- NvimcomEnv$pkgRdDB[[pkg]][[fun]], silent = FALSE)
    if (is.null(rdo))
        return(invisible(NULL))

    atbl <- tools:::.Rd_get_argument_table(rdo)
    if (length(atbl) == 0)
        return(invisible(NULL))

    atbl[, 1] <- gsub("\\\\dots", "...", atbl[, 1])
    args <- apply(atbl, 1,
                  function(x)
                      paste0(x[1], "\x05`", gsub(", ", "`, `", x[1]), "`: ",
                             .Call(rd2md, x[2]), "\x06"))
    line <- nvim.fix.string(paste0(fun, "\x06", paste0(args, collapse = "")))
    cat(line, sep = "", "\n")
}

#' Build in R.nvim's cache directory the `args_` file with arguments of
#' functions.
#' @param afile Full path of the `args_` file.
#' @param pkg Library name.
nvim.buildargs <- function(afile, pkg) {
    if (is.null(NvimcomEnv$pkgRdDB[[pkg]]))
        return(invisible(NULL))

    nms <- names(NvimcomEnv$pkgRdDB[[pkg]])
    sink(afile)
    sapply(nms, get_arg_doc_list, pkg)
    sink()
    return(invisible(NULL))
}

#' Build data files for auto completion and for the Object Browser in the
#' cache directory:
#'   - `alias_` : for finding the appropriate function during auto completion.
#'   - `objls_` : for auto completion and object browser
#'   - `args_`  : for describing selected arguments during auto completion.
#' @param cmpllist Full path of `objls_` file to be built.
#' @param libname Library name.
nvim.bol <- function(cmpllist, libname) {
    nvim.OutDec <- getOption("OutDec")
    on.exit(options(nvim.OutDec))
    options(OutDec = ".")

    if (is.null(NvimcomEnv$pkgdescr[[libname]]))
        GetFunDescription(libname)

    loadpack <- search()
    packname <- paste0("package:", libname)

    if (nvim.grepl(paste0(packname, "$"), loadpack) == FALSE) {
        ok <- try(require(libname, warn.conflicts = FALSE,
                          quietly = TRUE, character.only = TRUE))
        if (!ok)
            return(invisible(NULL))
    }

    obj.list <- objects(packname, all.names = TRUE)
    obj.list <- filter.objlist(obj.list)

    l <- length(obj.list)
    if (l > 0) {
        # Build objls_ for auto completion and Object Browser
        sink(cmpllist, append = FALSE)
        for (obj in obj.list) {
            ol <- try(nvim.cmpl.line(obj, packname, libname, 0))
            if (inherits(ol, "try-error"))
                warning(paste0("Error while generating completion line for: ",
                               obj, " (", packname, ", ", libname, ").\n"))
        }
        sink()
    } else {
        writeLines(text = "", con = cmpllist)
    }
    return(invisible(NULL))
}

#' This function calls nvim.bol which writes three files in `~/.cache/R.nvim`:
#' @param p Character vector with names of libraries.
nvim.build.cmplls <- function(p) {
    if (length(p) > 1) {
        n <- 0
        for (pkg in p)
            n <- n + nvim.build.cmplls(pkg)
        if (n > 0)
            return(invisible(1))
        return(invisible(0))
    }
    # No verbosity because running as Neovim job
    options(nvimcom.verbose = 0)

    pvi <- utils::packageDescription(p)$Version
    bdir <- paste0(Sys.getenv("RNVIM_COMPLDIR"), "/")
    odir <- dir(bdir)
    pbuilt <- odir[grep(paste0("objls_", p, "_"), odir)]
    abuilt <- odir[grep(paste0("args_", p, "_"), odir)]

    need_build <- FALSE

    if (length(pbuilt) == 0) {
        # no completion file
        need_build <- TRUE
    } else {
        if (length(pbuilt) > 1) {
            # completion file is duplicated (should never happen)
            need_build <- TRUE
        } else {
            pvb <- sub(".*_.*_", "", pbuilt)
            # completion file is either outdated or older than the README
            if (pvb != pvi ||
                file.info(paste0(bdir, "README"))$mtime > file.info(paste0(bdir, pbuilt))$mtime)
                need_build <- TRUE
        }
    }

    if (need_build) {
        msg <- paste0("ECHO: Building completion list for \"", p, "\"\x14\n")
        cat(msg)
        flush(stdout())
        unlink(c(paste0(bdir, pbuilt), paste0(bdir, abuilt)))
        t1 <- Sys.time()
        nvim.bol(paste0(bdir, "objls_", p, "_", pvi), p)
        t2 <- Sys.time()
        nvim.buildargs(paste0(bdir, "args_", p), p)
        t3 <- Sys.time()
        msg <- paste0("INFO: ", p, "=",
                      round(as.numeric(t2 - t1), 5), " + ",
                      round(as.numeric(t3 - t2), 5), "=Build time\x14")
        cat(msg)
        flush(stdout())

        return(invisible(1))
    }
    return(invisible(0))
}
