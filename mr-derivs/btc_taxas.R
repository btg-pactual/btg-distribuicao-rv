# =============================================================================
# BTC / BTB — taxa tomador (B3 Clearing + BTG D0)
# =============================================================================

BTG_BTC_API_URL <- "https://investimentos.btgpactual.com/services/api/btc/public"
B3_BDI_LOAN_URL   <- "https://arquivos.b3.com.br/bdi/table/BTBLoanBalance/{data_inicial}/{data_final}/{page}/{page_size}"
B3_RAPTOR_URL     <- "https://up2dataweb.blob.core.windows.net/raptor/{dd_mm_yyyy}_NEGOCIOSBTB.zip"

CACHE_BTG_HIST    <- "btg_btc_history.rds"
CACHE_B3_TOMADOR  <- "b3_btc_tomador.rds"
CACHE_B3_MANIFEST <- "b3_btc_manifest.rds"
DIR_B3_RAW        <- "b3_btc_raw"

taxa_pct_to_aa <- function(pct) {
  if (length(pct) == 0 || is.na(pct)) return(NA_real_)
  as.numeric(pct) / 100
}

#' Taxa BDI emprestimos registrados: valores ja em decimal a.a. (0.0034 = 0,34%).
taxa_bdi_para_aa <- function(pct) {
  if (length(pct) == 0 || is.na(pct)) return(NA_real_)
  as.numeric(pct)
}

#' Taxa BTG negotiationFee: mesmo formato decimal a.a. (0.0034 = 0,34%).
taxa_btg_para_aa <- function(fee) {
  if (length(fee) == 0 || is.na(fee)) return(NA_real_)
  as.numeric(fee)
}

taxa_aa_to_yield <- function(fee_aa) {
  if (length(fee_aa) == 0 || is.na(fee_aa)) return(NA_real_)
  log(1 + fee_aa)
}

ler_btg_btc_api <- function() {
  resp <- httr::GET(
    BTG_BTC_API_URL,
    httr::accept_json(),
    httr::user_agent("vol-implicita-b3-r")
  )
  httr::stop_for_status(resp)
  txt <- httr::content(resp, "text", encoding = "UTF-8")
  if (grepl("^\\s*<", txt)) stop("BTG BTC retornou HTML (SPA), nao JSON")
  jsonlite::fromJSON(txt, flatten = TRUE)
}

parse_btg_btc_snapshot <- function(raw) {
  fees <- raw$assetsFees
  if (is.null(fees) || nrow(fees) == 0) stop("BTG BTC: assetsFees vazio")
  fees |>
    dplyr::transmute(
      ticker           = toupper(companyCode),
      negotiation_fee  = as.numeric(negotiationFee),
      btc_updated      = as.POSIXct(
        lastModificationDate,
        format = "%Y-%m-%dT%H:%M:%OS",
        tz = "America/Sao_Paulo"
      ),
      snapshot_date    = as.Date(btc_updated)
    ) |>
    dplyr::filter(!is.na(ticker), !is.na(negotiation_fee), negotiation_fee >= 0)
}

atualizar_btg_btc_history <- function(cache_dir) {
  cache_file <- file.path(cache_dir, CACHE_BTG_HIST)
  raw <- tryCatch(
    ler_btg_btc_api(),
    error = function(e) {
      message("  Aviso BTG BTC API: ", conditionMessage(e))
      NULL
    }
  )
  snap <- if (!is.null(raw)) parse_btg_btc_snapshot(raw) else NULL
  hist <- if (file.exists(cache_file)) readRDS(cache_file) else NULL

  if (!is.null(snap)) {
    snap_date <- snap$snapshot_date[1]
    if (!is.null(hist)) {
      hist <- hist |> dplyr::filter(snapshot_date != snap_date)
    }
    hist <- dplyr::bind_rows(hist, snap)
    saveRDS(hist, cache_file)
  } else if (is.null(hist)) {
    stop("BTG BTC indisponivel e sem cache local (", cache_file, ")")
  }

  hist |>
    dplyr::distinct(snapshot_date, ticker, .keep_all = TRUE) |>
    dplyr::arrange(snapshot_date, ticker)
}

