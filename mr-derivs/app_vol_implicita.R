# =============================================================================
# Shiny — Vol Implicita B3 (IV, percentis, skew/smile, IV vs realizada)
# Rodar: shiny::runApp("app_vol_implicita.R")
# =============================================================================

options(vol_implicita.limpar_sessao = FALSE)
options(vol_implicita.autorun = FALSE)

APP_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})

source(file.path(APP_DIR, "config_mr_derivs.R"), local = FALSE)
source(file.path(APP_DIR, "vol_implicita_11.R"), local = FALSE)
source(file.path(APP_DIR, "busca_opcoes.R"), local = FALSE)
if (isTRUE(MR_DERIVS_FULL_UI)) {
  source(file.path(APP_DIR, "simulacao_short.R"), local = FALSE)
  source(file.path(APP_DIR, "correlacao_beta.R"), local = FALSE)
  source(file.path(APP_DIR, "universo_ibov.R"), local = FALSE)
  source(file.path(APP_DIR, "radar_fvol.R"), local = FALSE)
}

library(shiny)
library(DT)
library(ggplot2)
if (!requireNamespace("plotly", quietly = TRUE)) {
  stop("Pacote plotly necessario para graficos interativos. Rode: install.packages('plotly')")
}
library(plotly)

DEFAULT_CACHE <- DEFAULT_RB3_CACHE
RADAR_OUT_DIR <- DEFAULT_OUT_RADAR
if (!dir.exists(RADAR_OUT_DIR)) dir.create(RADAR_OUT_DIR, recursive = TRUE, showWarnings = FALSE)

BUSCA_PERIODO <- tryCatch(
  periodo_padrao_busca(DEFAULT_CACHE, dias = 7L),
  error = function(e) list(inicio = Sys.Date() - 6L, fim = Sys.Date())
)
BUSCA_PERIODO_INI <- BUSCA_PERIODO$inicio
BUSCA_PERIODO_FIM <- BUSCA_PERIODO$fim

TICKERS_PADRAO <- unique(c(TICKERS_SEED_24M, TICKERS_WATCHLIST))
CACHE_INICIO_UI <- cache_data_inicio_padrao(MR_CACHE_MESES)

prefixo_de_ticker <- function(ticker) substr(toupper(trimws(ticker)), 1, 4)

limpar_erro_shiny <- function(msg) {
  msg <- gsub("\x1b\\[[0-9;]*[a-zA-Z]", "", msg, perl = TRUE)
  msg <- gsub("in callr subprocess\\.\\s*", "", msg)
  msg <- sub("Caused by error[^:]*:\\s*", "", msg)
  msg <- sub("^\\s*!\\s*", "", msg)
  trimws(msg)
}

PLOT_H   <- 380
PLOT_RES <- 96

#' Roda o pipeline em processo separado (evita travar rb3/duckdb no 2o ativo).
#' Cache COTAHIST e atualizado no PROCESSO PAI (mais confiavel que dentro do callr).
calcular_vol_isolado <- function(
  ativo,
  ticker_spot,
  prefixo_opcoes,
  periodo_inicio,
  periodo_fim,
  data_inicio,
  janela_mm,
  du_alvo,
  du_tol,
  usar_apenas_vencimento_mensal,
  carrego,
  cache_dir,
  atualizar_cache,
  forcar_cache_desde = NULL
) {
  cache_info <- NULL
  if (isTRUE(atualizar_cache)) {
    message(">>> Sync COTAHIST no processo pai...")
    # Evita conflito cli/rb3 progress x withProgress do Shiny
    old_cli <- options(
      cli.progress_show_after = Inf,
      cli.progress_handlers = "none"
    )
    on.exit(options(old_cli), add = TRUE)
    cache_info <- tryCatch(
      atualizar_cache_cotahist(
        cache_dir = cache_dir,
        data_inicio = as.Date(data_inicio),
        data_fim = max(as.Date(periodo_fim), Sys.Date()),
        forcar_desde = forcar_cache_desde,
        quiet = FALSE
      ),
      error = function(e) {
        list(
          n_novas = NA_integer_,
          ultima_antes = as.Date(NA),
          ultima_depois = tryCatch(ultima_data_cotahist(cache_dir), error = function(e2) as.Date(NA)),
          mensagem = paste("Falha sync cache:", conditionMessage(e))
        )
      }
    )
    message(">>> ", cache_info$mensagem)
  }

  args_rodar <- list(
    ativo = ativo,
    ticker_spot = ticker_spot,
    prefixo_opcoes = prefixo_opcoes,
    periodo_inicio = periodo_inicio,
    periodo_fim = periodo_fim,
    data_inicio = data_inicio,
    janela_mm = janela_mm,
    du_alvo = du_alvo,
    du_tol = du_tol,
    usar_apenas_vencimento_mensal = usar_apenas_vencimento_mensal,
    carrego = carrego,
    cache_dir = cache_dir,
    # ja sincronizado no pai — evita segundo fetch lento/silencioso no callr
    atualizar_cache = FALSE,
    salvar_png = FALSE,
    incluir_tabela_grafico = FALSE,
    retorno_leve = TRUE
  )

  if (requireNamespace("callr", quietly = TRUE)) {
    tmp <- tempfile(tmpdir = cache_dir, fileext = ".rds")
    on.exit(unlink(tmp, force = TRUE), add = TRUE)
    callr::r(
      function(path, app_dir, dots) {
        options(vol_implicita.limpar_sessao = FALSE)
        options(vol_implicita.autorun = FALSE)
        source(file.path(app_dir, "vol_implicita_11.R"), local = FALSE)
        res <- do.call(rodar_vol_implicita, dots)
        saveRDS(res, path)
      },
      args = list(path = tmp, app_dir = APP_DIR, dots = args_rodar),
      wd = APP_DIR,
      show = FALSE,
      spinner = FALSE
    )
    out <- readRDS(tmp)
    out$cache_update <- cache_info
    invisible(gc())
    return(out)
  }

  out <- do.call(rodar_vol_implicita, args_rodar)
  out$cache_update <- cache_info
  invisible(gc())
  out
}

buscar_opcoes_isolado <- function(
  ticker_spot,
  tipo,
  periodo_inicio,
  periodo_fim,
  dist_strike_max,
  vol_min,
  du_alvo,
  du_tol,
  maturity_date,
  prefixo_opcoes,
  cache_dir,
  atualizar_cache = FALSE,
  data_inicio_cache = as.Date("2020-01-01")
) {
  args_busca <- list(
    ticker_spot = ticker_spot,
    tipo = tipo,
    periodo_inicio = periodo_inicio,
    periodo_fim = periodo_fim,
    dist_strike_max = dist_strike_max,
    vol_min = vol_min,
    du_alvo = du_alvo,
    du_tol = du_tol,
    maturity_date = maturity_date,
    prefixo_opcoes = prefixo_opcoes,
    cache_dir = cache_dir,
    atualizar_cache = atualizar_cache,
    data_inicio_cache = data_inicio_cache
  )

  if (requireNamespace("callr", quietly = TRUE)) {
    tmp <- tempfile(tmpdir = cache_dir, fileext = ".rds")
    on.exit(unlink(tmp, force = TRUE), add = TRUE)
    callr::r(
      function(path, app_dir, dots) {
        Sys.setenv(R_USER_CACHE_DIR = dots$cache_dir)
        options(rb3.cachedir = dots$cache_dir)
        source(file.path(app_dir, "busca_opcoes.R"), local = FALSE)
        res <- do.call(buscar_opcoes_historico, dots)
        saveRDS(res, path)
      },
      args = list(path = tmp, app_dir = APP_DIR, dots = args_busca),
      wd = APP_DIR,
      show = FALSE,
      spinner = FALSE
    )
    out <- readRDS(tmp)
    invisible(gc())
    return(out)
  }

  out <- do.call(buscar_opcoes_historico, args_busca)
  invisible(gc())
  out
}

simular_short_isolado <- function(
  ticker_spot,
  quantidade,
  preco_entrada,
  du_horizonte,
  modo_carrego,
  cache_dir
) {
  args_sim <- list(
    ticker_spot = ticker_spot,
    quantidade = quantidade,
    preco_entrada = preco_entrada,
    du_horizonte = du_horizonte,
    modo_carrego = modo_carrego,
    cache_dir = cache_dir
  )

  if (requireNamespace("callr", quietly = TRUE)) {
    tmp <- tempfile(tmpdir = cache_dir, fileext = ".rds")
    on.exit(unlink(tmp, force = TRUE), add = TRUE)
    callr::r(
      function(path, app_dir, dots) {
        Sys.setenv(R_USER_CACHE_DIR = dots$cache_dir)
        options(rb3.cachedir = dots$cache_dir)
        source(file.path(app_dir, "busca_opcoes.R"), local = FALSE)
        source(file.path(app_dir, "btc_taxas.R"), local = FALSE)
        source(file.path(app_dir, "carrego_pcp.R"), local = FALSE)
        source(file.path(app_dir, "simulacao_short.R"), local = FALSE)
        res <- do.call(simular_short_hedge, dots)
        saveRDS(res, path)
      },
      args = list(path = tmp, app_dir = APP_DIR, dots = args_sim),
      wd = APP_DIR,
      show = FALSE,
      spinner = FALSE
    )
    out <- readRDS(tmp)
    invisible(gc())
    return(out)
  }

  out <- do.call(simular_short_hedge, args_sim)
  invisible(gc())
  out
}

calcular_beta_isolado <- function(
  ticker_ativo,
  ticker_bench,
  tickers_corr,
  periodo_inicio,
  periodo_fim,
  janela_du,
  tipo_retorno,
  cache_dir
) {
  args_beta <- list(
    ticker_ativo = ticker_ativo,
    ticker_bench = ticker_bench,
    tickers_corr = tickers_corr,
    periodo_inicio = periodo_inicio,
    periodo_fim = periodo_fim,
    janela_du = janela_du,
    tipo_retorno = tipo_retorno,
    cache_dir = cache_dir
  )

  if (requireNamespace("callr", quietly = TRUE)) {
    tmp <- tempfile(tmpdir = cache_dir, fileext = ".rds")
    on.exit(unlink(tmp, force = TRUE), add = TRUE)
    callr::r(
      function(path, app_dir, dots) {
        Sys.setenv(R_USER_CACHE_DIR = dots$cache_dir)
        options(rb3.cachedir = dots$cache_dir)
        source(file.path(app_dir, "busca_opcoes.R"), local = FALSE)
        source(file.path(app_dir, "correlacao_beta.R"), local = FALSE)
        res <- do.call(rodar_correlacao_beta, dots)
        saveRDS(res, path)
      },
      args = list(path = tmp, app_dir = APP_DIR, dots = args_beta),
      wd = APP_DIR,
      show = FALSE,
      spinner = FALSE
    )
    out <- readRDS(tmp)
    invisible(gc())
    return(out)
  }

  out <- do.call(rodar_correlacao_beta, args_beta)
  invisible(gc())
  out
}

