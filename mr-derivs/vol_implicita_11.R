# =============================================================================
# VOL IMPLÍCITA B3 — rb3 (cotações) + BCB SGS (Selic) + oplib (BSM)
# =============================================================================

# =============================================================================
# LIMPA SESSAO (evita acumular dados de rodadas anteriores)
# =============================================================================
if (isTRUE(getOption("vol_implicita.limpar_sessao", TRUE))) {
rm(list = ls())
graphics.off()
invisible(gc())
}

# =============================================================================
# 0a. CONFIG + CACHE RB3 (precisa vir antes de library(rb3))
# =============================================================================
VI_SCRIPT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
source(file.path(VI_SCRIPT_DIR, "config_mr_derivs.R"), local = FALSE)
configurar_cache_rb3(DEFAULT_RB3_CACHE)

suppressPackageStartupMessages({
  library(rb3)
  library(bizdays)
  library(dplyr)
  library(ggplot2)
  library(stringr)
  library(lubridate)
  library(glue)
  library(scales)
  library(patchwork)
  library(zoo)
  library(oplib)
  library(httr)
  library(jsonlite)
  library(grid)
  library(gridExtra)
})

source(file.path(VI_SCRIPT_DIR, "btc_taxas.R"), local = FALSE)
source(file.path(VI_SCRIPT_DIR, "carrego_pcp.R"), local = FALSE)
if (!exists("atualizar_cache_cotahist", mode = "function")) {
  source(file.path(VI_SCRIPT_DIR, "busca_opcoes.R"), local = FALSE)
}

#' Vol realizada forward: stdev dos retornos nos proximos N dias uteis apos refdate.
calc_vol_realizada_forward <- function(price_df, janela_biz, cal) {
  price_df <- price_df |>
    dplyr::arrange(refdate) |>
    dplyr::mutate(log_ret = log(close / dplyr::lag(close)))

  dates <- price_df$refdate
  log_ret <- price_df$log_ret
  n <- length(dates)
  vol_fwd <- rep(NA_real_, n)

  for (i in seq_len(n)) {
    d_fim <- bizdays::add.bizdays(dates[i], janela_biz, cal)
    idx <- which(dates > dates[i] & dates <= d_fim)
    if (length(idx) < 2) next
    rets <- log_ret[idx]
    rets <- rets[!is.na(rets)]
    if (length(rets) < 2) next
    vol_fwd[i] <- stats::sd(rets) * sqrt(252)
  }

  tibble::tibble(refdate = dates, vol_realizada_fwd = vol_fwd)
}

