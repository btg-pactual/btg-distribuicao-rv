# =============================================================================
# Radar FVOL — scan em lote (Ibovespa) + percentis + setorial
# =============================================================================

RADAR_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
if (!exists("DEFAULT_RB3_CACHE_RADAR", inherits = TRUE)) {
  source(file.path(RADAR_DIR, "config_mr_derivs.R"), local = FALSE)
}

COR_BG_R     <- "#0a1628"
COR_PANEL_R  <- "#111f38"
COR_GRID_R   <- "#1e2f4a"
COR_TEXT_R   <- "#e8eeff"
COR_ACCENT_R <- "#00c37a"
COR_YELLOW_R <- "#f5c842"
COR_WHITE_R  <- "#ffffff"
COR_RED_R    <- "#e05252"

tema_radar <- function() {
  ggplot2::theme_classic(base_size = 13) +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = COR_BG_R, color = NA),
      panel.background = ggplot2::element_rect(fill = COR_PANEL_R, color = NA),
      panel.grid.major = ggplot2::element_line(color = COR_GRID_R, linewidth = 0.4),
      panel.grid.minor = ggplot2::element_blank(),
      axis.text        = ggplot2::element_text(color = COR_WHITE_R, face = "bold"),
      axis.title       = ggplot2::element_text(color = COR_WHITE_R, face = "bold"),
      plot.title       = ggplot2::element_text(color = COR_WHITE_R, face = "bold", size = 15),
      plot.subtitle    = ggplot2::element_text(color = COR_TEXT_R, size = 11),
      legend.background = ggplot2::element_rect(fill = COR_PANEL_R, color = COR_GRID_R),
      legend.text      = ggplot2::element_text(color = COR_WHITE_R),
      legend.title     = ggplot2::element_text(color = COR_WHITE_R, face = "bold")
    )
}

#' Extrai 1 linha snapshot do resultado de rodar_vol_implicita.
snapshot_de_fvol <- function(res, ticker, peso = NA_real_, setor = NA_character_) {
  if (is.null(res) || is.null(res$fvol) || !nrow(res$fvol)) {
    return(tibble::tibble(
      ticker = ticker,
      setor = setor,
      peso = peso,
      refdate = as.Date(NA),
      du = NA_integer_,
      vol_atm = NA_real_,
      skew = NA_real_,
      smile = NA_real_,
      pct_vol = NA_real_,
      pct_skew = NA_real_,
      pct_smile = NA_real_,
      diff_vol_media = NA_real_,
      diff_skew_media = NA_real_,
      diff_smile_media = NA_real_,
      vol_realizada = NA_real_,
      premio_iv = NA_real_,
      n_points = NA_integer_,
      r2 = NA_real_,
      status = "sem_fvol"
    ))
  }

  ult <- dplyr::slice_tail(res$fvol, n = 1)
  n_pts <- as.integer(ult$n_points[1])
  r2v <- as.numeric(ult$r2[1])
  status <- if (is.finite(n_pts) && n_pts >= 5 && is.finite(r2v) && r2v >= 0.7) {
    "ok"
  } else {
    "fit_fraco"
  }

  tibble::tibble(
    ticker = ticker,
    setor = setor,
    peso = peso,
    refdate = as.Date(ult$refdate[1]),
    du = as.integer(ult$biz_days[1]),
    vol_atm = as.numeric(ult$sigma_atm[1]),
    skew = as.numeric(ult$skew[1]),
    smile = as.numeric(ult$smile[1]),
    pct_vol = as.numeric(ult$pct_vol[1]),
    pct_skew = as.numeric(ult$pct_skew[1]),
    pct_smile = as.numeric(ult$pct_smile[1]),
    diff_vol_media = as.numeric(ult$diff_vol_media[1]),
    diff_skew_media = as.numeric(ult$diff_skew_media[1]),
    diff_smile_media = as.numeric(ult$diff_smile_media[1]),
    vol_realizada = as.numeric(ult$vol_realizada[1]),
    premio_iv = as.numeric(ult$premio_iv[1]),
    n_points = n_pts,
    r2 = r2v,
    status = status
  )
}

