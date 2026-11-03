# Exporta curva ADVFN para JSON (GitHub Pages / fetch no navegador)

montar_pts_xy <- function(df) {
  df <- df[is.finite(df$prazo_anos) & is.finite(df$taxa_aa), , drop = FALSE]
  df <- df[order(df$prazo_anos), , drop = FALSE]
  lapply(seq_len(nrow(df)), function(i) {
    list(x = df$prazo_anos[i], y = df$taxa_aa[i])
  })
}

export_curva_advfn_json <- function(curva_df,
                                    path,
                                    coleta_em = Sys.time(),
                                    data_ref = Sys.Date()) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  pts_df <- curva_df[, c("prazo_anos", "taxa_aa"), drop = FALSE]
  payload <- list(
    fonte = "advfn_ult",
    data = format(as.Date(data_ref), "%Y-%m-%d"),
    data_br = paste0(format(as.Date(data_ref), "%d/%m/%Y"), " · cotação ADVFN"),
    coleta_em = format(coleta_em, "%d/%m/%Y %H:%M"),
    coleta_iso = format(coleta_em, "%Y-%m-%dT%H:%M:%S%z"),
    pts = montar_pts_xy(pts_df)
  )
  jsonlite::write_json(
    payload,
    path = path,
    auto_unbox = TRUE,
    pretty = TRUE,
    digits = 8
  )
  invisible(path)
}
