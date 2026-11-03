# =============================================================================
# 00_setup.R — pacotes, pastas e constantes (curvas de juros)
# =============================================================================

pkgs <- c("tidyverse", "lubridate", "curl", "httr", "jsonlite", "scales", "bizdays", "xml2")

install_if_missing <- function(pkgs) {
  missing <- pkgs[!pkgs %in% rownames(installed.packages())]
  if (length(missing) > 0) {
    message("Instalando: ", paste(missing, collapse = ", "))
    install.packages(missing, repos = "https://cloud.r-project.org")
  }
  invisible(lapply(pkgs, library, character.only = TRUE))
}

install_if_missing(pkgs)

dirs <- c(
  "data", "data/raw", "data/raw/b3", "data/raw/b3/pr", "data/raw/advfn",
  "data/processed", "data/processed/di_curva",
  "output", "output/figs", "output/tables"
)
for (d in dirs) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

# Tipos do Tesouro usados como curva (títulos “bullet”, sem cupom semestral)
TIPOS_CURVA_TESOURO <- c("Tesouro Prefixado", "Tesouro IPCA+")

# Marcos para comparar com a curva atual (meses para trás)
MESES_COMPARACAO <- c(0L, 1L, 3L, 6L, 12L, 24L, 36L)

# Histórico mensal da curva DI (fim de mês → último dia útil simples)
MESES_HISTORICO_DI <- as.integer(
  Sys.getenv("MESES_HISTORICO_DI", unset = "60")
)

URL_CSV_TESOURO <- paste0(
  "https://www.tesourotransparente.gov.br/ckan/dataset/",
  "df56aa42-484a-4a59-8184-7676580c81e3/resource/",
  "796d2059-14e9-44e3-80c9-2d9e30b405c1/download/PrecoTaxaTesouroDireto.csv"
)

URL_ANBIMA_ETTJ <- "https://www.anbima.com.br/informacoes/est-termo/CZ-down.asp"

THEME_CURVA <- ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold"),
    plot.subtitle = ggplot2::element_text(color = "gray30"),
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank()
  )

message("Setup OK — curvas-juros")
