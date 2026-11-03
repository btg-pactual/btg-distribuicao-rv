# =============================================================================
# Config central — Mr Derivs (R local)
# Source este arquivo antes dos demais modulos.
# Override: Sys.setenv(MR_DERIVS_RB3_CACHE = "D:/meu_cache")
# =============================================================================

MR_DERIVS_ROOT <- local({
  # 1) se ja definido
  if (exists("APP_DIR", inherits = TRUE) && nzchar(get0("APP_DIR", ifnotfound = ""))) {
    return(normalizePath(APP_DIR, winslash = "/", mustWork = FALSE))
  }
  # 2) script em execucao
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) {
    return(dirname(normalizePath(sub("^--file=", "", f[[1]]), winslash = "/", mustWork = FALSE)))
  }
  # 3) ofile (source)
  of <- tryCatch(sys.frames()[[1]]$ofile, error = function(e) NULL)
  if (!is.null(of) && nzchar(of)) {
    return(dirname(normalizePath(of, winslash = "/", mustWork = FALSE)))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
})

#' Cache rb3: env MR_DERIVS_RB3_CACHE, senao Documentos/rb3_cache (OneDrive BTG), senao .rb3_cache local.
resolver_cache_rb3 <- function() {
  env <- Sys.getenv("MR_DERIVS_RB3_CACHE", unset = "")
  if (nzchar(env)) {
    return(normalizePath(env, winslash = "/", mustWork = FALSE))
  }
  doc_cache <- file.path(
    Sys.getenv("USERPROFILE", unset = "~"),
    "OneDrive - Banco BTG Pactual S.A",
    "Documentos",
    "rb3_cache"
  )
  if (dir.exists(doc_cache)) {
    return(normalizePath(doc_cache, winslash = "/", mustWork = FALSE))
  }
  file.path(MR_DERIVS_ROOT, ".rb3_cache")
}

DEFAULT_RB3_CACHE <- resolver_cache_rb3()

DEFAULT_OUT_RADAR <- file.path(MR_DERIVS_ROOT, "outputs_radar")
DEFAULT_OUT_GRAPHICS <- Sys.getenv(
  "MR_DERIVS_IV_GRAPHICS",
  unset = file.path(MR_DERIVS_ROOT, "outputs_iv")
)

MR_CALENDAR <- "Brazil/ANBIMA"

#' Alias unificados (modulos antigos apontam para estes nomes).
DEFAULT_RB3_CACHE_BUSCA <- DEFAULT_RB3_CACHE
DEFAULT_RB3_CACHE_SIM   <- DEFAULT_RB3_CACHE
DEFAULT_RB3_CACHE_BETA  <- DEFAULT_RB3_CACHE
DEFAULT_RB3_CACHE_RADAR <- DEFAULT_RB3_CACHE
DEFAULT_RB3_CACHE_UNIV  <- DEFAULT_RB3_CACHE

configurar_cache_rb3 <- function(cache_dir = DEFAULT_RB3_CACHE) {
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }
  Sys.setenv(R_USER_CACHE_DIR = cache_dir)
  options(rb3.cachedir = cache_dir)
  invisible(cache_dir)
}

#' Desliga progress cli/rb3 (evita crash com Shiny withProgress).
with_cli_quiet <- function(expr) {
  old <- options(
    cli.progress_show_after = Inf,
    cli.progress_handlers = "none"
  )
  on.exit(options(old), add = TRUE)
  force(expr)
}

garantir_calendario <- function(cal = MR_CALENDAR) {
  if (!requireNamespace("bizdays", quietly = TRUE)) {
    stop("Pacote bizdays necessario.")
  }
  bizdays::load_builtin_calendars()
  if (!cal %in% ls(bizdays::calendars())) {
    stop("Calendario nao carregado: ", cal)
  }
  bizdays::bizdays.options$set(default.calendar = cal)
  invisible(cal)
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

TICKERS_WATCHLIST <- c(
  "PETR4", "VALE3", "ITUB4", "BBDC4", "BBAS3", "WEGE3", "ABEV3", "B3SA3",
  "RENT3", "SUZB3", "RADL3", "CSMG3", "EQTL3", "GGBR4", "PRIO3", "VIVT3",
  "BOVA11", "SMAL11", "ROXO34"
)

#' Ativos prioritarios (seed cache 24m + defaults do app).
TICKERS_SEED_24M <- c(
  "BOVA11", "SMAL11", "PETR4", "EQTL3", "VALE3", "ITUB4", "BPAC11",
  "WEGE3", "BBDC4", "ITSA4", "ABEV3", "B3SA3"
)

MR_CACHE_MESES <- as.integer(Sys.getenv("MR_DERIVS_CACHE_MESES", unset = "24"))
if (!is.finite(MR_CACHE_MESES) || MR_CACHE_MESES < 1) MR_CACHE_MESES <- 24L

#' Inicio do COTAHIST para seed / job diario (N meses calendario).
cache_data_inicio_padrao <- function(meses = MR_CACHE_MESES) {
  meses <- as.integer(meses)
  if (!is.finite(meses) || meses < 1L) meses <- 24L
  anchor <- as.Date(format(Sys.Date(), "%Y-%m-01"))
  seq(anchor, by = paste0("-", meses, " months"), length = 2L)[2L]
}

MR_DERIVS_FULL_UI <- identical(
  tolower(Sys.getenv("MR_DERIVS_FULL_UI", unset = "false")),
  "true"
)

message_mr <- function(...) {
  message(">>> ", paste0(..., collapse = ""))
}