rodar_vol_implicita <- function(
  ativo = "VALE",
  prefixo_opcoes = NULL,
  ticker_spot = NULL,
  periodo_inicio = as.Date("2026-01-01"),
  periodo_fim = as.Date("2026-05-01"),
  data_inicio = as.Date("2020-01-01"),
  janela_mm = 21,
  janela_fwd = NULL,
  du_alvo = 22,
  du_tol = 10,
  min_pontos_fvol = 5,
  usar_apenas_vencimento_mensal = TRUE,
  atm_band = 0.03,
  iv_atm_min = 0.05,
  iv_atm_max = 1.00,
  carrego = c("pcp", "btc", "hibrido"),
  max_fw_rel_pcp = 0.15,
  cache_dir = DEFAULT_RB3_CACHE,
  out_dir = getwd(),
  atualizar_cache = TRUE,
  calendario = "Brazil/ANBIMA",
  largura = 22,
  altura = 14,
  dpi = 120,
  incluir_tabela_grafico = TRUE,
  salvar_png = TRUE,
  retorno_leve = FALSE
) {
ATIVO          <- toupper(ativo)
ATIVO_PREFIXO  <- if (!is.null(prefixo_opcoes)) toupper(prefixo_opcoes) else if (!is.null(ticker_spot)) substr(toupper(ticker_spot), 1, 4) else substr(ATIVO, 1, 4)
prefixo_limite_superior <- function(x) {
  chars <- strsplit(x, "", fixed = TRUE)[[1]]
  i <- length(chars)
  chars[i] <- rawToChar(as.raw(utf8ToInt(chars[i]) + 1L))
  paste(chars, collapse = "")
}
ATIVO_PREFIXO_LIMITE <- prefixo_limite_superior(ATIVO_PREFIXO)
TICKER_SPOT    <- if (is.null(ticker_spot)) NULL else toupper(ticker_spot)
JANELA_MM      <- janela_mm
JANELA_FWD     <- if (is.null(janela_fwd)) du_alvo else janela_fwd
DATA_INICIO    <- as.Date(data_inicio)
PERIODO_INICIO <- if (is.null(periodo_inicio)) NULL else as.Date(periodo_inicio)
PERIODO_FIM    <- if (is.null(periodo_fim)) NULL else as.Date(periodo_fim)
DU_ALVO        <- du_alvo
DU_TOL         <- du_tol
MIN_PONTOS_FVOL <- min_pontos_fvol
USAR_APENAS_VENCIMENTO_MENSAL <- usar_apenas_vencimento_mensal
ATM_BAND       <- atm_band
IV_ATM_MIN     <- iv_atm_min
IV_ATM_MAX     <- iv_atm_max
MODO_CARREGO   <- match.arg(carrego)
MAX_FW_REL_PCP <- max_fw_rel_pcp
CAL            <- calendario

if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(R_USER_CACHE_DIR = cache_dir)
options(rb3.cachedir = cache_dir)

# =============================================================================
# 0. CACHE RB3 (antes de qualquer chamada rb3)
# =============================================================================
message(sprintf(">>> Cache rb3: %s", getOption("rb3.cachedir")))
message(sprintf(">>> Ativo: %s | prefixo opcoes: %s | periodo: %s a %s | DU alvo: %s +/- %s",
                ATIVO, ATIVO_PREFIXO,
                ifelse(is.null(PERIODO_INICIO), "inicio", as.character(PERIODO_INICIO)),
                ifelse(is.null(PERIODO_FIM), "hoje", as.character(PERIODO_FIM)),
                DU_ALVO, DU_TOL))
message(sprintf(">>> Vencimentos: %s", ifelse(USAR_APENAS_VENCIMENTO_MENSAL, "mensais apenas", "mensais + semanais")))
message(sprintf(">>> Carrego BSM: %s", MODO_CARREGO))

# =============================================================================
# 2. CALENDÁRIO + DATA FIM
# =============================================================================
bizdays::load_builtin_calendars()
if (!CAL %in% ls(bizdays::calendars())) stop("Calendario nao carregado: ", CAL)
bizdays.options$set(default.calendar = CAL)
DATA_FIM <- bizdays::preceding(Sys.Date(), CAL)
message(sprintf(">>> Calendario: %s", CAL))
message(sprintf(">>> Data fim: %s", DATA_FIM))
DATA_CALC_INICIO <- if (!is.null(PERIODO_INICIO)) PERIODO_INICIO else DATA_INICIO
DATA_CALC_FIM    <- if (!is.null(PERIODO_FIM))    min(PERIODO_FIM, DATA_FIM) else DATA_FIM
message(sprintf(">>> Janela calculada: %s a %s", DATA_CALC_INICIO, DATA_CALC_FIM))

# =============================================================================
# 3. DOWNLOAD COTAHIST (delegado a busca_opcoes::atualizar_cache_cotahist)
# =============================================================================
# Sync so marca datas ate a ultima REAL no DuckDB (evita falso "atualizado").
if (isTRUE(atualizar_cache)) {
  if (exists("atualizar_cache_cotahist", mode = "function")) {
    cache_info_iv <- with_cli_quiet(
      atualizar_cache_cotahist(
        cache_dir = cache_dir,
        data_inicio = DATA_INICIO,
        data_fim = DATA_FIM,
        cal = CAL,
        quiet = FALSE
      )
    )
    message(">>> ", cache_info_iv$mensagem)
  } else {
    message(">>> Aviso: atualizar_cache_cotahist ausente — source busca_opcoes.R")
  }
} else {
  message(">>> COTAHIST: update desligado (atualizar_cache=FALSE).")
}

# =============================================================================
# 4. SELIC DIÁRIA do BCB (substitui yield curve do rb3 que está quebrada)
# =============================================================================
message(">>> Baixando Selic diária do BCB SGS...")

cache_selic_file <- file.path(cache_dir, "selic_sgs11_cache.rds")

ler_selic_json <- function() {
  url_bcb <- sprintf(
    "https://api.bcb.gov.br/dados/serie/bcdata.sgs.11/dados?formato=json&dataInicial=%s&dataFinal=%s",
    format(DATA_INICIO, "%d/%m/%Y"),
    format(DATA_FIM,    "%d/%m/%Y")
  )
  resp <- httr::GET(
    url_bcb,
    httr::accept_json(),
    httr::user_agent("vol-implicita-b3-r")
  )
  httr::stop_for_status(resp)
  txt <- httr::content(resp, "text", encoding = "UTF-8")
  if (grepl("^\\s*<", txt)) stop("BCB retornou XML/HTML")
  jsonlite::fromJSON(txt)
}

ler_selic_csv <- function() {
  url_bcb <- sprintf(
    "https://api.bcb.gov.br/dados/serie/bcdata.sgs.11/dados?formato=csv&dataInicial=%s&dataFinal=%s",
    format(DATA_INICIO, "%d/%m/%Y"),
    format(DATA_FIM,    "%d/%m/%Y")
  )
  resp <- httr::GET(
    url_bcb,
    httr::user_agent("vol-implicita-b3-r")
  )
  httr::stop_for_status(resp)
  txt <- httr::content(resp, "text", encoding = "UTF-8")
  if (grepl("^\\s*<", txt)) stop("BCB CSV retornou XML/HTML")
  utils::read.csv2(text = txt, stringsAsFactors = FALSE)
}

selic_raw <- tryCatch(
  ler_selic_json(),
  error = function(e_json) {
    message("  Aviso BCB JSON: ", conditionMessage(e_json), " | tentando CSV...")
    tryCatch(
      ler_selic_csv(),
      error = function(e_csv) {
        message("  Aviso BCB CSV: ", conditionMessage(e_csv), " | tentando cache local...")
        if (file.exists(cache_selic_file)) readRDS(cache_selic_file) else stop(e_csv)
      }
    )
  }
)

selic_df <- selic_raw |>
  dplyr::mutate(
    refdate     = as.Date(data, format = "%d/%m/%Y"),
    selic_dia   = as.numeric(gsub(",", ".", valor)) / 100,
    selic_anual = (1 + selic_dia)^252 - 1     # taxa diária -> anual em base 252
  ) |>
  dplyr::filter(!is.na(refdate), !is.na(selic_anual)) |>
  dplyr::select(refdate, selic_anual)

if (nrow(selic_df) > 0) saveRDS(selic_raw, cache_selic_file)

message(sprintf("  %d datas Selic carregadas (%.2f%% a %.2f%% a.a.)",
                nrow(selic_df),
                min(selic_df$selic_anual)*100,
                max(selic_df$selic_anual)*100))

PREGAO_ATUAL <- DATA_FIM
btg_snap <- NULL
b3_btc_df <- NULL
if (MODO_CARREGO %in% c("btc", "hibrido")) {
  message(">>> Taxas tomador BTC (B3 historico + BTG D0)...")
  btg_snap <- obter_btg_d0_snapshot(cache_dir, atualizar = TRUE)
  b3_btc_df <- ler_b3_btc_tomador(cache_dir)
  manifest <- ler_b3_btc_manifest(cache_dir)
  b3_ok <- sum(manifest$status == "ok", na.rm = TRUE)
  message(sprintf(
    "  Pregao atual: %s | B3 cache: %d pregões | BTG: %d tickers (%s)",
    PREGAO_ATUAL,
    b3_ok,
    if (!is.null(btg_snap)) dplyr::n_distinct(btg_snap$ticker) else 0L,
    if (!is.null(btg_snap)) as.character(max(btg_snap$snapshot_date)) else "sem cache"
  ))
} else {
  message(">>> Carrego via put-call parity (sem cache BTC)")
}

# =============================================================================
# 5. CARREGA COTAHIST (filtra por ATIVO antes de collect pra economizar RAM)
# =============================================================================
message(">>> Carregando cotações...")

# Padrão regex: começa com ATIVO seguido de fim-de-string ou não-letra
# Pega "VALE", "VALE ON NM", "VALE PN", "VALE3" etc., mas evita "VALERIA"
ATIVO_PATTERN <- paste0("^", ATIVO, "($|[^A-Z])")

# Helper: filtra spot do ATIVO de uma fonte lazy (yearly ou daily)
puxa_spot <- function(lazy_obj) {
  if (is.null(lazy_obj)) return(NULL)

  # ETFs/units como BOVA11 podem nao passar por cotahist_filter_equity().
  # Quando ticker_spot e informado, buscamos o simbolo direto no COTAHIST bruto.
  if (!is.null(TICKER_SPOT)) {
    return(
      lazy_obj |>
        dplyr::filter(
          refdate >= DATA_CALC_INICIO,
          refdate <= DATA_CALC_FIM,
          symbol == TICKER_SPOT
        ) |>
        dplyr::collect()
    )
  }

  lazy_obj |>
    rb3::cotahist_filter_equity() |>
    dplyr::filter(
      refdate >= DATA_CALC_INICIO,
      refdate <= DATA_CALC_FIM
    ) |>
    dplyr::collect() |>
    dplyr::filter(
      stringr::str_detect(corporation_name, ATIVO_PATTERN) |
        stringr::str_detect(symbol, paste0("^", ATIVO_PREFIXO))
    )
}

# Helper: filtra opções do ATIVO
puxa_options <- function(lazy_obj) {
  if (is.null(lazy_obj)) return(NULL)
  lazy_obj |>
    dplyr::filter(
      refdate >= DATA_CALC_INICIO,
      refdate <= DATA_CALC_FIM,
      symbol >= ATIVO_PREFIXO,
      symbol < ATIVO_PREFIXO_LIMITE
    ) |>
    dplyr::collect() |>
    dplyr::filter(
      stringr::str_detect(symbol, paste0("^", ATIVO_PREFIXO)) |
        stringr::str_detect(corporation_name, paste0("^", ATIVO))
    )
}

# Lazy refs (não carrega nada ainda)
ch_yearly_lazy <- tryCatch(rb3::cotahist_get(type = "yearly"), error = function(e) NULL)
ch_daily_lazy  <- tryCatch(rb3::cotahist_get(type = "daily"),  error = function(e) NULL)

# Spot do ATIVO (junta yearly + daily)
price_data <- dplyr::bind_rows(
  puxa_spot(ch_yearly_lazy),
  puxa_spot(ch_daily_lazy)
) |> dplyr::distinct(refdate, symbol, .keep_all = TRUE)

if (nrow(price_data) > 0) {
  if (is.null(TICKER_SPOT)) {
    spot_liquidez <- price_data |>
      dplyr::mutate(volume_fin = dplyr::coalesce(volume, 0) * dplyr::coalesce(close, 0)) |>
      dplyr::group_by(symbol) |>
      dplyr::summarise(volume_fin = sum(volume_fin, na.rm = TRUE), .groups = "drop") |>
      dplyr::arrange(dplyr::desc(volume_fin))
    TICKER_SPOT <- spot_liquidez$symbol[1]
  }
  price_data <- price_data |>
    dplyr::filter(symbol == TICKER_SPOT)
  message(sprintf(">>> Ticker spot escolhido: %s", TICKER_SPOT))
}

# Opções do ATIVO
options_data <- dplyr::bind_rows(
  puxa_options(ch_yearly_lazy),
  puxa_options(ch_daily_lazy)
) |> dplyr::distinct(refdate, symbol, .keep_all = TRUE)

# Libera memória
rm(ch_yearly_lazy, ch_daily_lazy)
gc()

message(sprintf("  %s opções | %s spot (%s)",
                format(nrow(options_data), big.mark = ","),
                format(nrow(price_data),   big.mark = ","),
                ifelse(is.null(TICKER_SPOT), ATIVO, TICKER_SPOT)))

opcoes_tipo_dbg <- options_data |>
  dplyr::mutate(
    tipo = dplyr::case_when(
      stringr::str_detect(symbol, "^[A-Z]{4}[A-L]") ~ "call",
      stringr::str_detect(symbol, "^[A-Z]{4}[M-X]") ~ "put",
      TRUE ~ "outro"
    )
  ) |>
  dplyr::count(tipo, sort = TRUE)
if (nrow(opcoes_tipo_dbg) > 0) {
  message(sprintf("  tipos opções: %s",
                  paste(sprintf("%s=%s", opcoes_tipo_dbg$tipo,
                                format(opcoes_tipo_dbg$n, big.mark = ",")),
                        collapse = " | ")))
}

# Diagnóstico: mostra quais corporation_names casaram
nomes_casados <- unique(c(price_data$corporation_name,
                          options_data$corporation_name))
nomes_casados <- nomes_casados[!is.na(nomes_casados)]
if (length(nomes_casados) > 0) {
  message(sprintf("  corporation_name casado: %s",
                  paste(nomes_casados, collapse = " | ")))
}

if (nrow(price_data) == 0) {
  stop(
    sprintf(
      "Nenhuma cotação spot encontrada para '%s'. ",
      ATIVO
    ),
    "Verifique:\n",
    "  1. O cache rb3 tem dados? Rode: rb3::fetch_marketdata('b3-cotahist-yearly', year = 2020:2026)\n",
    "  2. O nome do ATIVO está correto? Para ver os nomes disponíveis no cache, rode:\n",
    "     rb3::cotahist_get(type = 'yearly') |> rb3::cotahist_filter_equity() |> ",
    "dplyr::distinct(corporation_name) |> dplyr::collect() |> print(n = 200)"
  )
}

# Helper: vencimento mensal B3 ~= 3a semana do mes (dias 15-21).
# Cobre 3a segunda (acoes), 4a perto do dia 15 (indice) e 3a sexta.
# Semanais caem nas outras semanas (1-7, 8-14, 22-31).
eh_vencimento_mensal <- function(x) {
  d <- lubridate::mday(as.Date(x))
  d >= 15 & d <= 21
}

# =============================================================================
# 6. FUNÇÃO: calcula IV/Delta para 1 data usando Selic do dia
# =============================================================================
calcular_iv_dia <- function(dt) {
  # Spot
  price <- price_data |>
    dplyr::filter(refdate == dt)
  if (nrow(price) == 0) return(NULL)
  close_underlying <- price$close[1]

  # Opções (filtra por ano e classifica call/put pela letra do código)
  op1 <- options_data |>
    dplyr::filter(lubridate::year(refdate) == lubridate::year(dt)) |>
    dplyr::mutate(
      type = dplyr::case_when(
        stringr::str_detect(symbol, "^[A-Z]{4}[A-L]") ~ "call",
        stringr::str_detect(symbol, "^[A-Z]{4}[M-X]") ~ "put",
        TRUE ~ NA_character_
      )
    ) |>
    dplyr::filter(!is.na(type), refdate == dt,
                  close > 0,
                  strike_price > 0,
                  !is.na(maturity_date),
                  volume > 0)
  if (nrow(op1) == 0) return(NULL)

  # Selic do dia (fallback: data mais recente <= dt)
  sel <- selic_df |> dplyr::filter(refdate == dt)
  if (nrow(sel) == 0) {
    sel <- selic_df |>
      dplyr::filter(refdate <= dt) |>
      dplyr::filter(refdate == max(refdate))
  }
  if (nrow(sel) == 0) return(NULL)
  rate_dia  <- sel$selic_anual[1]

  # IV / Delta linha-por-linha com tryCatch (rowwise + safe)
  safe_iv <- function(pm, S, K, t, r, tipo) {
    # Checks individuais, defendendo contra NA em qualquer um
    if (length(pm) == 0 || length(S) == 0 || length(K) == 0 ||
        length(t) == 0  || length(r) == 0 || length(tipo) == 0) return(NA_real_)
    if (is.na(pm) || is.na(S) || is.na(K) || is.na(t) || is.na(r) || is.na(tipo)) return(NA_real_)
    if (pm <= 0 || t <= 0 || S <= 0 || K <= 0) return(NA_real_)
    # Filtra preços absurdos
    if (tipo == "call" && pm > S * 1.5) return(NA_real_)
    if (tipo == "put"  && pm > K * 1.5) return(NA_real_)
    tryCatch(
      oplib::bsmimpvol(option_prices = pm, type = tipo, spot = S,
                       strike = K, time = t, rate = r, yield = q),
      error = function(e) NA_real_,
      warning = function(w) NA_real_
    )
  }
  safe_delta <- function(S, K, t, r, q, sig, tipo) {
    if (length(sig) == 0 || is.na(sig)) return(NA_real_)
    if (is.na(S) || is.na(K) || is.na(t) || is.na(r) || is.na(q) || is.na(tipo)) return(NA_real_)
    if (sig <= 0 || t <= 0) return(NA_real_)
    tryCatch(
      oplib::bsmdelta(type = tipo, spot = S, strike = K, time = t,
                      rate = r, yield = q, sigma = sig),
      error = function(e) NA_real_,
      warning = function(w) NA_real_
    )
  }

  op_base <- op1 |>
    dplyr::mutate(
      underlying_price = close_underlying,
      biz_days         = bizdays::bizdays(
        dt,
        bizdays::following(maturity_date, CAL),
        CAL
      ),
      time_to_maturity = biz_days / 252,
      rate             = log(1 + rate_dia),
      is_venc_mensal  = eh_vencimento_mensal(maturity_date)
    ) |>
    dplyr::filter(biz_days >= max(1, DU_ALVO - DU_TOL), biz_days <= (DU_ALVO + DU_TOL))

  # Prefer mensal; se a janela DU nao pegar nenhum mensal (buraco out/nov),
  # cai para semanais no mesmo dia — evita serie FVOL "travada".
  usou_fallback_semanal <- FALSE
  if (USAR_APENAS_VENCIMENTO_MENSAL) {
    op_mensal <- op_base |> dplyr::filter(is_venc_mensal)
    if (nrow(op_mensal) >= 3) {
      op_base <- op_mensal
    } else if (nrow(op_base) >= 3) {
      usou_fallback_semanal <- TRUE
    }
  }

  if (nrow(op_base) == 0) return(NULL)

  op_base <- adicionar_yield_opcoes(
    op_base,
    spot = close_underlying,
    refdate = dt,
    modo = MODO_CARREGO,
    cache_dir = cache_dir,
    pregao_atual = PREGAO_ATUAL,
    btg_snap = btg_snap,
    b3_df = b3_btc_df,
    cal = CAL,
    ticker = TICKER_SPOT,
    atm_band = ATM_BAND,
    max_fw_rel = MAX_FW_REL_PCP
  )
  if (is.null(op_base) || nrow(op_base) == 0) return(NULL)

  impvol_vec <- tryCatch(
    oplib::bsmimpvol(
      option_prices = op_base$close,
      type = op_base$type,
      spot = op_base$underlying_price,
      strike = op_base$strike_price,
      time = op_base$time_to_maturity,
      rate = op_base$rate,
      yield = op_base$yield
    ),
    error = function(e) rep(NA_real_, nrow(op_base)),
    warning = function(w) rep(NA_real_, nrow(op_base))
  )

  delta_vec <- tryCatch(
    oplib::bsmdelta(
      type = op_base$type,
      spot = op_base$underlying_price,
      strike = op_base$strike_price,
      time = op_base$time_to_maturity,
      rate = op_base$rate,
      yield = op_base$yield,
      sigma = impvol_vec
    ),
    error = function(e) rep(NA_real_, nrow(op_base)),
    warning = function(w) rep(NA_real_, nrow(op_base))
  )

  op_vol <- op_base |>
    dplyr::mutate(
      impvol = impvol_vec,
      delta = delta_vec
    ) |>
    dplyr::filter(!is.na(impvol), impvol > 0.01, impvol < 3)

  if (nrow(op_vol) == 0) return(NULL)
  op_vol$refdate_calc <- dt
  op_vol$fallback_semanal <- usou_fallback_semanal
  op_vol
}

# =============================================================================
# 7. SÉRIE HISTÓRICA
# =============================================================================
message(">>> Calculando IV histórica...")
datas_calc <- sort(unique(price_data$refdate))
datas_calc <- datas_calc[datas_calc >= DATA_CALC_INICIO & datas_calc <= DATA_CALC_FIM]
message(sprintf("  %d datas a processar (%s a %s)",
                length(datas_calc), DATA_CALC_INICIO, DATA_CALC_FIM))

op_all <- lapply(datas_calc, calcular_iv_dia) |> dplyr::bind_rows()
dias_com_iv <- if (nrow(op_all) > 0) dplyr::n_distinct(op_all$refdate_calc) else 0L
dias_pulados <- length(datas_calc) - dias_com_iv
dias_fallback_semanal <- if (nrow(op_all) > 0 && "fallback_semanal" %in% names(op_all)) {
  length(unique(op_all$refdate_calc[op_all$fallback_semanal %in% TRUE]))
} else {
  0L
}
if (dias_pulados > 0) {
  msg_carrego <- switch(
    MODO_CARREGO,
    pcp = "sem par PCP valido",
    btc = "sem taxa B3/BTG",
    hibrido = "sem par PCP nem taxa BTC"
  )
  message(sprintf("  %d pregões pulados (%s)", dias_pulados, msg_carrego))
}
if (dias_fallback_semanal > 0) {
  message(sprintf(
    "  %d pregões usaram fallback semanal (sem mensal na janela DU)",
    dias_fallback_semanal
  ))
}
if (nrow(op_all) == 0) stop("Nenhum IV calculado para ", ATIVO)
message(sprintf("  %s linhas IV calculadas",
                format(nrow(op_all), big.mark = ",")))

# =============================================================================
# 8. FVOL — calibracao por strike normalizado
# =============================================================================
calibrar_fvol_dia <- function(df) {
  # Escolhe um unico vencimento: mensal primeiro, depois pontos, depois DU_ALVO.
  df_base <- df |>
    dplyr::filter(biz_days >= max(1, DU_ALVO - DU_TOL),
                  biz_days <= (DU_ALVO + DU_TOL),
                  !is.na(impvol), impvol > 0,
                  !is.na(strike_price), strike_price > 0,
                  !is.na(underlying_price), underlying_price > 0,
                  !is.na(rate), !is.na(time_to_maturity), time_to_maturity > 0) |>
    dplyr::mutate(
      dist_venc = abs(biz_days - DU_ALVO),
      is_venc_mensal = if ("is_venc_mensal" %in% names(df)) {
        is_venc_mensal
      } else {
        eh_vencimento_mensal(maturity_date)
      }
    )

  if (nrow(df_base) < 3) return(NULL)

  venc_rank <- df_base |>
    dplyr::summarise(
      n_pontos = dplyr::n(),
      volume_total = sum(volume, na.rm = TRUE),
      dist_venc = min(dist_venc, na.rm = TRUE),
      is_venc_mensal = any(is_venc_mensal %in% TRUE),
      .by = c(maturity_date, biz_days)
    ) |>
    dplyr::mutate(
      sem_pontos_suficientes = n_pontos < MIN_PONTOS_FVOL,
      # semanal exige mais pontos para competir com mensal
      penalidade_semanal = !is_venc_mensal & n_pontos < max(MIN_PONTOS_FVOL + 3L, 8L)
    ) |>
    dplyr::arrange(
      !is_venc_mensal,
      sem_pontos_suficientes,
      penalidade_semanal,
      dist_venc,
      dplyr::desc(n_pontos),
      dplyr::desc(volume_total)
    )

  venc_escolhido <- venc_rank |> dplyr::slice(1)
  df_front <- df_base |>
    dplyr::filter(maturity_date == venc_escolhido$maturity_date[1],
                  biz_days == venc_escolhido$biz_days[1])

  if (nrow(df_front) < 3) return(NULL)

  # ATM de mercado robusto: mediana das IVs proximas do forward.
  # Evita que um unico negocio ruim perto do forward contamine a serie inteira.
  df_front <- df_front |>
    dplyr::mutate(
      forward_tmp = underlying_price * exp((rate - yield) * time_to_maturity),
      dist_atm = abs(strike_price / forward_tmp - 1),
      dist_delta = dplyr::case_when(
        type == "call" & !is.na(delta) ~ abs(delta - 0.5),
        type == "put"  & !is.na(delta) ~ abs(abs(delta) - 0.5),
        TRUE ~ Inf
      )
    )

  atm_candidates <- df_front |>
    dplyr::filter(
      dist_atm <= ATM_BAND,
      !is.na(impvol), impvol >= IV_ATM_MIN, impvol <= IV_ATM_MAX,
      !is.na(volume), volume > 0
    )

  if (nrow(atm_candidates) < 3) {
    atm_candidates <- df_front |>
      dplyr::filter(
        !is.na(impvol), impvol >= IV_ATM_MIN, impvol <= IV_ATM_MAX,
        !is.na(volume), volume > 0
      ) |>
      dplyr::arrange(dist_atm, dist_delta, dplyr::desc(volume)) |>
      utils::head(5)
  }

  if (nrow(atm_candidates) == 0) return(NULL)

  sigma_atm_mkt <- stats::median(atm_candidates$impvol, na.rm = TRUE)
  if (is.na(sigma_atm_mkt) || sigma_atm_mkt <= 0) return(NULL)

  atm_row <- atm_candidates |>
    dplyr::mutate(dist_iv_atm = abs(impvol - sigma_atm_mkt)) |>
    dplyr::arrange(dist_atm, dist_iv_atm, dist_delta, dplyr::desc(volume)) |>
    dplyr::slice(1)
  T_ref <- atm_row$time_to_maturity[1]
  r_ref <- atm_row$rate[1]
  q_ref <- atm_row$yield[1]
  S_ref <- atm_row$underlying_price[1]
  F_ref <- S_ref * exp((r_ref - q_ref) * T_ref)

  df_fit <- df_front |>
    dplyr::mutate(
      forward = underlying_price * exp((rate - yield) * time_to_maturity),
      sn = log(strike_price / forward) / (sigma_atm_mkt * sqrt(time_to_maturity))
    ) |>
    dplyr::filter(is.finite(sn), sn >= -2, sn <= 2)

  if (nrow(df_fit) < 3 || length(unique(round(df_fit$sn, 8))) < 3) return(NULL)

  # Ancora o ATM na IV de mercado mais proxima do forward.
  # Assim a Vol ATM FVOL nunca vira uma extrapolacao negativa do intercepto.
  df_fit <- df_fit |>
    dplyr::mutate(iv_ex_atm = impvol - sigma_atm_mkt)

  fit <- tryCatch(
    stats::lm(iv_ex_atm ~ 0 + sn + I(sn^2), data = df_fit, weights = pmax(volume, 1)),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)

  co <- stats::coef(fit)
  sigma_atm_fit <- sigma_atm_mkt
  skew_fvol <- unname(co[["sn"]])
  smile_fvol <- 2 * unname(co[["I(sn^2)"]])

  if (any(is.na(c(sigma_atm_fit, skew_fvol, smile_fvol))) || sigma_atm_fit <= 0) return(NULL)

  df_fit$fvol_fit <- sigma_atm_fit + skew_fvol * df_fit$sn + (smile_fvol / 2) * df_fit$sn^2
  df_fit <- df_fit |>
    dplyr::filter(is.finite(fvol_fit), fvol_fit > 0)
  if (nrow(df_fit) < 3 || length(unique(round(df_fit$sn, 8))) < 3) return(NULL)

  r2_fit <- summary(fit)$r.squared
  is_mensal_dia <- eh_vencimento_mensal(atm_row$maturity_date[1])
  # Semanal fino com fit ruim: descarta. Mensal (3a semana) ou smile liquido: mantem
  # (evento tipo pos-eleicao pode ter vol alta com R2 ainda util).
  if (!is_mensal_dia && (is.na(r2_fit) || r2_fit < 0.15 || nrow(df_fit) < 6)) {
    return(NULL)
  }

  tibble::tibble(
    refdate = df_front$refdate_calc[1],
    biz_days = atm_row$biz_days[1],
    maturity_date = atm_row$maturity_date[1],
    is_venc_mensal = is_mensal_dia,
    yield = q_ref,
    carry_aa = exp(q_ref) - 1,
    underlying_price = S_ref,
    forward = F_ref,
    strike_atm = atm_row$strike_price[1],
    sigma_atm = sigma_atm_fit,
    sigma_atm_mkt = sigma_atm_mkt,
    skew = skew_fvol,
    smile = smile_fvol,
    n_points = nrow(df_fit),
    r2 = r2_fit,
    fit_data = list(df_fit)
  )
}

message(">>> Calibrando FVOL historico...")
fvol_ts <- op_all |>
  dplyr::group_by(refdate_calc) |>
  dplyr::group_split() |>
  lapply(calibrar_fvol_dia) |>
  dplyr::bind_rows() |>
  dplyr::arrange(refdate)

if (nrow(fvol_ts) == 0) stop("Nenhuma curva FVOL calibrada para ", ATIVO)
message(sprintf("  %s curvas FVOL calibradas", format(nrow(fvol_ts), big.mark = ",")))

if (!is.null(PERIODO_INICIO)) fvol_ts <- dplyr::filter(fvol_ts, refdate >= PERIODO_INICIO)
if (!is.null(PERIODO_FIM))    fvol_ts <- dplyr::filter(fvol_ts, refdate <= PERIODO_FIM)

# Remove so pregões com qualidade ruim (nao salto de vol puro).
# Eventos (ex.: dia apos eleicao) podem ter jump legitimo em mensal liquido.
if (nrow(fvol_ts) >= 3) {
  carry_abs <- if ("carry_aa" %in% names(fvol_ts)) {
    abs(fvol_ts$carry_aa)
  } else {
    rep(0, nrow(fvol_ts))
  }
  is_mensal_col <- if ("is_venc_mensal" %in% names(fvol_ts)) {
    fvol_ts$is_venc_mensal %in% TRUE
  } else {
    rep(TRUE, nrow(fvol_ts))
  }
  # lixo tipico: semanal fino + R2 ruim; PCP absurdo so se smile tambem fraco
  outlier <- (
    (!is_mensal_col & (!is.na(fvol_ts$r2) & fvol_ts$r2 < 0.20) & fvol_ts$n_points < 8) |
      (is.finite(carry_abs) & carry_abs > 0.35 &
         (fvol_ts$n_points < 10 | (!is.na(fvol_ts$r2) & fvol_ts$r2 < 0.30)))
  )
  if (any(outlier)) {
    message(sprintf(
      "  Removendo %d pregão(ões) com qualidade ruim (nao por salto de vol): %s",
      sum(outlier),
      paste(format(fvol_ts$refdate[outlier], "%Y-%m-%d"), collapse = ", ")
    ))
    fvol_ts <- fvol_ts[!outlier, , drop = FALSE]
  }
}
if (nrow(fvol_ts) == 0) stop("Nenhuma curva FVOL restante apos filtro de qualidade para ", ATIVO)

dias_iv_sem_fvol <- setdiff(
  unique(op_all$refdate_calc),
  unique(fvol_ts$refdate)
)
if (length(dias_iv_sem_fvol) > 0) {
  message(sprintf(
    "  %d pregão(ões) com IV mas sem FVOL: %s",
    length(dias_iv_sem_fvol),
    paste(format(sort(dias_iv_sem_fvol), "%Y-%m-%d"), collapse = ", ")
  ))
}

fvol_ts <- fvol_ts |>
  dplyr::mutate(
    vol_mm = zoo::rollmean(sigma_atm, k = JANELA_MM, fill = NA, align = "right"),
    pct_vol = ecdf(sigma_atm)(sigma_atm) * 100,
    pct_skew = ecdf(skew)(skew) * 100,
    pct_smile = ecdf(smile)(smile) * 100,
    media_vol = mean(sigma_atm, na.rm = TRUE),
    media_skew = mean(skew, na.rm = TRUE),
    media_smile = mean(smile, na.rm = TRUE),
    diff_vol_media = sigma_atm - media_vol,
    diff_skew_media = skew - media_skew,
    diff_smile_media = smile - media_smile
  )

hv_serie <- price_data |>
  dplyr::arrange(refdate) |>
  dplyr::mutate(
    log_ret = log(close / dplyr::lag(close)),
    vol_realizada = zoo::rollapply(
      log_ret,
      width = JANELA_MM,
      FUN = function(x) stats::sd(x, na.rm = TRUE) * sqrt(252),
      fill = NA,
      align = "right"
    )
  ) |>
  dplyr::select(refdate, vol_realizada)

fvol_ts <- fvol_ts |>
  dplyr::left_join(hv_serie, by = "refdate") |>
  dplyr::left_join(
    calc_vol_realizada_forward(price_data, JANELA_FWD, CAL),
    by = "refdate"
  ) |>
  dplyr::mutate(
    premio_iv = sigma_atm - vol_realizada,
    premio_iv_fwd = sigma_atm - vol_realizada_fwd
  )

premio_validos <- fvol_ts$premio_iv[!is.na(fvol_ts$premio_iv)]
fvol_ts$pct_premio <- if (length(premio_validos) >= 2) {
  ecdf(premio_validos)(fvol_ts$premio_iv) * 100
} else {
  NA_real_
}

premio_fwd_validos <- fvol_ts$premio_iv_fwd[!is.na(fvol_ts$premio_iv_fwd)]
fvol_ts$pct_premio_fwd <- if (length(premio_fwd_validos) >= 2) {
  ecdf(premio_fwd_validos)(fvol_ts$premio_iv_fwd) * 100
} else {
  NA_real_
}

fvol_fwd_stats <- fvol_ts |>
  dplyr::filter(!is.na(sigma_atm), !is.na(vol_realizada_fwd))
cor_iv_fwd <- if (nrow(fvol_fwd_stats) >= 3) {
  stats::cor(fvol_fwd_stats$sigma_atm, fvol_fwd_stats$vol_realizada_fwd)
} else {
  NA_real_
}
mae_iv_fwd <- if (nrow(fvol_fwd_stats) >= 1) {
  mean(abs(fvol_fwd_stats$premio_iv_fwd), na.rm = TRUE)
} else {
  NA_real_
}
pct_iv_acima_fwd <- if (nrow(fvol_fwd_stats) >= 1) {
  mean(fvol_fwd_stats$sigma_atm > fvol_fwd_stats$vol_realizada_fwd, na.rm = TRUE) * 100
} else {
  NA_real_
}

fvol_ult <- dplyr::slice_tail(fvol_ts, n = 1)
ult_data <- fvol_ult$refdate[1]

carry_ult <- op_all |>
  dplyr::filter(refdate_calc == ult_data) |>
  dplyr::slice(1)
BTC_TOMADOR_LABEL <- if (nrow(carry_ult) > 0 && !is.na(carry_ult$yield[1])) {
  carry_label_from_yield(
    carry_ult$yield[1],
    carry_ult$carrego_fonte[1],
    ult_data
  )
} else if (MODO_CARREGO %in% c("btc", "hibrido")) {
  btc_ult <- obter_taxa_tomador(
    ult_data, TICKER_SPOT, cache_dir,
    pregao_atual = PREGAO_ATUAL, btg_snap = btg_snap, b3_df = b3_btc_df, cal = CAL
  )
  if (!is.na(btc_ult$fee_aa)) {
    sprintf("%.4f%% a.a. (%s %s)", btc_ult$fee_aa * 100, btc_ult$fonte, ult_data)
  } else {
    "sem carrego"
  }
} else {
  "sem carrego PCP"
}

fmt_pct <- function(x) ifelse(is.na(x), "--", sprintf("%.2f%%", x * 100))
fmt_pp <- function(x) ifelse(is.na(x), "--", sprintf("%+.2f pp", x * 100))
fmt_rank <- function(x) ifelse(is.na(x), "--", sprintf("%.0f°", x))
fmt_num <- function(x) ifelse(is.na(x), "--", sprintf("%.0f", x))

resumo_tbl <- tibble::tibble(
  Variavel = c("Vol ATM", "Skew", "Smile", "Pontos smile", "R2"),
  Atual = c(
    fmt_pct(fvol_ult$sigma_atm),
    fmt_pct(fvol_ult$skew),
    fmt_pct(fvol_ult$smile),
    fmt_num(fvol_ult$n_points),
    sprintf("%.2f", fvol_ult$r2)
  ),
  Min = c(
    fmt_pct(min(fvol_ts$sigma_atm, na.rm = TRUE)),
    fmt_pct(min(fvol_ts$skew, na.rm = TRUE)),
    fmt_pct(min(fvol_ts$smile, na.rm = TRUE)),
    fmt_num(min(fvol_ts$n_points, na.rm = TRUE)),
    sprintf("%.2f", min(fvol_ts$r2, na.rm = TRUE))
  ),
  Max = c(
    fmt_pct(max(fvol_ts$sigma_atm, na.rm = TRUE)),
    fmt_pct(max(fvol_ts$skew, na.rm = TRUE)),
    fmt_pct(max(fvol_ts$smile, na.rm = TRUE)),
    fmt_num(max(fvol_ts$n_points, na.rm = TRUE)),
    sprintf("%.2f", max(fvol_ts$r2, na.rm = TRUE))
  ),
  Media = c(
    fmt_pct(fvol_ult$media_vol),
    fmt_pct(fvol_ult$media_skew),
    fmt_pct(fvol_ult$media_smile),
    fmt_num(mean(fvol_ts$n_points, na.rm = TRUE)),
    sprintf("%.2f", mean(fvol_ts$r2, na.rm = TRUE))
  ),
  Percentil = c(
    fmt_rank(fvol_ult$pct_vol),
    fmt_rank(fvol_ult$pct_skew),
    fmt_rank(fvol_ult$pct_smile),
    "--",
    "--"
  ),
  `Dif. media` = c(
    fmt_pp(fvol_ult$diff_vol_media),
    fmt_pp(fvol_ult$diff_skew_media),
    fmt_pp(fvol_ult$diff_smile_media),
    "--",
    "--"
  )
)

# =============================================================================
# 9. TEMA DARK (BTG-like)
# =============================================================================
COR_BG     <- "#0a1628"; COR_PANEL  <- "#111f38"; COR_GRID   <- "#1e2f4a"
COR_TEXT   <- "#e8eeff"; COR_ACCENT <- "#00c37a"; COR_YELLOW <- "#f5c842"
COR_RED    <- "#e05252"; COR_WHITE  <- "#ffffff"; COR_GRAY   <- "#8fa8c8"
COR_PURPLE <- "#8a6fff"

tema_dark <- function() {
  theme_classic(base_size = 14, base_family = "sans") +
    theme(
      plot.background   = element_rect(fill = COR_BG,    color = NA),
      panel.background  = element_rect(fill = COR_PANEL, color = NA),
      panel.grid.major  = element_line(color = COR_GRID, linewidth = 0.45),
      panel.grid.minor  = element_blank(),
      axis.line         = element_line(color = COR_GRAY, linewidth = 0.6),
      axis.ticks        = element_line(color = COR_WHITE, linewidth = 0.5),
      axis.text         = element_text(color = COR_WHITE, size = 12, face = "bold"),
      axis.text.x       = element_text(
        color = COR_WHITE, size = 11, face = "bold",
        angle = 35, hjust = 1, vjust = 1, margin = margin(t = 6)
      ),
      axis.text.y       = element_text(color = COR_WHITE, size = 12, face = "bold"),
      axis.title        = element_text(color = COR_WHITE, size = 13, face = "bold"),
      plot.title        = element_text(
        color = COR_WHITE, size = 17, face = "bold",
        hjust = 0, margin = margin(b = 6, t = 2)
      ),
      plot.subtitle     = element_text(
        color = COR_TEXT, size = 12, face = "plain",
        hjust = 0, lineheight = 1.3, margin = margin(b = 10)
      ),
      legend.background = element_rect(fill = COR_PANEL, color = COR_GRAY, linewidth = 0.5),
      legend.text       = element_text(color = COR_WHITE, size = 12, face = "bold"),
      legend.title      = element_text(color = COR_WHITE, size = 12, face = "bold"),
      legend.position   = "bottom",
      legend.direction  = "horizontal",
      legend.box        = "horizontal",
      legend.justification = "center",
      legend.key        = element_rect(fill = COR_PANEL, color = NA),
      legend.key.width  = grid::unit(1.8, "cm"),
      legend.key.height = grid::unit(0.55, "cm"),
      legend.spacing.x  = grid::unit(0.6, "cm"),
      legend.margin     = margin(t = 8, b = 2),
      strip.text        = element_text(color = COR_WHITE, face = "bold", size = 12),
      plot.margin       = margin(t = 10, r = 14, b = 8, l = 12)
    )
}

guia_legenda <- function() {
  guides(
    color = guide_legend(
      override.aes = list(linewidth = 2.8, size = 4, alpha = 1),
      nrow = 1,
      byrow = TRUE,
      keywidth = grid::unit(1.8, "cm"),
      keyheight = grid::unit(0.55, "cm")
    )
  )
}

escala_x_mensal <- function() {
  scale_x_date(
    date_labels = "%b/%y",
    date_breaks = "2 months",
    expand = expansion(mult = c(0.02, 0.05))
  )
}

# =============================================================================
# 10. GRAFICO 0 — Equity spot
# =============================================================================
price_plot_data <- price_data |>
  dplyr::filter(refdate >= DATA_CALC_INICIO, refdate <= DATA_CALC_FIM) |>
  dplyr::arrange(refdate) |>
  dplyr::mutate(ret_periodo = close / dplyr::first(close) - 1)
price_ult <- dplyr::slice_tail(price_plot_data, n = 1)

p0 <- ggplot(price_plot_data, aes(x = refdate, y = close)) +
  geom_line(color = COR_WHITE, linewidth = 1.3, alpha = 0.9) +
  geom_point(data = price_ult, aes(x = refdate, y = close),
             color = COR_WHITE, fill = COR_ACCENT, shape = 21, size = 4, stroke = 1.2) +
  escala_x_mensal() +
  scale_y_continuous(labels = scales::label_number(accuracy = 0.01, prefix = "R$ ")) +
  labs(
    title = glue("Preço — {ifelse(is.null(TICKER_SPOT), ATIVO_PREFIXO, TICKER_SPOT)}"),
    subtitle = glue("Retorno no período: {scales::percent(dplyr::last(price_plot_data$ret_periodo), accuracy = 0.1)}"),
    x = NULL, y = "Preço"
  ) +
  tema_dark()


# =============================================================================
# 10. GRAFICO 1 — Vol ATM FVOL + MM
# =============================================================================
p1 <- ggplot(fvol_ts, aes(x = refdate)) +
  geom_line(
    aes(
      y = sigma_atm * 100,
      color = "Vol ATM FVOL",
      text = paste0(
        "<b>", format(refdate, "%d/%m/%Y"), "</b><br>",
        "Vol ATM: ", sprintf("%.2f%%", sigma_atm * 100)
      )
    ),
    linewidth = 1.4, alpha = 0.95
  ) +
  geom_line(
    aes(
      y = vol_mm * 100,
      color = sprintf("MM%d", JANELA_MM),
      text = paste0(
        "<b>", format(refdate, "%d/%m/%Y"), "</b><br>",
        sprintf("MM%d: ", JANELA_MM), sprintf("%.2f%%", vol_mm * 100)
      )
    ),
    linewidth = 1.8, na.rm = TRUE
  ) +
  geom_point(
    data = fvol_ult,
    aes(
      x = refdate, y = sigma_atm * 100,
      text = paste0(
        "<b>", format(refdate, "%d/%m/%Y"), "</b><br>",
        "Vol ATM: ", sprintf("%.2f%%", sigma_atm * 100)
      )
    ),
    color = COR_WHITE, fill = COR_ACCENT, shape = 21, size = 4, stroke = 1.2
  ) +
  scale_color_manual(
    values = c("Vol ATM FVOL" = COR_YELLOW,
               setNames(COR_ACCENT, sprintf("MM%d", JANELA_MM))),
    name = NULL
  ) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  escala_x_mensal() +
  labs(
    title    = glue("Vol ATM FVOL — {ATIVO}"),
    subtitle = glue("SN = ln(K/F)/(sigma_ATM*sqrt(T)) | venc. ~{DU_ALVO}du | carrego={BTC_TOMADOR_LABEL}"),
    x = NULL, y = "Vol (%)"
  ) +
  tema_dark() + guia_legenda()


# =============================================================================
# 11. GRAFICO 2 — Percentis FVOL
# =============================================================================
percentis_long <- fvol_ts |>
  dplyr::select(refdate, pct_vol, pct_skew, pct_smile) |>
  tidyr::pivot_longer(-refdate, names_to = "variavel", values_to = "percentil") |>
  dplyr::mutate(
    variavel = dplyr::recode(variavel,
      pct_vol = "Vol ATM",
      pct_skew = "Skew",
      pct_smile = "Smile"
    )
  )

percentis_ult <- dplyr::filter(percentis_long, refdate == max(refdate))

p2 <- ggplot(percentis_long, aes(x = refdate, y = percentil, color = variavel)) +
  geom_hline(yintercept = c(25, 50, 75),
             color = COR_GRAY, linetype = "dashed", linewidth = 0.7) +
  geom_line(linewidth = 1.4) +
  geom_point(data = percentis_ult, aes(x = refdate, y = percentil, fill = variavel),
             color = COR_WHITE, shape = 21, size = 4, stroke = 1) +
  scale_color_manual(values = c("Vol ATM" = COR_YELLOW, "Skew" = COR_RED, "Smile" = COR_PURPLE), name = NULL) +
  scale_fill_manual(values = c("Vol ATM" = COR_YELLOW, "Skew" = COR_RED, "Smile" = COR_PURPLE), guide = "none") +
  scale_y_continuous(limits = c(0, 100), labels = function(x) paste0(x, "°")) +
  escala_x_mensal() +
  labs(
    title    = glue("Percentis FVOL — {ATIVO}"),
    subtitle = "Percentil empirico no periodo escolhido; ponto = ultima observacao",
    x = NULL, y = "Percentil"
  ) +
  tema_dark() + guia_legenda()

# =============================================================================
# 12b. GRAFICO — Skew e Smile historicos
# =============================================================================
skew_smile_long <- fvol_ts |>
  dplyr::select(refdate, skew, smile) |>
  tidyr::pivot_longer(-refdate, names_to = "variavel", values_to = "valor") |>
  dplyr::mutate(
    variavel = dplyr::recode(variavel, skew = "Skew", smile = "Smile")
  )

skew_smile_ult <- dplyr::filter(skew_smile_long, refdate == max(refdate))

p_skew_smile <- ggplot(
  skew_smile_long,
  aes(
    x = refdate, y = valor * 100, color = variavel,
    text = paste0(
      "<b>", format(refdate, "%d/%m/%Y"), "</b><br>",
      variavel, ": ", sprintf("%.2f%%", valor * 100)
    )
  )
) +
  geom_line(linewidth = 1.4) +
  geom_point(
    data = skew_smile_ult,
    aes(x = refdate, y = valor * 100, fill = variavel),
    color = COR_WHITE, shape = 21, size = 4, stroke = 1
  ) +
  scale_color_manual(values = c("Skew" = COR_RED, "Smile" = COR_PURPLE), name = NULL) +
  scale_fill_manual(values = c("Skew" = COR_RED, "Smile" = COR_PURPLE), guide = "none") +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  escala_x_mensal() +
  labs(
    title    = glue("Skew e Smile FVOL — {ATIVO}"),
    subtitle = glue("Coeficientes da regressao IV_ex_ATM ~ SN + SN^2 | venc. ~{DU_ALVO}du"),
    x = NULL, y = "Coeficiente (%)"
  ) +
  tema_dark() + guia_legenda()

# =============================================================================
# 12c. GRAFICO — IV implicita vs vol realizada
# =============================================================================
iv_hv_ult <- dplyr::slice_tail(
  dplyr::filter(fvol_ts, !is.na(vol_realizada)),
  n = 1
)
premio_iv_ult <- if (nrow(iv_hv_ult) > 0) iv_hv_ult$premio_iv[1] else NA_real_

p_iv_hv <- ggplot(fvol_ts, aes(x = refdate)) +
  geom_line(aes(y = sigma_atm * 100, color = "IV ATM FVOL"), linewidth = 1.4, na.rm = TRUE) +
  geom_line(aes(y = vol_realizada * 100, color = "Vol realizada"), linewidth = 1.4, na.rm = TRUE) +
  geom_line(aes(y = vol_mm * 100, color = sprintf("MM%d IV", JANELA_MM)),
            linewidth = 1.6, linetype = "dashed", na.rm = TRUE) +
  geom_point(
    data = iv_hv_ult,
    aes(x = refdate, y = sigma_atm * 100),
    color = COR_WHITE, fill = COR_ACCENT, shape = 21, size = 4, stroke = 1.2
  ) +
  scale_color_manual(
    values = c(
      "IV ATM FVOL" = COR_YELLOW,
      "Vol realizada" = COR_ACCENT,
      setNames(COR_WHITE, sprintf("MM%d IV", JANELA_MM))
    ),
    name = NULL
  ) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  escala_x_mensal() +
  labs(
    title    = glue("IV vs Vol Realizada — {ATIVO}"),
    subtitle = glue(
      "Vol realizada = stdev({JANELA_MM}d) * sqrt(252) | premio IV-HV ultimo: {fmt_pp(premio_iv_ult)}"
    ),
    x = NULL, y = "Vol (%)"
  ) +
  tema_dark() + guia_legenda()

p_premio <- ggplot(fvol_ts, aes(x = refdate, y = premio_iv * 100)) +
  geom_hline(yintercept = 0, color = COR_GRAY, linetype = "dashed", linewidth = 0.5) +
  geom_line(color = COR_YELLOW, linewidth = 1.4, na.rm = TRUE) +
  geom_point(
    data = iv_hv_ult,
    aes(x = refdate, y = premio_iv * 100),
    color = COR_WHITE, fill = COR_ACCENT, shape = 21, size = 4, stroke = 1.2,
    inherit.aes = FALSE
  ) +
  scale_y_continuous(labels = function(x) paste0(x, " pp")) +
  escala_x_mensal() +
  labs(
    title    = glue("Premio IV - Vol Realizada — {ATIVO}"),
    subtitle = "Positivo = mercado precificou mais vol do que o spot realizou na janela",
    x = NULL, y = "Premio (pp)"
  ) +
  tema_dark()

iv_fwd_ult <- dplyr::slice_tail(
  dplyr::filter(fvol_ts, !is.na(vol_realizada_fwd)),
  n = 1
)
premio_iv_fwd_ult <- if (nrow(iv_fwd_ult) > 0) iv_fwd_ult$premio_iv_fwd[1] else NA_real_
fmt_cor <- function(x) ifelse(is.na(x), "--", sprintf("%.2f", x))

p_iv_fwd <- ggplot(fvol_ts, aes(x = refdate)) +
  geom_line(aes(y = sigma_atm * 100, color = "IV ATM FVOL"), linewidth = 1.4, na.rm = TRUE) +
  geom_line(aes(y = vol_realizada_fwd * 100, color = "Vol realizada forward"),
            linewidth = 1.4, na.rm = TRUE) +
  geom_point(
    data = iv_fwd_ult,
    aes(x = refdate, y = sigma_atm * 100),
    color = COR_WHITE, fill = COR_ACCENT, shape = 21, size = 4, stroke = 1.2
  ) +
  scale_color_manual(
    values = c(
      "IV ATM FVOL" = COR_YELLOW,
      "Vol realizada forward" = COR_PURPLE
    ),
    name = NULL
  ) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  escala_x_mensal() +
  labs(
    title    = glue("IV vs Vol Realizada Forward — {ATIVO}"),
    subtitle = glue(
      "Forward = stdev dos proximos {JANELA_FWD}du * sqrt(252) | corr={fmt_cor(cor_iv_fwd)} | MAE={fmt_pp(mae_iv_fwd)} | IV>real {sprintf('%.0f', pct_iv_acima_fwd)}%"
    ),
    x = NULL, y = "Vol (%)"
  ) +
  tema_dark() + guia_legenda()

p_premio_fwd <- ggplot(fvol_ts, aes(x = refdate, y = premio_iv_fwd * 100)) +
  geom_hline(yintercept = 0, color = COR_GRAY, linetype = "dashed", linewidth = 0.5) +
  geom_line(color = COR_PURPLE, linewidth = 1.4, na.rm = TRUE) +
  geom_point(
    data = iv_fwd_ult,
    aes(x = refdate, y = premio_iv_fwd * 100),
    color = COR_WHITE, fill = COR_ACCENT, shape = 21, size = 4, stroke = 1.2,
    inherit.aes = FALSE
  ) +
  scale_y_continuous(labels = function(x) paste0(x, " pp")) +
  escala_x_mensal() +
  labs(
    title    = glue("Premio IV - Vol Forward — {ATIVO}"),
    subtitle = glue(
      "Ex post: IV em t vs realizacao nos proximos {JANELA_FWD}du | ultimo premio: {fmt_pp(premio_iv_fwd_ult)}"
    ),
    x = NULL, y = "Premio (pp)"
  ) +
  tema_dark()

p_scatter_iv_fwd <- ggplot(
  dplyr::filter(fvol_ts, !is.na(sigma_atm), !is.na(vol_realizada_fwd)),
  aes(x = sigma_atm * 100, y = vol_realizada_fwd * 100)
) +
  geom_abline(slope = 1, intercept = 0, color = COR_GRAY, linetype = "dashed", linewidth = 0.6) +
  geom_point(color = COR_ACCENT, alpha = 0.7, size = 3) +
  geom_point(
    data = iv_fwd_ult,
    aes(x = sigma_atm * 100, y = vol_realizada_fwd * 100),
    color = COR_WHITE, fill = COR_YELLOW, shape = 21, size = 4.5, stroke = 1.2
  ) +
  scale_x_continuous(labels = function(x) paste0(x, "%")) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  labs(
    title    = glue("IV vs Realizado Forward — {ATIVO}"),
    subtitle = "Diagonal = acerto perfeito; acima = spot realizou mais vol que a IV",
    x = "IV ATM (%)",
    y = "Vol realizada forward (%)"
  ) +
  tema_dark()

# =============================================================================
# 12d. GRAFICO 3 — Smile FVOL na ultima data
# =============================================================================
smile_data <- fvol_ult$fit_data[[1]]
curve_data <- tibble::tibble(
  sn = seq(max(-2, min(smile_data$sn, na.rm = TRUE)),
           min(2, max(smile_data$sn, na.rm = TRUE)),
           length.out = 200)
) |>
  dplyr::mutate(
    fvol_fit = fvol_ult$sigma_atm + fvol_ult$skew * sn + (fvol_ult$smile / 2) * sn^2
  )

p3 <- ggplot(smile_data, aes(x = sn, y = impvol * 100)) +
  geom_point(
    aes(
      size = volume, color = type,
      text = paste0(
        "<b>", toupper(type), "</b><br>",
        "SN: ", sprintf("%.3f", sn), "<br>",
        "IV: ", sprintf("%.2f%%", impvol * 100), "<br>",
        "Volume: ", format(round(volume), big.mark = ".")
      )
    ),
    alpha = 0.55
  ) +
  geom_line(
    data = curve_data,
    aes(
      x = sn, y = fvol_fit * 100,
      text = paste0(
        "<b>Curva FVOL</b><br>",
        "SN: ", sprintf("%.3f", sn), "<br>",
        "IV fit: ", sprintf("%.2f%%", fvol_fit * 100)
      ),
      group = 1
    ),
    inherit.aes = FALSE, color = COR_ACCENT, linewidth = 1.8
  ) +
  geom_vline(xintercept = 0, color = COR_GRAY, linetype = "dashed", linewidth = 0.5) +
  scale_color_manual(values = c("call" = COR_YELLOW, "put" = COR_RED), name = NULL) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  scale_size_continuous(range = c(0.7, 4), guide = "none") +
  coord_cartesian(xlim = c(-2, 2)) +
  labs(
    title    = glue("Smile FVOL — {ATIVO}"),
    subtitle = glue("Data: {ult_data} | venc. {fvol_ult$biz_days}du | curva = sigma_ATM + Skew*SN + Smile/2*SN^2"),
    x = "Strike Normalizado (SN)",
    y = "Vol implicita (%)"
  ) +
  tema_dark() + guia_legenda()

# =============================================================================
# 13. TABELA — Variaveis FVOL calculadas
# =============================================================================
tbl_theme <- gridExtra::ttheme_minimal(
  base_size = 15,
  core = list(
    fg_params = list(col = COR_WHITE, fontfamily = "sans", fontsize = 15),
    bg_params = list(fill = COR_PANEL, col = COR_GRID)
  ),
  colhead = list(
    fg_params = list(col = COR_WHITE, fontface = "bold", fontfamily = "sans", fontsize = 15),
    bg_params = list(fill = COR_GRID, col = COR_GRID)
  )
)

p4 <- gridExtra::tableGrob(resumo_tbl, rows = NULL, theme = tbl_theme)
p4 <- patchwork::wrap_elements(full = p4)
# =============================================================================
# 14. COMPOSIÇÃO + EXPORTAÇÃO
# =============================================================================
base_annotation <- plot_annotation(
  title   = glue("Análise de Volatilidade Implícita — {ATIVO}"),
  caption = glue("Cotações: B3/rb3 | Selic: BCB SGS | Carrego: {toupper(MODO_CARREGO)} | {format(Sys.Date(), '%d/%m/%Y')}"),
  theme   = theme(
    plot.background = element_rect(fill = COR_BG, color = NA),
    plot.title      = element_text(color = COR_WHITE, size = 18,
                                   face = "bold", family = "mono"),
    plot.caption    = element_text(color = COR_TEXT, size = 11,
                                   family = "mono")
  )
)

if (incluir_tabela_grafico) {
  final <- ((p0 / p1) | (p2 / p4) | p3) +
    plot_layout(widths = c(1, 1, 1.15)) +
    base_annotation
} else {
  final <- ((p0 / p1) | (p2 / p3)) +
    plot_layout(widths = c(1, 1.15)) +
    base_annotation
}

out_file <- file.path(out_dir, sprintf("vol_%s_%s.png", ATIVO, format(Sys.Date(), "%Y%m%d")))
if (isTRUE(salvar_png)) {
  ggsave(out_file, final, width = largura, height = altura, dpi = dpi, bg = COR_BG)
  message(">>> Salvo: ", out_file)
  print(final)
}

invisible({
  n_iv_dias <- dplyr::n_distinct(op_all$refdate_calc)
  payload <- list(
    ativo = ATIVO,
    ticker_spot = TICKER_SPOT,
    periodo = c(inicio = DATA_CALC_INICIO, fim = DATA_CALC_FIM),
    meta_datas = list(
      ultima_spot = if (nrow(price_data)) max(price_data$refdate) else as.Date(NA),
      ultima_iv = if (nrow(op_all)) max(op_all$refdate_calc) else as.Date(NA),
      ultima_fvol = if (nrow(fvol_ts)) max(fvol_ts$refdate) else as.Date(NA),
      n_datas_spot = length(datas_calc),
      n_datas_iv = dias_com_iv,
      n_datas_puladas = dias_pulados,
      n_datas_fallback_semanal = as.integer(dias_fallback_semanal),
      n_datas_iv_sem_fvol = length(dias_iv_sem_fvol),
      datas_iv_sem_fvol = if (length(dias_iv_sem_fvol)) {
        format(sort(dias_iv_sem_fvol), "%Y-%m-%d")
      } else {
        character(0)
      },
      ultimo_vencimento = if (nrow(fvol_ts)) fvol_ult$maturity_date[1] else as.Date(NA),
      ultimo_biz_days = if (nrow(fvol_ts)) as.integer(fvol_ult$biz_days[1]) else NA_integer_,
      ultimo_mensal = if (nrow(fvol_ts) && "is_venc_mensal" %in% names(fvol_ult)) {
        isTRUE(fvol_ult$is_venc_mensal[1])
      } else {
        NA
      },
      ultimo_carry_aa = if (nrow(fvol_ts) && "carry_aa" %in% names(fvol_ult)) {
        fvol_ult$carry_aa[1]
      } else {
        NA_real_
      },
      ultimo_n_points = if (nrow(fvol_ts)) as.integer(fvol_ult$n_points[1]) else NA_integer_,
      ultimo_r2 = if (nrow(fvol_ts)) fvol_ult$r2[1] else NA_real_
    ),
    arquivo = if (isTRUE(salvar_png)) out_file else NA_character_,
    graficos = list(
      preco = p0,
      vol_atm = p1,
      percentis = p2,
      skew_smile = p_skew_smile,
      iv_vs_hv = p_iv_hv,
      premio_iv = p_premio,
      iv_vs_fwd = p_iv_fwd,
      premio_iv_fwd = p_premio_fwd,
      scatter_iv_fwd = p_scatter_iv_fwd,
      smile = p3
    ),
    tabela = resumo_tbl,
    fvol = fvol_ts,
    n_iv_dias = n_iv_dias,
    carrego_modo = MODO_CARREGO,
    carrego_label = BTC_TOMADOR_LABEL,
    janela_mm = JANELA_MM,
    janela_fwd = JANELA_FWD,
    du_alvo = DU_ALVO,
    stats_iv_fwd = list(
      cor = cor_iv_fwd,
      mae = mae_iv_fwd,
      pct_iv_acima = pct_iv_acima_fwd,
      n = nrow(fvol_fwd_stats)
    )
  )
  if (!isTRUE(retorno_leve)) {
    payload$grafico <- final
    payload$iv_opcoes <- op_all
    payload$precos <- price_data
    payload$opcoes <- options_data
  }
  if (isTRUE(retorno_leve)) invisible(gc())
  payload
})
}