obter_btg_d0_snapshot <- function(cache_dir, atualizar = TRUE) {
  cache_file <- file.path(cache_dir, CACHE_BTG_HIST)
  if (atualizar) {
    tryCatch(atualizar_btg_btc_history(cache_dir), error = function(e) NULL)
  }
  if (!file.exists(cache_file)) return(NULL)
  readRDS(cache_file) |>
    dplyr::distinct(snapshot_date, ticker, .keep_all = TRUE) |>
    dplyr::arrange(snapshot_date, ticker)
}

b3_taxas_linha_bdi <- function(row) {
  # BTBLoanBalance: col 10 = media doador, col 13 = media tomador (B3 BDI).
  list(
    taxa_doador_pct = suppressWarnings(as.numeric(row[[10]])),
    taxa_tomador_pct = suppressWarnings(as.numeric(row[[13]]))
  )
}

b3_taxa_tomador_pct_linha_bdi <- function(row) {
  tx <- b3_taxas_linha_bdi(row)
  tx$taxa_tomador_pct
}

b3_agregar_loan_balance <- function(refdate, rows) {
  if (length(rows) == 0) return(NULL)
  parts <- lapply(rows, function(row) {
    ticker <- toupper(as.character(row[[3]]))
    qty    <- suppressWarnings(as.numeric(row[[8]]))
    tx     <- b3_taxas_linha_bdi(row)
    if (is.na(ticker) || ticker == "" || is.na(qty) || qty <= 0) return(NULL)
    if (is.na(tx$taxa_tomador_pct) && is.na(tx$taxa_doador_pct)) return(NULL)
    tibble::tibble(
      ticker = ticker,
      qty = qty,
      taxa_doador_pct = tx$taxa_doador_pct,
      taxa_tomador_pct = tx$taxa_tomador_pct
    )
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0) return(NULL)

  df <- dplyr::bind_rows(parts)
  df |>
    dplyr::group_by(ticker) |>
    dplyr::summarise(
      taxa_doador_aa = {
        ok <- !is.na(taxa_doador_pct)
        if (!any(ok)) NA_real_ else
          sum(taxa_doador_pct[ok] * qty[ok], na.rm = TRUE) / sum(qty[ok], na.rm = TRUE)
      },
      taxa_tomador_aa = {
        ok <- !is.na(taxa_tomador_pct)
        if (!any(ok)) NA_real_ else
          sum(taxa_tomador_pct[ok] * qty[ok], na.rm = TRUE) / sum(qty[ok], na.rm = TRUE)
      },
      .groups = "drop"
    ) |>
    dplyr::mutate(
      refdate = as.Date(refdate),
      fonte   = "B3_BDI_EMPRESTIMOS_REGISTRADOS"
    )
}

b3_bdi_fetch_loan_balance <- function(refdate, page_size = 1000, quiet = TRUE) {
  refdate <- as.Date(refdate)
  page <- 1L
  all_rows <- list()

  while (TRUE) {
    url <- glue::glue(
      "https://arquivos.b3.com.br/bdi/table/BTBLoanBalance/{refdate}/{refdate}/{page}/{page_size}"
    )
    resp <- tryCatch(
      httr::POST(
        url,
        httr::user_agent("vol-implicita-b3-r"),
        httr::content_type_json(),
        body = "",
        httr::timeout(60)
      ),
      error = function(e) e
    )
    if (inherits(resp, "error")) {
      if (!quiet) message("  BDI POST falhou: ", conditionMessage(resp))
      return(NULL)
    }
    if (httr::status_code(resp) >= 400) {
      if (!quiet) message("  BDI status ", httr::status_code(resp))
      return(NULL)
    }

    txt <- httr::content(resp, "text", encoding = "UTF-8")
    if (grepl("^\\s*<", txt)) {
      if (!quiet) message("  BDI retornou HTML")
      return(NULL)
    }
    raw <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
    table <- raw$table
    if (is.null(table) || is.null(table$values)) break

    vals <- table$values
    if (length(vals) == 0) break
    all_rows <- c(all_rows, vals)

    page_count <- suppressWarnings(as.integer(table$pageCount))
    if (is.na(page_count) || page >= page_count) break
    page <- page + 1L
    Sys.sleep(0.15)
  }

  if (length(all_rows) == 0) return(NULL)
  all_rows
}

ler_b3_btc_tomador <- function(cache_dir) {
  path <- file.path(cache_dir, CACHE_B3_TOMADOR)
  if (!file.exists(path)) {
    return(tibble::tibble(
      refdate = as.Date(character()),
      ticker = character(),
      taxa_doador_aa = double(),
      taxa_tomador_aa = double(),
      fonte = character()
    ))
  }
  df <- readRDS(path) |>
    dplyr::mutate(refdate = as.Date(refdate), ticker = toupper(ticker)) |>
    dplyr::distinct(refdate, ticker, .keep_all = TRUE) |>
    dplyr::arrange(refdate, ticker)
  if (!"taxa_doador_aa" %in% names(df)) {
    df$taxa_doador_aa <- NA_real_
  }
  df
}

salvar_b3_btc_tomador <- function(df, cache_dir) {
  path <- file.path(cache_dir, CACHE_B3_TOMADOR)
  df |>
    dplyr::mutate(refdate = as.Date(refdate), ticker = toupper(ticker)) |>
    dplyr::distinct(refdate, ticker, .keep_all = TRUE) |>
    dplyr::arrange(refdate, ticker) |>
    (\(x) {
      saveRDS(x, path)
      x
    })()
}

ler_b3_btc_manifest <- function(cache_dir) {
  path <- file.path(cache_dir, CACHE_B3_MANIFEST)
  if (!file.exists(path)) {
    return(tibble::tibble(
      refdate = as.Date(character()),
      status = character(),
      fonte = character(),
      n_tickers = integer(),
      updated_at = as.POSIXct(character())
    ))
  }
  readRDS(path)
}

salvar_b3_btc_manifest <- function(df, cache_dir) {
  path <- file.path(cache_dir, CACHE_B3_MANIFEST)
  saveRDS(df, path)
}

b3_nome_zip_negociosbtb <- function(refdate) {
  format(as.Date(refdate), "%d-%m-%Y")
}

localizar_zip_negociosbtb <- function(refdate, cache_dir) {
  refdate <- as.Date(refdate)
  stem <- paste0(b3_nome_zip_negociosbtb(refdate), "_NEGOCIOSBTB.zip")
  raw_dir <- file.path(cache_dir, DIR_B3_RAW)
  if (!dir.exists(raw_dir)) return(NULL)

  candidates <- c(
    file.path(raw_dir, stem),
    file.path(raw_dir, format(refdate, "%Y-%m-%d"), stem),
    list.files(
      raw_dir,
      pattern = paste0(b3_nome_zip_negociosbtb(refdate), "_NEGOCIOSBTB\\.zip$"),
      recursive = TRUE,
      full.names = TRUE,
      ignore.case = TRUE
    )
  )
  candidates <- unique(candidates[file.exists(candidates)])
  if (length(candidates) == 0) return(NULL)
  candidates[[1]]
}

extrair_refdate_zip_negociosbtb <- function(path) {
  name <- basename(path)
  m <- regmatches(
    name,
    regexec("(\\d{2})-(\\d{2})-(\\d{4})_NEGOCIOSBTB", name, perl = TRUE)
  )[[1]]
  if (length(m) >= 4) {
    return(as.Date(sprintf("%s-%s-%s", m[4], m[3], m[2])))
  }
  m <- regmatches(
    name,
    regexec("(\\d{4})-(\\d{2})-(\\d{2})_NEGOCIOSBTB", name, perl = TRUE)
  )[[1]]
  if (length(m) >= 4) {
    return(as.Date(sprintf("%s-%s-%s", m[2], m[3], m[4])))
  }
  NA
}

listar_zips_negociosbtb <- function(cache_dir) {
  raw_dir <- file.path(cache_dir, DIR_B3_RAW)
  if (!dir.exists(raw_dir)) return(character())
  list.files(
    raw_dir,
    pattern = "NEGOCIOSBTB\\.zip$",
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )
}

parse_negociosbtb_zip <- function(zip_path, refdate) {
  if (!file.exists(zip_path)) return(NULL)
  if (unname(file.info(zip_path)$size) < 100) return(NULL)
  tmp <- tempfile()
  dir.create(tmp)
  utils::unzip(zip_path, exdir = tmp)
  csvs <- list.files(tmp, pattern = "\\.csv$|\\.txt$", full.names = TRUE, ignore.case = TRUE)
  if (length(csvs) == 0) return(NULL)

  parts <- lapply(csvs, function(f) {
    hdr <- readLines(f, n = 1, warn = FALSE, encoding = "latin1")
    sep <- if (grepl(";", hdr[[1]], fixed = TRUE)) ";" else ","
    df <- tryCatch(
      utils::read.csv2(f, sep = sep, stringsAsFactors = FALSE, fileEncoding = "latin1"),
      error = function(e) NULL
    )
    if (is.null(df) || nrow(df) == 0) return(NULL)

    ticker_col <- intersect(
      names(df),
      c("TckrSymb", "TickerSymbol", "Papel", "CodigoIF", "Ticker")
    )[1]
    rate_col <- intersect(
      names(df),
      c(
        "IntrstRateTermTrad", "TaxaDeJurosDoTermoDoNegocio",
        "Taxa % Remuneração", "TaxaRemuneracao", "TaxaDeJurosDoTermoDoNegocio"
      )
    )[1]
    qty_col <- intersect(
      names(df),
      c("TradQty", "Quantidade", "QuantidadeNegociada", "TradgQty")
    )[1]
    if (is.na(ticker_col) || is.na(rate_col)) return(NULL)

    out <- tibble::tibble(
      ticker = toupper(df[[ticker_col]]),
      taxa_raw = suppressWarnings(as.numeric(df[[rate_col]])),
      qty = if (!is.na(qty_col)) suppressWarnings(as.numeric(df[[qty_col]])) else 1
    )
    out |>
      dplyr::filter(!is.na(ticker), ticker != "", !is.na(taxa_raw), taxa_raw >= 0) |>
      dplyr::mutate(
        qty = dplyr::if_else(is.na(qty) | qty <= 0, 1, qty),
        taxa_aa = dplyr::if_else(taxa_raw > 1, taxa_raw / 100, taxa_raw)
      )
  })

  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0) return(NULL)

  df <- dplyr::bind_rows(parts)
  df |>
    dplyr::group_by(ticker) |>
    dplyr::summarise(
      taxa_tomador_aa = {
        ok <- !is.na(taxa_aa)
        if (!any(ok)) NA_real_ else
          sum(taxa_aa[ok] * qty[ok], na.rm = TRUE) / sum(qty[ok], na.rm = TRUE)
      },
      taxa_doador_aa = NA_real_,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      refdate = as.Date(refdate),
      fonte   = "B3_NEGOCIOSBTB"
    )
}

