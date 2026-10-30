# =============================================================================
# Simulacao: venda descoberta + custo de aluguel (PCP/BTC) + hedges com opcoes
# Referencias: PCP (carrego_pcp.R), Hull cap. 10-11, collar/estruturas B3
# =============================================================================

SIM_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
if (!exists("DEFAULT_RB3_CACHE_SIM", inherits = TRUE)) {
  source(file.path(SIM_DIR, "config_mr_derivs.R"), local = FALSE)
}
MULT_B3_OPCAO <- 100L

suppressPackageStartupMessages({
  if (!"package:dplyr" %in% search()) library(dplyr)
  if (!"package:stringr" %in% search()) library(stringr)
  if (!"package:oplib" %in% search()) library(oplib)
  if (!"package:lubridate" %in% search()) library(lubridate)
  if (!"package:httr" %in% search()) library(httr)
  if (!"package:jsonlite" %in% search()) library(jsonlite)
  if (!"package:bizdays" %in% search()) library(bizdays)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

eh_vencimento_mensal <- function(x) {
  d <- lubridate::mday(as.Date(x))
  d >= 15 & d <= 21
}

yield_para_aluguel_aa <- function(yield) {
  if (length(yield) == 0 || is.na(yield)) return(NA_real_)
  exp(yield) - 1
}

entrada_caixa_short <- function(quantidade, preco_entrada, mult_ativo = 1L) {
  as.numeric(quantidade) * as.numeric(preco_entrada) * as.numeric(mult_ativo)
}

custo_aluguel_periodo <- function(notional, aluguel_aa, du, base_du = 252L) {
  if (is.na(aluguel_aa) || is.na(notional)) return(NA_real_)
  notional * aluguel_aa * (as.numeric(du) / base_du)
}

obter_selic_ultima <- function(cache_dir, dt = Sys.Date()) {
  dt <- as.Date(dt)
  cache_file <- file.path(cache_dir, "selic_sgs11_cache.rds")
  if (file.exists(cache_file)) {
    sel <- readRDS(cache_file)
    if (is.data.frame(sel) && "refdate" %in% names(sel)) {
      sel <- sel |>
        dplyr::filter(.data$refdate <= dt) |>
        dplyr::arrange(dplyr::desc(.data$refdate))
      if (nrow(sel) > 0) return(sel$selic_anual[1])
    }
  }
  ini <- dt - 30L
  url <- sprintf(
    "https://api.bcb.gov.br/dados/serie/bcdata.sgs.11/dados?formato=json&dataInicial=%s&dataFinal=%s",
    format(ini, "%d/%m/%Y"),
    format(dt, "%d/%m/%Y")
  )
  raw <- tryCatch({
    resp <- httr::GET(url, httr::accept_json(), httr::user_agent("mr-derivs-sim"))
    httr::stop_for_status(resp)
    jsonlite::fromJSON(httr::content(resp, "text", encoding = "UTF-8"))
  }, error = function(e) NULL)
  if (is.null(raw) || length(raw) == 0) return(0.10)
  val <- suppressWarnings(as.numeric(raw$valor))
  val <- val[!is.na(val)]
  if (!length(val)) return(0.10)
  tail(val, 1)
}

tipo_opcao_symbol <- function(symbol) {
  dplyr::case_when(
    stringr::str_detect(symbol, "^[A-Z]{4}[A-L]") ~ "call",
    stringr::str_detect(symbol, "^[A-Z]{4}[M-X]") ~ "put",
    TRUE ~ NA_character_
  )
}

mercado_para_simulacao <- function(
  ticker_spot,
  cache_dir = DEFAULT_RB3_CACHE_SIM,
  du_alvo = 22L,
  du_tol = 15L,
  modo_carrego = c("pcp", "btc_tomador", "btc_doador", "btc", "hibrido"),
  apenas_mensal = TRUE,
  cal = "Brazil/ANBIMA"
) {
  if (identical(modo_carrego, "btc")) modo_carrego <- "btc_tomador"
  modo_carrego <- match.arg(modo_carrego)
  ticker_spot <- toupper(trimws(ticker_spot))
  prefixo <- substr(ticker_spot, 1, 4)
  configurar_cache_rb3(cache_dir)

  bizdays::load_builtin_calendars()
  bizdays.options$set(default.calendar = cal)

  refdate <- ultima_data_ticker(ticker_spot, cache_dir)
  if (!is.finite(refdate)) stop("Sem cotacao para ", ticker_spot, " no cache.")

  dados <- carregar_spot_opcoes(
    ticker_spot = ticker_spot,
    prefixo_opcoes = prefixo,
    periodo_inicio = refdate,
    periodo_fim = refdate,
    cache_dir = cache_dir,
    cal = cal
  )
  if (nrow(dados$spot) == 0) stop("Sem spot em ", format(refdate, "%d/%m/%Y"))
  spot <- dados$spot$close[1]

  selic_aa <- obter_selic_ultima(cache_dir, refdate)
  rate <- log(1 + selic_aa)

  op <- dados$opcoes |>
    dplyr::mutate(
      type = tipo_opcao_symbol(symbol),
      maturity_date = as.Date(.data$maturity_date)
    ) |>
    dplyr::filter(
      !is.na(type),
      !is.na(maturity_date),
      strike_price > 0,
      close > 0,
      dplyr::coalesce(volume, 0) > 0
    ) |>
    dplyr::mutate(
      biz_days = bizdays::bizdays(
        refdate,
        bizdays::following(maturity_date, cal),
        cal
      ),
      time_to_maturity = biz_days / 252,
      rate = rate,
      underlying_price = spot,
      is_venc_mensal = eh_vencimento_mensal(maturity_date)
    ) |>
    dplyr::filter(
      biz_days >= max(1L, du_alvo - du_tol),
      biz_days <= (du_alvo + du_tol)
    )

  if (apenas_mensal) {
    op_m <- op |> dplyr::filter(is_venc_mensal)
    if (nrow(op_m) > 0) op <- op_m
  }
  if (nrow(op) == 0) stop("Sem opcoes no prazo ~", du_alvo, " DU.")

  venc_alvo <- op |>
    dplyr::distinct(maturity_date, biz_days) |>
    dplyr::mutate(dist = abs(biz_days - du_alvo)) |>
    dplyr::slice_min(dist, n = 1, with_ties = FALSE)
  op <- op |> dplyr::filter(maturity_date == venc_alvo$maturity_date[1])

  if (!exists("adicionar_yield_opcoes", mode = "function")) {
    stop("carrego_pcp.R nao carregado — source antes de simulacao_short.R")
  }

  op_pcp <- adicionar_yield_opcoes(
    op,
    spot = spot,
    refdate = refdate,
    modo = "pcp",
    cache_dir = cache_dir,
    cal = cal,
    ticker = ticker_spot
  )
  pcp_yield <- NA_real_
  pcp_forward <- NA_real_
  pcp_strike <- NA_real_
  if (!is.null(op_pcp) && nrow(op_pcp) > 0) {
    pcp_yield <- op_pcp$yield[1]
    pcp_forward <- op_pcp$forward_impl[1]
    pcp_strike <- op_pcp$strike_pcp[1]
  }

  btc_tom <- obter_taxa_tomador(refdate, ticker_spot, cache_dir, cal = cal)
  btc_doa <- obter_taxa_doador(refdate, ticker_spot, cache_dir, cal = cal)

  comparacao_carrego <- tibble::tibble(
    fonte = c("PCP (implicito)", "BTC tomador (short paga)", "BTC doador (quem empresta)"),
    taxa_aa = c(
      yield_para_aluguel_aa(pcp_yield),
      btc_tom$fee_aa,
      btc_doa$fee_aa
    ),
    detalhe = c(
      if (is.finite(pcp_forward)) {
        sprintf("F=%.2f K=%.2f", pcp_forward, pcp_strike)
      } else {
        "sem par call/put ATM"
      },
      paste0(btc_tom$fonte, " — custo de venda descoberta"),
      paste0(btc_doa$fonte, " — nao e custo do short")
    )
  ) |>
    dplyr::mutate(
      taxa_pct = round(taxa_aa * 100, 4)
    )

  yield_escolhido <- switch(
    modo_carrego,
    pcp = pcp_yield,
    btc_tomador = btc_tom$yield,
    btc_doador = btc_doa$yield,
    hibrido = if (is.finite(pcp_yield)) pcp_yield else btc_tom$yield
  )
  carrego_fonte <- switch(
    modo_carrego,
    pcp = "PCP",
    btc_tomador = paste0("BTC_TOMADOR_", btc_tom$fonte),
    btc_doador = paste0("BTC_DOADOR_", btc_doa$fonte),
    hibrido = if (is.finite(pcp_yield)) "PCP" else paste0("BTC_TOMADOR_", btc_tom$fonte)
  )

  if (!is.finite(yield_escolhido)) {
    stop(
      "Sem taxa para modo '", modo_carrego, "'. ",
      "PCP: ", if (is.finite(pcp_yield)) round(yield_para_aluguel_aa(pcp_yield) * 100, 3) else "NA", "% | ",
      "BTC tomador: ", if (is.finite(btc_tom$fee_aa)) round(btc_tom$fee_aa * 100, 3) else "NA", "% | ",
      "BTC doador: ", if (is.finite(btc_doa$fee_aa)) round(btc_doa$fee_aa * 100, 3) else "NA", "%."
    )
  }

  op <- if (modo_carrego == "pcp" && !is.null(op_pcp)) {
    op_pcp
  } else {
    op |> dplyr::mutate(
      yield = yield_escolhido,
      forward_impl = spot * exp((rate - yield_escolhido) * time_to_maturity),
      strike_pcp = NA_real_,
      carrego_fonte = carrego_fonte
    )
  }

  yield_dia <- yield_escolhido
  aluguel_aa <- yield_para_aluguel_aa(yield_dia)

  op <- op |>
    dplyr::mutate(
      iv = tryCatch(
        oplib::bsmimpvol(
          option_prices = close,
          type = type,
          spot = underlying_price,
          strike = strike_price,
          time = time_to_maturity,
          rate = rate,
          yield = yield
        ),
        error = function(e) NA_real_
      ),
      delta = tryCatch(
        oplib::bsmdelta(
          type = type,
          spot = underlying_price,
          strike = strike_price,
          time = time_to_maturity,
          rate = rate,
          yield = yield,
          sigma = iv
        ),
        error = function(e) NA_real_
      )
    )

  list(
    ticker = ticker_spot,
    refdate = refdate,
    spot = spot,
    selic_aa = selic_aa,
    rate = rate,
    yield = yield_dia,
    aluguel_aa = aluguel_aa,
    carrego_fonte = carrego_fonte,
    vencimento = venc_alvo$maturity_date[1],
    du = venc_alvo$biz_days[1],
    opcoes = op,
    comparacao_carrego = comparacao_carrego,
    pcp_forward = pcp_forward,
    pcp_strike = pcp_strike
  )
}

escolher_opcao <- function(op, tipo, spot, moneyness = c("atm", "otm5", "otm10", "itm5")) {
  moneyness <- match.arg(moneyness)
  alvo <- switch(
    moneyness,
    atm = spot,
    otm5 = if (tipo == "call") spot * 1.05 else spot * 0.95,
    otm10 = if (tipo == "call") spot * 1.10 else spot * 0.90,
    itm5 = if (tipo == "call") spot * 0.95 else spot * 1.05
  )
  op |>
    dplyr::filter(type == tipo, !is.na(iv)) |>
    dplyr::mutate(dist = abs(strike_price - alvo)) |>
    dplyr::arrange(dist, dplyr::desc(volume)) |>
    dplyr::slice_head(n = 1)
}

montar_pernas <- function(mercado, quantidade, du_horizonte) {
  op <- mercado$opcoes
  spot <- mercado$spot
  n_base <- max(1L, ceiling(quantidade / MULT_B3_OPCAO))

  call_atm <- escolher_opcao(op, "call", spot, "atm")
  call_otm5 <- escolher_opcao(op, "call", spot, "otm5")
  call_otm10 <- escolher_opcao(op, "call", spot, "otm10")
  put_atm <- escolher_opcao(op, "put", spot, "atm")
  put_otm5 <- escolher_opcao(op, "put", spot, "otm5")

  if (nrow(call_atm) == 0) stop("Sem calls liquidas para simular hedge.")

  delta_atm <- call_atm$delta[1]
  n_delta <- if (is.finite(delta_atm) && delta_atm > 0) {
    max(1L, ceiling(quantidade / (MULT_B3_OPCAO * delta_atm)))
  } else {
    n_base
  }

  perna <- function(row, lado, n) {
    if (nrow(row) == 0) return(NULL)
    list(
      lado = lado,
      type = row$type[1],
      symbol = row$symbol[1],
      strike = row$strike_price[1],
      preco = row$close[1],
      iv = row$iv[1],
      delta = row$delta[1],
      n = as.integer(n),
      custo = n * MULT_B3_OPCAO * row$close[1] * if (lado == "compra") 1 else -1
    )
  }

  list(
    n_base = n_base,
    n_delta = n_delta,
    call_atm = call_atm,
    call_otm5 = call_otm5,
    call_otm10 = call_otm10,
    put_atm = put_atm,
    put_otm5 = put_otm5,
    perna = perna
  )
}

pnl_opcao_venc <- function(tipo, strike, preco, spot_t, lado = c("compra", "venda")) {
  lado <- match.arg(lado)
  payoff <- if (tipo == "call") max(spot_t - strike, 0) else max(strike - spot_t, 0)
  sinal <- if (lado == "compra") 1 else -1
  sinal * (payoff - preco)
}

pnl_estrategia <- function(
  spot_0,
  spot_t,
  quantidade,
  preco_entrada,
  aluguel_aa,
  du,
  pernas = list()
) {
  pnl_short <- quantidade * (preco_entrada - spot_t)
  pnl_aluguel <- -custo_aluguel_periodo(
    quantidade * preco_entrada,
    aluguel_aa,
    du
  )
  pnl_ops <- 0
  for (p in pernas) {
    if (is.null(p)) next
    pnl_ops <- pnl_ops +
      p$n * MULT_B3_OPCAO *
      pnl_opcao_venc(p$type, p$strike, p$preco, spot_t, p$lado)
  }
  pnl_short + pnl_aluguel + pnl_ops
}

grid_cenarios <- function(
  spot_0,
  quantidade,
  preco_entrada,
  aluguel_aa,
  du,
  pernas,
  choques = seq(-0.15, 0.15, by = 0.01)
) {
  spots <- spot_0 * (1 + choques)
  pnl <- vapply(
    spots,
    function(st) {
      pnl_estrategia(
        spot_0, st, quantidade, preco_entrada,
        aluguel_aa, du, pernas
      )
    },
    numeric(1)
  )
  tibble::tibble(
    choque_pct = choques * 100,
    spot = spots,
    pnl = pnl
  )
}

montar_estrategias <- function(mercado, quantidade, preco_entrada, du_horizonte) {
  legs <- montar_pernas(mercado, quantidade, du_horizonte)
  pf <- legs$perna
  n <- legs$n_base
  nd <- legs$n_delta

  mk <- function(id, nome, desc, refs, pernas) {
    custos <- vapply(pernas, function(p) if (is.null(p)) 0 else p$custo, numeric(1))
    premio_liquido <- sum(custos)
    premio_pago <- sum(custos[custos > 0])
    premio_recebido <- -sum(custos[custos < 0])
    resumo_pernas <- paste(
      vapply(
        pernas,
        function(p) {
          if (is.null(p)) return("")
          sprintf(
            "%s %s K=%.2f @ %.2f",
            if (p$lado == "compra") "Compra" else "Venda",
            toupper(p$type),
            p$strike,
            p$preco
          )
        },
        character(1)
      ),
      collapse = " | "
    )
    list(
      id = id,
      nome = nome,
      descricao = desc,
      referencia = refs,
      pernas = pernas,
      resumo_pernas = resumo_pernas,
      premio_liquido = premio_liquido,
      premio_pago = premio_pago,
      premio_recebido = premio_recebido,
      custo_opcoes = premio_liquido,
      grid = grid_cenarios(
        mercado$spot, quantidade, preco_entrada,
        mercado$aluguel_aa, du_horizonte, pernas
      )
    )
  }

  estrategias <- list(
    mk(
      "sem_hedge",
      "Sem hedge",
      "Venda descoberta: entrada de caixa, risco de alta ilimitado, custo de aluguel (BTC/PCP).",
      "Custo de carregar short ~ yield PCP (F=K+e^{rT}(C-P)) ou taxa tomador B3.",
      list()
    )
  )

  if (nrow(legs$call_atm) > 0) {
    p1 <- pf(legs$call_atm, "compra", n)
    estrategias <- c(estrategias, list(mk(
      "call_atm",
      "Call protetiva ATM",
      sprintf(
        "Compra %d call(s) ATM K=%.2f. Limita perdas na alta (Hull: protecao de carteira).",
        p1$n, p1$strike
      ),
      "Hull, Options — protective call; risco de alta do short e neutralizado acima de K.",
      list(p1)
    )))
  }

  if (nrow(legs$call_otm5) > 0) {
    p1 <- pf(legs$call_otm5, "compra", n)
    estrategias <- c(estrategias, list(mk(
      "call_otm5",
      "Call protetiva OTM 5%",
      sprintf("Call OTM K=%.2f: hedge mais barato, protege apenas movimentos maiores.", p1$strike),
      "Seguro parcial — premio menor, dedutivel vs ATM.",
      list(p1)
    )))
  }

  if (nrow(legs$call_atm) > 0 && nrow(legs$call_otm10) > 0) {
    p_long <- pf(legs$call_atm, "compra", n)
    p_short <- pf(legs$call_otm10, "venda", n)
    estrategias <- c(estrategias, list(mk(
      "bull_call_spread",
      "Trava de alta (call spread)",
      sprintf("Compra call K=%.2f + vende call K=%.2f. Protecao com custo reduzido.", p_long$strike, p_short$strike),
      "Spread de calls — custo neto menor que call isolada; ganho de hedge limitado.",
      list(p_long, p_short)
    )))
  }

  if (nrow(legs$call_atm) > 0 && nrow(legs$put_atm) > 0) {
    pc <- pf(legs$call_atm, "compra", n)
    pp <- pf(legs$put_atm, "venda", n)
    estrategias <- c(estrategias, list(mk(
      "conversion",
      "Sintetico long (conversion)",
      sprintf("Compra call + vende put @ K=%.2f. Equivale a comprar o ativo a K — trava o short.", pc$strike),
      "PCP: C-P = (S-K)e^{-qT} — posicao sintetica longa neutraliza delta do short.",
      list(pc, pp)
    )))
  }

  if (nrow(legs$call_otm5) > 0 && nrow(legs$put_otm5) > 0) {
    pc <- pf(legs$call_otm5, "venda", n)
    pp <- pf(legs$put_otm5, "compra", n)
    estrategias <- c(estrategias, list(mk(
      "collar_short",
      "Collar (venda call + compra put)",
      sprintf(
        "Vende call K=%.2f + compra put K=%.2f. Trava na alta (call vendida) e protege na queda (put comprada).",
        pc$strike, pp$strike
      ),
      "Collar para short: venda de call OTM + compra de put OTM (espelho do collar de acao longa).",
      list(pc, pp)
    )))
  }

  if (nrow(legs$call_atm) > 0) {
    pd <- pf(legs$call_atm, "compra", nd)
    estrategias <- c(estrategias, list(mk(
      "delta_neutro",
      sprintf("Delta-neutro (~%d calls)", nd),
      sprintf(
        "%d calls ATM (delta~%.2f) para neutralizar delta do short de %s acoes.",
        pd$n, legs$call_atm$delta[1], format(quantidade, big.mark = ".")
      ),
      "Hedge dinamico estatico (1a ordem); requer rebalanceamento se spot/vol mudam.",
      list(pd)
    )))
  }

  estrategias
}

simular_short_hedge <- function(
  ticker_spot,
  quantidade,
  preco_entrada = NULL,
  du_horizonte = 22L,
  modo_carrego = c("pcp", "btc_tomador", "btc_doador", "btc", "hibrido"),
  cache_dir = DEFAULT_RB3_CACHE_SIM,
  apenas_mensal = TRUE
) {
  modo_carrego <- match.arg(modo_carrego)
  quantidade <- as.numeric(quantidade)
  if (!is.finite(quantidade) || quantidade <= 0) stop("Quantidade invalida.")

  mercado <- mercado_para_simulacao(
    ticker_spot = ticker_spot,
    cache_dir = cache_dir,
    du_alvo = du_horizonte,
    modo_carrego = modo_carrego,
    apenas_mensal = apenas_mensal
  )

  if (is.null(preco_entrada) || !is.finite(preco_entrada)) {
    preco_entrada <- mercado$spot
  }

  caixa <- entrada_caixa_short(quantidade, preco_entrada)
  notional <- caixa
  aluguel <- custo_aluguel_periodo(notional, mercado$aluguel_aa, mercado$du)
  estrategias <- montar_estrategias(mercado, quantidade, preco_entrada, mercado$du)
  names(estrategias) <- vapply(estrategias, `[[`, "", "id")

  tabela_estrategias <- dplyr::bind_rows(lapply(estrategias, function(e) {
    g <- e$grid
    tibble::tibble(
      id = e$id,
      estrategia = e$nome,
      descricao = e$descricao,
      pernas = e$resumo_pernas,
      premio_liquido = e$premio_liquido,
      premio_pago = e$premio_pago,
      premio_recebido = e$premio_recebido,
      pnl_spot_menos_10pct = g$pnl[which.min(abs(g$choque_pct + 10))],
      pnl_spot_mais_10pct = g$pnl[which.min(abs(g$choque_pct - 10))],
      pnl_spot_flat = g$pnl[which.min(abs(g$choque_pct))]
    )
  })) |>
    dplyr::arrange(premio_liquido)

  list(
    ticker = mercado$ticker,
    refdate = mercado$refdate,
    spot = mercado$spot,
    vencimento = mercado$vencimento,
    du = mercado$du,
    quantidade = quantidade,
    preco_entrada = preco_entrada,
    entrada_caixa = caixa,
    notional = notional,
    aluguel_aa = mercado$aluguel_aa,
    aluguel_periodo = aluguel,
    carrego_fonte = mercado$carrego_fonte,
    yield = mercado$yield,
    selic_aa = mercado$selic_aa,
    comparacao_carrego = mercado$comparacao_carrego,
    estrategias = estrategias,
    tabela_estrategias = tabela_estrategias
  )
}
