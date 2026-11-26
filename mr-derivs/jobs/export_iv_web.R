# Exporta series IV/FVOL para GitHub Pages (viz.html).
# Uso: Rscript jobs/export_iv_web.R [cache_dir] [dias]
# Env: MR_DERIVS_WEB_TICKERS=BOVA11,PETR4 (opcional, default TICKERS_SEED_24M)

options(vol_implicita.limpar_sessao = FALSE)
options(vol_implicita.autorun = FALSE)

JOB_DIR <- local({
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else file.path(getwd(), "jobs")
})
source(file.path(JOB_DIR, "_job_common.R"), local = FALSE)
APP_DIR <- job_root
source(file.path(job_root, "vol_implicita_11.R"), local = FALSE)

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite necessario")
}
if (!requireNamespace("zoo", quietly = TRUE)) {
  stop("zoo necessario (vol_mm no export web)")
}
suppressPackageStartupMessages(library(zoo))

args <- commandArgs(trailingOnly = TRUE)
cache_dir <- if (length(args) >= 1 && nzchar(args[[1]])) args[[1]] else DEFAULT_RB3_CACHE
dias <- if (length(args) >= 2 && nzchar(args[[2]])) as.integer(args[[2]]) else {
  as.integer(Sys.getenv("MR_DERIVS_WEB_DIAS", unset = "365"))
}
if (!is.finite(dias) || dias < 30L) dias <- 365L

tickers_env <- Sys.getenv("MR_DERIVS_WEB_TICKERS", unset = "")
tickers <- if (nzchar(tickers_env)) {
  unique(trimws(strsplit(tickers_env, ",", fixed = TRUE)[[1]]))
} else if (exists("TICKERS_WEB_20", inherits = TRUE)) {
  TICKERS_WEB_20
} else {
  TICKERS_SEED_24M
}

out_dir <- file.path(job_root, "data", "web")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

periodo_inicio <- Sys.Date() - dias
data_inicio <- cache_data_inicio_padrao(MR_CACHE_MESES)

serialize_series <- function(fvol_ts) {
  if (is.null(fvol_ts) || !nrow(fvol_ts)) {
    return(list())
  }
  keep <- intersect(
    c(
      "refdate", "sigma_atm", "vol_mm", "skew", "smile", "vol_realizada",
      "vol_realizada_fwd", "premio_iv", "pct_vol", "pct_skew", "pct_smile",
      "carry_aa", "biz_days", "maturity_date", "n_points", "r2"
    ),
    names(fvol_ts)
  )
  df <- as.data.frame(fvol_ts[, keep, drop = FALSE])
  df$refdate <- format(as.Date(df$refdate), "%Y-%m-%d")
  if ("maturity_date" %in% names(df)) {
    df$maturity_date <- format(as.Date(df$maturity_date), "%Y-%m-%d")
  }
  num_cols <- setdiff(names(df), c("refdate", "maturity_date"))
  for (nm in num_cols) {
    if (is.numeric(df[[nm]])) df[[nm]] <- round(df[[nm]], 6)
  }
  out <- jsonlite::fromJSON(jsonlite::toJSON(df, dataframe = "rows", na = "null"))
  if (is.data.frame(out)) {
    return(lapply(seq_len(nrow(out)), function(i) as.list(out[i, , drop = FALSE])))
  }
  out
}

enrich_fvol_for_web <- function(fvol) {
  if (is.null(fvol) || !nrow(fvol)) return(fvol)
  if ("fit_data" %in% names(fvol)) fvol$fit_data <- NULL
  if (requireNamespace("zoo", quietly = TRUE) && "sigma_atm" %in% names(fvol)) {
    fvol$vol_mm <- zoo::rollmean(fvol$sigma_atm, k = 21L, fill = NA, align = "right")
  }
  fvol
}

sanitize_meta <- function(meta) {
  if (is.null(meta)) return(NULL)
  lapply(meta, function(x) {
    if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
    if (length(x) == 1L && is.na(x)) return(NA)
    x
  })
}

manifest <- list(
  atualizado_em = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Sao_Paulo"),
  periodo_dias = dias,
  periodo_inicio = format(periodo_inicio, "%Y-%m-%d"),
  tickers = list(),
  erros = list()
)

