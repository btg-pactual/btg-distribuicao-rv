# =============================================================================
# Busca historica de opcoes B3 (COTAHIST / rb3)
# =============================================================================

BUSCA_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
if (!exists("configurar_cache_rb3", mode = "function")) {
  source(file.path(BUSCA_DIR, "config_mr_derivs.R"), local = FALSE)
}
configurar_cache_rb3(DEFAULT_RB3_CACHE_BUSCA)

suppressPackageStartupMessages({
  if (!"package:rb3" %in% search()) library(rb3)
  if (!"package:dplyr" %in% search()) library(dplyr)
  if (!"package:stringr" %in% search()) library(stringr)
  if (!"package:bizdays" %in% search()) library(bizdays)
  if (!"package:lubridate" %in% search()) library(lubridate)
})

#' Baixa COTAHIST faltante no cache rb3 (yearly + daily do ano corrente).
#' @param forcar_desde se informado, reapaga o controle apos essa data e rebaixa com force_download
#' @return list(n_novas, ultima_antes, ultima_depois, mensagem)
atualizar_cache_cotahist <- function(
  cache_dir,
  data_inicio = as.Date("2020-01-01"),
  data_fim = Sys.Date(),
  cal = "Brazil/ANBIMA",
  quiet = FALSE,
  forcar_desde = NULL,
  chunk_size = 5L
) {
  configurar_cache_rb3(cache_dir)
  if (!"package:rb3" %in% search()) library(rb3)

  bizdays::load_builtin_calendars()
  if (!cal %in% ls(bizdays::calendars())) stop("Calendario nao carregado: ", cal)

  data_inicio <- as.Date(data_inicio)
  data_fim <- as.Date(bizdays::preceding(as.Date(data_fim), cal))
  if (data_inicio > data_fim) stop("data_inicio > data_fim")

  ultima_antes <- tryCatch(ultima_data_cotahist(cache_dir), error = function(e) as.Date(NA))

  ctrl_file <- file.path(cache_dir, "datas_baixadas.rds")
  datas_baixadas <- if (file.exists(ctrl_file)) readRDS(ctrl_file) else as.Date(character(0))

  # Remove marcas falsas: so confia no que esta <= ultima data REAL do DuckDB
  if (!is.na(ultima_antes)) {
    datas_baixadas <- datas_baixadas[datas_baixadas <= ultima_antes]
  }
  if (!is.null(forcar_desde) && !is.na(as.Date(forcar_desde))) {
    corte <- as.Date(forcar_desde)
    datas_baixadas <- datas_baixadas[datas_baixadas <= corte]
    if (!quiet) {
      message(sprintf(">>> Forcando redownload apos %s", format(corte, "%d/%m/%Y")))
    }
  }
  saveRDS(sort(unique(datas_baixadas)), ctrl_file)

  todas_datas <- bizdays::bizseq(data_inicio, data_fim, cal)
  datas_novas <- todas_datas[!todas_datas %in% datas_baixadas]
  if (!is.na(ultima_antes)) {
    datas_apos <- todas_datas[todas_datas > ultima_antes]
    datas_novas <- sort(unique(c(datas_novas, datas_apos)))
  }
  if (!is.null(forcar_desde) && !is.na(as.Date(forcar_desde))) {
    datas_novas <- sort(unique(c(
      datas_novas,
      todas_datas[todas_datas > as.Date(forcar_desde)]
    )))
  }
  ano_atual <- lubridate::year(data_fim)

  if (!length(datas_novas)) {
    msg <- if (is.na(ultima_antes)) {
      "Cache vazio e sem datas novas na janela — confira calendario/rede."
    } else {
      sprintf("Cache ja atualizado ate %s.", format(ultima_antes, "%d/%m/%Y"))
    }
    return(list(
      n_novas = 0L,
      ultima_antes = ultima_antes,
      ultima_depois = ultima_antes,
      mensagem = msg
    ))
  }

  anos_hist <- unique(lubridate::year(datas_novas))
  anos_hist <- anos_hist[anos_hist < ano_atual]
  if (length(anos_hist) > 0) {
    if (!quiet) message(sprintf(">>> COTAHIST anual: %s", paste(anos_hist, collapse = ", ")))
    rb3::fetch_marketdata("b3-cotahist-yearly", year = anos_hist, force_download = TRUE)
  }

  datas_corrente <- datas_novas[lubridate::year(datas_novas) == ano_atual]
  if (length(datas_corrente) > 0) {
    if (!quiet) {
      message(sprintf(
        ">>> COTAHIST daily: %d datas (%s a %s)",
        length(datas_corrente),
        format(min(datas_corrente), "%d/%m/%Y"),
        format(max(datas_corrente), "%d/%m/%Y")
      ))
    }
    # rb3/cli progress quebra dentro do Shiny (bar$shiny_progress$set)
    old_cli <- options(
      cli.progress_show_after = Inf,
      cli.progress_handlers = "none"
    )
    on.exit(options(old_cli), add = TRUE)
    chunks <- split(datas_corrente, ceiling(seq_along(datas_corrente) / max(1L, as.integer(chunk_size))))
    for (i in seq_along(chunks)) {
      if (!quiet) {
        message(sprintf(
          ">>> chunk %d/%d: %s .. %s",
          i, length(chunks),
          format(min(chunks[[i]]), "%d/%m/%Y"),
          format(max(chunks[[i]]), "%d/%m/%Y")
        ))
      }
      tryCatch(
        rb3::fetch_marketdata(
          "b3-cotahist-daily",
          refdate = chunks[[i]],
          throttle = TRUE,
          force_download = TRUE
        ),
        error = function(e) {
          message("  ERRO chunk COTAHIST: ", conditionMessage(e))
        }
      )
    }
  }

  ultima_depois <- tryCatch(ultima_data_cotahist(cache_dir), error = function(e) ultima_antes)
  # So grava no controle datas ate a ultima REALMENTE presente no DuckDB
  if (!is.na(ultima_depois)) {
    datas_baixadas <- sort(unique(c(
      datas_baixadas[datas_baixadas <= ultima_depois],
      todas_datas[todas_datas <= ultima_depois]
    )))
  }
  saveRDS(datas_baixadas, ctrl_file)

  list(
    n_novas = length(datas_novas),
    ultima_antes = ultima_antes,
    ultima_depois = ultima_depois,
    mensagem = sprintf(
      "Cache: pediu +%d | antes %s | agora %s%s",
      length(datas_novas),
      format(ultima_antes, "%d/%m/%Y"),
      format(ultima_depois, "%d/%m/%Y"),
      if (!is.na(ultima_depois) && ultima_depois < data_fim - 2) {
        " (ainda atrasado vs B3/hoje)"
      } else {
        ""
      }
    )
  )
}

