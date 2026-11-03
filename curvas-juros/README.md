# curvas-juros

Projeto em R para **comparar curvas de juros**: nível atual vs marcos históricos (1, 3, 6, 12, 24 e 36 meses).

Publicado no hub **btg-distribuicao-rv** (branch `pages`):

- Painel: [Curvas de juros](https://btg-pactual.github.io/btg-distribuicao-rv/curvas-juros/)
- Swap CDI × pré: [Simulador](https://btg-pactual.github.io/btg-distribuicao-rv/curvas-juros/swap/)

## Fontes

- **DI futuro (DI1)** — B3 (histórico) + **ADVFN** (cotação ULT do dia).
- **Tesouro Direto** (CSV Tesouro Transparente).
- **ANBIMA ETTJ** (últimos dias úteis).

## Como rodar (local)

```text
"C:\Program Files\R\R-4.4.1\bin\Rscript.exe" "gerar_curvas_juros.R"
Rscript scripts/ci_publish.R
Rscript scripts/ci_publish.R advfn_only
```

## GitHub Actions (monorepo)

| Workflow | Função |
|----------|--------|
| `curvas-daily.yml` | B3 + ADVFN + HTML (~19h BRT) |
| `curvas-refresh-advfn.yml` | Só ADVFN (horário de pregão) + botão *Run workflow* |

Botão **Atualizar cotação ADVFN** no site recarrega `data/curva_advfn.json`. **Forçar coleta** abre o workflow no GitHub.
