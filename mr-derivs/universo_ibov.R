# =============================================================================
# Universo Ibovespa — carteira + setor via rb3 (com fallbacks)
# =============================================================================

UNIV_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
if (!exists("DEFAULT_RB3_CACHE_UNIV", inherits = TRUE)) {
  source(file.path(UNIV_DIR, "config_mr_derivs.R"), local = FALSE)
}

#' Mapa setorial fallback (B3 / uso comum) quando rb3 nao traz sector.
SETOR_FALLBACK <- c(
  PETR4 = "Petroleo e Gas", PETR3 = "Petroleo e Gas", PRIO3 = "Petroleo e Gas",
  VALE3 = "Materiais", GGBR4 = "Materiais", GOAU4 = "Materiais", CSNA3 = "Materiais",
  USIM5 = "Materiais", SUZB3 = "Materiais", KLBN11 = "Materiais",
  ITUB4 = "Financeiro", ITUB3 = "Financeiro", BBDC4 = "Financeiro", BBDC3 = "Financeiro",
  BBAS3 = "Financeiro", SANB11 = "Financeiro", BPAC11 = "Financeiro", B3SA3 = "Financeiro",
  BBSE3 = "Financeiro", CXSE3 = "Financeiro",
  ABEV3 = "Consumo", RENT3 = "Consumo", LREN3 = "Consumo", MGLU3 = "Consumo",
  VIVA3 = "Consumo", ASPS3 = "Consumo", PCAR3 = "Consumo", NTCO3 = "Consumo",
  RADL3 = "Saude", HAPV3 = "Saude", RDOR3 = "Saude", FLRY3 = "Saude",
  WEGE3 = "Bens Industriais", EMBR3 = "Bens Industriais", RAIL3 = "Bens Industriais",
  CCRO3 = "Bens Industriais", ECOR3 = "Bens Industriais",
  EQTL3 = "Utilidade Publica", EGIE3 = "Utilidade Publica", ENGI11 = "Utilidade Publica",
  CMIG4 = "Utilidade Publica", CPLE6 = "Utilidade Publica", SBSP3 = "Utilidade Publica",
  CSMG3 = "Utilidade Publica", TAEE11 = "Utilidade Publica",
  VIVT3 = "Telecom", TIMS3 = "Telecom",
  TOTS3 = "Tecnologia", LWSA3 = "Tecnologia",
  BRAV3 = "Diversos", MULT3 = "Diversos", IGTI11 = "Diversos",
  BOVA11 = "ETF", SMAL11 = "ETF"
)

configurar_cache_universo <- function(cache_dir = DEFAULT_RB3_CACHE_UNIV) {
  if (exists("configurar_cache_rb3", mode = "function")) {
    return(configurar_cache_rb3(cache_dir))
  }
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  Sys.setenv(R_USER_CACHE_DIR = cache_dir)
  options(rb3.cachedir = cache_dir)
  invisible(cache_dir)
}

pick_col <- function(df, candidates, required = TRUE) {
  hit <- intersect(candidates, names(df))
  if (!length(hit)) {
    if (required) stop("Coluna nao encontrada. Esperava uma de: ", paste(candidates, collapse = ", "))
    return(NULL)
  }
  hit[[1]]
}

normalizar_carteira <- function(df, indice = "IBOV") {
  if (is.null(df) || !nrow(df)) {
    return(tibble::tibble(
      ticker = character(),
      peso = numeric(),
      setor = character(),
      indice = character(),
      refdate = as.Date(character()),
      fonte = character()
    ))
  }

  col_sym <- pick_col(df, c("symbol", "asset", "code", "ticker", "codneg"))
  col_w <- pick_col(df, c("weight", "peso", "participation", "part"), required = FALSE)
  col_sec <- pick_col(df, c("sector", "setor", "segment", "segmento", "economic_sector"), required = FALSE)
  col_idx <- pick_col(df, c("index", "indice"), required = FALSE)
  col_dt <- pick_col(df, c("refdate", "update_date", "date"), required = FALSE)

  out <- tibble::tibble(
    ticker = toupper(trimws(as.character(df[[col_sym]]))),
    peso = if (!is.null(col_w)) as.numeric(df[[col_w]]) else NA_real_,
    setor_raw = if (!is.null(col_sec)) as.character(df[[col_sec]]) else NA_character_,
    indice = if (!is.null(col_idx)) as.character(df[[col_idx]]) else indice,
    refdate = if (!is.null(col_dt)) as.Date(df[[col_dt]]) else as.Date(NA)
  )

  if (!is.null(col_idx)) {
    out <- out |>
      dplyr::filter(toupper(.data$indice) == toupper(indice) | is.na(.data$indice))
  }

  if (any(!is.na(out$refdate))) {
    dmax <- max(out$refdate, na.rm = TRUE)
    out <- out |> dplyr::filter(is.na(refdate) | refdate == dmax)
  }

  # pesos: se vierem em % (ex. 10.5) normaliza; se ja fracao, mantem
  if (all(is.na(out$peso))) {
    out$peso <- 1 / nrow(out)
  } else {
    s <- sum(out$peso, na.rm = TRUE)
    if (is.finite(s) && s > 2) out$peso <- out$peso / 100
    s2 <- sum(out$peso, na.rm = TRUE)
    if (is.finite(s2) && s2 > 0) out$peso <- out$peso / s2
  }

  out |>
    dplyr::mutate(
      setor_fb = unname(SETOR_FALLBACK[ticker]),
      setor = dplyr::coalesce(
        dplyr::na_if(trimws(setor_raw), ""),
        setor_fb,
        "Outros"
      ),
      fonte = "rb3"
    ) |>
    dplyr::filter(nzchar(ticker), !grepl("\\s", ticker)) |>
    dplyr::distinct(ticker, .keep_all = TRUE) |>
    dplyr::arrange(dplyr::desc(peso)) |>
    dplyr::select(ticker, peso, setor, indice, refdate, fonte)
}

