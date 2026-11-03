# =============================================================================
# 02_montar_curvas.R — datas de comparação e painéis de curva (Tesouro)
# =============================================================================

source("scripts/00_setup.R")
source("scripts/R/utils_datas.R")

tesouro_raw <- ler_tesouro_processado()

datas_disponiveis <- sort(unique(coerce_date(tesouro_raw$data)))
data_atual <- max(datas_disponiveis)
stopifnot(inherits(data_atual, "Date"))

escolher_data_proxima <- function(alvo, candidatas) {
  alvo <- as.Date(alvo)
  candidatas <- as.Date(candidatas)
  candidatas[which.min(abs(as.numeric(candidatas - alvo)))]
}

mapa_datas <- tibble::tibble(
  meses = MESES_COMPARACAO,
  rotulo = c(
    "Atual", "1m atrás", "3m atrás", "6m atrás",
    "12m atrás", "24m atrás", "36m atrás"
  )
) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    alvo = data_atual %m-% lubridate::period(meses, "months"),
    data = escolher_data_proxima(alvo, datas_disponiveis)
  ) |>
  dplyr::ungroup() |>
  dplyr::distinct(meses, .keep_all = TRUE) |>
  dplyr::arrange(meses) |>
  dplyr::mutate(
    rotulo = factor(
      rotulo,
      levels = c(
        "36m atrás", "24m atrás", "12m atrás", "6m atrás",
        "3m atrás", "1m atrás", "Atual"
      )
    )
  )

readr::write_csv(mapa_datas, "data/processed/mapa_datas.csv")
message(
  "Mapa de datas: ",
  paste(format(mapa_datas$data, "%d/%m/%Y"), collapse = " | ")
)

curvas_tesouro <- tesouro_raw |>
  dplyr::filter(data %in% mapa_datas$data) |>
  dplyr::inner_join(
    dplyr::select(mapa_datas, data, rotulo, meses),
    by = "data"
  ) |>
  dplyr::arrange(tipo, data, prazo_anos)

readr::write_csv(curvas_tesouro, "data/processed/curvas_tesouro_comparativo.csv")

# Tabela resumo: taxa em ~5 anos (4,5–5,5a) por data
faixa_5y <- curvas_tesouro |>
  dplyr::filter(prazo_anos >= 4.5, prazo_anos <= 5.5) |>
  dplyr::group_by(tipo, rotulo, data) |>
  dplyr::summarise(
    taxa_5y = stats::median(taxa_compra, na.rm = TRUE),
    n_titulos = dplyr::n(),
    .groups = "drop"
  ) |>
  dplyr::arrange(tipo, rotulo)

readr::write_csv(faixa_5y, "output/tables/resumo_taxa_5y.csv")

message("Curvas Tesouro: ", length(unique(curvas_tesouro$data)), " datas de comparação")
message("Data atual: ", format(data_atual, "%d/%m/%Y"))
