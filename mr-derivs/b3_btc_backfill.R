# =============================================================================
# Backfill B3 taxa tomador (Clearing BDI) — janela limitada (default 2 anos)
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
cache_dir <- if (length(args) >= 1) args[[1]] else Sys.getenv(
  "RB3_CACHE",
  unset = "C:/Users/PIMENTPA/OneDrive - Banco BTG Pactual S.A/Documentos/rb3_cache"
)
anos <- if (length(args) >= 2) as.numeric(args[[2]]) else 2
cal  <- if (length(args) >= 3) args[[3]] else "Brazil/ANBIMA"
somente_zip <- any(vapply(args, function(x) x %in% c("somente-zip", "zip-only"), logical(1)))

suppressPackageStartupMessages({
  library(bizdays)
  library(dplyr)
  library(httr)
  library(jsonlite)
  library(glue)
})

script_dir <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
source(file.path(script_dir, "btc_taxas.R"), local = TRUE)

bizdays::load_builtin_calendars()
if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

fim    <- bizdays::preceding(Sys.Date(), cal)
inicio <- bizdays::offset(fim, -as.integer(anos * 252), cal)
dias   <- bizdays::bizseq(inicio, fim, cal)
manifest <- ler_b3_btc_manifest(cache_dir)
ja_ok    <- manifest |> dplyr::filter(status == "ok") |> dplyr::pull(refdate)
pendentes <- dias[!dias %in% ja_ok]

message(sprintf(
  "B3 BTC backfill | cache: %s | %s a %s | %d pregões (%d pendentes) | modo: %s",
  cache_dir, inicio, fim, length(dias), length(pendentes),
  if (somente_zip) "somente ZIP local" else "API BDI + ZIP"
))

ok <- 0L
sem <- 0L
for (i in seq_along(pendentes)) {
  dt <- pendentes[[i]]
  message(sprintf("[%d/%d] %s", i, length(pendentes), dt))
  res <- atualizar_b3_btc_tomador_dia(dt, cache_dir, quiet = TRUE, somente_zip = somente_zip)
  if (is.null(res)) sem <- sem + 1L else ok <- ok + 1L
  if (!somente_zip) Sys.sleep(0.25)
}

message(sprintf("Concluido: %d com taxa, %d sem dado B3", ok, sem))
