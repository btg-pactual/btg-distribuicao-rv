# Pacotes minimos — Mr Derivs (CI + local)
pkgs <- c(
  "shiny", "DT", "ggplot2", "plotly", "dplyr", "tidyr", "rb3", "bizdays", "oplib",
  "lubridate", "callr", "httr", "jsonlite", "zoo", "stringr", "tibble",
  "patchwork", "glue", "scales"
)
for (p in pkgs) {
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p, repos = "https://cloud.r-project.org", dependencies = TRUE)
  }
}