#' Ultima data disponivel no COTAHIST em cache (yearly + daily).
#' Retorna NA se o DuckDB estiver vazio / inacessivel (nao inventa Sys.Date()).
ultima_data_cotahist <- function(cache_dir) {
  configurar_cache_rb3(cache_dir)
  max_d <- as.Date(character(0))
  for (tipo in c("yearly", "daily")) {
    ch <- tryCatch(rb3::cotahist_get(type = tipo), error = function(e) NULL)
    if (is.null(ch)) next
    m <- tryCatch(
      ch |>
        dplyr::summarise(mx = max(refdate, na.rm = TRUE)) |>
        dplyr::collect() |>
        dplyr::pull(mx),
      error = function(e) as.Date(NA)
    )
    if (length(m) && !is.na(m[[1]])) max_d <- c(max_d, as.Date(m[[1]]))
  }
  if (!length(max_d)) return(as.Date(NA))
  max(max_d, na.rm = TRUE)
}

#' Resumo rapido do cache (para status UI / sanity).
diagnostico_cache_cotahist <- function(cache_dir) {
  configurar_cache_rb3(cache_dir)
  ult <- tryCatch(ultima_data_cotahist(cache_dir), error = function(e) as.Date(NA))
  ctrl_file <- file.path(cache_dir, "datas_baixadas.rds")
  n_ctrl <- if (file.exists(ctrl_file)) {
    length(readRDS(ctrl_file))
  } else {
    0L
  }
  lag <- if (!is.na(ult)) as.integer(Sys.Date() - ult) else NA_integer_
  list(
    cache_dir = cache_dir,
    ultima_duckdb = ult,
    lag_dias = lag,
    n_datas_controle = n_ctrl,
    ok = !is.na(ult) && is.finite(lag) && lag <= 5L,
    mensagem = if (is.na(ult)) {
      "DuckDB sem COTAHIST — rode Atualizar cache."
    } else if (lag > 5L) {
      sprintf("COTAHIST ate %s (~%d dias atras).", format(ult, "%Y-%m-%d"), lag)
    } else {
      sprintf("COTAHIST ok ate %s.", format(ult, "%Y-%m-%d"))
    }
  )
}

