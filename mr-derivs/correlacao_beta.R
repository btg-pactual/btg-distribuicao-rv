# =============================================================================
# Correlacao e beta — precos spot B3 (COTAHIST / rb3)
# =============================================================================

BETA_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
if (!exists("DEFAULT_RB3_CACHE_BETA", inherits = TRUE)) {
  source(file.path(BETA_DIR, "config_mr_derivs.R"), local = FALSE)
}

COR_BG     <- "#0a1628"
COR_PANEL  <- "#111f38"
COR_GRID   <- "#1e2f4a"
COR_TEXT   <- "#e8eeff"
COR_ACCENT <- "#00c37a"
COR_YELLOW <- "#f5c842"
COR_WHITE  <- "#ffffff"
COR_GRAY   <- "#8fa8c8"

tema_beta <- function() {
  ggplot2::theme_classic(base_size = 14, base_family = "sans") +
    ggplot2::theme(
      plot.background   = ggplot2::element_rect(fill = COR_BG, color = NA),
      panel.background  = ggplot2::element_rect(fill = COR_PANEL, color = NA),
      panel.grid.major  = ggplot2::element_line(color = COR_GRID, linewidth = 0.45),
      panel.grid.minor  = ggplot2::element_blank(),
      axis.line         = ggplot2::element_line(color = COR_GRAY, linewidth = 0.6),
      axis.text         = ggplot2::element_text(color = COR_WHITE, face = "bold"),
      axis.title        = ggplot2::element_text(color = COR_WHITE, face = "bold"),
      plot.title        = ggplot2::element_text(color = COR_WHITE, face = "bold", size = 16),
      plot.subtitle     = ggplot2::element_text(color = COR_TEXT, size = 12),
      legend.background = ggplot2::element_rect(fill = COR_PANEL, color = COR_GRAY),
      legend.text       = ggplot2::element_text(color = COR_WHITE),
      legend.title      = ggplot2::element_text(color = COR_WHITE, face = "bold"),
      plot.margin       = ggplot2::margin(10, 14, 8, 12)
    )
}

configurar_cache_rb3_beta <- function(cache_dir = DEFAULT_RB3_CACHE_BETA) {
  if (exists("configurar_cache_rb3", mode = "function")) {
    return(configurar_cache_rb3(cache_dir))
  }
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  Sys.setenv(R_USER_CACHE_DIR = cache_dir)
  options(rb3.cachedir = cache_dir)
  invisible(cache_dir)
}

