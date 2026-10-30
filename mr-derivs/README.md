# Mr Derivs — IV & opções B3 (R + Shiny)

Pipeline de vol implícita / FVOL (skew, smile), IV vs realizada e busca histórica de opções via **rb3** (COTAHIST) + Selic BCB + **oplib** (BSM).

## App (4 abas)

Pasta oficial: `btg-distribuicao-rv/mr-derivs` (monorepo, branch `pages`).

**Windows (duplo clique):** `scripts\run_app.bat`

```r
setwd(".../btg-distribuicao-rv/mr-derivs")
source("sanity_check.R")
options(vol_implicita.autorun = FALSE)
shiny::runApp("app_vol_implicita.R")
```

O cache COTAHIST usa automaticamente `Documentos/rb3_cache` no OneDrive BTG, se existir (override: `MR_DERIVS_RB3_CACHE`).

| Aba | Conteúdo |
|-----|----------|
| IV histórica | Vol ATM FVOL + MM (plotly) |
| Skew & Smile | Histórico + smile do dia |
| IV vs Realizada | Backward / forward |
| Busca opções | Filtros + série de preços |

Ativos padrão (watchlist seed): **BOVA11, SMAL11, PETR4, EQTL3, VALE3, ITUB4, BPAC11**, etc. — ver `TICKERS_SEED_24M` em `config_mr_derivs.R`.

## Cache COTAHIST (24 meses + diário)

O COTAHIST é **único para a B3** (não é por ticker). Baixar 24 meses cobre BOVA, PETR, etc.

**Seed inicial** (pode demorar):

```bat
scripts\run_seed_24m.bat
```

ou:

```bat
Rscript jobs/seed_cache_24m.R "C:/.../Documentos/rb3_cache" 24
```

**Atualização diária** (incremental):

```bat
scripts\run_cache_diario.bat
```

Agende no **Agendador de Tarefas** do Windows (ex.: 19:30, dias úteis). Log: `jobs/logs/cache_cotahist.log`.

Variáveis úteis:

```r
Sys.setenv(MR_DERIVS_RB3_CACHE = "D:/rb3_cache")
Sys.setenv(MR_DERIVS_CACHE_MESES = "24")
```

## GitHub

Ver [GITHUB.md](GITHUB.md). O cache **não** entra no repositório.

## Estrutura

| Path | Função |
|------|--------|
| `app_vol_implicita.R` | Shiny |
| `vol_implicita_11.R` | Pipeline IV / FVOL |
| `busca_opcoes.R` | COTAHIST + busca |
| `carrego_pcp.R` | Carrego PCP |
| `config_mr_derivs.R` | Config central |
| `jobs/seed_cache_24m.R` | Seed 24m |
| `jobs/atualizar_cache_diario.R` | Job diário |

Módulos extras (radar IBOV, beta, simulação short): ainda no repo, fora do app enxuto.

## Pacotes R

`shiny`, `DT`, `ggplot2`, `plotly`, `dplyr`, `tidyr`, `rb3`, `bizdays`, `oplib`, `lubridate`, `callr`, `httr`, `jsonlite`, `zoo`, `stringr`, `tibble`, `patchwork`, `glue`, `scales`

```r
install.packages(c("shiny", "DT", "ggplot2", "plotly", "dplyr", "tidyr",
  "rb3", "bizdays", "oplib", "lubridate", "callr", "httr", "jsonlite",
  "zoo", "stringr", "tibble", "patchwork", "glue", "scales"))
```
