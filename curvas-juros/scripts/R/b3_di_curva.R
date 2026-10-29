# API B3 (arquivos.b3.com.br) — Negócios consolidados → curva DI1
# Ref.: TradeInformationConsolidated (boletim / negócios consolidados)

baixar_negocios_b3 <- function(data_ref,
                               file_name = "TradeInformationConsolidated",
                               cache_dir = "data/raw/b3") {
  data_ref <- as.Date(data_ref)
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_path <- file.path(
    cache_dir,
    paste0(file_name, "_", format(data_ref, "%Y%m%d"), ".csv")
  )
  if (file.exists(cache_path) && file.info(cache_path)$size > 1000) {
    return(cache_path)
  }

  url_req <- "https://arquivos.b3.com.br/api/download/requestname"
  r1 <- httr::GET(
    url_req,
    query = list(
      fileName = file_name,
      date = format(data_ref, "%Y-%m-%d")
    ),
    httr::timeout(120)
  )
  if (httr::status_code(r1) != 200L) {
    stop(
      "B3 requestname HTTP ", httr::status_code(r1),
      " (", format(data_ref, "%d/%m/%Y"), ")"
    )
  }
  meta <- jsonlite::fromJSON(httr::content(r1, as = "text", encoding = "UTF-8"))
  token <- meta$token
  if (is.null(token) || !nzchar(token)) {
    stop("Token B3 ausente em ", format(data_ref, "%d/%m/%Y"))
  }

  r2 <- httr::GET(
    "https://arquivos.b3.com.br/api/download/",
    query = list(token = token),
    httr::timeout(240)
  )
  if (httr::status_code(r2) != 200L) {
    stop("B3 download HTTP ", httr::status_code(r2))
  }
  txt <- httr::content(r2, as = "text", encoding = "UTF-8")
  if (nchar(txt) < 500L ||
      (!grepl("RptDt;", txt) && !grepl("TckrSymb;", txt))) {
    stop(
      "CSV indisponível na API para ",
      format(data_ref, "%d/%m/%Y"),
      " (use fallback PriceReport / PR)."
    )
  }
  writeLines(txt, cache_path, useBytes = TRUE)
  cache_path
}

is_zip_ok <- function(path, min_bytes = 10000L) {
  if (!file.exists(path)) return(FALSE)
  if (file.info(path)$size < min_bytes) return(FALSE)
  hdr <- readBin(path, what = raw(2), n = 2)
  length(hdr) == 2L && all(hdr == as.raw(c(0x50, 0x4B)))
}

baixar_pr_b3 <- function(data_ref,
                         cache_dir = "data/raw/b3/pr",
                         max_tentativas = 3L,
                         timeout_seg = 180L) {
  data_ref <- as.Date(data_ref)
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  tag <- format(data_ref, "%y%m%d")
  cache_path <- file.path(cache_dir, paste0("PR", tag, ".zip"))
  if (is_zip_ok(cache_path)) {
    return(cache_path)
  }

  url <- paste0(
    "https://www.b3.com.br/pesquisapregao/download?filelist=PR",
    tag, ".zip"
  )
  tmp <- paste0(cache_path, ".part")
  last_err <- NULL
  for (i in seq_len(max_tentativas)) {
    ok <- FALSE
    tryCatch({
      h <- curl::new_handle()
      curl::handle_setopt(
        h,
        timeout = timeout_seg,
        followlocation = TRUE,
        ssl_verifypeer = TRUE
      )
      curl::handle_setheaders(h, `User-Agent` = "Mozilla/5.0 (curvas-juros)")
      curl::curl_download(url, tmp, handle = h)
      ok <- is_zip_ok(tmp)
    }, error = function(e) {
      last_err <<- conditionMessage(e)
    })
    if (!ok) {
      tryCatch({
        httr::GET(
          url,
          httr::write_disk(tmp, overwrite = TRUE),
          httr::timeout(timeout_seg),
          httr::user_agent("Mozilla/5.0 (curvas-juros)")
        )
        ok <- is_zip_ok(tmp)
      }, error = function(e) {
        last_err <<- conditionMessage(e)
      })
    }
    if (ok) {
      file.rename(tmp, cache_path)
      return(cache_path)
    }
    if (file.exists(tmp)) file.remove(tmp)
    Sys.sleep(min(5L * i, 15L))
  }
  stop(
    "Download PR", tag, " falhou (",
    format(data_ref, "%d/%m/%Y"), "): ",
    if (is.null(last_err)) "arquivo inválido" else last_err
  )
}