suppressPackageStartupMessages({
  if (!"package:dplyr" %in% search()) library(dplyr)
  if (!"package:tidyr" %in% search()) library(tidyr)
  if (!"package:tibble" %in% search()) library(tibble)
  if (!"package:ggplot2" %in% search()) library(ggplot2)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

carregar_precos_tickers <- function(
  tickers,
  periodo_inicio,
  periodo_fim,
  cache_dir = DEFAULT_RB3_CACHE_BETA,
  cal = "Brazil/ANBIMA"
) {
  tickers <- unique(toupper(trimws(tickers)))
  tickers <- tickers[nzchar(tickers)]
  if (!length(tickers)) stop("Informe ao menos um ticker.")

  if (!requireNamespace("rb3", quietly = TRUE)) {
    stop("Pacote rb3 necessario para carregar COTAHIST.")
  }

  configurar_cache_rb3_beta(cache_dir)
  if (!"package:rb3" %in% search()) library(rb3)

  bizdays::load_builtin_calendars()
  if (!cal %in% ls(bizdays::calendars())) stop("Calendario nao carregado: ", cal)
  bizdays.options$set(default.calendar = cal)

  data_ini <- as.Date(periodo_inicio)
  data_fim <- as.Date(periodo_fim)

  puxa <- function(ch) {
    if (is.null(ch)) return(NULL)
    ch |>
      dplyr::filter(
        refdate >= data_ini,
        refdate <= data_fim,
        symbol %in% tickers
      ) |>
      dplyr::collect()
  }

  ch_y <- tryCatch(rb3::cotahist_get(type = "yearly"), error = function(e) NULL)
  ch_d <- tryCatch(rb3::cotahist_get(type = "daily"), error = function(e) NULL)

  raw <- dplyr::bind_rows(puxa(ch_y), puxa(ch_d)) |>
    dplyr::distinct(refdate, symbol, .keep_all = TRUE) |>
    dplyr::arrange(refdate, symbol)

  if (nrow(raw) == 0) {
    stop(
      "Sem precos no cache para: ", paste(tickers, collapse = ", "),
      " entre ", format(data_ini, "%d/%m/%Y"), " e ", format(data_fim, "%d/%m/%Y"), "."
    )
  }

  wide <- raw |>
    dplyr::select(refdate, symbol, close) |>
    dplyr::filter(is.finite(close), close > 0) |>
    tidyr::pivot_wider(names_from = symbol, values_from = close)

  faltando <- setdiff(tickers, names(wide)[-1])
  if (length(faltando)) {
    warning("Tickers sem dados no periodo: ", paste(faltando, collapse = ", "))
  }

  ultimos <- raw |>
    dplyr::group_by(symbol) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::transmute(ticker = symbol, refdate, preco = close)

  list(
    long = raw,
    wide = wide,
    tickers = intersect(tickers, names(wide)[-1]),
    ultimos = ultimos,
    periodo_inicio = data_ini,
    periodo_fim = data_fim
  )
}

calc_retornos <- function(wide, tipo = c("log", "simple")) {
  tipo <- match.arg(tipo)
  if (!"refdate" %in% names(wide)) stop("wide precisa ter coluna refdate.")

  cols <- setdiff(names(wide), "refdate")
  out <- wide |>
    dplyr::arrange(refdate)

  for (col in cols) {
    px <- out[[col]]
    if (tipo == "log") {
      out[[col]] <- log(px / dplyr::lag(px))
    } else {
      out[[col]] <- px / dplyr::lag(px) - 1
    }
  }

  out |>
    dplyr::filter(dplyr::if_any(dplyr::all_of(cols), ~ !is.na(.x)))
}

stats_reg <- function(y, x) {
  ok <- is.finite(y) & is.finite(x)
  y <- y[ok]
  x <- x[ok]
  n <- length(y)
  if (n < 5) {
    return(list(
      n = n, beta = NA_real_, alpha_dia = NA_real_, alpha_aa = NA_real_,
      correlacao = NA_real_, r2 = NA_real_, vol_ativo_aa = NA_real_,
      vol_bench_aa = NA_real_
    ))
  }
  beta <- stats::cov(y, x) / stats::var(x)
  alpha_dia <- mean(y) - beta * mean(x)
  alpha_aa <- alpha_dia * 252
  rho <- stats::cor(y, x)
  list(
    n = n,
    beta = beta,
    alpha_dia = alpha_dia,
    alpha_aa = alpha_aa,
    correlacao = rho,
    r2 = rho^2,
    vol_ativo_aa = stats::sd(y) * sqrt(252),
    vol_bench_aa = stats::sd(x) * sqrt(252)
  )
}

calc_beta_estatico <- function(ret, ticker_ativo, ticker_bench) {
  if (!all(c(ticker_ativo, ticker_bench) %in% names(ret))) {
    stop("Retornos nao contem ativo ou benchmark.")
  }
  y <- ret[[ticker_ativo]]
  x <- ret[[ticker_bench]]
  st <- stats_reg(y, x)
  c(
    list(
      ticker_ativo = ticker_ativo,
      ticker_bench = ticker_bench
    ),
    st
  )
}

calc_beta_rolling <- function(ret, ticker_ativo, ticker_bench, janela_du = 63L) {
  janela_du <- as.integer(janela_du)
  if (!all(c(ticker_ativo, ticker_bench) %in% names(ret))) {
    stop("Retornos nao contem ativo ou benchmark.")
  }

  y <- ret[[ticker_ativo]]
  x <- ret[[ticker_bench]]
  n <- nrow(ret)
  beta <- rep(NA_real_, n)
  correlacao <- rep(NA_real_, n)

  for (i in seq_len(n)) {
    if (i < janela_du) next
    idx <- (i - janela_du + 1L):i
    st <- stats_reg(y[idx], x[idx])
    beta[i] <- st$beta
    correlacao[i] <- st$correlacao
  }

  tibble::tibble(
    refdate = ret$refdate,
    beta = beta,
    correlacao = correlacao,
    ticker_ativo = ticker_ativo,
    ticker_bench = ticker_bench,
    janela_du = janela_du
  )
}

calc_matriz_correlacao <- function(ret, tickers = NULL) {
  cols <- setdiff(names(ret), "refdate")
  if (!is.null(tickers)) cols <- intersect(cols, tickers)
  cols <- cols[cols %in% names(ret)]
  if (length(cols) < 2) stop("Informe ao menos 2 tickers para correlacao.")

  mat <- as.matrix(ret[, cols, drop = FALSE])
  m <- stats::cor(mat, use = "pairwise.complete.obs")
  df <- as.data.frame(m)
  df$ticker <- rownames(m)
  df |>
    tidyr::pivot_longer(-ticker, names_to = "ticker2", values_to = "correlacao")
}

sugerir_hedge_beta <- function(
  quantidade,
  lado_ativo = c("long", "short"),
  preco_ativo,
  beta,
  preco_bench,
  pct_hedge = 100
) {
  lado_ativo <- match.arg(lado_ativo)
  quantidade <- as.numeric(quantidade)
  preco_ativo <- as.numeric(preco_ativo)
  preco_bench <- as.numeric(preco_bench)
  beta <- as.numeric(beta)
  pct_hedge <- as.numeric(pct_hedge) / 100

  if (!all(is.finite(c(quantidade, preco_ativo, beta, preco_bench, pct_hedge)))) {
    stop("Parametros invalidos para hedge.")
  }
  if (quantidade <= 0 || preco_ativo <= 0 || preco_bench <= 0) {
    stop("Quantidade e precos devem ser positivos.")
  }

  sinal <- if (lado_ativo == "long") 1 else -1
  notional <- quantidade * preco_ativo
  beta_exposicao <- sinal * beta * notional * pct_hedge

  qty_bench <- -beta_exposicao / preco_bench
  lado_bench <- if (qty_bench >= 0) "compra" else "venda"
  qty_bench_abs <- abs(qty_bench)

  list(
    lado_ativo = lado_ativo,
    quantidade_ativo = quantidade,
    preco_ativo = preco_ativo,
    notional_ativo = notional,
    beta = beta,
    pct_hedge = pct_hedge * 100,
    beta_exposicao = beta_exposicao,
    ticker_bench_acao = lado_bench,
    quantidade_bench = qty_bench_abs,
    quantidade_bench_signed = qty_bench,
    preco_bench = preco_bench,
    notional_bench = qty_bench_abs * preco_bench
  )
}

plot_scatter_beta <- function(ret, ticker_ativo, ticker_bench, stats) {
  df <- tibble::tibble(
    x = ret[[ticker_bench]],
    y = ret[[ticker_ativo]]
  ) |>
    dplyr::filter(is.finite(x), is.finite(y))

  ggplot2::ggplot(df, ggplot2::aes(x = x, y = y)) +
    ggplot2::geom_point(color = COR_GRAY, alpha = 0.45, size = 1.8) +
    ggplot2::geom_smooth(
      method = "lm", se = TRUE, color = COR_ACCENT, fill = COR_ACCENT, alpha = 0.15
    ) +
    ggplot2::labs(
      title = sprintf("Retornos diarios: %s vs %s", ticker_ativo, ticker_bench),
      subtitle = sprintf(
        "Beta = %.2f | Corr = %.2f | R2 = %.2f | n = %d",
        stats$beta, stats$correlacao, stats$r2, stats$n
      ),
      x = sprintf("Retorno %s", ticker_bench),
      y = sprintf("Retorno %s", ticker_ativo)
    ) +
    tema_beta()
}

plot_beta_rolling <- function(roll) {
  ggplot2::ggplot(roll, ggplot2::aes(x = refdate, y = beta)) +
    ggplot2::geom_line(color = COR_YELLOW, linewidth = 0.9) +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed", color = COR_GRAY, linewidth = 0.5) +
    ggplot2::labs(
      title = sprintf(
        "Beta rolling (%d DU): %s vs %s",
        roll$janela_du[1], roll$ticker_ativo[1], roll$ticker_bench[1]
      ),
      subtitle = "Linha tracejada = beta 1",
      x = NULL,
      y = "Beta"
    ) +
    tema_beta()
}

plot_precos_base100 <- function(wide, tickers) {
  cols <- intersect(tickers, setdiff(names(wide), "refdate"))
  if (length(cols) < 1) return(NULL)

  base <- wide |>
    dplyr::select(refdate, dplyr::all_of(cols)) |>
    tidyr::pivot_longer(-refdate, names_to = "ticker", values_to = "preco") |>
    dplyr::group_by(ticker) |>
    dplyr::mutate(base100 = preco / dplyr::first(preco) * 100) |>
    dplyr::ungroup()

  ggplot2::ggplot(base, ggplot2::aes(x = refdate, y = base100, color = ticker)) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::scale_color_manual(values = c(COR_ACCENT, COR_YELLOW, COR_WHITE, "#8a6fff", "#e05252")) +
    ggplot2::labs(
      title = "Precos normalizados (base 100)",
      x = NULL,
      y = "Indice (1o dia = 100)",
      color = NULL
    ) +
    tema_beta() +
    ggplot2::theme(legend.position = "bottom")
}

plot_correlacao_heatmap <- function(corr_long) {
  tickers <- unique(c(corr_long$ticker, corr_long$ticker2))
  ggplot2::ggplot(corr_long, ggplot2::aes(x = ticker2, y = ticker, fill = correlacao)) +
    ggplot2::geom_tile(color = COR_GRID) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("%.2f", correlacao)),
      color = COR_WHITE, size = 3.2
    ) +
    ggplot2::scale_fill_gradient2(
      low = "#e05252", mid = COR_PANEL, high = COR_ACCENT,
      midpoint = 0, limits = c(-1, 1), name = "Corr"
    ) +
    ggplot2::labs(
      title = "Matriz de correlacao (retornos diarios)",
      x = NULL,
      y = NULL
    ) +
    tema_beta() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      panel.grid = ggplot2::element_blank()
    )
}

