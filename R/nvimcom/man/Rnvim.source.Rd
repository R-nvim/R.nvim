\name{Rnvim.source}
\alias{Rnvim.source}
\alias{Rnvim.selection}
\alias{Rnvim.paragraph}
\alias{Rnvim.function}
\alias{Rnvim.chunk}
\alias{Rnvim.block}
\title{Wrapper to base::source}
\description{
  Call base::source with the arguments \code{print.eval=TRUE} and
  \code{spaced=FALSE}.
}
\usage{
  Rnvim.source(..., print.eval = TRUE, spaced = FALSE)
  Rnvim.selection(..., local = parent.frame())
  Rnvim.paragraph(..., local = parent.frame())
  Rnvim.function(..., local = parent.frame())
  Rnvim.chunk(..., local = parent.frame())
  Rnvim.block(..., local = parent.frame())
}
\arguments{
  \item{print.eval}{See base::source.}
  \item{spaced}{See base::source.}
  \item{local}{See base::source.}
  \item{...}{Further arguments passed to base::source.}
}
