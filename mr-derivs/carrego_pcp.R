# =============================================================================
# Carrego implicito via put-call parity (COTAHIST opcoes)
# F = K + exp(r*T)*(C-P)  ;  yield = r - ln(F/S)/T
# =============================================================================

#' Par call/put no mesmo strike e vencimento -> forward sintetico e yield BSM.
#'
#' @param op_maturity data.frame com type, close, strike_price, volume,
#'   time_to_maturity, rate (um vencimento).
#' @param spot preco do underlying no dia.
#' @param atm_band faixa relativa |K/S - 1| maxima para o par.
#' @param max_fw_rel |F/S - 1| maximo aceitavel.
#' @return lista yield, forward, strike, fonte ou NULL se invalido.
obter_yield_pcp <- function(
  op_maturity,
  spot,
  atm_band = 0.03,
  max_fw_rel = 0.15,
  min_volume = 1,
  max_carry_aa = 0.35
) {
  if (is.null(op_maturity) || nrow(op_maturity) == 0) return(NULL)
  if (length(spot) == 0 || is.na(spot) || spot <= 0) return(NULL)

  t <- op_maturity$time_to_maturity[1]
  r <- op_maturity$rate[1]
  if (is.na(t) || t <= 0 || is.na(r)) return(NULL)

  calls <- op_maturity |>
    dplyr::filter(type == "call", close > 0, volume >= min_volume) |>
    dplyr::transmute(
      strike_price,
      close_c = close,
      vol_c = volume
    )
  puts <- op_maturity |>
    dplyr::filter(type == "put", close > 0, volume >= min_volume) |>
    dplyr::transmute(
      strike_price,
      close_p = close,
      vol_p = volume
    )
  if (nrow(calls) == 0 || nrow(puts) == 0) return(NULL)

  pares <- dplyr::inner_join(calls, puts, by = "strike_price")
  if (nrow(pares) == 0) return(NULL)

  pares <- pares |>
    dplyr::mutate(
      dist_atm = abs(strike_price - spot) / spot,
      vol_min  = pmin(vol_c, vol_p),
      forward  = strike_price + exp(r * t) * (close_c - close_p),
      fw_rel   = forward / spot - 1,
      yield    = r - log(forward / spot) / t,
      carry_aa = exp(yield) - 1
    ) |>
    dplyr::filter(
      is.finite(forward), forward > 0,
      is.finite(yield), is.finite(carry_aa),
      dist_atm <= atm_band,
      abs(fw_rel) <= max_fw_rel,
      # rejeita PCP absurdo (ex.: -13% a.a. em ETF liquido = par ruim / pregao incompleto)
      abs(carry_aa) <= max_carry_aa
    ) |>
    dplyr::arrange(dist_atm, dplyr::desc(vol_min))

  if (nrow(pares) == 0) return(NULL)

  best <- pares[1, ]
  list(
    yield   = best$yield,
    forward = best$forward,
    strike  = best$strike_price,
    carry_aa = best$carry_aa,
    fonte   = "PCP"
  )
}

#' Aplica carrego (PCP e/ou BTC) por vencimento nas opcoes do dia.
adicionar_yield_opcoes <- function(
  op_base,
  spot,
  refdate,
  modo = c("pcp", "btc", "hibrido"),
  cache_dir = NULL,
  pregao_atual = NULL,
  btg_snap = NULL,
  b3_df = NULL,
  cal = "Brazil/ANBIMA",
  ticker = NULL,
  atm_band = 0.03,
  max_fw_rel = 0.15
) {
  modo <- match.arg(modo)
  if (nrow(op_base) == 0) return(NULL)

  if (modo %in% c("pcp", "hibrido")) {
    yield_map <- op_base |>
      dplyr::group_by(maturity_date) |>
      dplyr::group_modify(\(.x, .y) {
        pcp <- obter_yield_pcp(
          .x, spot = spot, atm_band = atm_band, max_fw_rel = max_fw_rel
        )
        if (is.null(pcp)) {
          return(tibble::tibble(
            yield = numeric(),
            forward_impl = numeric(),
            strike_pcp = numeric(),
            carrego_fonte = character()
          ))
        }
        tibble::tibble(
          yield = pcp$yield,
          forward_impl = pcp$forward,
          strike_pcp = pcp$strike,
          carrego_fonte = pcp$fonte
        )
      }) |>
      dplyr::ungroup()

    if (nrow(yield_map) > 0) {
      out <- op_base |>
        dplyr::inner_join(yield_map, by = "maturity_date")
      if (nrow(out) > 0) return(out)
    }
    if (identical(modo, "pcp")) return(NULL)
  }

  if (modo %in% c("btc", "hibrido")) {
    taxa <- obter_taxa_tomador(
      refdate, ticker, cache_dir,
      pregao_atual = pregao_atual,
      btg_snap = btg_snap,
      b3_df = b3_df,
      cal = cal
    )
    if (is.na(taxa$yield)) return(NULL)
    op_base |>
      dplyr::mutate(
        yield = taxa$yield,
        forward_impl = underlying_price * exp((rate - taxa$yield) * time_to_maturity),
        strike_pcp = NA_real_,
        carrego_fonte = taxa$fonte
      )
  } else {
    NULL
  }
}

carry_label_from_yield <- function(yield, fonte, refdate = NULL) {
  if (length(yield) == 0 || is.na(yield)) return("sem carrego")
  carry_aa <- exp(yield) - 1
  dt_txt <- if (is.null(refdate)) "" else paste0(" ", refdate)
  sprintf("%.4f%% a.a. impl. (%s%s)", carry_aa * 100, fonte, dt_txt)
}