periodo_padrao_busca <- function(cache_dir, dias = 7L) {
  fim <- ultima_data_cotahist(cache_dir)
  if (is.na(fim)) fim <- Sys.Date()
  list(
    inicio = fim - (as.integer(dias) - 1L),
    fim = fim
  )
}

ultima_data_ticker <- function(ticker_spot, cache_dir) {
  configurar_cache_rb3(cache_dir)
  ticker_spot <- toupper(trimws(ticker_spot))
  max_d <- as.Date(character(0))
  for (tipo in c("yearly", "daily")) {
    ch <- tryCatch(rb3::cotahist_get(type = tipo), error = function(e) NULL)
    if (is.null(ch)) next
    m <- ch |>
      dplyr::filter(symbol == ticker_spot) |>
      dplyr::summarise(mx = max(refdate, na.rm = TRUE)) |>
      dplyr::collect() |>
      dplyr::pull(mx)
    if (length(m) && !is.na(m)) max_d <- c(max_d, as.Date(m))
  }
  if (!length(max_d)) return(as.Date(NA))
  max(max_d, na.rm = TRUE)
}

#' Ajusta periodo ao intervalo disponivel no cache rb3.
ajustar_periodo_busca <- function(periodo_inicio, periodo_fim, cache_dir, ticker_spot = NULL) {
  ini <- as.Date(periodo_inicio)
  fim <- as.Date(periodo_fim)
  if (ini > fim) stop("Data inicial maior que data final.")
  fim_disp <- ultima_data_cotahist(cache_dir)
  if (!is.null(ticker_spot) && nzchar(ticker_spot)) {
    fim_tk <- ultima_data_ticker(ticker_spot, cache_dir)
    if (!is.na(fim_tk)) fim_disp <- fim_tk
  }
  fim_adj <- min(fim, fim_disp)
  ini_adj <- ini
  if (ini_adj > fim_adj) {
    ini_adj <- fim_adj - 6L
  }
  list(
    inicio = ini_adj,
    fim = fim_adj,
    ultima_cache = fim_disp,
    ajustado = !identical(ini, ini_adj) || !identical(fim, fim_adj)
  )
}

prefixo_limite_superior <- function(x) {
  chars <- strsplit(x, "", fixed = TRUE)[[1]]
  i <- length(chars)
  chars[i] <- rawToChar(as.raw(utf8ToInt(chars[i]) + 1L))
  paste(chars, collapse = "")
}

tipo_opcao_symbol <- function(symbol) {
  dplyr::case_when(
    stringr::str_detect(symbol, "^[A-Z]{4}[A-L]") ~ "call",
    stringr::str_detect(symbol, "^[A-Z]{4}[M-X]") ~ "put",
    TRUE ~ NA_character_
  )
}

