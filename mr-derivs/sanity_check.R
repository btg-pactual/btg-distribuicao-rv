# =============================================================================
# Sanity check local — Mr Derivs
# Uso: Rscript sanity_check.R
# =============================================================================

options(vol_implicita.limpar_sessao = FALSE)
options(vol_implicita.autorun = FALSE)

ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
setwd(ROOT)

ok <- function(msg) message("[OK]  ", msg)
warn <- function(msg) message("[!!]  ", msg)
fail <- function(msg) message("[ERR] ", msg)

n_err <- 0L
check <- function(cond, msg_ok, msg_fail) {
  if (isTRUE(cond)) {
    ok(msg_ok)
  } else {
    fail(msg_fail)
    n_err <<- n_err + 1L
  }
}

message("=== Mr Derivs — sanity check ===")
message("Root: ", ROOT)

source("config_mr_derivs.R", local = FALSE)
ok(paste("Cache default:", DEFAULT_RB3_CACHE))
check(dir.exists(DEFAULT_RB3_CACHE), "Pasta rb3_cache existe", "Pasta rb3_cache NAO existe")

pkgs <- c(
  "shiny", "DT", "ggplot2", "plotly", "dplyr", "tidyr", "rb3", "bizdays", "oplib",
  "lubridate", "callr", "httr", "jsonlite", "zoo", "stringr", "tibble"
)
for (p in pkgs) {
  check(
    requireNamespace(p, quietly = TRUE),
    paste("pacote", p),
    paste("FALTA pacote:", p, "— install.packages('", p, "')", sep = "")
  )
}

files <- c(
  "config_mr_derivs.R", "vol_implicita_11.R", "busca_opcoes.R", "app_vol_implicita.R",
  "simulacao_short.R", "correlacao_beta.R", "radar_fvol.R", "universo_ibov.R",
  "btc_taxas.R", "carrego_pcp.R", "rodar_radar_ibov.R"
)
for (f in files) {
  check(file.exists(f), paste("arquivo", f), paste("arquivo ausente:", f))
}

garantir_calendario()
ok(paste("Calendario:", MR_CALENDAR))

configurar_cache_rb3(DEFAULT_RB3_CACHE)
if (requireNamespace("rb3", quietly = TRUE)) {
  library(rb3)
  library(dplyr)
  ult <- tryCatch({
    source("busca_opcoes.R", local = FALSE)
    ultima_data_cotahist(DEFAULT_RB3_CACHE)
  }, error = function(e) {
    fail(paste("ultima_data_cotahist:", conditionMessage(e)))
    n_err <<- n_err + 1L
    as.Date(NA)
  })
  diag <- tryCatch(diagnostico_cache_cotahist(DEFAULT_RB3_CACHE), error = function(e) NULL)
  if (!is.null(diag)) {
    if (isTRUE(diag$ok)) {
      ok(diag$mensagem)
    } else {
      warn(paste0(diag$mensagem, " No app: atualizar cache + forcar redownload."))
    }
  } else if (!is.na(ult)) {
    lag <- as.integer(Sys.Date() - ult)
    if (lag > 5) {
      warn(paste0("COTAHIST atrasado: ultimo=", format(ult), " (~", lag, " dias). No app: atualizar cache + forcar redownload."))
    } else {
      ok(paste("COTAHIST ate", format(ult)))
    }
  } else {
    warn("COTAHIST sem data (cache vazio?)")
  }
}

message("")
if (n_err == 0) {
  message("=== SANITY OK — pode rodar: shiny::runApp('app_vol_implicita.R') ===")
  quit(status = 0)
} else {
  message("=== SANITY com ", n_err, " problema(s) ===")
  quit(status = 1)
}
