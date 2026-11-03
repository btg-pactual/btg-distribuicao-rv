# ADVFN — cotações DI1 (ULT) para curva intraday / dia corrente
# Histórico continua via B3 (scripts/R/b3_di_curva.R).

ADVFN_DI_URL <- paste0(
  "https://br.advfn.com/investimentos/futuros/",
  "di-depositos-interfinanceiros/cotacoes"
)

# Requer funções de scripts/R/b3_di_curva.R (parse_num_br, codigo_vencimento_di).

baixar_html_advfn_di <- function(cache_dir = "data/raw/advfn") {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  if (!requireNamespace("httr", quietly = TRUE)) {
    stop("Pacote 'httr' necessário para ADVFN.")
  }
  r <- httr::GET(
    ADVFN_DI_URL,
    httr::user_agent(
      "Mozilla/5.0 (compatible; curvas-juros/1.0; +local)"
    ),
    httr::timeout(60)
  )
  if (httr::status_code(r) != 200L) {
    stop("ADVFN HTTP ", httr::status_code(r))
  }
  html <- httr::content(r, as = "text", encoding = "UTF-8")
  if (!grepl("BMF:DI1", html, fixed = TRUE)) {
    stop("Página ADVFN sem tabela DI1 (layout alterado?).")
  }
  path <- file.path(cache_dir, "di_cotacoes.html")
  writeLines(html, path, useBytes = TRUE)
  list(html = html, path = path, fetched_at = Sys.time())
}

ler_curva_di1_advfn_html <- function(html, data_ref = Sys.Date()) {
  data_ref <- as.Date(data_ref)
  pat <- paste0(
    "BMF:DI1([A-Z0-9]+)</a></td>",
    "<td class=\"[^\"]*Column2\">[^<]*</td>",
    "<td class=\"[^\"]*Column3\">([^<]+)</td>",
    "<td class=\"[^\"]*Column4\">[^<]*</td>",
    "<td class=\"[^\"]*Column5\">([^<]*)</td>",
    "<td class=\"[^\"]*Column6\">([^<]*)</td>",
    "<td class=\"[^\"]*Column7[^\"]*\">([^<]*)</td>"
  )
  m <- gregexpr(pat, html, perl = TRUE)[[1L]]
  if (length(m) == 1L && m[1L] == -1L) {
    return(tibble::tibble())
  }

  starts <- attr(m, "capture.start")
  lens <- attr(m, "capture.length")
  if (is.null(starts) || length(dim(starts)) != 2L) {
    return(tibble::tibble())
  }

  n <- length(m)
  codigo <- character(n)
  taxa_txt <- character(n)
  vol_txt <- character(n)
  for (i in seq_len(n)) {
    codigo[i] <- substr(html, starts[i, 1L], starts[i, 1L] + lens[i, 1L] - 1L)
    taxa_txt[i] <- substr(html, starts[i, 2L], starts[i, 2L] + lens[i, 2L] - 1L)
    vol_txt[i] <- substr(html, starts[i, 5L], starts[i, 5L] + lens[i, 5L] - 1L)
  }

  parse_vol_advfn <- function(x) {
    x <- gsub("\\.", "", as.character(x))
    x <- gsub(",", ".", x, fixed = TRUE)
    suppressWarnings(as.numeric(x))
  }
  vol <- parse_vol_advfn(vol_txt)
  taxa_aa <- parse_num_br(taxa_txt)

  out <- tibble::tibble(
    codigo_venc = codigo,
    taxa_aa = taxa_aa,
    vol = vol
  ) |>
    dplyr::mutate(
      simbolo = paste0("DI1", .data$codigo_venc),
      data = data_ref,
      vencimento = vapply(
        .data$codigo_venc,
        codigo_vencimento_di,
        FUN.VALUE = as.Date("2000-01-01"),
        refdate = data_ref
      ),
      vencimento = as.Date(.data$vencimento, origin = "1970-01-01"),
      prazo_dias = as.integer(.data$vencimento - .data$data),
      prazo_anos = .data$prazo_dias / 365.25,
      fonte = "advfn_ult"
    ) |>
    dplyr::filter(
      !is.na(.data$vencimento),
      !is.na(.data$taxa_aa),
      .data$prazo_dias > 0L,
      .data$taxa_aa >= 8,
      .data$taxa_aa <= 22,
      is.finite(.data$vol),
      .data$vol > 0
    ) |>
    dplyr::arrange(.data$vencimento) |>
    dplyr::select(
      .data$data, .data$simbolo, .data$codigo_venc, .data$vencimento,
      .data$prazo_dias, .data$prazo_anos, .data$taxa_aa, .data$vol,
      .data$fonte
    )

  out
}

obter_curva_di1_advfn <- function(data_ref = Sys.Date(),
                                  cache_dir = "data/raw/advfn",
                                  save_csv = TRUE) {
  data_ref <- as.Date(data_ref)
  dl <- baixar_html_advfn_di(cache_dir = cache_dir)
  curva <- ler_curva_di1_advfn_html(dl$html, data_ref = data_ref)
  if (nrow(curva) == 0L) {
    stop("Nenhum contrato DI1 válido parseado da ADVFN.")
  }
  attr(curva, "fetched_at") <- dl$fetched_at
  if (isTRUE(save_csv)) {
    out_path <- file.path(
      "data/processed/di_curva",
      paste0("di_advfn_", format(data_ref, "%Y%m%d"), ".csv")
    )
    readr::write_csv(curva, out_path)
  }
  curva
}
