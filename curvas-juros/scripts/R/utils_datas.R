coerce_date <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }
  if (is.numeric(x)) {
    return(as.Date(x, origin = "1970-01-01"))
  }
  readr::parse_date(as.character(x))
}

# Leitura consistente do painel Tesouro (evita coluna `data` como número serial)
ler_tesouro_processado <- function(path = "data/processed/tesouro_curvas_long.csv") {
  df <- readr::read_csv(
    path,
    col_types = readr::cols(
      tipo = readr::col_character(),
      vencimento = readr::col_date(),
      data = readr::col_date(),
      taxa_compra = readr::col_double(),
      prazo_dias = readr::col_integer(),
      prazo_anos = readr::col_double()
    )
  )
  df$vencimento <- coerce_date(df$vencimento)
  df$data <- coerce_date(df$data)
  df
}