rodar_correlacao_beta <- function(
  ticker_ativo,
  ticker_bench = "BOVA11",
  tickers_corr = NULL,
  periodo_inicio,
  periodo_fim,
  janela_du = 63L,
  tipo_retorno = c("log", "simple"),
  cache_dir = DEFAULT_RB3_CACHE_BETA
) {
  tipo_retorno <- match.arg(tipo_retorno)
  ticker_ativo <- toupper(trimws(ticker_ativo))
  ticker_bench <- toupper(trimws(ticker_bench))
  janela_du <- as.integer(janela_du)

  if (!nzchar(ticker_ativo)) stop("Informe o ticker do ativo.")
  if (!nzchar(ticker_bench)) stop("Informe o benchmark.")

  if (!exists("ajustar_periodo_busca", mode = "function")) {
    stop("Funcao ajustar_periodo_busca nao carregada (source busca_opcoes.R).")
  }
  per <- ajustar_periodo_busca(periodo_inicio, periodo_fim, cache_dir, ticker_spot = ticker_ativo)

  if (is.null(tickers_corr) || !length(tickers_corr)) {
    tickers_corr <- unique(c(ticker_ativo, ticker_bench))
  } else {
    tickers_corr <- unique(toupper(trimws(tickers_corr)))
  }
  tickers_corr <- unique(c(ticker_ativo, ticker_bench, tickers_corr))

  precos <- carregar_precos_tickers(
    tickers = tickers_corr,
    periodo_inicio = per$inicio,
    periodo_fim = per$fim,
    cache_dir = cache_dir
  )

  ret <- calc_retornos(precos$wide, tipo = tipo_retorno)

  if (!all(c(ticker_ativo, ticker_bench) %in% names(ret))) {
    stop("Ativo ou benchmark sem retornos no periodo.")
  }

  stats <- calc_beta_estatico(ret, ticker_ativo, ticker_bench)
  roll <- calc_beta_rolling(ret, ticker_ativo, ticker_bench, janela_du = janela_du)

  corr_tickers <- intersect(tickers_corr, setdiff(names(ret), "refdate"))
  corr_long <- if (length(corr_tickers) >= 2) {
    calc_matriz_correlacao(ret, corr_tickers)
  } else {
    NULL
  }

  ult_ativo <- precos$ultimos |> dplyr::filter(ticker == ticker_ativo)
  ult_bench <- precos$ultimos |> dplyr::filter(ticker == ticker_bench)
  preco_ativo <- if (nrow(ult_ativo)) ult_ativo$preco[1] else NA_real_
  preco_bench <- if (nrow(ult_bench)) ult_bench$preco[1] else NA_real_

  tabela_beta <- tibble::tibble(
    metrica = c(
      "Beta", "Correlacao", "R2", "Alpha a.a.", "Vol ativo a.a.", "Vol bench a.a.",
      "Observacoes", "Janela rolling (DU)"
    ),
    valor = c(
      sprintf("%.3f", stats$beta),
      sprintf("%.3f", stats$correlacao),
      sprintf("%.3f", stats$r2),
      sprintf("%+.2f%%", stats$alpha_aa * 100),
      sprintf("%.2f%%", stats$vol_ativo_aa * 100),
      sprintf("%.2f%%", stats$vol_bench_aa * 100),
      format(stats$n, big.mark = "."),
      as.character(janela_du)
    )
  )

  list(
    ticker_ativo = ticker_ativo,
    ticker_bench = ticker_bench,
    tickers_corr = corr_tickers,
    periodo_inicio = per$inicio,
    periodo_fim = per$fim,
    periodo_ajustado = isTRUE(per$ajustado),
    janela_du = janela_du,
    tipo_retorno = tipo_retorno,
    stats = stats,
    beta_rolling = roll,
    matriz_correlacao = corr_long,
    tabela_beta = tabela_beta,
    preco_ativo = preco_ativo,
    preco_bench = preco_bench,
    graficos = list(
      scatter = plot_scatter_beta(ret, ticker_ativo, ticker_bench, stats),
      beta_rolling = plot_beta_rolling(roll),
      precos_base100 = plot_precos_base100(precos$wide, c(ticker_ativo, ticker_bench)),
      heatmap = if (!is.null(corr_long)) plot_correlacao_heatmap(corr_long) else NULL
    ),
    retornos = ret
  )
}