snapshot_erro <- function(ticker, peso, setor, msg) {
  tibble::tibble(
    ticker = ticker,
    setor = setor,
    peso = peso,
    refdate = as.Date(NA),
    du = NA_integer_,
    vol_atm = NA_real_,
    skew = NA_real_,
    smile = NA_real_,
    pct_vol = NA_real_,
    pct_skew = NA_real_,
    pct_smile = NA_real_,
    diff_vol_media = NA_real_,
    diff_skew_media = NA_real_,
    diff_smile_media = NA_real_,
    vol_realizada = NA_real_,
    premio_iv = NA_real_,
    n_points = NA_integer_,
    r2 = NA_real_,
    status = paste0("erro: ", substr(gsub("\\s+", " ", msg), 1, 120))
  )
}

#' Percentis cross-section no dia (entre ativos ok).
adicionar_ranks_xsec <- function(df) {
  ok <- df$status == "ok" & is.finite(df$vol_atm)
  rank_pct <- function(x, mask) {
    out <- rep(NA_real_, length(x))
    if (sum(mask, na.rm = TRUE) < 2) return(out)
    out[mask] <- dplyr::percent_rank(x[mask]) * 100
    out
  }
  df |>
    dplyr::mutate(
      pct_vol_xsec = rank_pct(vol_atm, ok),
      pct_skew_xsec = rank_pct(skew, ok),
      pct_smile_xsec = rank_pct(smile, ok)
    )
}

#' Agrega radar por setor.
agregar_radar_setorial <- function(df) {
  df |>
    dplyr::filter(status == "ok", !is.na(setor), nzchar(setor)) |>
    dplyr::group_by(setor) |>
    dplyr::summarise(
      n_ok = dplyr::n(),
      peso = sum(peso, na.rm = TRUE),
      vol_atm_med = stats::median(vol_atm, na.rm = TRUE),
      pct_vol_med = stats::median(pct_vol, na.rm = TRUE),
      pct_vol_xsec_med = stats::median(pct_vol_xsec, na.rm = TRUE),
      skew_med = stats::median(skew, na.rm = TRUE),
      pct_skew_med = stats::median(pct_skew, na.rm = TRUE),
      pct_skew_xsec_med = stats::median(pct_skew_xsec, na.rm = TRUE),
      smile_med = stats::median(smile, na.rm = TRUE),
      pct_smile_med = stats::median(pct_smile, na.rm = TRUE),
      pct_smile_xsec_med = stats::median(pct_smile_xsec, na.rm = TRUE),
      premio_iv_med = stats::median(premio_iv, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(pct_vol_med))
}

plot_heatmap_setorial <- function(setorial) {
  if (is.null(setorial) || !nrow(setorial)) return(NULL)

  long <- setorial |>
    dplyr::select(
      setor,
      Vol = pct_vol_med,
      Skew = pct_skew_med,
      Smile = pct_smile_med
    ) |>
    tidyr::pivot_longer(-setor, names_to = "metrica", values_to = "percentil")

  long$metrica <- factor(long$metrica, levels = c("Vol", "Skew", "Smile"))
  ord <- setorial$setor[order(setorial$pct_vol_med, decreasing = TRUE)]
  long$setor <- factor(long$setor, levels = rev(ord))

  ggplot2::ggplot(long, ggplot2::aes(x = metrica, y = setor, fill = percentil)) +
    ggplot2::geom_tile(color = COR_GRID_R, linewidth = 0.4) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("%.0f", percentil)),
      color = COR_WHITE_R, size = 3.3, fontface = "bold"
    ) +
    ggplot2::scale_fill_gradient2(
      low = COR_ACCENT_R, mid = COR_PANEL_R, high = COR_RED_R,
      midpoint = 50, limits = c(0, 100), name = "Pct"
    ) +
    ggplot2::labs(
      title = "Radar setorial — percentis (historico proprio, mediana)",
      subtitle = "0 = barato no historico do setor | 100 = caro / extremo",
      x = NULL, y = NULL
    ) +
    tema_radar() +
    ggplot2::theme(panel.grid = ggplot2::element_blank())
}

