# =============================================================================
# Job diario: incrementa COTAHIST ate o pregão anterior (ANBIMA).
# Uso: Rscript jobs/atualizar_cache_diario.R [cache_dir]
# Agendar no Windows: scripts/agendar_cache_diario.bat
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

# Mantem janela minima de 24m (re-baixa buracos se datas_baixadas estiver desalinhado).
data_inicio <- cache_data_inicio_padrao(MR_CACHE_MESES)
data_fim <- Sys.Date()

job_log("=== CACHE DIARIO ===")
job_log("Cache: ", cache_dir)

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
lag <- if (!is.na(ult)) as.integer(Sys.Date() - ult) else NA_integer_
job_log("Ultima DuckDB: ", if (is.na(ult)) "N/A" else format(ult, "%Y-%m-%d"),
        if (is.finite(lag)) paste0(" (lag ~", lag, "d)") else "")

if (is.finite(lag) && lag > 5L) {
  job_log("AVISO: cache atrasado — conferir rede/B3 ou rodar seed com forcar no app.")
  quit(status = 2)
}

if (identical(Sys.getenv("MR_DERIVS_EXPORT_STATUS", unset = "0"), "1")) {
  source(file.path(JOB_DIR, "export_cache_status.R"), local = FALSE)
}

job_log("=== DIARIO OK ===")
invisible(res)
