# =============================================================================
# 01_download_dados.R — Tesouro Transparente + ETTJ ANBIMA (últimos dias úteis)
# =============================================================================

source("scripts/00_setup.R")

# --- Tesouro -----------------------------------------------------------------
csv_local <- file.path("data", "raw", "PrecoTaxaTesouroDireto.csv")
csv_irmao <- file.path("..", "taxas tesouro", "data", "PrecoTaxaTesouroDireto.csv")

if (file.exists(csv_irmao)) {
  file.copy(csv_irmao, csv_local, overwrite = TRUE)
  message("Tesouro: copiado de taxas tesouro/ → ", csv_local)
} else if (!file.exists(csv_local) ||
           difftime(Sys.Date(), file.info(csv_local)$mtime, units = "days") > 1) {
  message("Baixando CSV Tesouro Transparente...")
  h <- curl::new_handle()
  curl::handle_setopt(h, timeout = 180, followlocation = TRUE)
  curl::handle_setheaders(
    h,
    `User-Agent` = "Mozilla/5.0 (compatible; curvas-juros/1.0; R)"
  )
  curl::curl_download(URL_CSV_TESOURO, csv_local, handle = h)
  message("Salvo: ", csv_local)
} else {
  message("Tesouro: usando cache ", csv_local)
}