plot_barras_pct_vol <- function(df, top_n = 20L) {
  d <- df |>
    dplyr::filter(status == "ok", is.finite(pct_vol)) |>
    dplyr::arrange(dplyr::desc(pct_vol)) |>
    dplyr::slice_head(n = as.integer(top_n))

  if (!nrow(d)) return(NULL)
  d$ticker <- factor(d$ticker, levels = rev(d$ticker))

  ggplot2::ggplot(d, ggplot2::aes(x = ticker, y = pct_vol, fill = pct_vol)) +
    ggplot2::geom_col(width = 0.75) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_gradient2(
      low = COR_ACCENT_R, mid = COR_YELLOW_R, high = COR_RED_R,
      midpoint = 50, limits = c(0, 100), guide = "none"
    ) +
    ggplot2::geom_hline(yintercept = 50, linetype = "dashed", color = COR_TEXT_R, linewidth = 0.4) +
    ggplot2::labs(
      title = sprintf("Top %d — percentil de Vol ATM (historico proprio)", nrow(d)),
      x = NULL, y = "Percentil vol"
    ) +
    tema_radar()
}

salvar_radar <- function(resultado, out_dir) {
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  stamp <- format(Sys.time(), "%Y%m%d_%H%M")
  csv <- file.path(out_dir, sprintf("radar_fvol_%s.csv", stamp))
  latest_csv <- file.path(out_dir, "radar_fvol_latest.csv")
  latest_rds <- file.path(out_dir, "radar_fvol_latest.rds")
  utils::write.csv(resultado$ativos, csv, row.names = FALSE, fileEncoding = "UTF-8")
  utils::write.csv(resultado$ativos, latest_csv, row.names = FALSE, fileEncoding = "UTF-8")
  saveRDS(resultado, latest_rds)
  list(csv = csv, latest_csv = latest_csv, latest_rds = latest_rds)
}

