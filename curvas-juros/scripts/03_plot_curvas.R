# =============================================================================
# 03_plot_curvas.R — gráficos comparativos (Tesouro + ANBIMA)
# =============================================================================

source("scripts/00_setup.R")
source("scripts/R/utils_datas.R")

curvas_tesouro <- readr::read_csv(
  "data/processed/curvas_tesouro_comparativo.csv",
  col_types = readr::cols(
    tipo = readr::col_character(),
    vencimento = readr::col_date(),
    data = readr::col_date(),
    taxa_compra = readr::col_double(),
    prazo_dias = readr::col_integer(),
    prazo_anos = readr::col_double(),
    rotulo = readr::col_character(),
    meses = readr::col_integer()
  )
) |>
  dplyr::mutate(
    rotulo = factor(
      rotulo,
      levels = c(
        "36m atrás", "24m atrás", "12m atrás", "6m atrás",
        "3m atrás", "1m atrás", "Atual"
      )
    )
  )

data_atual <- max(curvas_tesouro$data)

cores_atual <- c(
  "Atual" = "#0b5fff",
  "1m atrás" = "#6366f1",
  "3m atrás" = "#8b5cf6",
  "6m atrás" = "#a855f7",
  "12m atrás" = "#d946ef",
  "24m atrás" = "#f97316",
  "36m atrás" = "#ef4444"
)

p_tesouro <- ggplot2::ggplot(
  curvas_tesouro,
  ggplot2::aes(
    x = prazo_anos, y = taxa_compra,
    color = rotulo, group = interaction(data, tipo)
  )
) +
  ggplot2::geom_line(linewidth = 0.9) +
  ggplot2::geom_point(size = 1.6, alpha = 0.85) +
  ggplot2::facet_wrap(~tipo, scales = "free_y", ncol = 1) +
  ggplot2::scale_color_manual(values = cores_atual, name = "Referência") +
  ggplot2::scale_x_continuous(breaks = scales::pretty_breaks(n = 8)) +
  ggplot2::labs(
    title = "Curvas do Tesouro Direto — nível atual vs histórico",
    subtitle = paste0(
      "Taxa de compra (manhã) por prazo | última data: ",
      format(data_atual, "%d/%m/%Y")
    ),
    x = "Prazo (anos)",
    y = "Taxa (% a.a.)"
  ) +
  THEME_CURVA

ggplot2::ggsave(
  "output/figs/curvas_tesouro_comparativo.png",
  p_tesouro, width = 10, height = 9, dpi = 144, bg = "white"
)

# Só atual vs 12m vs 36m (leitura mais limpa)
rotulos_foco <- c("Atual", "12m atrás", "36m atrás")
curvas_foco <- curvas_tesouro |>
  dplyr::filter(rotulo %in% rotulos_foco)

p_foco <- ggplot2::ggplot(
  curvas_foco,
  ggplot2::aes(
    x = prazo_anos, y = taxa_compra,
    color = rotulo, group = interaction(data, tipo)
  )
) +
  ggplot2::geom_line(linewidth = 1.1) +
  ggplot2::geom_point(size = 2) +
  ggplot2::facet_wrap(~tipo, scales = "free_y", ncol = 1) +
  ggplot2::scale_color_manual(
    values = cores_atual[rotulos_foco], name = "Referência"
  ) +
  ggplot2::labs(
    title = "Foco: atual vs 12 meses vs 36 meses",
    subtitle = "Mesma métrica — títulos Prefixado e IPCA+ (sem cupom semestral)",
    x = "Prazo (anos)",
    y = "Taxa (% a.a.)"
  ) +
  THEME_CURVA

ggplot2::ggsave(
  "output/figs/curvas_tesouro_foco.png",
  p_foco, width = 10, height = 8, dpi = 144, bg = "white"
)

# Evolução da taxa ~5y (proxy de nível da curva)
resumo_5y <- readr::read_csv("output/tables/resumo_taxa_5y.csv", show_col_types = FALSE)

p_nivel <- ggplot2::ggplot(
  resumo_5y,
  ggplot2::aes(x = data, y = taxa_5y, color = tipo, group = tipo)
) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::geom_point(size = 2.5) +
  ggplot2::scale_x_date(date_labels = "%b/%y") +
  ggplot2::labs(
    title = "Nível da curva (~5 anos) ao longo das datas de comparação",
    subtitle = "Mediana das taxas com prazo entre 4,5 e 5,5 anos",
    x = NULL, y = "Taxa (% a.a.)", color = NULL
  ) +
  THEME_CURVA

ggplot2::ggsave(
  "output/figs/nivel_curva_5y.png",
  p_nivel, width = 9, height = 5, dpi = 144, bg = "white"
)