job_log("=== EXPORT IV WEB ===")
job_log("Cache: ", cache_dir, " | dias UI: ", dias, " | tickers: ", length(tickers))

PRAZOS_DU <- c(`1` = 21L, `2` = 42L, `3` = 63L)

exportar_prazo <- function(tk, pref, du) {
  res <- rodar_vol_implicita(
    ativo = pref,
    ticker_spot = tk,
    prefixo_opcoes = pref,
    periodo_inicio = periodo_inicio,
    periodo_fim = Sys.Date(),
    data_inicio = data_inicio,
    du_alvo = du,
    atualizar_cache = FALSE,
    retorno_leve = TRUE,
    salvar_png = FALSE,
    incluir_tabela_grafico = FALSE,
    somente_dados = TRUE,
    out_dir = file.path(job_root, "outputs_iv")
  )
  fvol <- enrich_fvol_for_web(res$fvol)
  ser <- serialize_series(fvol)
  bounds <- if (length(ser)) {
    list(inicio = ser[[1]]$refdate, fim = ser[[length(ser)]]$refdate)
  } else {
    list(inicio = NA_character_, fim = NA_character_)
  }
  list(
    du = as.integer(du),
    meses = as.integer(names(PRAZOS_DU)[match(du, PRAZOS_DU)]),
    bounds = bounds,
    meta_datas = sanitize_meta(res$meta_datas),
    series = ser
  )
}

for (tk in tickers) {
  tk <- toupper(trimws(tk))
  if (!nzchar(tk)) next
  pref <- substr(tk, 1, 4)
  job_log("Ticker ", tk, "...")
  prazos <- list()
  erros_prazo <- list()
  for (du in PRAZOS_DU) {
    job_log("  prazo ", du, " DU")
    one <- tryCatch(exportar_prazo(tk, pref, du), error = function(e) e)
    if (inherits(one, "error")) {
      job_log("  ERRO ", tk, " ", du, " DU: ", conditionMessage(one))
      erros_prazo[[length(erros_prazo) + 1L]] <- list(
        du = as.integer(du),
        mensagem = conditionMessage(one)
      )
    } else if (!length(one$series)) {
      erros_prazo[[length(erros_prazo) + 1L]] <- list(
        du = as.integer(du),
        mensagem = "Serie vazia"
      )
    } else {
      prazos[[as.character(du)]] <- one
    }
  }
  if (!length(prazos)) {
    manifest$erros <<- c(
      manifest$erros,
      list(list(ticker = tk, mensagem = paste(vapply(erros_prazo, function(e) {
        paste0(e$du, " DU: ", e$mensagem)
      }, character(1)), collapse = " | ")))
    )
    next
  }
  base <- if (!is.null(prazos[["21"]])) prazos[["21"]] else prazos[[1]]
  payload <- list(
    ticker = tk,
    ativo = pref,
    meta_datas = base$meta_datas,
    bounds = base$bounds,
    series = base$series,
    prazos = prazos,
    erros_prazo = erros_prazo
  )
  out_file <- file.path(out_dir, paste0(tk, ".json"))
  jsonlite::write_json(payload, out_file, auto_unbox = TRUE, pretty = FALSE, na = "null")
  n_pts <- length(payload$series)
  ult_ref <- if (n_pts >= 1L) {
    s <- payload$series
    if (is.data.frame(s)) s$refdate[n_pts] else s[[n_pts]]$refdate
  } else {
    NA_character_
  }
  manifest$tickers[[length(manifest$tickers) + 1L]] <- list(
    ticker = tk,
    n_pontos = n_pts,
    ultima = ult_ref,
    inicio = payload$bounds$inicio,
    fim = payload$bounds$fim
  )
  job_log("  OK ", tk, " (", n_pts, " pregões)")
}

jsonlite::write_json(
  manifest,
  file.path(out_dir, "manifest.json"),
  auto_unbox = TRUE,
  pretty = TRUE,
  na = "null"
)
job_log("=== EXPORT WEB OK: ", out_dir, " ===")
