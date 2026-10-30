# =============================================================================
# Job: Radar FVOL Ibovespa (Rscript rodar_radar_ibov.R)
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
top_n <- if (length(args) >= 1) as.integer(args[[1]]) else 15L
# top_n <= 0 => IBOV completo

APP_DIR <- local({
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})

options(vol_implicita.limpar_sessao = FALSE)
options(vol_implicita.autorun = FALSE)

source(file.path(APP_DIR, "config_mr_derivs.R"), local = FALSE)
source(file.path(APP_DIR, "busca_opcoes.R"), local = FALSE)
source(file.path(APP_DIR, "universo_ibov.R"), local = FALSE)
source(file.path(APP_DIR, "radar_fvol.R"), local = FALSE)

CACHE <- DEFAULT_RB3_CACHE_RADAR
OUT <- file.path(APP_DIR, "outputs_radar")

message(">>> Carteira IBOV...")
cart <- obter_carteira_indice("IBOV", cache_dir = CACHE, atualizar = TRUE)
if (!is.finite(top_n) || top_n <= 0) {
  message(">>> Universo: IBOV completo (", nrow(cart), ")")
} else {
  cart <- filtrar_carteira_top(cart, top_n)
  message(">>> Universo: top ", top_n, " (", nrow(cart), ")")
}

calc_fn <- function(row, atualizar_cache) {
  if (requireNamespace("callr", quietly = TRUE)) {
    tmp <- tempfile(tmpdir = CACHE, fileext = ".rds")
    on.exit(unlink(tmp, force = TRUE), add = TRUE)
    dots <- list(
      ticker = row$ticker[1],
      peso = row$peso[1],
      setor = row$setor[1],
      periodo_inicio = Sys.Date() - 365,
      periodo_fim = Sys.Date(),
      data_inicio_cache = as.Date("2020-01-01"),
      du_alvo = 22L,
      du_tol = 10L,
      janela_mm = 21L,
      carrego = "pcp",
      usar_apenas_vencimento_mensal = TRUE,
      cache_dir = CACHE,
      atualizar_cache = FALSE,
      app_dir = APP_DIR
    )
    callr::r(
      function(path, app_dir, dots) {
        Sys.setenv(R_USER_CACHE_DIR = dots$cache_dir)
        options(rb3.cachedir = dots$cache_dir)
        options(vol_implicita.limpar_sessao = FALSE)
        options(vol_implicita.autorun = FALSE)
        source(file.path(app_dir, "radar_fvol.R"), local = FALSE)
        res <- do.call(calcular_snapshot_ticker, dots)
        saveRDS(res, path)
      },
      args = list(path = tmp, app_dir = APP_DIR, dots = dots),
      wd = APP_DIR,
      show = FALSE,
      spinner = FALSE
    )
    return(readRDS(tmp))
  }
  calcular_snapshot_ticker(
    ticker = row$ticker[1],
    peso = row$peso[1],
    setor = row$setor[1],
    periodo_inicio = Sys.Date() - 365,
    periodo_fim = Sys.Date(),
    cache_dir = CACHE,
    app_dir = APP_DIR
  )
}

message(">>> Rodando radar...")
res <- rodar_radar_fvol(
  carteira = cart,
  atualizar_cache_inicial = TRUE,
  cache_dir = CACHE,
  out_dir = OUT,
  progress_fn = function(p, msg) message(sprintf("[%.0f%%] %s", 100 * p, msg)),
  calc_fn = calc_fn
)

message(sprintf(
  ">>> OK %d | erro %d | CSV: %s",
  res$n_ok, res$n_erro, res$arquivos$latest_csv
))
