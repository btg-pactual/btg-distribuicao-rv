# Diagnostico + force update COTAHIST apos 2026-09-29
options(warn = 1)
cache_dir <- "C:/Users/PIMENTPA/OneDrive - Banco BTG Pactual S.A/Documentos/rb3_cache"
Sys.setenv(R_USER_CACHE_DIR = cache_dir)
options(rb3.cachedir = cache_dir)

out_txt <- "C:/Users/PIMENTPA/OneDrive - Banco BTG Pactual S.A/Desktop/Mr Derivs/_diag_cache_out.txt"
sink(out_txt)
on.exit(sink(), add = TRUE)

cat("CACHE:", cache_dir, "\n")
library(rb3)
library(dplyr)
library(bizdays)
library(lubridate)
load_builtin_calendars()
bizdays.options$set(default.calendar = "Brazil/ANBIMA")

max_cotahist <- function(tipo) {
  ch <- tryCatch(cotahist_get(type = tipo), error = function(e) NULL)
  if (is.null(ch)) return(as.Date(NA))
  ch |> summarise(mx = max(refdate, na.rm = TRUE)) |> collect() |> pull(mx) |> as.Date()
}

cat("max yearly:", format(max_cotahist("yearly")), "\n")
cat("max daily :", format(max_cotahist("daily")), "\n")

ctrl <- file.path(cache_dir, "datas_baixadas.rds")
db <- if (file.exists(ctrl)) readRDS(ctrl) else as.Date(character(0))
cat("datas_baixadas max:", format(max(db)), " n=", length(db), "\n")
cat("datas_baixadas > 2026-09-29:", sum(db > as.Date("2026-09-29")), "\n")

# Spot / opcoes BOVA apos 29/09
for (tipo in c("yearly", "daily")) {
  ch <- tryCatch(cotahist_get(type = tipo), error = function(e) NULL)
  if (is.null(ch)) next
  sp <- ch |>
    filter(symbol == "BOVA11", refdate >= as.Date("2026-09-01")) |>
    summarise(mx = max(refdate, na.rm = TRUE), n = n()) |>
    collect()
  cat("BOVA11 spot", tipo, "max=", format(sp$mx), "n=", sp$n, "\n")
  op <- ch |>
    filter(refdate >= as.Date("2026-09-01"), symbol >= "BOVA", symbol < "BOVB") |>
    summarise(mx = max(refdate, na.rm = TRUE), n = n()) |>
    collect()
  cat("BOVA* opcoes", tipo, "max=", format(op$mx), "n=", op$n, "\n")
}

# Limpa controle falso apos 29/09 e forca download
corte <- as.Date("2026-09-29")
db2 <- db[db <= corte]
saveRDS(db2, ctrl)
cat("Controle limpo: max agora", format(max(db2)), "\n")

fim <- preceding(Sys.Date(), "Brazil/ANBIMA")
datas <- bizseq(corte + 1, fim, "Brazil/ANBIMA")
cat("Baixando", length(datas), "datas:", format(min(datas)), "a", format(max(datas)), "\n")

# Em chunks de 5
chunks <- split(datas, ceiling(seq_along(datas) / 5))
for (i in seq_along(chunks)) {
  cat("chunk", i, "/", length(chunks), ":", paste(format(chunks[[i]]), collapse = ", "), "\n")
  tryCatch(
    fetch_marketdata(
      "b3-cotahist-daily",
      refdate = chunks[[i]],
      throttle = TRUE,
      force_download = TRUE
    ),
    error = function(e) cat("ERRO chunk:", conditionMessage(e), "\n")
  )
  cat("  max daily agora:", format(max_cotahist("daily")), "\n")
}

# Atualiza controle so ate o que realmente entrou
ult <- max(max_cotahist("yearly"), max_cotahist("daily"), na.rm = TRUE)
todas <- bizseq(as.Date("2020-01-01"), ult, "Brazil/ANBIMA")
saveRDS(sort(unique(c(db2, todas))), ctrl)
cat("FINAL max cotahist:", format(ult), "\n")
cat("DONE\n")
