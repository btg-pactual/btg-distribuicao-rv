# =============================================================================
# 01_download_curva_di.R — Curva DI (DI1): API recente + PriceReport (PR) histórico
# =============================================================================

source("scripts/00_setup.R")
source("scripts/R/b3_di_curva.R")

if (!file.exists("data/processed/mapa_datas.csv")) {
  stop("Execute scripts/02_montar_curvas.R antes (mapa_datas.csv).")
}

mapa <- readr::read_csv(
  "data/processed/mapa_datas.csv",
  col_types = readr::cols(
    meses = readr::col_integer(),
    rotulo = readr::col_character(),
    alvo = readr::col_date(),
    data = readr::col_date()
  )
)

data_fim <- max(mapa$data)
datas_mensais <- datas_mensais_di(data_fim, MESES_HISTORICO_DI)
mapa_mensal <- tibble::tibble(
  data = as.Date(datas_mensais, origin = "1970-01-01"),
  mes_ref = format(as.Date(datas_mensais, origin = "1970-01-01"), "%Y-%m")
) |>
  dplyr::distinct(data, .keep_all = TRUE) |>
  dplyr::arrange(dplyr::desc(data))

readr::write_csv(mapa_mensal, "data/processed/mapa_datas_di_mensal.csv")

# Mais recentes primeiro (útil se interromper; resultado final é o mesmo)
datas_baixar <- sort(unique(c(mapa$data, mapa_mensal$data)), decreasing = TRUE)

baixar_uma_data <- function(dt) {
  message("DI1: ", format(dt, "%d/%m/%Y"))
  tryCatch(
    {
      curva <- obter_curva_di1(dt)
      if (nrow(curva) == 0L) {
        message("  (sem contratos DI1)")
        return(NULL)
      }
      message(
        "  OK ", nrow(curva), " contratos | ",
        unique(curva$fonte)
      )
      curva
    },
    error = function(e) {
      message("  ERRO: ", conditionMessage(e))
      NULL
    }
  )
}

curvas_hist <- purrr::map(datas_baixar, baixar_uma_data) |>
  purrr::compact() |>
  dplyr::bind_rows()

if (nrow(curvas_hist) == 0L) {
  warning("Nenhuma curva DI1 baixada.")
} else {
  curvas_hist <- curvas_hist |>
    dplyr::mutate(
      mes_ref = format(.data$data, "%Y-%m"),
      rotulo = dplyr::case_when(
        .data$data %in% mapa$data ~ mapa$rotulo[match(.data$data, mapa$data)],
        TRUE ~ NA_character_
      )
    )

  readr::write_csv(
    curvas_hist,
    "data/processed/curvas_di_futuros_historico.csv"
  )

  curvas_di <- curvas_hist |>
    dplyr::filter(!is.na(.data$rotulo)) |>
    dplyr::mutate(
      meses = mapa$meses[match(.data$data, mapa$data)],
      rotulo = factor(
        rotulo,
        levels = c(
          "36m atrás", "24m atrás", "12m atrás", "6m atrás",
          "3m atrás", "1m atrás", "Atual"
        )
      )
    )

  readr::write_csv(
    curvas_di,
    "data/processed/curvas_di_futuros_comparativo.csv"
  )

  resumo_di_hist <- curvas_hist |>
    dplyr::filter(.data$prazo_anos >= 4.5, .data$prazo_anos <= 5.5) |>
    dplyr::group_by(.data$data, .data$mes_ref) |>
    dplyr::summarise(
      taxa_5y = stats::median(.data$taxa_aa, na.rm = TRUE),
      n = dplyr::n(),
      fonte = dplyr::first(.data$fonte),
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$data)

  readr::write_csv(
    resumo_di_hist,
    "output/tables/resumo_di_taxa_5y_historico.csv"
  )

  resumo_di <- curvas_di |>
    dplyr::filter(.data$prazo_anos >= 4.5, .data$prazo_anos <= 5.5) |>
    dplyr::group_by(.data$rotulo, .data$data) |>
    dplyr::summarise(
      taxa_5y = stats::median(.data$taxa_aa, na.rm = TRUE),
      n = dplyr::n(),
      fonte = dplyr::first(.data$fonte),
      .groups = "drop"
    )
  readr::write_csv(resumo_di, "output/tables/resumo_di_taxa_5y.csv")

  message(
    "Curva DI: ", length(unique(curvas_hist$data)), " datas (",
    sum(curvas_hist$fonte == "api_negocios", na.rm = TRUE), " API | ",
    sum(curvas_hist$fonte == "pricereport_pr", na.rm = TRUE), " PR) | ",
    nrow(curvas_hist), " pontos"
  )
}