#' Snapshot FVOL de 1 ticker em processo isolado (callr).
calcular_snapshot_isolado <- function(
  ticker,
  peso,
  setor,
  periodo_inicio,
  periodo_fim,
  data_inicio_cache,
  du_alvo,
  du_tol,
  janela_mm,
  carrego,
  usar_apenas_vencimento_mensal,
  cache_dir,
  atualizar_cache = FALSE
) {
  args <- list(
    ticker = ticker,
    peso = peso,
    setor = setor,
    periodo_inicio = periodo_inicio,
    periodo_fim = periodo_fim,
    data_inicio_cache = data_inicio_cache,
    du_alvo = du_alvo,
    du_tol = du_tol,
    janela_mm = janela_mm,
    carrego = carrego,
    usar_apenas_vencimento_mensal = usar_apenas_vencimento_mensal,
    cache_dir = cache_dir,
    atualizar_cache = atualizar_cache,
    app_dir = APP_DIR
  )

  if (requireNamespace("callr", quietly = TRUE)) {
    tmp <- tempfile(tmpdir = cache_dir, fileext = ".rds")
    on.exit(unlink(tmp, force = TRUE), add = TRUE)
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
      args = list(path = tmp, app_dir = APP_DIR, dots = args),
      wd = APP_DIR,
      show = FALSE,
      spinner = FALSE
    )
    out <- readRDS(tmp)
    invisible(gc())
    return(out)
  }

  do.call(calcular_snapshot_ticker, args)
}

render_grafico <- function(expr) {
  renderPlot(
    expr,
    bg = "#0a1628",
    height = PLOT_H,
    res = PLOT_RES
  )
}

PLOTLY_BG <- "#0a1628"
PLOTLY_PANEL <- "#111f38"
PLOTLY_GRID <- "#1e2f4a"
PLOTLY_YELLOW <- "#f5c842"
PLOTLY_ACCENT <- "#00c37a"
PLOTLY_RED <- "#e05252"
PLOTLY_PURPLE <- "#8a6fff"
PLOTLY_WHITE <- "#ffffff"

layout_plotly_dark <- function(p, title, subtitle = NULL, ylab = NULL, xlab = NULL,
                               hovermode = "x unified") {
  full_title <- if (!is.null(subtitle) && nzchar(subtitle)) {
    list(
      text = paste0(title, "<br><sup style='font-size:12px;color:#a8b8d8'>", subtitle, "</sup>"),
      font = list(color = PLOTLY_WHITE, size = 16)
    )
  } else {
    list(text = title, font = list(color = PLOTLY_WHITE, size = 16))
  }
  p <- plotly::layout(
    p,
    title = full_title,
    paper_bgcolor = PLOTLY_BG,
    plot_bgcolor = PLOTLY_PANEL,
    font = list(color = "#e8eeff", size = 13),
    hovermode = hovermode,
    hoverlabel = list(
      bgcolor = PLOTLY_PANEL,
      bordercolor = PLOTLY_GRID,
      font = list(color = PLOTLY_WHITE, size = 13)
    ),
    legend = list(
      orientation = "h",
      x = 0.5,
      xanchor = "center",
      y = -0.18,
      bgcolor = "rgba(17,31,56,0.85)",
      font = list(color = PLOTLY_WHITE)
    ),
    xaxis = list(
      title = if (is.null(xlab)) "" else xlab,
      gridcolor = PLOTLY_GRID,
      zerolinecolor = PLOTLY_GRID,
      tickfont = list(color = PLOTLY_WHITE),
      titlefont = list(color = "#e8eeff"),
      automargin = TRUE
    ),
    yaxis = list(
      title = if (is.null(ylab)) "" else ylab,
      gridcolor = PLOTLY_GRID,
      zerolinecolor = PLOTLY_GRID,
      tickfont = list(color = PLOTLY_WHITE),
      titlefont = list(color = "#e8eeff"),
      automargin = TRUE,
      tickformat = ".1f",
      ticksuffix = "%"
    ),
    margin = list(l = 60, r = 30, t = 70, b = 70)
  )
  plotly::config(
    p,
    displayModeBar = TRUE,
    displaylogo = FALSE,
    modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d")
  )
}

#' Vol ATM + MM — plotly nativo (evita bug de escala do ggplotly).
plotly_vol_atm <- function(res) {
  df <- res$fvol
  req_ok <- !is.null(df) && nrow(df) > 0 && "sigma_atm" %in% names(df)
  if (!isTRUE(req_ok)) return(plotly::plotly_empty())
  mm_lab <- sprintf("MM%d", res$janela_mm %||% 21L)
  df <- df |>
    dplyr::arrange(refdate) |>
    dplyr::mutate(
      vol_pct = sigma_atm * 100,
      mm_pct = vol_mm * 100,
      hover_vol = paste0(
        "<b>", format(refdate, "%d/%m/%Y"), "</b><br>",
        "Vol ATM: ", sprintf("%.2f%%", vol_pct)
      ),
      hover_mm = paste0(
        "<b>", format(refdate, "%d/%m/%Y"), "</b><br>",
        mm_lab, ": ", sprintf("%.2f%%", mm_pct)
      )
    )
  ult <- dplyr::slice_tail(df, n = 1)
  sub <- sprintf(
    "venc. ~%sdu | carrego=%s",
    res$du_alvo %||% "?",
    res$carrego_label %||% (res$carrego_modo %||% "")
  )
  p <- plotly::plot_ly() |>
    plotly::add_lines(
      data = df, x = ~refdate, y = ~vol_pct,
      name = "Vol ATM FVOL",
      line = list(color = PLOTLY_YELLOW, width = 2.2),
      hoverinfo = "text", text = ~hover_vol
    ) |>
    plotly::add_lines(
      data = dplyr::filter(df, !is.na(mm_pct)),
      x = ~refdate, y = ~mm_pct,
      name = mm_lab,
      line = list(color = PLOTLY_ACCENT, width = 2.6),
      hoverinfo = "text", text = ~hover_mm
    ) |>
    plotly::add_markers(
      data = ult, x = ~refdate, y = ~vol_pct,
      name = "Ultimo",
      marker = list(
        color = PLOTLY_ACCENT, size = 10,
        line = list(color = PLOTLY_WHITE, width = 1.5)
      ),
      hoverinfo = "text", text = ~hover_vol,
      showlegend = FALSE
    )
  layout_plotly_dark(
    p,
    title = sprintf("Vol ATM FVOL — %s", res$ativo %||% ""),
    subtitle = sub,
    ylab = "Vol (%)",
    hovermode = "x unified"
  )
}

#' Skew e Smile historicos — plotly nativo.
plotly_skew_smile <- function(res) {
  df <- res$fvol
  if (is.null(df) || !nrow(df) || !all(c("skew", "smile") %in% names(df))) {
    return(plotly::plotly_empty())
  }
  df <- df |>
    dplyr::arrange(refdate) |>
    dplyr::mutate(
      skew_pct = skew * 100,
      smile_pct = smile * 100,
      hover_skew = paste0(
        "<b>", format(refdate, "%d/%m/%Y"), "</b><br>",
        "Skew: ", sprintf("%.2f%%", skew_pct)
      ),
      hover_smile = paste0(
        "<b>", format(refdate, "%d/%m/%Y"), "</b><br>",
        "Smile: ", sprintf("%.2f%%", smile_pct)
      )
    )
  ult <- dplyr::slice_tail(df, n = 1)
  p <- plotly::plot_ly() |>
    plotly::add_lines(
      data = df, x = ~refdate, y = ~skew_pct,
      name = "Skew",
      line = list(color = PLOTLY_RED, width = 2.2),
      hoverinfo = "text", text = ~hover_skew
    ) |>
    plotly::add_lines(
      data = df, x = ~refdate, y = ~smile_pct,
      name = "Smile",
      line = list(color = PLOTLY_PURPLE, width = 2.2),
      hoverinfo = "text", text = ~hover_smile
    ) |>
    plotly::add_markers(
      data = ult, x = ~refdate, y = ~skew_pct,
      marker = list(color = PLOTLY_RED, size = 9, line = list(color = PLOTLY_WHITE, width = 1)),
      hoverinfo = "text", text = ~hover_skew, showlegend = FALSE, name = "ult_skew"
    ) |>
    plotly::add_markers(
      data = ult, x = ~refdate, y = ~smile_pct,
      marker = list(color = PLOTLY_PURPLE, size = 9, line = list(color = PLOTLY_WHITE, width = 1)),
      hoverinfo = "text", text = ~hover_smile, showlegend = FALSE, name = "ult_smile"
    )
  layout_plotly_dark(
    p,
    title = sprintf("Skew e Smile FVOL — %s", res$ativo %||% ""),
    subtitle = sprintf("IV_ex_ATM ~ SN + SN^2 | venc. ~%sdu", res$du_alvo %||% "?"),
    ylab = "Coeficiente (%)",
    hovermode = "x unified"
  )
}

#' Smile do dia (SN x IV) — plotly nativo.
plotly_smile_dia <- function(res) {
  df <- res$fvol
  if (is.null(df) || !nrow(df) || !"fit_data" %in% names(df)) {
    return(plotly::plotly_empty())
  }
  ult <- dplyr::slice_tail(df, n = 1)
  smile_data <- ult$fit_data[[1]]
  if (is.null(smile_data) || !nrow(smile_data)) return(plotly::plotly_empty())

  sn_min <- max(-2, min(smile_data$sn, na.rm = TRUE))
  sn_max <- min(2, max(smile_data$sn, na.rm = TRUE))
  curve <- tibble::tibble(sn = seq(sn_min, sn_max, length.out = 200)) |>
    dplyr::mutate(
      fvol_fit = ult$sigma_atm[1] + ult$skew[1] * sn + (ult$smile[1] / 2) * sn^2,
      hover = paste0(
        "<b>Curva FVOL</b><br>",
        "SN: ", sprintf("%.3f", sn), "<br>",
        "IV fit: ", sprintf("%.2f%%", fvol_fit * 100)
      )
    )
  pts <- smile_data |>
    dplyr::mutate(
      iv_pct = impvol * 100,
      hover = paste0(
        "<b>", toupper(type), "</b><br>",
        "SN: ", sprintf("%.3f", sn), "<br>",
        "IV: ", sprintf("%.2f%%", iv_pct), "<br>",
        "Volume: ", format(round(volume), big.mark = ".")
      )
    )
  calls <- dplyr::filter(pts, type == "call")
  puts <- dplyr::filter(pts, type == "put")

  p <- plotly::plot_ly()
  if (nrow(calls)) {
    p <- plotly::add_markers(
      p, data = calls, x = ~sn, y = ~iv_pct,
      name = "call",
      marker = list(
        color = PLOTLY_YELLOW,
        size = pmax(6, pmin(14, sqrt(calls$volume / max(pts$volume, na.rm = TRUE)) * 14)),
        opacity = 0.7
      ),
      hoverinfo = "text", text = ~hover
    )
  }
  if (nrow(puts)) {
    p <- plotly::add_markers(
      p, data = puts, x = ~sn, y = ~iv_pct,
      name = "put",
      marker = list(
        color = PLOTLY_RED,
        size = pmax(6, pmin(14, sqrt(puts$volume / max(pts$volume, na.rm = TRUE)) * 14)),
        opacity = 0.7
      ),
      hoverinfo = "text", text = ~hover
    )
  }
  p <- plotly::add_lines(
    p, data = curve, x = ~sn, y = ~fvol_fit * 100,
    name = "Curva FVOL",
    line = list(color = PLOTLY_ACCENT, width = 2.8),
    hoverinfo = "text", text = ~hover
  )
  p <- layout_plotly_dark(
    p,
    title = sprintf("Smile FVOL — %s", res$ativo %||% ""),
    subtitle = sprintf(
      "Data: %s | venc. %sdu",
      format(ult$refdate[1], "%Y-%m-%d"),
      ult$biz_days[1] %||% "?"
    ),
    ylab = "Vol implicita (%)",
    xlab = "Strike Normalizado (SN)",
    hovermode = "closest"
  )
  plotly::layout(
    p,
    shapes = list(list(
      type = "line", x0 = 0, x1 = 0, y0 = 0, y1 = 1, yref = "paper",
      line = list(color = "#8fa8c8", dash = "dash", width = 1)
    )),
    xaxis = list(range = c(-2, 2), title = "Strike Normalizado (SN)")
  )
}

