# Exporta status do cache para GitHub Pages / monitoramento.
JOB_DIR <- local({
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else file.path(getwd(), "jobs")
})
source(file.path(JOB_DIR, "_job_common.R"), local = FALSE)

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite necessario")
}

cache_dir <- Sys.getenv("MR_DERIVS_RB3_CACHE", unset = DEFAULT_RB3_CACHE)
ult <- tryCatch(ultima_data_cotahist(cache_dir), error = function(e) as.Date(NA))
diag <- tryCatch(diagnostico_cache_cotahist(cache_dir), error = function(e) NULL)

tickers <- lapply(TICKERS_SEED_24M, function(tk) {
  u <- tryCatch(ultima_data_ticker(tk, cache_dir), error = function(e) as.Date(NA))
  list(ticker = tk, ultima_spot = if (is.na(u)) NA_character_ else format(u, "%Y-%m-%d"))
})

out_dir <- file.path(job_root, "data")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

payload <- list(
  atualizado_em = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Sao_Paulo"),
  cache_dir = cache_dir,
  ultima_cotahist = if (is.na(ult)) NA_character_ else format(ult, "%Y-%m-%d"),
  lag_dias = if (!is.null(diag)) diag$lag_dias else NA_integer_,
  ok = if (!is.null(diag)) diag$ok else FALSE,
  mensagem = if (!is.null(diag)) diag$mensagem else NA_character_,
  tickers = tickers,
  meses_janela = MR_CACHE_MESES
)

jsonlite::write_json(payload, file.path(out_dir, "cotahist_status.json"), auto_unbox = TRUE, pretty = TRUE)
message(">>> Export: ", file.path(out_dir, "cotahist_status.json"))