b3_download_raptor_zip <- function(refdate, dest_path) {
  dd <- b3_nome_zip_negociosbtb(refdate)
  url <- glue::glue("https://up2dataweb.blob.core.windows.net/raptor/{dd}_NEGOCIOSBTB.zip")
  resp <- tryCatch(
    httr::GET(url, httr::user_agent("vol-implicita-b3-r"), httr::timeout(90)),
    error = function(e) NULL
  )
  if (is.null(resp) || httr::status_code(resp) >= 400) return(FALSE)
  bin <- httr::content(resp, as = "raw")
  if (length(bin) < 100) return(FALSE)
  writeBin(bin, dest_path)
  TRUE
}

b3_baixar_taxas_dia <- function(refdate, cache_dir, quiet = FALSE, somente_zip = FALSE) {
  refdate <- as.Date(refdate)
  raw_dir <- file.path(cache_dir, DIR_B3_RAW)
  if (!dir.exists(raw_dir)) dir.create(raw_dir, recursive = TRUE)

  zip_local <- localizar_zip_negociosbtb(refdate, cache_dir)
  if (!is.null(zip_local)) {
    agg_zip <- parse_negociosbtb_zip(zip_local, refdate)
    if (!is.null(agg_zip) && nrow(agg_zip) > 0) {
      return(list(df = agg_zip, status = "ok", fonte = agg_zip$fonte[1]))
    }
  }
  if (isTRUE(somente_zip)) {
    return(list(df = NULL, status = "sem_zip", fonte = NA_character_))
  }

  rows <- b3_bdi_fetch_loan_balance(refdate, quiet = quiet)
  agg <- if (!is.null(rows)) b3_agregar_loan_balance(refdate, rows) else NULL
  if (!is.null(agg) && nrow(agg) > 0) {
    return(list(df = agg, status = "ok", fonte = agg$fonte[1]))
  }

  zip_name <- paste0(b3_nome_zip_negociosbtb(refdate), "_NEGOCIOSBTB.zip")
  zip_fallback <- file.path(raw_dir, zip_name)
  if (!file.exists(zip_fallback)) {
    ok <- b3_download_raptor_zip(refdate, zip_fallback)
    if (ok) {
      agg2 <- parse_negociosbtb_zip(zip_fallback, refdate)
      if (!is.null(agg2) && nrow(agg2) > 0) {
        return(list(df = agg2, status = "ok", fonte = agg2$fonte[1]))
      }
    }
  } else {
    agg2 <- parse_negociosbtb_zip(zip_fallback, refdate)
    if (!is.null(agg2) && nrow(agg2) > 0) {
      return(list(df = agg2, status = "ok", fonte = agg2$fonte[1]))
    }
  }

  list(df = NULL, status = "sem_dado", fonte = NA_character_)
}