estilizar_dt <- function(dt) {
  DT::formatStyle(
    dt,
    columns = colnames(dt$x$data),
    color = "#ffffff",
    fontSize = "16px",
    backgroundColor = "#111f38"
  ) |>
    DT::formatStyle(
      columns = colnames(dt$x$data),
      border = "1px solid #1e2f4a"
    )
}

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { background-color: #0a1628; color: #ffffff; font-size: 15px; }
    .well, .sidebar-panel { background-color: #111f38 !important; border: 1px solid #1e2f4a; }
    .nav-tabs > li > a { color: #e8f0ff; background-color: #111f38; font-size: 15px; padding: 10px 16px; }
    .nav-tabs > li.active > a { color: #ffffff; background-color: #1e2f4a; border-color: #1e2f4a; font-weight: bold; }
    .tab-content { padding-top: 12px; }
    h2 { color: #ffffff; font-size: 26px; font-weight: bold; }
    h4, label, .control-label { color: #ffffff !important; font-size: 15px !important; font-weight: 600; }
    .selectize-input, .selectize-dropdown, .form-control {
      background-color: #111f38 !important; color: #ffffff !important;
      border-color: #1e2f4a !important; font-size: 14px !important;
    }
    .selectize-dropdown .option { color: #ffffff !important; }
    .selectize-dropdown .active { background-color: #1e2f4a !important; }
    .shiny-output-error { color: #e05252; font-size: 14px; }
    .js-plotly-plot, .plotly { background: #0a1628 !important; }
    .plotly .modebar { top: 4px !important; right: 4px !important; }
    .status-box { background: #111f38; border: 1px solid #1e2f4a; padding: 12px 16px;
                   border-radius: 6px; margin-bottom: 12px; font-family: monospace;
                   font-size: 14px; color: #ffffff; }
    .status-ok { color: #00c37a; font-weight: bold; }
    .status-warn { color: #f5c842; font-weight: bold; }
    .dataTables_wrapper { color: #ffffff !important; font-size: 14px !important; }
    table.dataTable { background-color: #111f38 !important; color: #ffffff !important; }
    table.dataTable thead th {
      color: #ffffff !important; background-color: #1e2f4a !important;
      font-size: 16px !important; font-weight: bold !important; border-color: #2a3f5f !important;
    }
    table.dataTable tbody td {
      color: #f0f4ff !important; background-color: #111f38 !important;
      font-size: 14px !important; border-color: #1e2f4a !important;
    }
    table.dataTable.stripe tbody tr.odd { background-color: #0d1a30 !important; }
    table.dataTable.hover tbody tr:hover td { background-color: #1a2d4d !important; }
    .dataTables_info, .dataTables_length, .dataTables_filter, .dataTables_paginate {
      color: #ffffff !important; font-size: 13px !important;
    }
    .dataTables_filter input {
      background: #111f38 !important; color: #ffffff !important; border: 1px solid #1e2f4a !important;
    }
    .paginate_button { color: #ffffff !important; }
    .shiny-plot-output { margin-bottom: 16px !important; }
    .loading-banner {
      background: #1a2d4d; border: 1px solid #00c37a; color: #ffffff;
      padding: 10px 14px; border-radius: 6px; margin-bottom: 12px;
      font-size: 14px; font-weight: 600;
    }
    .radar-hero {
      background: linear-gradient(120deg, #0d1f3c 0%, #132a4a 45%, #0a1628 100%);
      border: 1px solid #1e2f4a;
      border-radius: 10px;
      padding: 18px 20px 14px 20px;
      margin-bottom: 14px;
    }
    .radar-hero h3 {
      margin: 0 0 6px 0;
      color: #ffffff;
      font-size: 22px;
      font-weight: 700;
      letter-spacing: 0.2px;
    }
    .radar-hero p {
      margin: 0;
      color: #a8b8d8;
      font-size: 13px;
      line-height: 1.45;
    }
    .kpi-row { margin-bottom: 12px; }
    .kpi-card {
      background: #111f38;
      border: 1px solid #1e2f4a;
      border-radius: 8px;
      padding: 12px 14px;
      min-height: 78px;
    }
    .kpi-card .kpi-label {
      color: #8fa8c8;
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      margin-bottom: 4px;
    }
    .kpi-card .kpi-value {
      color: #ffffff;
      font-size: 22px;
      font-weight: 700;
      font-family: monospace;
      line-height: 1.1;
    }
    .kpi-card .kpi-sub {
      color: #a8b8d8;
      font-size: 12px;
      margin-top: 4px;
    }
    .kpi-accent { border-left: 3px solid #00c37a; }
    .kpi-warn { border-left: 3px solid #f5c842; }
    .kpi-hot { border-left: 3px solid #e05252; }
    .radar-empty {
      border: 1px dashed #2a3f5f;
      border-radius: 10px;
      padding: 36px 20px;
      text-align: center;
      color: #a8b8d8;
      background: #0d1a30;
      margin-top: 8px;
    }
    .radar-empty strong { color: #ffffff; font-size: 16px; }
    .radar-legend {
      display: flex; gap: 14px; flex-wrap: wrap;
      color: #a8b8d8; font-size: 12px; margin: 8px 0 12px 0;
    }
    .radar-legend span::before {
      content: '';
      display: inline-block;
      width: 10px; height: 10px;
      border-radius: 2px;
      margin-right: 6px;
      vertical-align: middle;
    }
    .lg-low::before { background: #00c37a; }
    .lg-mid::before { background: #f5c842; }
    .lg-high::before { background: #e05252; }
    /* Datepicker: nao cortar dropdown em colunas estreitas / abas */
    .tab-content, .tab-pane, .fluidRow, .row, [class*='col-'],
    .sidebar-panel, .well, .shiny-date-input, .shiny-date-range-input {
      overflow: visible !important;
    }
    .datepicker-dropdown, .datepicker {
      z-index: 100000 !important;
    }
    .datepicker {
      background-color: #111f38 !important;
      border: 1px solid #1e2f4a !important;
      color: #ffffff !important;
      padding: 8px !important;
      border-radius: 6px !important;
    }
    .datepicker table tr th,
    .datepicker table tr td {
      color: #e8f0ff !important;
    }
    .datepicker table tr td.day:hover,
    .datepicker table tr td.focused {
      background: #1e2f4a !important;
      color: #ffffff !important;
    }
    .datepicker table tr td.active,
    .datepicker table tr td.active:hover {
      background: #00c37a !important;
      color: #0a1628 !important;
    }
    .datepicker table tr td.old,
    .datepicker table tr td.new {
      color: #6b7c99 !important;
    }
    .datepicker .datepicker-switch,
    .datepicker .prev, .datepicker .next {
      color: #ffffff !important;
    }
    .input-daterange .input-group-addon {
      background-color: #1e2f4a !important;
      color: #ffffff !important;
      border-color: #1e2f4a !important;
    }
    .shiny-date-input input, .shiny-date-range-input input {
      width: 100% !important;
    }
  "))),
  tags$head(tags$script(HTML("
    $(function() {
      if ($.fn.datepicker && $.fn.datepicker.Constructor) {
        $.fn.datepicker.Constructor.Default.container = 'body';
        $.fn.datepicker.Constructor.Default.orientation = 'bottom auto';
        $.fn.datepicker.Constructor.Default.autoclose = true;
        $.fn.datepicker.Constructor.Default.todayHighlight = true;
      }
    });
  "))),
  titlePanel(if (MR_DERIVS_FULL_UI) {
    "Mr Derivs — Radar de Vol & IV B3"
  } else {
    "Mr Derivs — IV & Opções B3"
  }),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      h4("Ativo"),
      selectizeInput(
        "ticker",
        "Ticker spot",
        choices = TICKERS_PADRAO,
        selected = "PETR4",
        options = list(create = TRUE, placeholder = "ex: PETR4")
      ),
      textInput("prefixo_opcoes", "Prefixo opcoes (opcional)", value = "", placeholder = "auto = 4 letras"),
      dateRangeInput(
        "periodo",
        "Periodo IV",
        start = Sys.Date() - 365,
        end = Sys.Date(),
        format = "dd/mm/yyyy",
        separator = " ate ",
        language = "pt-BR"
      ),
      dateInput("data_inicio_cache", "Cache COTAHIST desde",
                value = CACHE_INICIO_UI, format = "dd/mm/yyyy"),
      hr(),
      h4("Parametros"),
      numericInput("du_alvo", "DU alvo (~vencimento)", 22, min = 5, max = 120),
      numericInput("du_tol", "Tolerancia DU", 10, min = 1, max = 30),
      numericInput("janela_mm", "Janela vol realizada / MM", 21, min = 5, max = 126),
      selectInput("carrego", "Carrego BSM", c("pcp", "btc", "hibrido"), selected = "pcp"),
      checkboxInput("venc_mensal", "Apenas vencimento mensal", TRUE),
      checkboxInput("atualizar_cache", "Atualizar cache rb3", TRUE),
      checkboxInput(
        "forcar_cache",
        "Forcar redownload (se travado em data velha)",
        FALSE
      ),
      tags$p(
        style = "color:#a8b8d8; font-size:12px; margin-top:-8px;",
        "Se 'Ultimo' ficar parado (ex. 29/09), marque as duas caixas e Calcular. Sync roda antes do IV."
      ),
      hr(),
      actionButton("calcular", "Calcular", class = "btn-primary", width = "100%"),
      br(),
      div(class = "status-box", uiOutput("status_txt"))
    ),
    mainPanel(
      width = 9,
      uiOutput("banner_calculando"),
      tabsetPanel(
        id = "tabs",
        selected = "IV historica",
        tabPanel(
          "IV historica",
          br(),
          plotlyOutput("plot_vol_atm", height = "420px"),
          plotOutput("plot_percentis", height = "380px"),
          downloadButton("dl_fvol", "Baixar FVOL (CSV)"),
          br(), br(),
          DTOutput("tbl_resumo")
        ),
        tabPanel(
          "Skew & Smile",
          br(),
          plotlyOutput("plot_skew_smile", height = "420px"),
          fluidRow(
            column(6, plotlyOutput("plot_smile", height = "420px")),
            column(6, plotOutput("plot_preco", height = "380px"))
          )
        ),
        tabPanel(
          "IV vs Realizada",
          br(),
          tags$p(
            style = "color:#e8f0ff; font-size:14px; font-family:monospace; margin-bottom:8px;",
            "Backward = vol historica na janela MM | Forward = o que o spot realizou nos proximos DU alvo (ex post)"
          ),
          plotOutput("plot_iv_hv", height = "380px"),
          plotOutput("plot_premio", height = "320px"),
          hr(style = "border-color:#1e2f4a"),
          plotOutput("plot_iv_fwd", height = "380px"),
          fluidRow(
            column(7, plotOutput("plot_premio_fwd", height = "320px")),
            column(5, plotOutput("plot_scatter_fwd", height = "320px"))
          ),
          uiOutput("stats_fwd_txt")
        ),
        tabPanel(
          "Busca opcoes",
          br(),
          fluidRow(
            column(
              3,
              h4("Filtros"),
              selectizeInput(
                "busca_ticker",
                "Ticker spot",
                choices = TICKERS_PADRAO,
                selected = "BOVA11",
                options = list(create = TRUE, placeholder = "ex: BOVA11")
              ),
              radioButtons(
                "busca_tipo",
                "Tipo",
                choices = c("Call" = "call", "Put" = "put"),
                selected = "call",
                inline = TRUE
              ),
              selectInput(
                "busca_dist",
                "Distancia max. ao spot",
                choices = c(
                  "3%" = 0.03,
                  "5%" = 0.05,
                  "10%" = 0.10,
                  "15%" = 0.15,
                  "20%" = 0.20
                ),
                selected = 0.05
              ),
              selectInput(
                "busca_du",
                "DU alvo (prazo)",
                choices = c(
                  "~1 semana (5 DU)" = 5,
                  "~1 mes (22 DU)" = 22,
                  "~2 meses (45 DU)" = 45,
                  "~3 meses (63 DU)" = 63,
                  "~6 meses (126 DU)" = 126
                ),
                selected = 22
              ),
              numericInput("busca_du_tol", "Tolerancia DU", 10, min = 1, max = 30),
              selectInput(
                "busca_venc",
                "Vencimento",
                choices = c("Auto (DU alvo)" = ""),
                selected = ""
              ),
              numericInput("busca_vol_min", "Volume minimo (contratos)", 1, min = 0, step = 1),
              dateInput(
                "busca_periodo_de",
                "Precos de",
                value = BUSCA_PERIODO_INI,
                min = CACHE_INICIO_UI,
                max = Sys.Date(),
                format = "dd/mm/yyyy",
                language = "pt-BR"
              ),
              dateInput(
                "busca_periodo_ate",
                "Precos ate",
                value = BUSCA_PERIODO_FIM,
                min = CACHE_INICIO_UI,
                max = Sys.Date(),
                format = "dd/mm/yyyy",
                language = "pt-BR"
              ),
              checkboxInput(
                "busca_atualizar_cache",
                "Atualizar cache rb3 (COTAHIST)",
                value = TRUE
              ),
              tags$p(
                style = "color:#a8b8d8; font-size:12px; margin-top:-6px;",
                "Se o periodo cair em 'ajustado ao cache', marque e busque de novo para baixar pregões novos."
              ),
              actionButton("busca_btn", "Buscar opcoes", class = "btn-primary", width = "100%"),
              br(), br(),
              div(class = "status-box", uiOutput("busca_status"))
            ),
            column(
              9,
              downloadButton("dl_busca", "Baixar CSV"),
              br(), br(),
              DTOutput("tbl_busca"),
              br(),
              selectInput("busca_symbol_plot", "Opcao para grafico de preco", choices = character(0)),
              plotOutput("plot_busca", height = "380px")
            )
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  resultado <- reactiveVal(NULL)
  erro <- reactiveVal(NULL)
  calculando <- reactiveVal(FALSE)
  plot_seq <- reactiveVal(0L)

  observeEvent(TRUE, {
    if (!requireNamespace("callr", quietly = TRUE)) {
      showNotification(
        "Pacote 'callr' nao encontrado. Instale com install.packages('callr') para trocar ativos sem travar.",
        type = "warning",
        duration = 12
      )
    }
  }, once = TRUE)

  observe({
    label <- if (isTRUE(calculando())) "Calculando..." else "Calcular"
    updateActionButton(session, "calcular", label = label)
  })

  output$banner_calculando <- renderUI({
    if (!calculando()) return(NULL)
    msg <- if (toupper(trimws(input$ticker)) %in% c("BOVA11", "SMAL11", "BOVA", "SMAL")) {
      "Calculando BOVA/ETF — pode levar 1-3 min. Graficos abaixo mostram a ultima rodada concluida."
    } else {
      "Calculando... Graficos abaixo mostram a ultima rodada concluida."
    }
    tags$div(class = "loading-banner", msg)
  })

  output$status_txt <- renderUI({
    err <- erro()
    res <- resultado()
    diag_cache <- tryCatch(
      diagnostico_cache_cotahist(DEFAULT_CACHE),
      error = function(e) NULL
    )
    if (calculando()) {
      return(tags$span(class = "status-ok", "Processando..."))
    }
    if (!is.null(err)) {
      return(tags$span(class = "status-warn", err))
    }
    if (is.null(res)) {
      return(tags$div(
        tags$span("Selecione o ativo e clique em Calcular."),
        if (!is.null(diag_cache)) {
          tagList(tags$br(), tags$span(style = "color:#a8b8d8;", diag_cache$mensagem))
        }
      ))
    }
    n_iv <- res$n_iv_dias %||% 0L
    n_fvol <- if (!is.null(res$fvol) && nrow(res$fvol)) nrow(res$fvol) else 0L
    ult <- if (n_fvol > 0) max(res$fvol$refdate) else as.Date(NA)
    atraso_dias <- if (!is.na(ult)) as.integer(Sys.Date() - as.Date(ult)) else NA_integer_
    duck_txt <- if (!is.null(res$cache_update) && !is.null(res$cache_update$ultima_depois) &&
                    !is.na(res$cache_update$ultima_depois)) {
      format(res$cache_update$ultima_depois, "%Y-%m-%d")
    } else if (!is.null(diag_cache) && !is.na(diag_cache$ultima_duckdb)) {
      format(diag_cache$ultima_duckdb, "%Y-%m-%d")
    } else {
      "n/d"
    }
    tags$div(
      tags$span(class = "status-ok", sprintf("%s | %s", res$ativo, res$ticker_spot)),
      tags$br(),
      sprintf(
        "%d pregões IV | %d curvas FVOL | carrego: %s",
        n_iv, n_fvol, res$carrego_modo %||% "?"
      ),
      tags$br(),
      sprintf(
        "Ultimo FVOL: %s | %s",
        if (!is.na(ult)) format(ult, "%Y-%m-%d") else "n/d",
        res$carrego_label %||% ""
      ),
      if (!is.null(res$meta_datas) && !is.null(res$meta_datas$ultimo_vencimento) &&
          !is.na(res$meta_datas$ultimo_vencimento)) {
        tagList(
          tags$br(),
          sprintf(
            "Venc: %s (%sdu, %s) | pts=%s | R2=%.2f",
            format(res$meta_datas$ultimo_vencimento, "%Y-%m-%d"),
            res$meta_datas$ultimo_biz_days %||% "?",
            if (isTRUE(res$meta_datas$ultimo_mensal)) "mensal" else "semanal",
            res$meta_datas$ultimo_n_points %||% "?",
            res$meta_datas$ultimo_r2 %||% NA_real_
          )
        )
      },
      if (!is.null(res$meta_datas) &&
          is.finite(res$meta_datas$n_datas_iv_sem_fvol) &&
          res$meta_datas$n_datas_iv_sem_fvol > 0) {
        tagList(
          tags$br(),
          tags$span(
            class = "status-warn",
            sprintf(
              "IV sem FVOL (%d): %s",
              res$meta_datas$n_datas_iv_sem_fvol,
              paste(utils::head(res$meta_datas$datas_iv_sem_fvol, 8), collapse = ", ")
            )
          )
        )
      },
      if (!is.null(res$meta_datas)) {
        fb <- res$meta_datas$n_datas_fallback_semanal %||% 0L
        tagList(
          tags$br(),
          sprintf(
            "Spot: %s | IV: %s | pulados: %s/%s%s",
            format(res$meta_datas$ultima_spot, "%Y-%m-%d"),
            format(res$meta_datas$ultima_iv, "%Y-%m-%d"),
            res$meta_datas$n_datas_puladas,
            res$meta_datas$n_datas_spot,
            if (fb > 0) sprintf(" | fallback semanal: %s", fb) else ""
          )
        )
      },
      if (!is.null(res$cache_update) && !is.null(res$cache_update$mensagem)) {
        tagList(tags$br(), tags$span(style = "color:#a8b8d8;", res$cache_update$mensagem))
      },
      tagList(tags$br(), sprintf("COTAHIST DuckDB: %s", duck_txt)),
      if (is.finite(atraso_dias) && atraso_dias > 5) {
        tagList(
          tags$br(),
          tags$span(
            class = "status-warn",
            sprintf(
              "FVOL atrasado ~%d dias. Se DuckDB/Spot ja estao recentes: desmarque 'Apenas venc. mensal' ou aumente Tolerancia DU e Calcule de novo.",
              atraso_dias
            )
          )
        )
      }
    )
  })

  observeEvent(input$calcular, {
    if (isTRUE(calculando())) {
      showNotification("Aguarde o calculo anterior terminar.", type = "warning", duration = 3)
      return()
    }

    erro(NULL)
    calculando(TRUE)
    on.exit(calculando(FALSE), add = TRUE)

    ticker <- toupper(trimws(input$ticker))
    if (!nzchar(ticker)) {
      erro("Informe um ticker spot valido.")
      return()
    }
    if (is.null(input$periodo) || length(input$periodo) < 2 ||
        any(is.na(as.Date(input$periodo)))) {
      erro("Periodo IV invalido.")
      return()
    }
    if (as.Date(input$periodo[1]) > as.Date(input$periodo[2])) {
      erro("Periodo IV: inicio maior que fim.")
      return()
    }
    if (!is.finite(input$du_alvo) || input$du_alvo < 1 ||
        !is.finite(input$du_tol) || input$du_tol < 0) {
      erro("DU alvo / tolerancia invalidos.")
      return()
    }
    prefixo <- trimws(input$prefixo_opcoes)
    prefixo <- if (nzchar(prefixo)) toupper(prefixo) else prefixo_de_ticker(ticker)

    withProgress(message = sprintf("Calculando %s...", ticker), value = 0, {
      detail0 <- if (isTRUE(input$atualizar_cache)) {
        "Sync COTAHIST (pai) + IV isolado..."
      } else {
        "Processo isolado (rb3)..."
      }
      incProgress(0.05, detail = detail0)
      forcar_desde <- if (isTRUE(input$forcar_cache)) {
        # reapaga marcas e rebaixa ~ultimos 45 dias corridos (cobre travamento tipo 29/09)
        Sys.Date() - 45
      } else {
        NULL
      }
      out <- tryCatch(
        calcular_vol_isolado(
          ativo = prefixo,
          ticker_spot = ticker,
          prefixo_opcoes = prefixo,
          periodo_inicio = input$periodo[1],
          periodo_fim = input$periodo[2],
          data_inicio = input$data_inicio_cache,
          janela_mm = input$janela_mm,
          du_alvo = input$du_alvo,
          du_tol = input$du_tol,
          usar_apenas_vencimento_mensal = input$venc_mensal,
          carrego = input$carrego,
          cache_dir = DEFAULT_CACHE,
          atualizar_cache = isTRUE(input$atualizar_cache),
          forcar_cache_desde = forcar_desde
        ),
        error = function(e) e
      )
      incProgress(1)
      if (inherits(out, "error")) {
        msg <- limpar_erro_shiny(conditionMessage(out))
        erro(msg)
        showNotification(msg, type = "error", duration = 10)
        return()
      }
      plot_seq(plot_seq() + 1L)
      resultado(out)
      invisible(gc())
      n_fvol <- if (!is.null(out$fvol) && nrow(out$fvol)) nrow(out$fvol) else 0L
      showNotification(
        sprintf("%s concluido — %d curvas FVOL", ticker, n_fvol),
        type = if (n_fvol > 0) "message" else "warning",
        duration = 5
      )
    })
  }, ignoreInit = TRUE)

  res_ativo <- reactive({
    resultado()
  })

  pick_plot <- function(name) {
    render_grafico({
      req(res_ativo())
      plot_seq()
      res_ativo()$graficos[[name]]
    })
  }

  output$plot_vol_atm <- plotly::renderPlotly({
    req(res_ativo())
    plot_seq()
    plotly_vol_atm(res_ativo())
  })
  output$plot_percentis <- pick_plot("percentis")
  output$plot_skew_smile <- plotly::renderPlotly({
    req(res_ativo())
    plot_seq()
    plotly_skew_smile(res_ativo())
  })
  output$plot_smile <- plotly::renderPlotly({
    req(res_ativo())
    plot_seq()
    plotly_smile_dia(res_ativo())
  })
  output$plot_preco <- pick_plot("preco")
  output$plot_iv_hv <- pick_plot("iv_vs_hv")
  output$plot_premio <- pick_plot("premio_iv")
  output$plot_iv_fwd <- pick_plot("iv_vs_fwd")
  output$plot_premio_fwd <- pick_plot("premio_iv_fwd")
  output$plot_scatter_fwd <- pick_plot("scatter_iv_fwd")

  output$stats_fwd_txt <- renderUI({
    req(res_ativo())
    st <- res_ativo()$stats_iv_fwd
    tags$div(
      class = "status-box",
      sprintf(
        "Validacao ex post (%d pregões): corr IV×forward = %s | MAE = %s | IV acima do realizado em %.0f%% dos dias",
        st$n,
        ifelse(is.na(st$cor), "--", sprintf("%.2f", st$cor)),
        ifelse(is.na(st$mae), "--", sprintf("%+.2f pp", st$mae * 100)),
        st$pct_iv_acima
      )
    )
  })

  output$tbl_resumo <- renderDT({
    req(res_ativo())
    plot_seq()
    estilizar_dt(
      DT::datatable(
        res_ativo()$tabela,
        rownames = FALSE,
        options = list(dom = "t", pageLength = 10),
        class = "cell-border stripe hover"
      )
    )
  })

  output$tbl_fvol <- renderDT({
    req(res_ativo())
    plot_seq()
    estilizar_dt(
      DT::datatable(
        res_ativo()$fvol |>
          dplyr::select(
            refdate, biz_days, maturity_date, sigma_atm, vol_realizada, vol_realizada_fwd,
            premio_iv, premio_iv_fwd, skew, smile, pct_vol, pct_skew, pct_smile, n_points, r2
          ) |>
          dplyr::mutate(
            dplyr::across(
              c(sigma_atm, vol_realizada, vol_realizada_fwd, premio_iv, premio_iv_fwd, skew, smile),
              ~ round(.x * 100, 2)
            ),
            dplyr::across(starts_with("pct_"), ~ round(.x, 1))
          ),
        rownames = FALSE,
        options = list(pageLength = 15, scrollX = TRUE),
        colnames = c(
          "Data", "DU", "Vencimento", "IV ATM %", "Vol back %", "Vol fwd %",
          "Premio back pp", "Premio fwd pp", "Skew %", "Smile %",
          "Pct IV", "Pct Skew", "Pct Smile", "Pontos", "R2"
        ),
        class = "cell-border stripe hover"
      )
    )
  })

  output$dl_fvol <- downloadHandler(
    filename = function() {
      req(res_ativo())
      sprintf("fvol_%s_%s.csv", res_ativo()$ativo, format(Sys.Date(), "%Y%m%d"))
    },
    content = function(file) {
      req(res_ativo())
      utils::write.csv(res_ativo()$fvol, file, row.names = FALSE)
    }
  )

  # --- Correlacao & Beta ---
  beta_res <- reactiveVal(NULL)
  beta_erro <- reactiveVal(NULL)
  beta_calculando <- reactiveVal(FALSE)
  beta_hedge_res <- reactiveVal(NULL)

  output$beta_status <- renderUI({
    if (isTRUE(beta_calculando())) {
      return(tags$span(class = "status-ok", "Calculando beta..."))
    }
    err <- beta_erro()
    if (!is.null(err)) return(tags$span(class = "status-warn", err))
    res <- beta_res()
    if (is.null(res)) return(tags$span("Configure os parametros e clique em Calcular beta."))
    tags$div(
      tags$span(
        class = "status-ok",
        sprintf("%s vs %s", res$ticker_ativo, res$ticker_bench)
      ),
      tags$br(),
      sprintf(
        "Beta = %.2f | Corr = %.2f | %s a %s | janela %d DU",
        res$stats$beta,
        res$stats$correlacao,
        format(res$periodo_inicio, "%d/%m/%Y"),
        format(res$periodo_fim, "%d/%m/%Y"),
        res$janela_du
      ),
      if (isTRUE(res$periodo_ajustado)) {
        tagList(tags$br(), tags$span(class = "status-warn", "Periodo ajustado ao cache rb3"))
      }
    )
  })

  observeEvent(input$beta_btn, {
    if (isTRUE(beta_calculando())) {
      showNotification("Calculo anterior em andamento.", type = "warning", duration = 3)
      return()
    }
    beta_erro(NULL)
    beta_hedge_res(NULL)
    beta_calculando(TRUE)
    on.exit(beta_calculando(FALSE), add = TRUE)

    ativo <- toupper(trimws(input$beta_ativo))
    bench <- toupper(trimws(input$beta_bench))
    if (!nzchar(ativo)) {
      beta_erro("Informe o ticker do ativo.")
      return()
    }
    if (!nzchar(bench)) {
      beta_erro("Informe o benchmark.")
      return()
    }
    if (input$beta_periodo_de > input$beta_periodo_ate) {
      beta_erro("Data inicial maior que data final.")
      return()
    }

    tickers_corr <- input$beta_tickers_corr
    if (is.null(tickers_corr) || !length(tickers_corr)) {
      tickers_corr <- unique(c(ativo, bench))
    }

    withProgress(message = sprintf("Beta %s vs %s...", ativo, bench), value = 0, {
      out <- tryCatch(
        calcular_beta_isolado(
          ticker_ativo = ativo,
          ticker_bench = bench,
          tickers_corr = tickers_corr,
          periodo_inicio = input$beta_periodo_de,
          periodo_fim = input$beta_periodo_ate,
          janela_du = as.integer(input$beta_janela),
          tipo_retorno = input$beta_retorno,
          cache_dir = DEFAULT_CACHE
        ),
        error = function(e) e
      )
      incProgress(1)
      if (inherits(out, "error")) {
        msg <- limpar_erro_shiny(conditionMessage(out))
        beta_erro(msg)
        showNotification(msg, type = "error", duration = 10)
        return()
      }
      beta_res(out)
      showNotification(
        sprintf("Beta %s = %.2f", ativo, out$stats$beta),
        type = "message",
        duration = 4
      )
    })
  }, ignoreInit = TRUE)

  output$tbl_beta_stats <- renderDT({
    req(beta_res())
    estilizar_dt(
      DT::datatable(
        beta_res()$tabela_beta,
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE),
        colnames = c("Metrica", "Valor"),
        class = "cell-border stripe hover"
      )
    )
  })

  output$plot_beta_scatter <- renderPlot({
    req(beta_res())
    beta_res()$graficos$scatter
  }, bg = "#0a1628", height = 380, res = 96)

  output$plot_beta_rolling <- renderPlot({
    req(beta_res())
    beta_res()$graficos$beta_rolling
  }, bg = "#0a1628", height = 380, res = 96)

  output$plot_beta_precos <- renderPlot({
    req(beta_res())
    beta_res()$graficos$precos_base100
  }, bg = "#0a1628", height = 320, res = 96)

  output$plot_beta_heatmap <- renderPlot({
    req(beta_res())
    p <- beta_res()$graficos$heatmap
    if (is.null(p)) {
      plot.new()
      text(0.5, 0.5, "Selecione ao menos 2 tickers na matriz.", col = "white", cex = 1.2)
    } else {
      print(p)
    }
  }, bg = "#0a1628", height = 420, res = 96)

  output$dl_beta_corr <- downloadHandler(
    filename = function() {
      req(beta_res())
      sprintf("correlacao_%s_%s.csv", beta_res()$ticker_ativo, format(Sys.Date(), "%Y%m%d"))
    },
    content = function(file) {
      req(beta_res())
      corr <- beta_res()$matriz_correlacao
      if (is.null(corr)) {
        utils::write.csv(data.frame(msg = "Sem matriz"), file, row.names = FALSE)
      } else {
        utils::write.csv(corr, file, row.names = FALSE)
      }
    }
  )

  observeEvent(input$beta_hedge_btn, {
    res <- beta_res()
    if (is.null(res)) {
      showNotification("Calcule o beta antes do hedge.", type = "warning", duration = 4)
      return()
    }

    beta_use <- input$beta_hedge_beta
    if (is.null(beta_use) || !is.finite(beta_use) || beta_use <= 0) {
      beta_use <- res$stats$beta
    }
    if (!is.finite(beta_use)) {
      showNotification("Beta invalido.", type = "error", duration = 4)
      return()
    }

    preco_ativo <- input$beta_hedge_preco_ativo
    if (is.null(preco_ativo) || !is.finite(preco_ativo) || preco_ativo <= 0) {
      preco_ativo <- res$preco_ativo
    }
    preco_bench <- res$preco_bench

    out <- tryCatch(
      sugerir_hedge_beta(
        quantidade = input$beta_hedge_qty,
        lado_ativo = input$beta_hedge_lado,
        preco_ativo = preco_ativo,
        beta = beta_use,
        preco_bench = preco_bench,
        pct_hedge = input$beta_hedge_pct
      ),
      error = function(e) {
        showNotification(limpar_erro_shiny(conditionMessage(e)), type = "error", duration = 6)
        NULL
      }
    )
    if (!is.null(out)) beta_hedge_res(out)
  }, ignoreInit = TRUE)

  output$beta_hedge_resumo <- renderUI({
    res <- beta_res()
    hedge <- beta_hedge_res()
    if (is.null(res)) {
      return(tags$div(class = "status-box", "Calcule o beta na aba ao lado."))
    }
    if (is.null(hedge)) {
      return(tags$div(
        class = "status-box",
        sprintf(
          "Beta estimado: %.2f (%s vs %s) | Preco ref. ativo: R$ %.2f | benchmark: R$ %.2f",
          res$stats$beta,
          res$ticker_ativo,
          res$ticker_bench,
          res$preco_ativo,
          res$preco_bench
        ),
        tags$br(),
        tags$span(style = "color:#a8b8d8;", "Clique em Calcular hedge.")
      ))
    }

    tags$div(
      class = "status-box",
      tags$strong("Posicao ativo: "),
      sprintf(
        "%s %s x %s @ R$ %.2f (notional R$ %s)",
        toupper(hedge$lado_ativo),
        format(hedge$quantidade_ativo, big.mark = "."),
        res$ticker_ativo,
        hedge$preco_ativo,
        format(round(hedge$notional_ativo, 2), big.mark = ".", decimal.mark = ",")
      ),
      tags$br(),
      tags$strong("Beta usado: "),
      sprintf("%.2f (hedge %.0f%%)", hedge$beta, hedge$pct_hedge),
      tags$br(),
      tags$strong("Acao no benchmark: "),
      tags$span(
        class = "status-ok",
        sprintf(
          "%s %s x %s @ R$ %.2f",
          toupper(hedge$ticker_bench_acao),
          format(round(hedge$quantidade_bench, 0), big.mark = "."),
          res$ticker_bench,
          hedge$preco_bench
        )
      ),
      tags$br(),
      tags$strong("Notional benchmark: "),
      sprintf("R$ %s", format(round(hedge$notional_bench, 2), big.mark = ".", decimal.mark = ",")),
      tags$br(),
      tags$span(
        style = "color:#a8b8d8; font-size:12px;",
        sprintf(
          "Exposicao beta neutralizada ~R$ %s | Risco idiossincratico (~%.0f%% da vol) permanece.",
          format(round(abs(hedge$beta_exposicao), 2), big.mark = ".", decimal.mark = ","),
          sqrt(max(0, 1 - res$stats$r2)) * 100
        )
      )
    )
  })

  # --- Busca opcoes ---
  busca_res <- reactiveVal(NULL)
  busca_erro <- reactiveVal(NULL)
  busca_calculando <- reactiveVal(FALSE)

  output$busca_status <- renderUI({
    if (isTRUE(busca_calculando())) {
      return(tags$span(class = "status-ok", "Buscando opcoes..."))
    }
    err <- busca_erro()
    if (!is.null(err)) return(tags$span(class = "status-warn", err))
    res <- busca_res()
    if (is.null(res)) return(tags$span("Configure os filtros e clique em Buscar."))
    tags$div(
      tags$span(class = "status-ok", sprintf("%s | %s", res$ticker_spot, toupper(res$tipo))),
      tags$br(),
      sprintf(
        "%s linhas | %s simbolos | %s pregões | dist max %s",
        format(res$n_linhas, big.mark = "."),
        res$n_simbolos,
        res$n_dias,
        paste0(round(as.numeric(input$busca_dist) * 100), "%")
      ),
      tags$br(),
      sprintf(
        "Pedido: %s a %s | Usado: %s a %s%s",
        format(
          if (!is.null(res$periodo_pedido_inicio)) res$periodo_pedido_inicio else res$periodo_inicio,
          "%d/%m/%Y"
        ),
        format(
          if (!is.null(res$periodo_pedido_fim)) res$periodo_pedido_fim else res$periodo_fim,
          "%d/%m/%Y"
        ),
        format(res$periodo_inicio, "%d/%m/%Y"),
        format(res$periodo_fim, "%d/%m/%Y"),
        if (isTRUE(res$periodo_ajustado)) " (ajustado ao cache)" else ""
      ),
      if (!is.null(res$ultima_cache) && !is.na(res$ultima_cache)) {
        tagList(
          tags$br(),
          sprintf("Ultima data no cache (ticker/geral): %s", format(res$ultima_cache, "%d/%m/%Y"))
        )
      },
      if (!is.null(res$cache_update) && !is.null(res$cache_update$mensagem)) {
        tagList(tags$br(), tags$span(class = "status-ok", res$cache_update$mensagem))
      },
      if (isTRUE(res$periodo_ajustado)) {
        tagList(
          tags$br(),
          tags$span(
            class = "status-warn",
            "Periodo cortado: cache desatualizado ou ticker sem pregão recente. Marque 'Atualizar cache rb3' e busque de novo."
          )
        )
      },
      if (!is.null(res$du_aviso) && nzchar(res$du_aviso)) {
        tagList(tags$br(), tags$span(class = "status-warn", res$du_aviso))
      }
    )
  })

  observeEvent(input$busca_btn, {
    if (isTRUE(busca_calculando())) {
      showNotification("Busca anterior em andamento.", type = "warning", duration = 3)
      return()
    }
    busca_erro(NULL)
    busca_calculando(TRUE)
    on.exit(busca_calculando(FALSE), add = TRUE)

    ticker <- toupper(trimws(input$busca_ticker))
    if (!nzchar(ticker)) {
      busca_erro("Informe um ticker spot.")
      return()
    }

    if (input$busca_periodo_de > input$busca_periodo_ate) {
      busca_erro("Data inicial maior que data final.")
      return()
    }

    venc <- input$busca_venc
    venc <- if (is.null(venc) || !nzchar(venc)) NULL else venc

    withProgress(message = sprintf("Buscando %s...", ticker), value = 0, {
      detail <- if (isTRUE(input$busca_atualizar_cache)) {
        "Atualizando COTAHIST + busca..."
      } else {
        "COTAHIST opcoes..."
      }
      incProgress(0.1, detail = detail)
      out <- tryCatch(
        buscar_opcoes_isolado(
          ticker_spot = ticker,
          tipo = input$busca_tipo,
          periodo_inicio = input$busca_periodo_de,
          periodo_fim = input$busca_periodo_ate,
          dist_strike_max = as.numeric(input$busca_dist),
          vol_min = input$busca_vol_min,
          du_alvo = input$busca_du,
          du_tol = input$busca_du_tol,
          maturity_date = venc,
          prefixo_opcoes = prefixo_de_ticker(ticker),
          cache_dir = DEFAULT_CACHE,
          atualizar_cache = isTRUE(input$busca_atualizar_cache),
          data_inicio_cache = input$data_inicio_cache
        ),
        error = function(e) e
      )
      incProgress(1)
      if (inherits(out, "error")) {
        msg <- limpar_erro_shiny(conditionMessage(out))
        busca_erro(msg)
        showNotification(msg, type = "error", duration = 8)
        return()
      }
      busca_res(out)

      venc_choices <- c("Auto (DU alvo)" = "")
      if (nrow(out$vencimentos) > 0) {
        labs <- sprintf(
          "%s (%ddu)",
          format(out$vencimentos$maturity_date, "%d/%m/%Y"),
          out$vencimentos$biz_days
        )
        venc_choices <- c(venc_choices, stats::setNames(
          as.character(out$vencimentos$maturity_date),
          labs
        ))
      }
      updateSelectInput(
        session,
        "busca_venc",
        choices = venc_choices,
        selected = if (is.null(venc) || !nzchar(venc)) "" else venc
      )

      sym_labs <- if (nrow(out$simbolos) > 0) {
        paste0(
          out$simbolos$symbol,
          " K=", out$simbolos$strike,
          " (", format(out$simbolos$vencimento, "%d/%m/%y"), ")"
        )
      } else {
        character(0)
      }
      updateSelectInput(
        session,
        "busca_symbol_plot",
        choices = stats::setNames(out$simbolos$symbol, sym_labs),
        selected = if (length(sym_labs)) out$simbolos$symbol[1] else NULL
      )

      showNotification(
        sprintf("%d linhas encontradas", out$n_linhas),
        type = "message",
        duration = 4
      )
    })
  }, ignoreInit = TRUE)

  output$tbl_busca <- renderDT({
    req(busca_res())
    estilizar_dt(
      DT::datatable(
        busca_res()$tabela |>
          dplyr::mutate(
            refdate = format(refdate, "%d/%m/%Y"),
            vencimento = format(vencimento, "%d/%m/%Y"),
            preco = round(preco, 2),
            spot = round(spot, 2),
            moneyness = round(moneyness, 4)
          ),
        rownames = FALSE,
        options = list(pageLength = 20, scrollX = TRUE, deferRender = TRUE),
        colnames = c(
          "Data", "Simbolo", "Tipo", "Strike", "Vencimento", "DU",
          "Dist. strike %", "Preco", "Volume", "Spot", "Moneyness"
        ),
        class = "cell-border stripe hover"
      )
    )
  })

  output$plot_busca <- renderPlot({
    req(busca_res(), input$busca_symbol_plot)
    df <- busca_res()$tabela |>
      dplyr::filter(symbol == input$busca_symbol_plot) |>
      dplyr::arrange(refdate)
    req(nrow(df) > 0)
    ggplot2::ggplot(df, ggplot2::aes(x = refdate, y = preco)) +
      ggplot2::geom_line(color = "#00c37a", linewidth = 1.1) +
      ggplot2::geom_point(color = "#ffffff", fill = "#f5c842", shape = 21, size = 2.5) +
      ggplot2::scale_y_continuous(labels = function(x) paste0("R$ ", x)) +
      ggplot2::labs(
        title = sprintf("Preco historico — %s", input$busca_symbol_plot),
        subtitle = sprintf(
          "Strike %s | Venc. %s | %d pregões",
          df$strike[1],
          format(df$vencimento[1], "%d/%m/%Y"),
          nrow(df)
        ),
        x = NULL,
        y = "Preco"
      ) +
      ggplot2::theme_classic(base_size = 14) +
      ggplot2::theme(
        plot.background = ggplot2::element_rect(fill = "#0a1628", color = NA),
        panel.background = ggplot2::element_rect(fill = "#111f38", color = NA),
        panel.grid.major = ggplot2::element_line(color = "#1e2f4a"),
        axis.text = ggplot2::element_text(color = "#ffffff", face = "bold"),
        axis.title = ggplot2::element_text(color = "#ffffff", face = "bold"),
        plot.title = ggplot2::element_text(color = "#ffffff", face = "bold", size = 16),
        plot.subtitle = ggplot2::element_text(color = "#e8eeff", size = 12)
      )
  }, bg = "#0a1628", height = 380, res = 96)

  output$dl_busca <- downloadHandler(
    filename = function() {
      tk <- if (is.null(busca_res())) "opcoes" else busca_res()$ticker_spot
      sprintf("busca_%s_%s.csv", tk, format(Sys.Date(), "%Y%m%d"))
    },
    content = function(file) {
      req(busca_res())
      utils::write.csv(busca_res()$tabela, file, row.names = FALSE)
    }
  )

  # --- Simulacoes short + hedge ---
  sim_res <- reactiveVal(NULL)
  sim_erro <- reactiveVal(NULL)
  sim_calculando <- reactiveVal(FALSE)

  output$sim_status <- renderUI({
    if (isTRUE(sim_calculando())) {
      return(tags$span(class = "status-ok", "Simulando..."))
    }
    err <- sim_erro()
    if (!is.null(err)) return(tags$span(class = "status-warn", err))
    res <- sim_res()
    if (is.null(res)) {
      return(tags$span("Informe o short e clique em Simular."))
    }
    tags$div(
      tags$span(class = "status-ok", sprintf("%s | %s", res$ticker, format(res$refdate, "%d/%m/%Y"))),
      tags$br(),
      sprintf(
        "Vencimento hedge: %s (%d DU) | Carrego: %s",
        format(res$vencimento, "%d/%m/%Y"),
        res$du,
        res$carrego_fonte
      )
    )
  })

  output$sim_resumo_txt <- renderUI({
    res <- sim_res()
    if (is.null(res)) return(NULL)
  tags$div(
      class = "status-box",
      tags$strong("Entrada de caixa (short): "),
      sprintf("R$ %s", format(round(res$entrada_caixa, 2), big.mark = ".", decimal.mark = ",")),
      tags$br(),
      tags$strong("Notional: "),
      sprintf("R$ %s", format(round(res$notional, 2), big.mark = ".", decimal.mark = ",")),
      tags$br(),
      tags$strong("Aluguel estimado (periodo): "),
      sprintf(
        "R$ %s  (%.2f%% a.a. via %s)",
        format(round(res$aluguel_periodo, 2), big.mark = ".", decimal.mark = ","),
        res$aluguel_aa * 100,
        res$carrego_fonte
      ),
      tags$br(),
      tags$strong("Spot ref.: "),
      sprintf("R$ %.2f | Preco entrada short: R$ %.2f | Qtd: %s",
              res$spot, res$preco_entrada, format(res$quantidade, big.mark = "."))
    )
  })

  observeEvent(input$sim_btn, {
    if (isTRUE(sim_calculando())) return()
    sim_erro(NULL)
    sim_calculando(TRUE)
    on.exit(sim_calculando(FALSE), add = TRUE)

    ticker <- toupper(trimws(input$sim_ticker))
    if (!nzchar(ticker)) {
      sim_erro("Informe um ticker.")
      return()
    }

    preco <- input$sim_preco
    if (is.null(preco) || !is.finite(preco) || preco <= 0) preco <- NULL

    withProgress(message = sprintf("Simulando short %s...", ticker), value = 0, {
      out <- tryCatch(
        simular_short_isolado(
          ticker_spot = ticker,
          quantidade = input$sim_qty,
          preco_entrada = preco,
          du_horizonte = as.integer(input$sim_du),
          modo_carrego = input$sim_carrego,
          cache_dir = DEFAULT_CACHE
        ),
        error = function(e) e
      )
      incProgress(1)
      if (inherits(out, "error")) {
        msg <- limpar_erro_shiny(conditionMessage(out))
        sim_erro(msg)
        showNotification(msg, type = "error", duration = 10)
        return()
      }
      sim_res(out)
      labs <- stats::setNames(
        vapply(out$estrategias, `[[`, "", "nome"),
        vapply(out$estrategias, `[[`, "", "id")
      )
      updateSelectInput(session, "sim_estrategia", choices = labs, selected = labs[1])
      showNotification("Simulacao concluida", type = "message", duration = 3)
    })
  }, ignoreInit = TRUE)

  output$tbl_sim_carrego <- renderDT({
    req(sim_res())
    estilizar_dt(
      DT::datatable(
        sim_res()$comparacao_carrego |>
          dplyr::transmute(
            Fonte = fonte,
            `Taxa a.a.` = sprintf("%.4f%%", taxa_pct),
            Detalhe = detalhe
          ),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE),
        class = "cell-border stripe hover"
      )
    )
  })

  output$tbl_sim_estrategias <- renderDT({
    req(sim_res())
    tb <- sim_res()$tabela_estrategias |>
      dplyr::mutate(
        premio_liquido = round(premio_liquido, 2),
        premio_pago = round(premio_pago, 2),
        premio_recebido = round(premio_recebido, 2),
        pnl_spot_menos_10pct = round(pnl_spot_menos_10pct, 2),
        pnl_spot_mais_10pct = round(pnl_spot_mais_10pct, 2),
        pnl_spot_flat = round(pnl_spot_flat, 2)
      ) |>
      dplyr::select(-id)
    estilizar_dt(
      DT::datatable(
        tb,
        rownames = FALSE,
        options = list(pageLength = 10, scrollX = TRUE),
        colnames = c(
          "Estrategia", "Descricao", "Pernas",
          "Premio liquido (R$)", "Premio pago", "Premio recebido",
          "P&L spot -10%", "P&L spot +10%", "P&L spot flat"
        ),
        class = "cell-border stripe hover"
      )
    )
  })

  output$plot_sim_pnl <- renderPlot({
    req(sim_res(), input$sim_estrategia)
    est <- sim_res()$estrategias[[input$sim_estrategia]]
    req(!is.null(est))
    g <- est$grid
    ggplot2::ggplot(g, ggplot2::aes(x = choque_pct, y = pnl)) +
      ggplot2::geom_hline(yintercept = 0, color = "#6b7c99", linewidth = 0.5) +
      ggplot2::geom_vline(xintercept = 0, color = "#6b7c99", linetype = "dashed", linewidth = 0.5) +
      ggplot2::geom_line(color = "#00c37a", linewidth = 1.2) +
      ggplot2::labs(
        title = est$nome,
        subtitle = "P&L no vencimento vs movimento do spot (inclui aluguel)",
        x = "Choque no spot (%)",
        y = "P&L (R$)"
      ) +
      ggplot2::theme_classic(base_size = 14) +
      ggplot2::theme(
        plot.background = ggplot2::element_rect(fill = "#0a1628", color = NA),
        panel.background = ggplot2::element_rect(fill = "#111f38", color = NA),
        panel.grid.major = ggplot2::element_line(color = "#1e2f4a"),
        axis.text = ggplot2::element_text(color = "#ffffff", face = "bold"),
        axis.title = ggplot2::element_text(color = "#ffffff", face = "bold"),
        plot.title = ggplot2::element_text(color = "#ffffff", face = "bold", size = 16),
        plot.subtitle = ggplot2::element_text(color = "#e8eeff", size = 12)
      )
  }, bg = "#0a1628", height = 380, res = 96)

  output$sim_detalhe_txt <- renderUI({
    req(sim_res(), input$sim_estrategia)
    est <- sim_res()$estrategias[[input$sim_estrategia]]
    req(!is.null(est))
    tags$div(
      class = "status-box",
      tags$strong(est$nome),
      tags$br(),
      est$descricao,
      if (nzchar(est$resumo_pernas)) {
        tagList(tags$br(), tags$span(style = "color:#a8b8d8;", est$resumo_pernas))
      },
      tags$br(),
      sprintf(
        "Premio liquido: R$ %s (pago R$ %s | recebido R$ %s)",
        format(round(est$premio_liquido, 2), big.mark = ".", decimal.mark = ","),
        format(round(est$premio_pago, 2), big.mark = ".", decimal.mark = ","),
        format(round(est$premio_recebido, 2), big.mark = ".", decimal.mark = ",")
      ),
      tags$br(), tags$br(),
      tags$em(est$referencia),
      tags$br(),
      tags$span(
        style = "color:#a8b8d8; font-size:12px;",
        "P&L no vencimento = short + aluguel + opcoes (nao inclui entrada de caixa R$ do short)."
      )
    )
  })

  # --- Radar FVOL ---
  radar_res <- reactiveVal(NULL)
  radar_carteira <- reactiveVal(NULL)
  radar_erro <- reactiveVal(NULL)
  radar_calculando <- reactiveVal(FALSE)

  # Carrega ultimo scan automaticamente ao abrir o app
  observeEvent(TRUE, {
    res <- tryCatch(carregar_radar_latest(RADAR_OUT_DIR), error = function(e) NULL)
    if (!is.null(res)) radar_res(res)
  }, once = TRUE)

  output$radar_tem_dados <- reactive({
    !is.null(radar_res())
  })
  outputOptions(output, "radar_tem_dados", suspendWhenHidden = FALSE)

  output$radar_kpis <- renderUI({
    res <- radar_res()
    if (is.null(res) || is.null(res$ativos)) {
      return(fluidRow(
        column(3, div(class = "kpi-card", div(class = "kpi-label", "Ativos ok"), div(class = "kpi-value", "—"), div(class = "kpi-sub", "rode o scan"))),
        column(3, div(class = "kpi-card", div(class = "kpi-label", "Pct vol mediano"), div(class = "kpi-value", "—"))),
        column(3, div(class = "kpi-card", div(class = "kpi-label", "Setor mais alto"), div(class = "kpi-value", "—"))),
        column(3, div(class = "kpi-card", div(class = "kpi-label", "Ultimo scan"), div(class = "kpi-value", "—")))
      ))
    }
    ok <- res$ativos[res$ativos$status == "ok", , drop = FALSE]
    pct_med <- if (nrow(ok)) round(stats::median(ok$pct_vol, na.rm = TRUE), 0) else NA_real_
    top_setor <- if (!is.null(res$setorial) && nrow(res$setorial)) res$setorial$setor[1] else "—"
    top_pct <- if (!is.null(res$setorial) && nrow(res$setorial)) round(res$setorial$pct_vol_med[1], 0) else NA_real_
    hot <- if (nrow(ok)) {
      i <- which.max(ok$pct_vol)
      sprintf("%s (%.0f)", ok$ticker[i], ok$pct_vol[i])
    } else "—"

    kpi_class_pct <- if (is.finite(pct_med) && pct_med >= 70) {
      "kpi-card kpi-hot"
    } else if (is.finite(pct_med) && pct_med >= 40) {
      "kpi-card kpi-warn"
    } else {
      "kpi-card kpi-accent"
    }

    fluidRow(
      class = "kpi-row",
      column(
        3,
        div(
          class = "kpi-card kpi-accent",
          div(class = "kpi-label", "Ativos ok"),
          div(class = "kpi-value", sprintf("%d / %d", res$n_ok, res$n_carteira)),
          div(class = "kpi-sub", sprintf("%d erros de fit", res$n_erro))
        )
      ),
      column(
        3,
        div(
          class = kpi_class_pct,
          div(class = "kpi-label", "Pct vol mediano"),
          div(class = "kpi-value", if (is.finite(pct_med)) sprintf("%.0f", pct_med) else "—"),
          div(class = "kpi-sub", "historico proprio")
        )
      ),
      column(
        3,
        div(
          class = "kpi-card kpi-hot",
          div(class = "kpi-label", "Setor mais alto"),
          div(class = "kpi-value", style = "font-size:16px;", top_setor),
          div(class = "kpi-sub", if (is.finite(top_pct)) sprintf("pct vol med %.0f", top_pct) else "")
        )
      ),
      column(
        3,
        div(
          class = "kpi-card",
          div(class = "kpi-label", "Nome mais estressado"),
          div(class = "kpi-value", style = "font-size:16px;", hot),
          div(class = "kpi-sub", format(res$gerado_em, "%d/%m %H:%M"))
        )
      )
    )
  })

  output$radar_status <- renderUI({
    if (isTRUE(radar_calculando())) {
      return(tags$span(class = "status-ok", "Rodando radar (pode demorar)..."))
    }
    err <- radar_erro()
    if (!is.null(err)) return(tags$span(class = "status-warn", err))
    cart <- radar_carteira()
    res <- radar_res()
    if (is.null(cart) && is.null(res)) {
      return(tags$span("Pronto para carregar a carteira."))
    }
    tags$div(
      if (!is.null(cart)) {
        tagList(
          tags$span(
            class = "status-ok",
            sprintf("Carteira: %d | %s", nrow(cart), cart$fonte[1])
          ),
          tags$br()
        )
      },
      if (!is.null(res)) {
        tagList(
          sprintf("Scan %s | DU %d", format(res$gerado_em, "%d/%m %H:%M"), res$du_alvo)
        )
      }
    )
  })

  colorir_pct_dt <- function(dt, cols) {
    brks <- seq(0, 100, by = 10)
    clrs <- grDevices::colorRampPalette(c("#0d3b2e", "#1a2d4d", "#5a2a2a"))(length(brks) + 1)
    DT::formatStyle(
      dt,
      columns = cols,
      backgroundColor = DT::styleInterval(brks, clrs),
      color = "#ffffff",
      fontWeight = "bold"
    )
  }

  observeEvent(input$radar_carteira_btn, {
    radar_erro(NULL)
    withProgress(message = "Carregando carteira IBOV...", value = 0.3, {
      cart <- tryCatch(
        obter_carteira_indice(
          indice = "IBOV",
          cache_dir = DEFAULT_CACHE,
          atualizar = isTRUE(input$radar_atualizar_carteira)
        ),
        error = function(e) e
      )
      if (inherits(cart, "error")) {
        msg <- limpar_erro_shiny(conditionMessage(cart))
        radar_erro(msg)
        showNotification(msg, type = "error", duration = 8)
        return()
      }
      top_n <- as.integer(input$radar_top)
      if (!is.finite(top_n) || top_n <= 0) top_n <- NULL
      cart2 <- filtrar_carteira_top(cart, top_n)
      radar_carteira(cart2)
      showNotification(
        sprintf("Carteira pronta: %d tickers", nrow(cart2)),
        type = "message",
        duration = 4
      )
    })
  }, ignoreInit = TRUE)

  observeEvent(input$radar_load_btn, {
    radar_erro(NULL)
    res <- tryCatch(carregar_radar_latest(RADAR_OUT_DIR), error = function(e) e)
    if (inherits(res, "error") || is.null(res)) {
      radar_erro("Nenhum scan salvo em outputs_radar/.")
      return()
    }
    radar_res(res)
    showNotification("Ultimo radar carregado.", type = "message", duration = 3)
  }, ignoreInit = TRUE)

  observeEvent(input$radar_btn, {
    if (isTRUE(radar_calculando())) {
      showNotification("Radar ja em andamento.", type = "warning", duration = 3)
      return()
    }
    radar_erro(NULL)
    radar_calculando(TRUE)
    on.exit(radar_calculando(FALSE), add = TRUE)

    cart <- radar_carteira()
    if (is.null(cart) || !nrow(cart)) {
      cart <- tryCatch(
        obter_carteira_indice(
          indice = "IBOV",
          cache_dir = DEFAULT_CACHE,
          atualizar = isTRUE(input$radar_atualizar_carteira)
        ),
        error = function(e) e
      )
      if (inherits(cart, "error")) {
        radar_erro(limpar_erro_shiny(conditionMessage(cart)))
        return()
      }
      top_n <- as.integer(input$radar_top)
      if (!is.finite(top_n) || top_n <= 0) top_n <- NULL
      cart <- filtrar_carteira_top(cart, top_n)
      radar_carteira(cart)
    } else {
      # reaplica top se usuario mudou o select
      full <- tryCatch(
        obter_carteira_indice(
          indice = "IBOV",
          cache_dir = DEFAULT_CACHE,
          atualizar = FALSE
        ),
        error = function(e) cart
      )
      top_n <- as.integer(input$radar_top)
      if (!is.finite(top_n) || top_n <= 0) top_n <- NULL
      if (!inherits(full, "error") && nrow(full) > 0) {
        cart <- filtrar_carteira_top(full, top_n)
        radar_carteira(cart)
      }
    }

    calc_fn <- function(row, atualizar_cache) {
      calcular_snapshot_isolado(
        ticker = row$ticker[1],
        peso = row$peso[1],
        setor = row$setor[1],
        periodo_inicio = input$radar_periodo_de,
        periodo_fim = Sys.Date(),
        data_inicio_cache = input$data_inicio_cache,
        du_alvo = as.integer(input$radar_du),
        du_tol = as.integer(input$du_tol),
        janela_mm = as.integer(input$janela_mm),
        carrego = input$radar_carrego,
        usar_apenas_vencimento_mensal = isTRUE(input$venc_mensal),
        cache_dir = DEFAULT_CACHE,
        atualizar_cache = atualizar_cache
      )
    }

    withProgress(message = "Radar FVOL...", value = 0, {
      out <- tryCatch(
        rodar_radar_fvol(
          carteira = cart,
          periodo_inicio = input$radar_periodo_de,
          periodo_fim = Sys.Date(),
          data_inicio_cache = input$data_inicio_cache,
          du_alvo = as.integer(input$radar_du),
          du_tol = as.integer(input$du_tol),
          janela_mm = as.integer(input$janela_mm),
          carrego = input$radar_carrego,
          usar_apenas_vencimento_mensal = isTRUE(input$venc_mensal),
          cache_dir = DEFAULT_CACHE,
          atualizar_cache_inicial = isTRUE(input$radar_atualizar_cache),
          out_dir = RADAR_OUT_DIR,
          progress_fn = function(p, msg) {
            incProgress(amount = 0, detail = msg)
            # shiny progress value is absolute-ish via set — use setProgress if available
            if (requireNamespace("shiny", quietly = TRUE)) {
              shiny::setProgress(value = min(0.95, max(0.05, p)), detail = msg)
            }
          },
          calc_fn = calc_fn
        ),
        error = function(e) e
      )
      if (inherits(out, "error")) {
        msg <- limpar_erro_shiny(conditionMessage(out))
        radar_erro(msg)
        showNotification(msg, type = "error", duration = 10)
        return()
      }
      radar_res(out)
      showNotification(
        sprintf("Radar ok: %d/%d ativos", out$n_ok, out$n_carteira),
        type = "message",
        duration = 5
      )
    })
  }, ignoreInit = TRUE)

  output$tbl_radar_ativos <- renderDT({
    req(radar_res())
    tb <- radar_res()$ativos |>
      dplyr::transmute(
        Ticker = ticker,
        Setor = setor,
        `Peso %` = round(peso * 100, 2),
        Data = refdate,
        DU = du,
        `Vol ATM %` = round(vol_atm * 100, 2),
        `Pct Vol` = round(pct_vol, 1),
        `Pct Vol xsec` = round(pct_vol_xsec, 1),
        `Skew %` = round(skew * 100, 2),
        `Pct Skew` = round(pct_skew, 1),
        `Smile %` = round(smile * 100, 2),
        `Pct Smile` = round(pct_smile, 1),
        `Diff Vol pp` = round(diff_vol_media * 100, 2),
        `Premio IV pp` = round(premio_iv * 100, 2),
        R2 = round(r2, 2),
        Pontos = n_points,
        Status = status
      ) |>
      dplyr::arrange(dplyr::desc(`Pct Vol`))
    dt <- DT::datatable(
      tb,
      rownames = FALSE,
      options = list(pageLength = 20, scrollX = TRUE, order = list(list(6, "desc"))),
      class = "cell-border stripe hover"
    )
    dt <- estilizar_dt(dt)
    colorir_pct_dt(dt, c("Pct Vol", "Pct Vol xsec", "Pct Skew", "Pct Smile"))
  })

  output$tbl_radar_setores <- renderDT({
    req(radar_res())
    tb <- radar_res()$setorial |>
      dplyr::transmute(
        Setor = setor,
        N = n_ok,
        `Peso %` = round(peso * 100, 2),
        `Vol med %` = round(vol_atm_med * 100, 2),
        `Pct Vol` = round(pct_vol_med, 1),
        `Pct Vol xsec` = round(pct_vol_xsec_med, 1),
        `Skew med %` = round(skew_med * 100, 2),
        `Pct Skew` = round(pct_skew_med, 1),
        `Smile med %` = round(smile_med * 100, 2),
        `Pct Smile` = round(pct_smile_med, 1)
      )
    dt <- DT::datatable(
      tb,
      rownames = FALSE,
      options = list(dom = "t", paging = FALSE, scrollX = TRUE),
      class = "cell-border stripe hover"
    )
    dt <- estilizar_dt(dt)
    colorir_pct_dt(dt, c("Pct Vol", "Pct Vol xsec", "Pct Skew", "Pct Smile"))
  })

  output$plot_radar_top <- renderPlot({
    req(radar_res())
    p <- radar_res()$graficos$top_pct_vol
    if (is.null(p)) {
      plot.new()
      text(0.5, 0.5, "Sem ativos ok para o grafico.", col = "white")
    } else {
      print(p)
    }
  }, bg = "#0a1628", height = 380, res = 96)

  output$plot_radar_heatmap <- renderPlot({
    req(radar_res())
    p <- radar_res()$graficos$heatmap
    if (is.null(p)) {
      plot.new()
      text(0.5, 0.5, "Sem dados setoriais.", col = "white")
    } else {
      print(p)
    }
  }, bg = "#0a1628", height = 420, res = 96)

  output$dl_radar_ativos <- downloadHandler(
    filename = function() {
      sprintf("radar_fvol_%s.csv", format(Sys.Date(), "%Y%m%d"))
    },
    content = function(file) {
      req(radar_res())
      utils::write.csv(radar_res()$ativos, file, row.names = FALSE)
    }
  )
}

shinyApp(ui, server)