parse_num_br <- function(x) {
  if (is.numeric(x)) return(x)
  x <- as.character(x)
  x <- gsub("\\.", "", x)
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

ler_csv_tesouro <- function(path) {
  raw <- utils::read.csv(
    path, sep = ";", dec = ",",
    stringsAsFactors = FALSE, fileEncoding = "UTF-8", check.names = FALSE
  )
  if (ncol(raw) < 4L) {
    raw <- utils::read.csv(
      path, sep = ";", dec = ",",
      stringsAsFactors = FALSE, fileEncoding = "Latin1", check.names = FALSE
    )
  }
  names(raw) <- trimws(names(raw))
  ren <- c(
    "Tipo Titulo" = "tipo", "Tipo Título" = "tipo",
    "Data Vencimento" = "vencimento", "Data Base" = "data",
    "Taxa Compra Manha" = "taxa_compra", "Taxa Compra Manhã" = "taxa_compra"
  )
  for (nm in names(ren)) {
    if (nm %in% names(raw)) names(raw)[names(raw) == nm] <- ren[[nm]]
  }

  df <- tibble::tibble(
    tipo = trimws(raw$tipo),
    vencimento = as.Date(raw$vencimento, format = "%d/%m/%Y"),
    data = as.Date(raw$data, format = "%d/%m/%Y"),
    taxa_compra = parse_num_br(raw$taxa_compra)
  ) |>
    dplyr::filter(
      !is.na(data), !is.na(vencimento), !is.na(taxa_compra),
      tipo %in% TIPOS_CURVA_TESOURO
    ) |>
    dplyr::mutate(
      prazo_dias = as.integer(vencimento - data),
      prazo_anos = prazo_dias / 365.25
    ) |>
    dplyr::filter(prazo_dias > 30)

  df
}

tesouro_raw <- ler_csv_tesouro(csv_local)
readr::write_csv(tesouro_raw, "data/processed/tesouro_curvas_long.csv")
message("Tesouro curvas: ", nrow(tesouro_raw), " linhas | ",
        "até ", max(tesouro_raw$data))

# --- ANBIMA ETTJ (últimos ~6 dias úteis) ------------------------------------
parse_vertice <- function(x) {
  as.numeric(gsub("\\.", "", trimws(as.character(x))))
}

parse_taxa_br <- function(x) {
  x <- trimws(as.character(x))
  x[!nzchar(x)] <- NA_character_
  suppressWarnings(as.numeric(gsub(",", ".", x)))
}

parse_ettj_anbima <- function(texto) {
  linhas <- strsplit(texto, "\r?\n", perl = TRUE)[[1]]
  linhas <- trimws(linhas)
  linhas <- linhas[nzchar(linhas)]
  idx <- grep("Vertices;", linhas, ignore.case = TRUE, value = FALSE)
  if (length(idx) < 1L) {
    stop("Formato ANBIMA inesperado (linha Vertices não encontrada).")
  }
  idx <- idx[1L]
  data_linha <- strsplit(linhas[1], ";", fixed = TRUE)[[1]][1]
  data_ref <- as.Date(data_linha, format = "%d/%m/%Y")

  corpo <- linhas[(idx + 1L):length(linhas)]
  df <- utils::read.csv(
    text = paste(corpo, collapse = "\n"),
    sep = ";", dec = ",",
    header = FALSE, stringsAsFactors = FALSE,
    check.names = FALSE
  )
  names(df) <- c("vertices", "ettj_ipca", "ettj_pref", "inflacao_implicita")

  df |>
    dplyr::mutate(
      data_ref = data_ref,
      vertices = parse_vertice(vertices),
      prazo_anos = vertices / 252,
      ettj_ipca = parse_taxa_br(ettj_ipca),
      ettj_pref = parse_taxa_br(ettj_pref),
      inflacao_implicita = parse_taxa_br(inflacao_implicita)
    ) |>
    tidyr::pivot_longer(
      c(ettj_ipca, ettj_pref, inflacao_implicita),
      names_to = "serie",
      values_to = "taxa"
    ) |>
    dplyr::filter(!is.na(taxa)) |>
    dplyr::mutate(
      serie = dplyr::recode(
        serie,
        ettj_ipca = "ETTJ IPCA (% a.a.)",
        ettj_pref = "ETTJ Prefixada (% a.a.)",
        inflacao_implicita = "Inflação implícita (% a.a.)"
      )
    )
}

baixar_ettj_anbima <- function(data_ref) {
  r <- httr::POST(
    URL_ANBIMA_ETTJ,
    body = list(
      Idioma = "PT",
      Dt_Ref = format(data_ref, "%d/%m/%Y"),
      saida = "csv"
    ),
    encode = "form",
    httr::timeout(60)
  )
  if (httr::status_code(r) >= 400L) {
    stop("ANBIMA HTTP ", httr::status_code(r), " em ", format(data_ref))
  }
  raw_bytes <- httr::content(r, as = "raw")
  txt <- rawToChar(raw_bytes)
  if (!grepl("^Vertices;", txt, ignore.case = TRUE) && !grepl("Vertices;", txt)) {
    txt <- iconv(txt, from = "latin1", to = "UTF-8", sub = "byte")
  }
  parse_ettj_anbima(txt)
}

bizdays::load_builtin_calendars()
cal_anbima <- bizdays::create.calendar(
  "ANBIMA_proj",
  bizdays::calendars()[["Brazil/ANBIMA"]]$holidays,
  weekdays = c("saturday", "sunday")
)

d_fim <- Sys.Date()
d_ini <- bizdays::add.bizdays(d_fim, -8, cal = cal_anbima)
datas_anbima <- bizdays::bizseq(d_ini, d_fim, cal_anbima)

ettj_list <- purrr::map(datas_anbima, function(d) {
  tryCatch(
    baixar_ettj_anbima(d),
    error = function(e) {
      message("ANBIMA ", format(d, "%d/%m/%Y"), ": ", conditionMessage(e))
      NULL
    }
  )
})
ettj_anbima <- dplyr::bind_rows(ettj_list[!vapply(ettj_list, is.null, logical(1))])

if (nrow(ettj_anbima) > 0L) {
  readr::write_csv(ettj_anbima, "data/processed/anbima_ettj_recente.csv")
  message("ANBIMA ETTJ: ", length(unique(ettj_anbima$data_ref)), " datas | ",
          min(ettj_anbima$data_ref), " → ", max(ettj_anbima$data_ref))
} else {
  message("ANBIMA ETTJ: nenhuma data baixada (verifique conexão).")
}