extrair_xmls_pricereport <- function(pr_zip) {
  td <- tempfile()
  dir.create(td)
  utils::unzip(pr_zip, exdir = td)
  files <- list.files(td, recursive = TRUE, full.names = TRUE)
  inner <- files[grepl("\\.zip$", files, ignore.case = TRUE)][1]
  if (!is.na(inner)) {
    utils::unzip(inner, exdir = td)
    files <- list.files(td, recursive = TRUE, full.names = TRUE)
  }
  files[grepl("\\.xml$", files, ignore.case = TRUE)]
}

ler_curva_di1_pricereport_xml <- function(xml_path, data_ref) {
  ns <- c(d = "urn:bvmf.217.01.xsd")
  doc <- xml2::read_xml(xml_path)
  nodes <- xml2::xml_find_all(doc, "//d:PricRpt", ns = ns)
  if (length(nodes) == 0L) {
    return(tibble::tibble())
  }

  rows <- lapply(nodes, function(node) {
    sym <- xml2::xml_text(xml2::xml_find_first(node, ".//d:TckrSymb", ns = ns))
    if (!grepl("^DI1", sym)) {
      return(NULL)
    }
    tax <- xml2::xml_text(xml2::xml_find_first(node, ".//d:AdjstdQtTax", ns = ns))
    pu <- xml2::xml_text(xml2::xml_find_first(node, ".//d:AdjstdQt", ns = ns))
    data.frame(
      simbolo = sym,
      taxa_aa = as.numeric(tax),
      pu_ajuste = as.numeric(pu),
      stringsAsFactors = FALSE
    )
  })
  df <- do.call(rbind, rows)
  if (is.null(df) || nrow(df) == 0L) {
    return(tibble::tibble())
  }

  df |>
    tibble::as_tibble() |>
    dplyr::mutate(
      data = as.Date(data_ref),
      codigo_venc = sub("^DI1", "", .data$simbolo),
      vencimento = vapply(
        codigo_venc,
        codigo_vencimento_di,
        FUN.VALUE = as.Date("2000-01-01"),
        refdate = as.Date(data_ref)
      ),
      vencimento = as.Date(vencimento, origin = "1970-01-01"),
      prazo_dias = as.integer(vencimento - data),
      prazo_anos = prazo_dias / 365.25
    ) |>
    dplyr::filter(!is.na(vencimento), !is.na(taxa_aa), prazo_dias > 0) |>
    dplyr::arrange(vencimento) |>
    dplyr::select(
      data, simbolo, codigo_venc, vencimento,
      prazo_dias, prazo_anos, taxa_aa, pu_ajuste
    )
}

ler_curva_di1_pricereport <- function(data_ref, pr_zip = NULL) {
  data_ref <- as.Date(data_ref)
  if (is.null(pr_zip)) {
    pr_zip <- baixar_pr_b3(data_ref)
  }
  xmls <- extrair_xmls_pricereport(pr_zip)
  if (length(xmls) == 0L) {
    stop("Nenhum XML no PriceReport ", basename(pr_zip))
  }
  for (xp in xmls) {
    curva <- ler_curva_di1_pricereport_xml(xp, data_ref)
    if (nrow(curva) > 0L) {
      return(curva)
    }
  }
  tibble::tibble()
}

ultimo_dia_util_simples <- function(d) {
  d <- as.Date(d)
  while (lubridate::wday(d, week_start = 1L) >= 6L) {
    d <- d - 1L
  }
  d
}

datas_mensais_di <- function(data_fim, n_meses) {
  data_fim <- ultimo_dia_util_simples(as.Date(data_fim))
  meses_fim <- lubridate::floor_date(data_fim, "month")
  refs <- seq.Date(
    meses_fim,
    by = "-1 month",
    length.out = as.integer(n_meses)
  )
  vapply(
    refs,
    function(m) {
      ultimo_dia_util_simples(lubridate::ceiling_date(m, "month") - 1L)
    },
    FUN.VALUE = as.Date("2000-01-01")
  )
}

