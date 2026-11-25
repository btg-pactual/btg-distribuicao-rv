# Pacotes minimos — Mr Derivs (CI + local)
# Falha o job se algum pacote nao instalar. Nao troca o repositorio
# que o setup-r ja apontou para o binario (RSPM): cloud.r-project.org
# compila do fonte e quebra sem libpng.
# oplib saiu do CRAN; a mesma versao usada no R local vem do GitHub.
pkgs <- c(
  "shiny", "DT", "ggplot2", "plotly", "dplyr", "tidyr", "rb3", "bizdays",
  "lubridate", "callr", "httr", "jsonlite", "zoo", "stringr", "tibble",
  "patchwork", "glue", "scales", "remotes", "nloptr"
)
repos <- getOption("repos")
cran <- if (is.null(repos)) NA_character_ else unname(repos["CRAN"])
if (is.na(cran) || !nzchar(cran) || identical(cran, "@CRAN@")) {
  repos <- c(CRAN = "https://cloud.r-project.org")
}
options(Ncpus = max(1L, parallel::detectCores(logical = TRUE) - 1L))

for (p in pkgs) {
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p, repos = repos, dependencies = TRUE)
  }
}

if (!requireNamespace("oplib", quietly = TRUE)) {
  remotes::install_github(
    "wilsonfreitas/oplib",
    dependencies = TRUE,
    upgrade = "never"
  )
}

faltam <- c(setdiff(pkgs, "remotes"), "oplib")
faltam <- faltam[!vapply(faltam, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltam)) {
  stop(
    "Pacotes nao instalados: ", paste(faltam, collapse = ", "),
    call. = FALSE
  )
}
message("Pacotes ok: ", paste(c(setdiff(pkgs, "remotes"), "oplib"), collapse = ", "))
