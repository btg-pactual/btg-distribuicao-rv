# =============================================================================
# Seed: baixa COTAHIST dos ultimos MR_CACHE_MESES (default 24) para o cache rb3.
# Uso: Rscript jobs/seed_cache_24m.R [cache_dir] [meses]
# =============================================================================

options(vol_implicita.limpar_sessao = FALSE)
options(vol_implicita.autorun = FALSE)

JOB_DIR <- local({
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else file.path(getwd(), "jobs")
})
source(file.path(JOB_DIR, "_job_common.R"), local = FALSE)

args <- commandArgs(trailingOnly = TRUE)
cache_dir <- if (length(args) >= 1 && nzchar(args[[1]])) args[[1]] else DEFAULT_RB3_CACHE
meses <- if (length(args) >= 2) as.integer(args[[2]]) else MR_CACHE_MESES
if (!is.finite(meses) || meses < 1) meses <- 24L

data_inicio <- cache_data_inicio_padrao(meses)
data_fim <- Sys.Date()

job_log("=== SEED COTAHIST ", meses, " meses ===")
job_log("Cache: ", cache_dir)
job_log("Janela: ", format(data_inicio, "%Y-%m-%d"), " .. ", format(data_fim, "%Y-%m-%d"))

res <- with_cli_quiet(
  atualizar_cache_cotahist(
    cache_dir = cache_dir,
    data_inicio = data_inicio,
    data_fim = data_fim,
    quiet = FALSE
  )
)
job_log(res$mensagem)

ult <- tryCatch(ultima_data_cotahist(cache_dir), error = function(e) as.Date(NA))
job_log("Ultima data DuckDB: ", if (is.na(ult)) "N/A" else format(ult, "%Y-%m-%d"))

job_log("Tickers seed (verificacao spot no cache):")
for (tk in TICKERS_SEED_24M) {
  u <- tryCatch(ultima_data_ticker(tk, cache_dir), error = function(e) as.Date(NA))
  job_log("  ", tk, ": ", if (is.na(u)) "sem spot" else format(u, "%Y-%m-%d"))
}

job_log("=== SEED OK ===")
invisible(res)