carteira_fallback_local <- function(tickers = NULL) {
  if (is.null(tickers) || !length(tickers)) {
    tickers <- names(SETOR_FALLBACK)
    tickers <- tickers[!grepl("11$", tickers) | tickers %in% c("KLBN11", "SANB11", "BPAC11", "ENGI11", "TAEE11", "IGTI11")]
  }
  tickers <- unique(toupper(trimws(tickers)))
  tibble::tibble(
    ticker = tickers,
    peso = 1 / length(tickers),
    setor = dplyr::coalesce(unname(SETOR_FALLBACK[tickers]), "Outros"),
    indice = "LOCAL",
    refdate = Sys.Date(),
    fonte = "fallback"
  ) |>
    dplyr::arrange(ticker)
}

#' Baixa e retorna carteira do indice (default IBOV) com setor e peso.
obter_carteira_indice <- function(
  indice = "IBOV",
  cache_dir = DEFAULT_RB3_CACHE_UNIV,
  atualizar = TRUE,
  quiet = FALSE
) {
  indice <- toupper(trimws(indice))
  configurar_cache_universo(cache_dir)

  cache_file <- file.path(cache_dir, sprintf("carteira_%s.rds", tolower(indice)))

  try_rb3 <- function() {
    if (!requireNamespace("rb3", quietly = TRUE)) stop("Pacote rb3 nao disponivel.")
    if (!"package:rb3" %in% search()) library(rb3)
    if (!"package:dplyr" %in% search()) library(dplyr)

    if (isTRUE(atualizar)) {
      if (!quiet) message(">>> Baixando carteira corrente ", indice, "...")
      tryCatch(
        rb3::fetch_marketdata("b3-indexes-current-portfolio", index = indice, throttle = TRUE),
        error = function(e) {
          if (!quiet) message("  current-portfolio falhou: ", conditionMessage(e))
          NULL
        }
      )
      tryCatch(
        rb3::fetch_marketdata("b3-indexes-theoretical-portfolio", index = indice, throttle = TRUE),
        error = function(e) {
          if (!quiet) message("  theoretical-portfolio falhou: ", conditionMessage(e))
          NULL
        }
      )
    }

    cur <- tryCatch(
      rb3::indexes_current_portfolio_get() |> dplyr::collect(),
      error = function(e) NULL
    )
    if (!is.null(cur) && nrow(cur) > 0) {
      out <- normalizar_carteira(cur, indice = indice)
      if (nrow(out) > 0) {
        out$fonte <- "rb3_current"
        return(out)
      }
    }

    th <- tryCatch(
      rb3::indexes_theoretical_portfolio_get() |> dplyr::collect(),
      error = function(e) NULL
    )
    if (!is.null(th) && nrow(th) > 0) {
      out <- normalizar_carteira(th, indice = indice)
      if (nrow(out) > 0) {
        out$fonte <- "rb3_theoretical"
        return(out)
      }
    }

    # composition sem peso
    comp <- tryCatch({
      rb3::fetch_marketdata("b3-indexes-composition")
      rb3::indexes_composition_get() |> dplyr::collect()
    }, error = function(e) NULL)

    if (!is.null(comp) && nrow(comp) > 0) {
      # indexes pode ser coluna CSV de indices
      if ("indexes" %in% names(comp) && !"index" %in% names(comp)) {
        comp <- comp |>
          dplyr::filter(grepl(paste0("\\b", indice, "\\b"), toupper(as.character(indexes))))
      }
      out <- normalizar_carteira(comp, indice = indice)
      if (nrow(out) > 0) {
        out$fonte <- "rb3_composition"
        return(out)
      }
    }

    stop("Nao foi possivel montar carteira via rb3.")
  }

  carteira <- tryCatch(try_rb3(), error = function(e) {
    if (!quiet) message("  Aviso carteira rb3: ", conditionMessage(e))
    if (file.exists(cache_file)) {
      if (!quiet) message("  Usando carteira em cache local: ", cache_file)
      return(readRDS(cache_file))
    }
    if (!quiet) message("  Usando fallback local de tickers.")
    carteira_fallback_local()
  })

  if (nrow(carteira) > 0) {
    saveRDS(carteira, cache_file)
  }
  carteira
}

#' Seleciona top N por peso (ou todos).
filtrar_carteira_top <- function(carteira, top_n = NULL) {
  if (is.null(top_n) || !is.finite(top_n) || top_n <= 0) return(carteira)
  carteira |>
    dplyr::arrange(dplyr::desc(peso)) |>
    dplyr::slice_head(n = as.integer(top_n))
}
