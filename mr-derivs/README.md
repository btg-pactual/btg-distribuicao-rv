# Mr Derivs (dentro de btg-distribuicao-rv)

Hub Pages: [mr-derivs/](https://btg-pactual.github.io/btg-distribuicao-rv/mr-derivs/)

## App Shiny (local)

```r
setwd("mr-derivs")
source("sanity_check.R")
shiny::runApp("app_vol_implicita.R")
```

## Cache

- Pasta local/CI: `mr-derivs/.rb3_cache` (não versionada)
- Status público: `data/cotahist_status.json` (atualizado pelo workflow **Mr Derivs COTAHIST diário**)
- Primeira carga: no GitHub Actions, rode o workflow manualmente com **seed_24m = true**

## Ativos seed (24 meses)

`TICKERS_SEED_24M` em `config_mr_derivs.R`: BOVA11, SMAL11, PETR4, EQTL3, VALE3, ITUB4, BPAC11, …
