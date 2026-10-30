# =============================================================================
# ci_publish.R — build para GitHub Pages (pasta curvas-juros/ no site)
# Uso:
#   Rscript scripts/ci_publish.R              # pipeline completo
#   Rscript scripts/ci_publish.R advfn_only   # só ADVFN + HTML
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
advfn_only <- "advfn_only" %in% args ||
  identical(tolower(Sys.getenv("ADVFN_ONLY", "")), "true")

resolve_layout <- function() {
  ws <- Sys.getenv("GITHUB_WORKSPACE", unset = getwd())
  ws <- normalizePath(ws, winslash = "/", mustWork = FALSE)
  nested <- file.path(ws, "curvas-juros", "scripts", "run_all.R")
  if (file.exists(nested)) {
    return(list(
      repo_root = ws,
      code_root = file.path(ws, "curvas-juros"),
      site_root = file.path(ws, "curvas-juros")
    ))
  }
  if (file.exists(file.path(ws, "scripts", "run_all.R"))) {
    return(list(repo_root = ws, code_root = ws, site_root = ws))
  }
  stop("Não encontrei scripts/run_all.R (monorepo ou pasta curvas-juros).")
}

layout <- resolve_layout()
setwd(layout$code_root)
site_root <- layout$site_root

message("ci_publish — code: ", layout$code_root)
message("site: ", site_root)
message("modo advfn_only: ", advfn_only)

if (advfn_only) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    install.packages("jsonlite", repos = "https://cloud.r-project.org")
  }
  source("scripts/R/b3_di_curva.R")
  source("scripts/R/advfn_di_curva.R")
  source("scripts/R/export_viva_json.R")
  curva <- obter_curva_di1_advfn(Sys.Date())
  fetched <- attr(curva, "fetched_at")
  coleta <- if (!is.null(fetched)) fetched else Sys.time()
  json_path <- file.path(site_root, "data/curva_advfn.json")
  export_curva_advfn_json(
    curva,
    path = json_path,
    coleta_em = coleta,
    data_ref = Sys.Date()
  )
  message("JSON: ", json_path, " (", nrow(curva), " vértices)")
} else {
  Sys.setenv(MESES_HISTORICO_DI = Sys.getenv("MESES_HISTORICO_DI", unset = "24"))
  source("scripts/run_all.R")
}

message("Gerando simulador swap...")
status <- system2(
  "Rscript",
  c("swap-cdi-pre/gerar_swap_simulador.R"),
  stdout = TRUE,
  stderr = TRUE
)
if (!is.null(attr(status, "status")) && attr(status, "status") != 0L) {
  cat(paste(status, collapse = "\n"), "\n")
  stop("Falha ao gerar swap_simulador.R")
}
cat(paste(status, collapse = "\n"), "\n")

copy_unless_same <- function(from, to) {
  if (!file.exists(from)) return(invisible(FALSE))
  from_n <- normalizePath(from, winslash = "/", mustWork = TRUE)
  if (file.exists(to)) {
    to_n <- normalizePath(to, winslash = "/", mustWork = TRUE)
    if (identical(from_n, to_n)) return(invisible(TRUE))
  }
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  file.copy(from, to, overwrite = TRUE)
}

dir.create(file.path(site_root, "swap"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(site_root, "data"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(site_root, "vendor"), recursive = TRUE, showWarnings = FALSE)
vendor_src <- file.path(layout$code_root, "vendor/chart.umd.min.js")
copy_unless_same(vendor_src, file.path(site_root, "vendor/chart.umd.min.js"))
dados_src <- file.path(layout$code_root, "swap/dados.json")
if (!file.exists(dados_src)) {
  dados_src <- file.path(layout$code_root, "swap-cdi-pre/dados.json")
}

if (!copy_unless_same("curvas_juros.html", file.path(site_root, "index.html"))) {
  stop("curvas_juros.html não encontrado")
}
if (!copy_unless_same(
  "swap-cdi-pre/swap_simulador.html",
  file.path(site_root, "swap/index.html")
)) {
  stop("swap_simulador.html não encontrado")
}
if (file.exists(dados_src)) {
  copy_unless_same(dados_src, file.path(site_root, "swap/dados.json"))
}
docs_swap <- file.path(site_root, "docs/swap")
dir.create(docs_swap, recursive = TRUE, showWarnings = FALSE)
copy_unless_same(
  file.path(site_root, "swap/index.html"),
  file.path(docs_swap, "index.html")
)
if (file.exists(file.path(site_root, "swap/dados.json"))) {
  copy_unless_same(
    file.path(site_root, "swap/dados.json"),
    file.path(docs_swap, "dados.json")
  )
}

json_src <- file.path(site_root, "data/curva_advfn.json")
if (!file.exists(json_src)) {
  advfn_csv <- file.path(
    "data/processed/di_curva",
    paste0("di_advfn_", format(Sys.Date(), "%Y%m%d"), ".csv")
  )
  if (file.exists(advfn_csv)) {
    source("scripts/R/export_viva_json.R")
    df <- readr::read_csv(advfn_csv, show_col_types = FALSE)
    export_curva_advfn_json(df, json_src, coleta_em = Sys.time(), data_ref = Sys.Date())
  }
}

meta <- list(
  gerado_em = format(Sys.time(), "%d/%m/%Y %H:%M"),
  github_repo = Sys.getenv("GITHUB_REPOSITORY", ""),
  curva_advfn = if (file.exists(json_src)) jsonlite::fromJSON(json_src) else NULL
)
jsonlite::write_json(
  meta,
  file.path(site_root, "data/meta.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)

message("Site OK em ", site_root)