# Curva DI (futuros DI1 — B3)
path_di <- "data/processed/curvas_di_futuros_comparativo.csv"
if (file.exists(path_di)) {
  curvas_di <- readr::read_csv(
    path_di,
    col_types = readr::cols(
      data = readr::col_date(),
      vencimento = readr::col_date(),
      simbolo = readr::col_character(),
      codigo_venc = readr::col_character(),
      prazo_dias = readr::col_integer(),
      prazo_anos = readr::col_double(),
      taxa_aa = readr::col_double(),
      pu_ajuste = readr::col_double(),
      rotulo = readr::col_character(),
      meses = readr::col_integer()
    )
  ) |>
    dplyr::mutate(
      rotulo = factor(
        rotulo,
        levels = c(
          "36m atrás", "24m atrás", "12m atrás", "6m atrás",
          "3m atrás", "1m atrás", "Atual"
        )
      )
    )

  p_di <- ggplot2::ggplot(
    curvas_di,
    ggplot2::aes(
      x = prazo_anos, y = taxa_aa,
      color = rotulo, group = interaction(data, rotulo)
    )
  ) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_color_manual(values = cores_atual, name = "Referência") +
    ggplot2::labs(
      title = "Curva DI (futuros DI1) — atual vs histórico",
      subtitle = "Taxa de ajuste (% a.a.) — fonte B3, negócios consolidados",
      x = "Prazo (anos, vencimento do contrato)",
      y = "Taxa DI (% a.a.)"
    ) +
    THEME_CURVA

  ggplot2::ggsave(
    "output/figs/curvas_di_futuros_comparativo.png",
    p_di, width = 10, height = 6, dpi = 144, bg = "white"
  )

  curvas_di_foco <- curvas_di |>
    dplyr::filter(rotulo %in% c("Atual", "12m atrás", "36m atrás"))

  path_hist <- "output/tables/resumo_di_taxa_5y_historico.csv"
  if (file.exists(path_hist)) {
    hist_di <- readr::read_csv(path_hist, show_col_types = FALSE)
    hist_di$data <- as.Date(hist_di$data)
    if (nrow(hist_di) >= 3L) {
      p_di_hist <- ggplot2::ggplot(
        hist_di,
        ggplot2::aes(x = data, y = taxa_5y)
      ) +
        ggplot2::geom_line(linewidth = 0.9, color = "#0b5fff") +
        ggplot2::geom_point(size = 1.8, color = "#0b5fff", alpha = 0.85) +
        ggplot2::scale_x_date(date_labels = "%b/%y") +
        ggplot2::labs(
          title = "DI futuro — nível ~5 anos (série mensal)",
          subtitle = paste0(
            "Mediana DI1 com prazo 4,5–5,5 anos | ",
            nrow(hist_di), " meses (API + PriceReport PR)"
          ),
          x = NULL,
          y = "Taxa (% a.a.)"
        ) +
        THEME_CURVA

      ggplot2::ggsave(
        "output/figs/di_futuro_nivel_5y_historico.png",
        p_di_hist, width = 10, height = 5, dpi = 144, bg = "white"
      )
    }
  }

  if (nrow(curvas_di_foco) > 0L) {
    p_di_foco <- ggplot2::ggplot(
      curvas_di_foco,
      ggplot2::aes(
        x = prazo_anos, y = taxa_aa,
        color = rotulo, group = interaction(data, rotulo)
      )
    ) +
      ggplot2::geom_line(linewidth = 1.1) +
      ggplot2::geom_point(size = 2) +
      ggplot2::scale_color_manual(
        values = cores_atual[c("Atual", "12m atrás", "36m atrás")],
        name = "Referência"
      ) +
      ggplot2::labs(
        title = "DI futuro — foco: atual vs 12m vs 36m",
        x = "Prazo (anos)",
        y = "Taxa DI (% a.a.)"
      ) +
      THEME_CURVA

    ggplot2::ggsave(
      "output/figs/curvas_di_futuros_foco.png",
      p_di_foco, width = 10, height = 6, dpi = 144, bg = "white"
    )
  }
}

# ANBIMA recente
path_anbima <- "data/processed/anbima_ettj_recente.csv"
if (file.exists(path_anbima)) {
  ettj <- readr::read_csv(path_anbima, show_col_types = FALSE)
  ettj$data_ref <- as.Date(ettj$data_ref)

  p_anbima <- ggplot2::ggplot(
    ettj,
    ggplot2::aes(
      x = prazo_anos, y = taxa,
      color = factor(data_ref), group = interaction(data_ref, serie)
    )
  ) +
    ggplot2::geom_line(linewidth = 0.85) +
    ggplot2::facet_wrap(~serie, scales = "free_y", ncol = 1) +
    ggplot2::labs(
      title = "ETTJ ANBIMA — últimos dias úteis disponíveis",
      subtitle = "Fonte: download CSV ANBIMA (até 5 dias úteis no site)",
      x = "Prazo (~anos, vértices/252)",
      y = "Taxa (% a.a.)",
      color = "Data ref."
    ) +
    THEME_CURVA +
    ggplot2::theme(legend.position = "right")

  ggplot2::ggsave(
    "output/figs/anbima_ettj_recente.png",
    p_anbima, width = 10, height = 9, dpi = 144, bg = "white"
  )
}

message("Figuras salvas em output/figs/")
