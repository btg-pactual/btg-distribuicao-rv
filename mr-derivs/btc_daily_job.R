# =============================================================================
# Job diário — snapshot BTG BTC (D0)
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
cache_dir <- if (length(args) >= 1) args[[1]] else Sys.getenv(
  "RB3_CACHE",
  unset = "C:/Users/PIMENTPA/OneDrive - Banco BTG Pactual S.A/Documentos/rb3_cache"
)

suppressPackageStartupMessages({
  library(dplyr)
  library(httr)
  library(jsonlite)
})

script_dir <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
source(file.path(script_dir, "btc_taxas.R"), local = TRUE)

if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

message("BTG BTC daily job | cache: ", cache_dir)
hist <- atualizar_btg_btc_history(cache_dir)
message(sprintf(
  "  %d tickers | snapshot %s",
  dplyr::n_distinct(hist$ticker),
  max(hist$snapshot_date)
))

cal <- "Brazil/ANBIMA"
if (requireNamespace("bizdays", quietly = TRUE)) {
  bizdays::load_builtin_calendars()
  hoje <- bizdays::preceding(Sys.Date(), cal)
  message(sprintf("  Atualizando B3 BDI para %s...", hoje))
  atualizar_b3_btc_tomador_dia(hoje, cache_dir)
}

message("OK")