carregar_radar_latest <- function(out_dir) {
  path <- file.path(out_dir, "radar_fvol_latest.rds")
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

#' Roda FVOL de 1 ticker e devolve snapshot (para uso em callr).
calcular_snapshot_ticker <- function(
  ticker,
  peso = NA_real_,
  setor = NA_character_,
  periodo_inicio,
  periodo_fim,
  data_inicio_cache = as.Date("2020-01-01"),
  du_alvo = 22L,
  du_tol = 10L,
  janela_mm = 21L,
  carrego = "pcp",
  usar_apenas_vencimento_mensal = TRUE,
  cache_dir = DEFAULT_RB3_CACHE_RADAR,
  atualizar_cache = FALSE,
  app_dir = NULL
) {
  ticker <- toupper(trimws(ticker))
  prefixo <- substr(ticker, 1, 4)

  if (!is.null(app_dir)) {
    options(vol_implicita.limpar_sessao = FALSE)
    options(vol_implicita.autorun = FALSE)
    source(file.path(app_dir, "vol_implicita_11.R"), local = FALSE)
  }

  out <- tryCatch(
    rodar_vol_implicita(
      ativo = prefixo,
      ticker_spot = ticker,
      prefixo_opcoes = prefixo,
      periodo_inicio = periodo_inicio,
      periodo_fim = periodo_fim,
      data_inicio = data_inicio_cache,
      janela_mm = janela_mm,
      du_alvo = du_alvo,
      du_tol = du_tol,
      usar_apenas_vencimento_mensal = usar_apenas_vencimento_mensal,
      carrego = carrego,
      cache_dir = cache_dir,
      atualizar_cache = atualizar_cache,
      salvar_png = FALSE,
      incluir_tabela_grafico = FALSE,
      retorno_leve = TRUE
    ),
    error = function(e) e
  )

  if (inherits(out, "error")) {
    return(snapshot_erro(ticker, peso, setor, conditionMessage(out)))
  }
  snapshot_de_fvol(out, ticker, peso = peso, setor = setor)
}

#' Scan completo da carteira (loop sequencial; isolamento via callr no app).
rodar_radar_fvol <- function(
  carteira,
  periodo_inicio = Sys.Date() - 365,
  periodo_fim = Sys.Date(),
  data_inicio_cache = as.Date("2020-01-01"),
  du_alvo = 22L,
  du_tol = 10L,
  janela_mm = 21L,
  carrego = "pcp",
  usar_apenas_vencimento_mensal = TRUE,
  cache_dir = DEFAULT_RB3_CACHE_RADAR,
  atualizar_cache_inicial = TRUE,
  out_dir = NULL,
  progress_fn = NULL,
  calc_fn = NULL
) {
  if (is.null(carteira) || !nrow(carteira)) stop("Carteira vazia.")

  if (isTRUE(atualizar_cache_inicial) && exists("atualizar_cache_cotahist", mode = "function")) {
    if (is.function(progress_fn)) progress_fn(0, "Atualizando COTAHIST...")
    tryCatch(
      atualizar_cache_cotahist(
        cache_dir = cache_dir,
        data_inicio = data_inicio_cache,
        data_fim = max(as.Date(periodo_fim), Sys.Date())
      ),
      error = function(e) message("Aviso cache: ", conditionMessage(e))
    )
  }

  if (is.null(calc_fn)) {
    calc_fn <- function(row, atualizar_cache) {
      calcular_snapshot_ticker(
        ticker = row$ticker,
        peso = row$peso,
        setor = row$setor,
        periodo_inicio = periodo_inicio,
        periodo_fim = periodo_fim,
        data_inicio_cache = data_inicio_cache,
        du_alvo = du_alvo,
        du_tol = du_tol,
        janela_mm = janela_mm,
        carrego = carrego,
        usar_apenas_vencimento_mensal = usar_apenas_vencimento_mensal,
        cache_dir = cache_dir,
        atualizar_cache = atualizar_cache
      )
    }
  }

  n <- nrow(carteira)
  rows <- vector("list", n)
  for (i in seq_len(n)) {
    row <- carteira[i, , drop = FALSE]
    if (is.function(progress_fn)) {
      progress_fn(i / (n + 1), sprintf("%s (%d/%d)", row$ticker[1], i, n))
    }
    rows[[i]] <- calc_fn(row, atualizar_cache = FALSE)
    invisible(gc())
  }

  ativos <- dplyr::bind_rows(rows) |> adicionar_ranks_xsec()
  setorial <- agregar_radar_setorial(ativos)

  resultado <- list(
    gerado_em = Sys.time(),
    periodo_inicio = as.Date(periodo_inicio),
    periodo_fim = as.Date(periodo_fim),
    du_alvo = as.integer(du_alvo),
    carrego = carrego,
    n_carteira = n,
    n_ok = sum(ativos$status == "ok", na.rm = TRUE),
    n_erro = sum(grepl("^erro", ativos$status), na.rm = TRUE),
    ativos = ativos,
    setorial = setorial,
    graficos = list(
      heatmap = plot_heatmap_setorial(setorial),
      top_pct_vol = plot_barras_pct_vol(ativos, top_n = 20L)
    )
  )

  if (!is.null(out_dir)) {
    paths <- salvar_radar(resultado, out_dir)
    resultado$arquivos <- paths
  }

  if (is.function(progress_fn)) progress_fn(1, "Concluido")
  resultado
}
