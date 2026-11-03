# =============================================================================
# run_all.R — pipeline completo curvas-juros
# =============================================================================

message("=== curvas-juros — início ===")

source("scripts/01_download_dados.R")
source("scripts/02_montar_curvas.R")
source("scripts/01_download_curva_di.R")
source("scripts/03_plot_curvas.R")
source("scripts/04_gerar_html.R")

message("\n=== curvas-juros — concluído ===")
message("Dados:   data/processed/")
message("Figuras: output/figs/")
message("HTML:    curvas_juros.html")
