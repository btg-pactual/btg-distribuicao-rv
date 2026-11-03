# Swap CDI × Pré — simulador (interno)

Uso **local** por enquanto. Não publicar no GitHub Pages até revisão.

## Gerar

Na pasta `curvas-juros`:

```text
"C:\Program Files\R\R-4.4.1\bin\Rscript.exe" "swap-cdi-pre/gerar_swap_simulador.R"
```

Requisito: `data/processed/curvas_di_futuros_historico.csv` (pipeline `01_download_curva_di.R`).

**Curva atual:** cotações **ADVFN** (ULT por contrato DI1). **Histórico:** fechamento **B3**. Se a ADVFN falhar, usa a última data B3 do CSV.

## Abrir

Arquivo gerado: **`swap-cdi-pre/swap_simulador.html`** (duplo clique no navegador).

## Funcionalidades

- Swap **paga %CDI / recebe pré**
- Prazo até **10 anos**
- Choque paralelo na curva DI (±200 bp)
- MTM simplificado + histórico DI1 interativo