persistir_b3_btc_hit <- function(refdate, hit, cache_dir) {
  refdate <- as.Date(refdate)
  manifest <- ler_b3_btc_manifest(cache_dir)
  row_manifest <- tibble::tibble(
    refdate = refdate,
    status = hit$status,
    fonte = hit$fonte,
    n_tickers = if (!is.null(hit$df)) nrow(hit$df) else 0L,
    updated_at = Sys.time()
  )
  manifest <- manifest |> dplyr::filter(refdate != !!refdate)
  manifest <- dplyr::bind_rows(manifest, row_manifest) |> dplyr::arrange(refdate)
  salvar_b3_btc_manifest(manifest, cache_dir)

  if (hit$status != "ok" || is.null(hit$df)) return(NULL)

  hist <- ler_b3_btc_tomador(cache_dir)
  hist <- hist |> dplyr::filter(refdate != refdate)
  hist <- dplyr::bind_rows(hist, hit$df)
  salvar_b3_btc_tomador(hist, cache_dir)
  hit$df
}

atualizar_b3_btc_tomador_dia <- function(
  refdate,
  cache_dir,
  quiet = FALSE,
  somente_zip = FALSE
) {
  refdate <- as.Date(refdate)
  hit <- b3_baixar_taxas_dia(refdate, cache_dir, quiet = quiet, somente_zip = somente_zip)
  persistir_b3_btc_hit(refdate, hit, cache_dir)
}