carregar_spot_opcoes <- function(
  ticker_spot,
  prefixo_opcoes = NULL,
  periodo_inicio,
  periodo_fim,
  cache_dir,
  cal = "Brazil/ANBIMA"
) {
  ticker_spot <- toupper(trimws(ticker_spot))
  prefixo <- if (is.null(prefixo_opcoes) || !nzchar(prefixo_opcoes)) {
    substr(ticker_spot, 1, 4)
  } else {
    toupper(prefixo_opcoes)
  }
  limite <- prefixo_limite_superior(prefixo)
  data_ini <- as.Date(periodo_inicio)
  data_fim <- as.Date(periodo_fim)

  configurar_cache_rb3(cache_dir)

  bizdays::load_builtin_calendars()
  if (!cal %in% ls(bizdays::calendars())) stop("Calendario nao carregado: ", cal)
  bizdays::bizdays.options$set(default.calendar = cal)

  ch_y <- tryCatch(rb3::cotahist_get(type = "yearly"), error = function(e) NULL)
  ch_d <- tryCatch(rb3::cotahist_get(type = "daily"), error = function(e) NULL)

  puxa_spot <- function(ch) {
    if (is.null(ch)) return(NULL)
    ch |>
      dplyr::filter(
        refdate >= data_ini,
        refdate <= data_fim,
        symbol == ticker_spot
      ) |>
      dplyr::collect()
  }

  puxa_opcoes <- function(ch) {
    if (is.null(ch)) return(NULL)
    ch |>
      dplyr::filter(
        refdate >= data_ini,
        refdate <= data_fim,
        symbol >= prefixo,
        symbol < limite
      ) |>
      dplyr::collect() |>
      dplyr::filter(stringr::str_detect(symbol, paste0("^", prefixo)))
  }

  spot <- dplyr::bind_rows(puxa_spot(ch_y), puxa_spot(ch_d)) |>
    dplyr::distinct(refdate, symbol, .keep_all = TRUE)

  opcoes <- dplyr::bind_rows(puxa_opcoes(ch_y), puxa_opcoes(ch_d)) |>
    dplyr::distinct(refdate, symbol, .keep_all = TRUE)

  list(
    spot = spot,
    opcoes = opcoes,
    ticker_spot = ticker_spot,
    prefixo = prefixo
  )
}

