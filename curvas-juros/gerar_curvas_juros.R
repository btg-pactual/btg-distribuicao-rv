# Rode este arquivo no RStudio (ou via Rscript) para atualizar tudo.
raiz <- {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1L) {
    dirname(normalizePath(sub("^--file=", "", file_arg)))
  } else if (requireNamespace("rstudioapi", quietly = TRUE) &&
             rstudioapi::isAvailable()) {
    dirname(rstudioapi::getActiveDocumentContext()$path)
  } else {
    "."
  }
}
setwd(raiz)
source("scripts/run_all.R")
