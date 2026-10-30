# Setup comum para jobs CLI (cache COTAHIST).
job_root <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) {
    normalizePath(
      file.path(dirname(sub("^--file=", "", f[[1]])), ".."),
      winslash = "/",
      mustWork = FALSE
    )
  } else {
    normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
})

setwd(job_root)
source(file.path(job_root, "config_mr_derivs.R"), local = FALSE)
source(file.path(job_root, "busca_opcoes.R"), local = FALSE)
garantir_calendario()

job_log_dir <- file.path(job_root, "jobs", "logs")
if (!dir.exists(job_log_dir)) dir.create(job_log_dir, recursive = TRUE, showWarnings = FALSE)

job_log <- function(...) {
  msg <- paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " | ", paste0(..., collapse = ""))
  message(msg)
  cat(msg, "\n", file = file.path(job_log_dir, "cache_cotahist.log"), append = TRUE)
}
