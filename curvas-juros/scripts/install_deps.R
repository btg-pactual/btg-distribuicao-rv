# Pacotes para CI (GitHub Actions)
advfn_only <- identical(tolower(Sys.getenv("ADVFN_ONLY", "")), "true")

pkgs <- if (advfn_only) {
  c("httr", "jsonlite", "readr", "dplyr", "tibble", "lubridate")
} else {
  c(
    "readr", "dplyr", "tidyr", "tibble", "purrr", "stringr", "ggplot2",
    "lubridate", "httr", "jsonlite", "curl", "scales", "bizdays", "xml2"
  )
}

repos <- getOption("repos")
cran <- unname(repos["CRAN"])
if (length(cran) == 0L || is.na(cran) || !nzchar(cran) || identical(cran, "@CRAN@")) {
  repos <- c(CRAN = "https://cloud.r-project.org")
}

missing <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(missing) > 0L) {
  message("Instalando: ", paste(missing, collapse = ", "))
  message("CRAN: ", repos["CRAN"])
  install.packages(missing, repos = repos, dependencies = TRUE)
}

still_missing <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(still_missing) > 0L) {
  stop(
    "Pacotes ausentes após install: ",
    paste(still_missing, collapse = ", ")
  )
}
