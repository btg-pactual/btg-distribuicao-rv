# Pacotes para CI (GitHub Actions)
advfn_only <- identical(tolower(Sys.getenv("ADVFN_ONLY", "")), "true")

pkgs <- if (advfn_only) {
  c("httr", "jsonlite", "readr", "dplyr", "tibble", "lubridate")
} else {
  c(
    "tidyverse", "lubridate", "httr", "jsonlite", "curl",
    "scales", "bizdays", "xml2", "readr", "dplyr", "tibble"
  )
}

missing <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(missing) > 0L) {
  message("Instalando: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
}