importar_zip_negociosbtb <- function(zip_path, cache_dir, forcar = FALSE) {
  zip_path <- normalizePath(zip_path, winslash = "/", mustWork = TRUE)
  refdate <- extrair_refdate_zip_negociosbtb(zip_path)
  if (is.na(refdate)) {
    message("  Nome invalido (esperado DD-MM-AAAA_NEGOCIOSBTB.zip): ", basename(zip_path))
    return(NULL)
  }

  if (!forcar) {
    manifest <- ler_b3_btc_manifest(cache_dir)
    ja <- manifest |>
      dplyr::filter(refdate == !!refdate, status == "ok", fonte == "B3_NEGOCIOSBTB")
    if (nrow(ja) > 0) {
      message(sprintf("  %s ja importado de NEGOCIOSBTB, pulando", refdate))
      return(NULL)
    }
  }

  agg <- parse_negociosbtb_zip(zip_path, refdate)
  hit <- if (!is.null(agg) && nrow(agg) > 0) {
    list(df = agg, status = "ok", fonte = "B3_NEGOCIOSBTB")
  } else {
    list(df = NULL, status = "zip_invalido", fonte = NA_character_)
  }
  message(sprintf(
    "  %s <- %s (%d tickers)",
    refdate,
    basename(zip_path),
    if (!is.null(hit$df)) nrow(hit$df) else 0L
  ))
  persistir_b3_btc_hit(refdate, hit, cache_dir)
}