#' Filtra opcoes e retorna precos diarios no periodo.
buscar_opcoes_historico <- function(
  ticker_spot,
  tipo = c("call", "put"),
  periodo_inicio,
  periodo_fim,
  dist_strike_max = 0.05,
  vol_min = 1,
  du_alvo = 22,
  du_tol = 5,
  maturity_date = NULL,
  prefixo_opcoes = NULL,
  cache_dir,
  cal = "Brazil/ANBIMA",
  atualizar_cache = FALSE,
  data_inicio_cache = as.Date("2020-01-01")
) {
  tipo <- match.arg(tipo)
  dist_strike_max <- as.numeric(dist_strike_max)
  if (dist_strike_max > 1) dist_strike_max <- dist_strike_max / 100
  venc_filtro <- maturity_date
  du_alvo <- as.integer(du_alvo)
  du_tol <- as.integer(du_tol)

  cache_info <- NULL
  if (isTRUE(atualizar_cache)) {
    cache_info <- atualizar_cache_cotahist(
      cache_dir = cache_dir,
      data_inicio = as.Date(data_inicio_cache),
      data_fim = max(as.Date(periodo_fim), Sys.Date()),
      cal = cal
    )
  }

  per <- ajustar_periodo_busca(periodo_inicio, periodo_fim, cache_dir, ticker_spot = ticker_spot)

  dados <- carregar_spot_opcoes(
    ticker_spot = ticker_spot,
    prefixo_opcoes = prefixo_opcoes,
    periodo_inicio = per$inicio,
    periodo_fim = per$fim,
    cache_dir = cache_dir,
    cal = cal
  )

  if (nrow(dados$spot) == 0) {
    stop(
      "Sem cotacao spot para ", dados$ticker_spot,
      " entre ", format(per$inicio, "%d/%m/%Y"), " e ", format(per$fim, "%d/%m/%Y"),
      ". Ultima data no cache: ", format(per$ultima_cache, "%d/%m/%Y"), "."
    )
  }
  if (nrow(dados$opcoes) == 0) {
    stop("Sem opcoes para prefixo ", dados$prefixo, " no periodo.")
  }

  spot_diario <- dados$spot |>
    dplyr::select(refdate, spot = close)

  op <- dados$opcoes |>
    dplyr::mutate(
      type = tipo_opcao_symbol(symbol),
      maturity_date = as.Date(.data$maturity_date)
    ) |>
    dplyr::filter(
      !is.na(type),
      type == !!tipo,
      !is.na(maturity_date),
      strike_price > 0,
      close > 0,
      dplyr::coalesce(volume, 0) >= vol_min
    ) |>
    dplyr::left_join(spot_diario, by = "refdate") |>
    dplyr::filter(!is.na(spot), spot > 0) |>
    dplyr::mutate(
      dist_strike_pct = abs(strike_price / spot - 1),
      biz_days = bizdays::bizdays(
        refdate,
        bizdays::following(maturity_date, cal),
        cal
      )
    ) |>
    dplyr::filter(
      is.finite(dist_strike_pct),
      dist_strike_pct <= dist_strike_max
    )

  if (nrow(op) == 0) {
    stop("Nenhuma opcao apos filtros de tipo, volume e distancia ao strike.")
  }

  vencimentos <- op |>
    dplyr::distinct(refdate, maturity_date, biz_days) |>
    dplyr::mutate(dist_du = abs(biz_days - du_alvo)) |>
    dplyr::group_by(maturity_date, biz_days) |>
    dplyr::summarise(dist_du = min(dist_du), .groups = "drop") |>
    dplyr::arrange(dist_du, maturity_date)

  du_aviso <- NULL

  if (!is.null(venc_filtro) && nzchar(as.character(venc_filtro))) {
    alvo_venc <- as.Date(venc_filtro)
    op <- op |> dplyr::filter(maturity_date == alvo_venc)
    if (nrow(op) == 0) {
      venc_disp <- vencimentos |>
        dplyr::arrange(dist_du, maturity_date) |>
        dplyr::slice_head(n = 5)
      labs <- paste0(
        format(venc_disp$maturity_date, "%d/%m/%Y"),
        " (", venc_disp$biz_days, "du)"
      )
      stop(
        "Sem negocios para vencimento ", format(alvo_venc, "%d/%m/%Y"),
        ". Proximos: ", paste(labs, collapse = ", ")
      )
    }
  } else {
    op_janela <- op |>
      dplyr::filter(
        biz_days >= max(1L, du_alvo - du_tol),
        biz_days <= (du_alvo + du_tol)
      )
    if (nrow(op_janela) == 0L) {
      du_aviso <- sprintf(
        "Nenhum vencimento em %d (+/-%d) DU; usando o mais proximo do alvo.",
        du_alvo, du_tol
      )
      op_janela <- op
    }
    venc_por_dia <- op_janela |>
      dplyr::distinct(refdate, maturity_date, biz_days) |>
      dplyr::mutate(dist_du = abs(biz_days - du_alvo)) |>
      dplyr::group_by(refdate) |>
      dplyr::slice_min(order_by = dist_du, n = 1, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::select(refdate, maturity_date)

    op <- op |>
      dplyr::inner_join(venc_por_dia, by = c("refdate", "maturity_date"))
  }

  tabela <- op |>
    dplyr::transmute(
      refdate,
      symbol,
      type,
      strike = strike_price,
      vencimento = maturity_date,
      du = biz_days,
      dist_strike_pct = round(dist_strike_pct * 100, 2),
      preco = close,
      volume = volume,
      spot,
      moneyness = dplyr::if_else(type == "call", spot / strike_price, strike_price / spot)
    ) |>
    dplyr::arrange(dplyr::desc(refdate), dist_strike_pct, dplyr::desc(volume))

  simbolos <- tabela |>
    dplyr::group_by(symbol, strike, vencimento) |>
    dplyr::summarise(
      vol_total = sum(volume, na.rm = TRUE),
      n_dias = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(vol_total))

  list(
    ticker_spot = dados$ticker_spot,
    prefixo = dados$prefixo,
    tipo = tipo,
    tabela = tabela,
    vencimentos = vencimentos,
    simbolos = simbolos,
    n_linhas = nrow(tabela),
    n_simbolos = nrow(simbolos),
    n_dias = dplyr::n_distinct(tabela$refdate),
    periodo_inicio = per$inicio,
    periodo_fim = per$fim,
    periodo_ajustado = per$ajustado,
    periodo_pedido_inicio = as.Date(periodo_inicio),
    periodo_pedido_fim = as.Date(periodo_fim),
    ultima_cache = per$ultima_cache,
    cache_update = cache_info,
    du_aviso = du_aviso
  )
}
