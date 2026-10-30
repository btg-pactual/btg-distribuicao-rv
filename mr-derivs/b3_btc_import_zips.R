# =============================================================================
# Importa ZIPs NEGOCIOSBTB ja baixados em rb3_cache/b3_btc_raw/
#
# Uso:
#   Rscript b3_btc_import_zips.R [cache_dir] [forcar]
#
# Exemplos:
#   Rscript b3_btc_import_zips.R
#   Rscript b3_btc_import_zips.R "C:/.../rb3_cache"
#   Rscript b3_btc_import_zips.R "C:/.../rb3_cache" forcar
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
cache_dir <- if (length(args) >= 1) args[[1]] else Sys.getenv(
  "RB3_CACHE",
  unset = "C:/Users/PIMENTPA/OneDrive - Banco BTG Pactual S.A/Documentos/rb3_cache"
)
forcar <- length(args) >= 2 && identical(args[[2]], "forcar")

suppressPackageStartupMessages({
  library(dplyr)
  library(httr)
  library(jsonlite)
  library(glue)
})

script_dir <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[[1]]))) else getwd()
})
source(file.path(script_dir, "btc_taxas.R"), local = TRUE)

if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
raw_dir <- file.path(cache_dir, DIR_B3_RAW)
if (!dir.exists(raw_dir)) dir.create(raw_dir, recursive = TRUE)

message("Import ZIP NEGOCIOSBTB")
message("  cache: ", cache_dir)
message("  pasta: ", raw_dir)
message("  forcar reimport: ", forcar)

importar_zips_raw(cache_dir, forcar = forcar)