importar_zips_raw <- function(cache_dir, forcar = FALSE) {
  zips <- listar_zips_negociosbtb(cache_dir)
  raw_dir <- file.path(cache_dir, DIR_B3_RAW)
  message(sprintf("ZIPs NEGOCIOSBTB em %s: %d arquivo(s)", raw_dir, length(zips)))
  if (length(zips) == 0) {
    message("  Coloque arquivos DD-MM-AAAA_NEGOCIOSBTB.zip nessa pasta.")
    return(0L)
  }

  ok <- 0L
  for (z in zips) {
    res <- importar_zip_negociosbtb(z, cache_dir, forcar = forcar)
    if (!is.null(res)) ok <- ok + 1L
  }
  message(sprintf("Importacao concluida: %d/%d ZIPs com taxa", ok, length(zips)))
  ok
}

obter_pregao_atual <- function(cal = "Brazil/ANBIMA") {
  bizdays::preceding(Sys.Date(), cal)
}

taxa_btc_label <- function(fee_aa, fonte, lado = "tomador") {
  if (length(fee_aa) == 0 || is.na(fee_aa)) return(sprintf("sem taxa BTC %s", lado))
  sprintf("%.4f%% a.a. %s (%s)", fee_aa * 100, lado, fonte)
}

#' Taxa BTC/BTB — tomador (short paga) ou doador (quem empresta recebe).
obter_taxa_btc <- function(
  refdate,
  ticker,
  cache_dir,
  lado = c("tomador", "doador"),
  pregao_atual = NULL,
  btg_snap = NULL,
  b3_df = NULL,
  cal = "Brazil/ANBIMA",
  tol_dias_btg = 7L
) {
  lado <- match.arg(lado)
  refdate <- as.Date(refdate)
  ticker  <- toupper(ticker)
  vazio <- list(yield = NA_real_, fee_aa = NA_real_, fonte = NA_character_, lado = lado)
  if (is.null(pregao_atual)) pregao_atual <- obter_pregao_atual(cal)
  pregao_atual <- as.Date(pregao_atual)
  if (refdate > pregao_atual) refdate <- pregao_atual

  dias_dif <- as.integer(pregao_atual - refdate)

  if (lado == "tomador" && dias_dif >= 0L && dias_dif <= tol_dias_btg) {
    snap <- btg_snap
    if (is.null(snap)) snap <- obter_btg_d0_snapshot(cache_dir, atualizar = TRUE)
    if (!is.null(snap)) {
      sel <- snap |> dplyr::filter(ticker == !!ticker)
      if (nrow(sel) > 0) {
        sel <- sel |> dplyr::slice_max(snapshot_date, n = 1, with_ties = FALSE)
        fee <- taxa_btg_para_aa(sel$negotiation_fee[1])
        return(list(
          yield = taxa_aa_to_yield(fee),
          fee_aa = fee,
          fonte = "BTG",
          lado = lado
        ))
      }
    }
  }

  b3 <- b3_df
  if (is.null(b3)) b3 <- ler_b3_btc_tomador(cache_dir)
  campo <- if (lado == "tomador") "taxa_tomador_aa" else "taxa_doador_aa"

  if (nrow(b3) > 0) {
    sel <- b3 |> dplyr::filter(refdate == !!refdate, ticker == !!ticker)
    if (nrow(sel) == 0 || is.na(sel[[campo]][1])) {
      sel <- b3 |>
        dplyr::filter(ticker == !!ticker, !is.na(.data[[campo]])) |>
        dplyr::arrange(dplyr::desc(refdate)) |>
        dplyr::slice_head(n = 1)
    }
    if (nrow(sel) > 0 && !is.na(sel[[campo]][1])) {
      fee <- taxa_bdi_para_aa(sel[[campo]][1])
      return(list(
        yield = taxa_aa_to_yield(fee),
        fee_aa = fee,
        fonte = sel$fonte[1],
        lado = lado
      ))
    }
  }

  rows_bdi <- tryCatch(b3_bdi_fetch_loan_balance(refdate, quiet = TRUE), error = function(e) NULL)
  if (!is.null(rows_bdi)) {
    agg <- b3_agregar_loan_balance(refdate, rows_bdi)
    if (!is.null(agg) && nrow(agg) > 0) {
      sel <- agg |> dplyr::filter(ticker == !!ticker)
      if (nrow(sel) > 0 && !is.na(sel[[campo]][1])) {
        fee <- taxa_bdi_para_aa(sel[[campo]][1])
        return(list(
          yield = taxa_aa_to_yield(fee),
          fee_aa = fee,
          fonte = paste0(sel$fonte[1], "_LIVE"),
          lado = lado
        ))
      }
    }
  }

  if (lado == "tomador") {
    hist <- tryCatch(readRDS(file.path(cache_dir, CACHE_BTG_HIST)), error = function(e) NULL)
    if (!is.null(hist) && nrow(hist) > 0) {
      sel <- hist |>
        dplyr::filter(ticker == !!ticker) |>
        dplyr::arrange(dplyr::desc(snapshot_date)) |>
        dplyr::slice_head(n = 1)
      if (nrow(sel) > 0) {
        fee <- taxa_btg_para_aa(sel$negotiation_fee[1])
        return(list(
          yield = taxa_aa_to_yield(fee),
          fee_aa = fee,
          fonte = "BTG_HIST",
          lado = lado
        ))
      }
    }
  }

  vazio
}

obter_taxa_tomador <- function(
  refdate,
  ticker,
  cache_dir,
  pregao_atual = NULL,
  btg_snap = NULL,
  b3_df = NULL,
  cal = "Brazil/ANBIMA"
) {
  obter_taxa_btc(
    refdate, ticker, cache_dir,
    lado = "tomador",
    pregao_atual = pregao_atual,
    btg_snap = btg_snap,
    b3_df = b3_df,
    cal = cal
  )
}

obter_taxa_doador <- function(
  refdate,
  ticker,
  cache_dir,
  pregao_atual = NULL,
  btg_snap = NULL,
  b3_df = NULL,
  cal = "Brazil/ANBIMA"
) {
  obter_taxa_btc(
    refdate, ticker, cache_dir,
    lado = "doador",
    pregao_atual = pregao_atual,
    btg_snap = btg_snap,
    b3_df = b3_df,
    cal = cal
  )
}