# Autorun desligado por padrao (Shiny / source). Para rodar standalone:
#   options(vol_implicita.autorun = TRUE); source("vol_implicita_11.R")
if (isTRUE(getOption("vol_implicita.autorun", FALSE))) {
# =============================================================================
# ESCOLHA AQUI E RODE O SCRIPT INTEIRO
# =============================================================================
ATIVO_RODAR          <- "BOVA"
TICKER_SPOT_RODAR    <- "BOVA11"
PREFIXO_OPCOES_RODAR <- NULL
PERIODO_INICIO_RODAR <- Sys.Date() - 365
PERIODO_FIM_RODAR    <- Sys.Date()
DU_ALVO_RODAR        <- 22
DU_TOL_RODAR         <- 10
MIN_PONTOS_FVOL_RODAR <- 5
USAR_APENAS_VENCIMENTO_MENSAL_RODAR <- TRUE
ATM_BAND_RODAR       <- 0.03
IV_ATM_MIN_RODAR     <- 0.05
IV_ATM_MAX_RODAR     <- 1.00
CARGEO_RODAR         <- "pcp"
OUT_DIR_RODAR        <- DEFAULT_OUT_GRAPHICS
if (!dir.exists(OUT_DIR_RODAR)) dir.create(OUT_DIR_RODAR, recursive = TRUE, showWarnings = FALSE)

resultado <- rodar_vol_implicita(
  ativo = ATIVO_RODAR,
  prefixo_opcoes = PREFIXO_OPCOES_RODAR,
  ticker_spot = TICKER_SPOT_RODAR,
  periodo_inicio = PERIODO_INICIO_RODAR,
  periodo_fim = PERIODO_FIM_RODAR,
  du_alvo = DU_ALVO_RODAR,
  du_tol = DU_TOL_RODAR,
  min_pontos_fvol = MIN_PONTOS_FVOL_RODAR,
  usar_apenas_vencimento_mensal = USAR_APENAS_VENCIMENTO_MENSAL_RODAR,
  atm_band = ATM_BAND_RODAR,
  iv_atm_min = IV_ATM_MIN_RODAR,
  iv_atm_max = IV_ATM_MAX_RODAR,
  carrego = CARGEO_RODAR,
  out_dir = OUT_DIR_RODAR
)
}