obter_curva_di1 <- function(data_ref, cache_dir = "data/raw/b3") {
  data_ref <- as.Date(data_ref)
  cache_curva <- file.path(
    "data/processed/di_curva",
    paste0("di_", format(data_ref, "%Y%m%d"), ".csv")
  )
  if (file.exists(cache_curva) && file.info(cache_curva)$size > 50) {
    out <- readr::read_csv(
      cache_curva,
      col_types = readr::cols(
        data = readr::col_date(),
        vencimento = readr::col_date(),
        simbolo = readr::col_character(),
        codigo_venc = readr::col_character(),
        prazo_dias = readr::col_integer(),
        prazo_anos = readr::col_double(),
        taxa_aa = readr::col_double(),
        pu_ajuste = readr::col_double(),
        fonte = readr::col_character()
      )
    )
    return(out)
  }

  curva <- tryCatch(
    {
      path <- baixar_negocios_b3(data_ref, cache_dir = cache_dir)
      df <- ler_curva_di1_csv(path, data_ref)
      if (nrow(df) > 0L) {
        df$fonte <- "api_negocios"
      }
      df
    },
    error = function(e) {
      NULL
    }
  )

  if (is.null(curva) || nrow(curva) == 0L) {
    curva <- ler_curva_di1_pricereport(data_ref)
    if (nrow(curva) > 0L) {
      curva$fonte <- "pricereport_pr"
    }
  }

  if (nrow(curva) > 0L) {
    readr::write_csv(curva, cache_curva)
  }
  curva
}

parse_num_br <- function(x) {
  if (is.numeric(x)) return(x)
  x <- as.character(x)
  x <- gsub("\\.", "", x)
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

# Código BMF (F27, N26, …) → 1º dia do mês de vencimento
codigo_vencimento_di <- function(codigo, refdate) {
  codigo <- toupper(trimws(codigo))
  if (nchar(codigo) < 2L) return(as.Date(NA))
  mes_letra <- substr(codigo, 1, 1)
  ano2 <- as.integer(substr(codigo, 2, nchar(codigo)))
  if (is.na(ano2)) return(as.Date(NA))
  ano_full <- ano2 + 2000L
  if (!is.na(refdate) && ano_full < as.integer(format(refdate, "%Y")) - 1L) {
    ano_full <- ano_full + 100L
  }
  meses <- c(
    F = 1L, G = 2L, H = 3L, J = 4L, K = 5L, M = 6L,
    N = 7L, Q = 8L, U = 9L, V = 10L, X = 11L, Z = 12L
  )
  mes <- meses[[mes_letra]]
  if (is.null(mes)) return(as.Date(NA))
  as.Date(sprintf("%04d-%02d-01", ano_full, mes))
}

ler_curva_di1_csv <- function(path, data_ref) {
  linhas <- readLines(path, encoding = "UTF-8", warn = FALSE)
  if (length(linhas) < 2L) return(tibble::tibble())

  ini <- grep("^RptDt;", linhas)[1]
  if (is.na(ini)) ini <- grep("TckrSymb", linhas)[1]
  if (is.na(ini)) stop("Cabeçalho CSV B3 não encontrado em ", path)

  df <- utils::read.csv2(
    text = paste(linhas[ini:length(linhas)], collapse = "\n"),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  names(df) <- trimws(names(df))

  if (!all(c("TckrSymb", "SgmtNm") %in% names(df))) {
    stop("Colunas esperadas ausentes no CSV B3.")
  }

  df <- df |>
    dplyr::filter(
      grepl("^DI1", .data$TckrSymb),
      .data$SgmtNm == "FINANCIAL"
    )

  if (nrow(df) == 0L) return(tibble::tibble())

  taxa_col <- if ("AdjstdQtTax" %in% names(df)) "AdjstdQtTax" else "RefPric"
  pu_col <- if ("AdjstdQt" %in% names(df)) "AdjstdQt" else "LastPric"

  df |>
    dplyr::mutate(
      data = as.Date(data_ref),
      simbolo = .data$TckrSymb,
      codigo_venc = sub("^DI1", "", .data$TckrSymb),
      vencimento = vapply(
        codigo_venc,
        codigo_vencimento_di,
        FUN.VALUE = as.Date("2000-01-01"),
        refdate = as.Date(data_ref)
      ),
      vencimento = as.Date(vencimento, origin = "1970-01-01"),
      taxa_aa = parse_num_br(.data[[taxa_col]]),
      pu_ajuste = if (pu_col %in% names(df)) parse_num_br(.data[[pu_col]]) else NA_real_,
      prazo_dias = as.integer(vencimento - data),
      prazo_anos = prazo_dias / 365.25
    ) |>
    dplyr::filter(!is.na(vencimento), !is.na(taxa_aa), prazo_dias > 0) |>
    dplyr::arrange(vencimento) |>
    dplyr::select(
      data, simbolo, codigo_venc, vencimento,
      prazo_dias, prazo_anos, taxa_aa, pu_ajuste
    )
}
