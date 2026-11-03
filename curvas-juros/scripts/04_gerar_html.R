# =============================================================================
# 04_gerar_html.R — dashboard HTML interativo (Chart.js)
# =============================================================================

source("scripts/00_setup.R")

fmt_date <- function(x) format(as.Date(x), "%Y-%m-%d")
fmt_date_br <- function(x) format(as.Date(x), "%d/%m/%Y")

montar_pts <- function(df, x_col, y_col) {
  df <- df[!is.na(df[[x_col]]) & !is.na(df[[y_col]]), , drop = FALSE]
  if (nrow(df) == 0L) {
    return(list())
  }
  lapply(seq_len(nrow(df)), function(i) {
    list(
      x = as.numeric(df[[x_col]][i]),
      y = as.numeric(df[[y_col]][i])
    )
  })
}

# --- DI -----------------------------------------------------------------------
di_curvas <- list()
path_di <- "data/processed/curvas_di_futuros_historico.csv"
if (file.exists(path_di)) {
  di_raw <- readr::read_csv(
    path_di,
    col_types = readr::cols(
      data = readr::col_date(),
      vencimento = readr::col_date(),
      simbolo = readr::col_character(),
      rotulo = readr::col_character(),
      fonte = readr::col_character(),
      prazo_anos = readr::col_double(),
      taxa_aa = readr::col_double(),
      .default = readr::col_guess()
    )
  )
  di_datas <- di_raw |>
    dplyr::distinct(.data$data, .data$rotulo, .data$fonte, .data$mes_ref) |>
    dplyr::arrange(dplyr::desc(.data$data))

  di_curvas <- lapply(seq_len(nrow(di_datas)), function(i) {
    dt <- di_datas$data[i]
    pts_df <- di_raw |>
      dplyr::filter(.data$data == dt) |>
      dplyr::arrange(.data$prazo_anos)
    list(
      id = fmt_date(dt),
      data = fmt_date(dt),
      data_br = fmt_date_br(dt),
      rotulo = {
        r <- di_datas$rotulo[i]
        if (is.na(r) || !nzchar(r)) NULL else as.character(r)
      },
      fonte = as.character(di_datas$fonte[i]),
      pts = montar_pts(pts_df, "prazo_anos", "taxa_aa")
    )
  })

  source("scripts/R/b3_di_curva.R")
  source("scripts/R/advfn_di_curva.R")
  di_ao_vivo <- tryCatch(
    obter_curva_di1_advfn(Sys.Date()),
    error = function(e) {
      message("ADVFN (dashboard): ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(di_ao_vivo) && nrow(di_ao_vivo) >= 5L) {
    fetched <- attr(di_ao_vivo, "fetched_at")
    live <- list(
      id = "ao-vivo-advfn",
      data = fmt_date(Sys.Date()),
      data_br = paste0(fmt_date_br(Sys.Date()), " · ADVFN"),
      rotulo = "cotação ULT",
      fonte = "advfn_ult",
      pts = montar_pts(di_ao_vivo, "prazo_anos", "taxa_aa")
    )
    di_curvas <- c(list(live), di_curvas)
    di_vivo_meta <- list(
      br = fmt_date_br(Sys.Date()),
      iso = fmt_date(Sys.Date()),
      coleta = if (!is.null(fetched)) format(fetched, "%d/%m/%Y %H:%M") else NULL
    )
    source("scripts/R/export_viva_json.R")
    export_curva_advfn_json(
      di_ao_vivo,
      path = "data/curva_advfn.json",
      coleta_em = if (!is.null(fetched)) fetched else Sys.time(),
      data_ref = Sys.Date()
    )
  }
}

di_vivo_meta <- if (exists("di_vivo_meta", inherits = FALSE)) {
  di_vivo_meta
} else {
  NULL
}

# --- Tesouro ------------------------------------------------------------------
tes_tipos <- character()
tes_curvas <- list()
path_tes <- "data/processed/curvas_tesouro_comparativo.csv"
data_atual_tes <- NA_character_
if (file.exists(path_tes)) {
  tes_raw <- readr::read_csv(
    path_tes,
    col_types = readr::cols(
      tipo = readr::col_character(),
      data = readr::col_date(),
      vencimento = readr::col_date(),
      rotulo = readr::col_character(),
      prazo_anos = readr::col_double(),
      taxa_compra = readr::col_double(),
      .default = readr::col_guess()
    )
  )
  data_atual_tes <- fmt_date_br(max(tes_raw$data))
  tes_tipos <- sort(unique(tes_raw$tipo))
  tes_datas <- tes_raw |>
    dplyr::distinct(.data$data, .data$rotulo) |>
    dplyr::arrange(dplyr::desc(.data$data))

  tes_curvas <- lapply(seq_len(nrow(tes_datas)), function(i) {
    dt <- tes_datas$data[i]
    bloco <- tes_raw |>
      dplyr::filter(.data$data == dt)
    series <- lapply(tes_tipos, function(tp) {
      pts_df <- bloco |>
        dplyr::filter(.data$tipo == tp) |>
        dplyr::arrange(.data$prazo_anos)
      montar_pts(pts_df, "prazo_anos", "taxa_compra")
    })
    names(series) <- tes_tipos
    list(
      id = fmt_date(dt),
      data = fmt_date(dt),
      data_br = fmt_date_br(dt),
      rotulo = as.character(tes_datas$rotulo[i]),
      series = series
    )
  })
}

# --- ANBIMA -------------------------------------------------------------------
anbima <- list(curvas = list(), refs = character(), series = character())
path_anb <- "data/processed/anbima_ettj_recente.csv"
if (file.exists(path_anb)) {
  anb_raw <- readr::read_csv(path_anb, show_col_types = FALSE)
  anb_raw$data_ref <- as.Date(anb_raw$data_ref)
  anbima$refs <- sort(unique(fmt_date(anb_raw$data_ref)), decreasing = TRUE)
  anbima$series <- sort(unique(anb_raw$serie))
  anbima$curvas <- lapply(
    split(anb_raw, interaction(anb_raw$data_ref, anb_raw$serie, drop = TRUE)),
    function(g) {
      g <- g[order(g$prazo_anos), ]
      list(
        ref = fmt_date(g$data_ref[1]),
        ref_br = fmt_date_br(g$data_ref[1]),
        serie = g$serie[1],
        pts = montar_pts(g, "prazo_anos", "taxa")
      )
    }
  )
}

ultima_tesouro <- NA_Date_
path_tes_long <- "data/processed/tesouro_curvas_long.csv"
if (file.exists(path_tes_long)) {
  tes_long <- readr::read_csv(
    path_tes_long,
    col_types = readr::cols(data = readr::col_date(), .default = readr::col_guess())
  )
  ultima_tesouro <- max(tes_long$data, na.rm = TRUE)
} else if (exists("tes_raw", inherits = FALSE)) {
  ultima_tesouro <- max(tes_raw$data, na.rm = TRUE)
}

ultima_di <- NA_Date_
if (length(di_curvas) > 0L) {
  ultima_di <- max(as.Date(vapply(di_curvas, `[[`, "", "data"), origin = "1970-01-01"))
}

ultima_anbima <- NA_Date_
if (length(anbima$refs) > 0L) {
  ultima_anbima <- as.Date(anbima$refs[[1]])
}

ultimas <- function(d) {
  if (length(d) != 1L || is.na(d)) {
    return(list(iso = NULL, br = NULL))
  }
  list(iso = fmt_date(d), br = fmt_date_br(d))
}

gh_repo <- Sys.getenv("GITHUB_REPOSITORY", unset = "")
if (!nzchar(gh_repo)) gh_repo <- NULL

payload <- list(
  gerado_em = format(Sys.time(), "%d/%m/%Y %H:%M"),
  hoje = fmt_date(Sys.Date()),
  github = list(
    repo = gh_repo,
    curva_json = "data/curva_advfn.json",
    workflow_advfn = "curvas-refresh-advfn.yml"
  ),
  ultimas = list(
    tesouro = ultimas(ultima_tesouro),
    di = ultimas(ultima_di),
    di_vivo = di_vivo_meta,
    anbima = ultimas(ultima_anbima)
  ),
  di = list(
    curvas = di_curvas,
    defaults = list(
      prazo_min = 0.25,
      prazo_max = 15,
      nivel_prazo_min = 4.5,
      nivel_prazo_max = 5.5
    )
  ),
  tesouro = list(
    tipos = tes_tipos,
    curvas = tes_curvas,
    defaults = list(prazo_min = 0.5, prazo_max = 22)
  ),
  anbima = anbima
)

json_txt <- jsonlite::toJSON(
  payload,
  auto_unbox = TRUE,
  null = "null",
  digits = 6
)

html <- paste0(
'<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Curvas de juros — interativo</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
  <style>
    :root {
      --bg: #f4f6f8; --card: #fff; --text: #1a2332; --muted: #5b6775;
      --line: #e2e8f0; --accent: #0b5fff; --accent-soft: #e8f0ff;
    }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: "Segoe UI", system-ui, sans-serif; background: var(--bg); color: var(--text); }
    header {
      background: linear-gradient(135deg, #0b2a4a, #0b5fff);
      color: #fff; padding: 1.4rem 1.25rem;
    }
    header h1 { margin: 0 0 .3rem; font-size: 1.45rem; }
    header p { margin: 0; opacity: .92; font-size: .92rem; }
    .meta-wrap { background: linear-gradient(135deg, #0a2440, #0a4fd4); padding-bottom: .25rem; }
    .meta {
      display: flex; flex-wrap: wrap; gap: .55rem;
      margin: -.35rem auto 0; padding: 0 1.25rem 1rem;
      max-width: 1180px;
    }
    .meta .chip {
      background: rgba(255,255,255,0.14);
      border: 1px solid rgba(255,255,255,0.35);
      color: #fff;
      border-radius: 999px;
      padding: .32rem .75rem;
      font-size: .82rem;
      font-variant-numeric: tabular-nums;
    }
    .meta .chip strong { font-weight: 600; }
    main { max-width: 1180px; margin: 0 auto; padding: 1rem 1.25rem 2rem; }
    .ultima-aba { font-size: .88rem; color: var(--muted); margin: 0 0 .75rem; }
    .ultima-aba strong { color: var(--text); }
    .tabs { display: flex; flex-wrap: wrap; gap: .45rem; margin: 1rem 0; }
    .tabs button {
      border: 1px solid var(--line); background: var(--card); color: var(--muted);
      padding: .45rem .95rem; border-radius: 999px; cursor: pointer; font-size: .9rem;
    }
    .tabs button.active { background: var(--accent); border-color: var(--accent); color: #fff; }
    .panel { display: none; }
    .panel.active { display: block; }
    section {
      background: var(--card); border: 1px solid var(--line); border-radius: 12px;
      padding: 1rem 1.1rem 1.15rem; margin-bottom: 1rem;
    }
    section h2 { margin: 0 0 .65rem; font-size: 1.05rem; }
    section p.hint { margin: 0 0 .85rem; color: var(--muted); font-size: .88rem; }
    .grid-controls {
      display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
      gap: .75rem 1rem; margin-bottom: .85rem; align-items: end;
    }
    label { display: grid; gap: .25rem; font-size: .82rem; color: var(--muted); }
    input[type=number], select {
      padding: .4rem .55rem; border: 1px solid var(--line); border-radius: 8px;
      font-size: .92rem; width: 100%;
    }
    input[type=range] { width: 100%; }
    .range-val { font-size: .85rem; color: var(--text); font-variant-numeric: tabular-nums; }
    .btn-row { display: flex; flex-wrap: wrap; gap: .4rem; margin-bottom: .65rem; }
    .btn-row button {
      border: 1px solid var(--line); background: #fff; color: var(--muted);
      border-radius: 8px; padding: .3rem .65rem; font-size: .82rem; cursor: pointer;
    }
    .btn-row button:hover { border-color: var(--accent); color: var(--accent); }
    .date-list {
      max-height: 160px; overflow: auto; border: 1px solid var(--line);
      border-radius: 8px; padding: .5rem .65rem; background: #fafbfc;
    }
    .date-list label.row {
      display: flex; align-items: center; gap: .45rem; font-size: .85rem;
      color: var(--text); margin: .2rem 0; cursor: pointer;
    }
    .chart-wrap { position: relative; height: 380px; }
    .chart-wrap.sm { height: 320px; }
    footer { color: var(--muted); font-size: .82rem; padding-top: .5rem; }
    a { color: var(--accent); }
  </style>
</head>
<body>
  <header>
    <h1>Curvas de juros — painel interativo</h1>
    <p>Ajuste prazos, datas de referência e séries. Gerado em ',
format(Sys.time(), "%d/%m/%Y %H:%M"),
'.</p>
  </header>
  <div class="meta-wrap"><div class="meta" id="meta-ultimas"></div></div>
  <main>
    <div class="tabs" id="tabs">
      <button type="button" data-tab="di" class="active">DI futuro (DI1)</button>
      <button type="button" data-tab="tes">Tesouro Direto</button>
      <button type="button" data-tab="anb">ANBIMA ETTJ</button>
    </div>

    <div id="panel-di" class="panel active">
      <p class="ultima-aba" id="ultima-di"></p>
      <div class="btn-row" style="margin-bottom:.75rem">
        <button type="button" id="btn-di-refresh-advfn">Atualizar cotação ADVFN</button>
        <button type="button" id="btn-di-server-advfn" class="secondary">Forçar coleta (GitHub Actions)</button>
      </div>
      <p class="hint" id="di-refresh-status"></p>
      <section>
        <h2>Curva DI — comparar datas</h2>
        <p class="hint">Eixo X = prazo (anos até o vencimento do contrato). Fonte: B3 (API + boletim PR).</p>
        <div class="grid-controls">
          <label>Prazo mín. (anos)
            <input type="number" id="di-prazo-min" step="0.1" min="0" max="30" />
          </label>
          <label>Prazo máx. (anos)
            <input type="number" id="di-prazo-max" step="0.1" min="0" max="30" />
          </label>
        </div>
        <div class="btn-row" id="di-date-btns"></div>
        <div class="date-list" id="di-dates"></div>
        <div class="chart-wrap" style="margin-top:.85rem">
          <canvas id="chart-di-curva"></canvas>
        </div>
      </section>
      <section>
        <h2>DI — nível da curva no tempo</h2>
        <p class="hint">Mediana da taxa DI1 na faixa de prazo escolhida (proxy do “nível” da curva).</p>
        <div class="grid-controls">
          <label>Faixa prazo mín. (anos)
            <input type="number" id="di-nivel-min" step="0.1" min="0" max="30" />
          </label>
          <label>Faixa prazo máx. (anos)
            <input type="number" id="di-nivel-max" step="0.1" min="0" max="30" />
          </label>
        </div>
        <div class="chart-wrap sm">
          <canvas id="chart-di-nivel"></canvas>
        </div>
      </section>
    </div>

    <div id="panel-tes" class="panel">
      <p class="ultima-aba" id="ultima-tes"></p>
      <section>
        <h2>Tesouro — curvas por tipo</h2>
        <p class="hint">Taxa de compra (manhã) — Tesouro Transparente.</p>
        <div class="grid-controls">
          <label>Tipo de título
            <select id="tes-tipo"></select>
          </label>
          <label>Prazo mín. (anos)
            <input type="number" id="tes-prazo-min" step="0.1" min="0" max="40" />
          </label>
          <label>Prazo máx. (anos)
            <input type="number" id="tes-prazo-max" step="0.1" min="0" max="40" />
          </label>
        </div>
        <div class="btn-row" id="tes-date-btns"></div>
        <div class="date-list" id="tes-dates"></div>
        <div class="chart-wrap" style="margin-top:.85rem">
          <canvas id="chart-tes"></canvas>
        </div>
      </section>
      <section>
        <h2>Tesouro — nível no tempo</h2>
        <div class="grid-controls">
          <label>Faixa prazo mín.
            <input type="number" id="tes-nivel-min" step="0.1" />
          </label>
          <label>Faixa prazo máx.
            <input type="number" id="tes-nivel-max" step="0.1" />
          </label>
        </div>
        <div class="chart-wrap sm">
          <canvas id="chart-tes-nivel"></canvas>
        </div>
      </section>
    </div>

    <div id="panel-anb" class="panel">
      <p class="ultima-aba" id="ultima-anb"></p>
      <section>
        <h2>ETTJ ANBIMA</h2>
        <p class="hint">Últimos dias úteis disponíveis no download ANBIMA.</p>
        <div class="grid-controls">
          <label>Data de referência
            <select id="anb-ref"></select>
          </label>
          <label>Série
            <select id="anb-serie"></select>
          </label>
          <label>Prazo mín. (anos)
            <input type="number" id="anb-prazo-min" step="0.1" min="0" max="40" />
          </label>
          <label>Prazo máx. (anos)
            <input type="number" id="anb-prazo-max" step="0.1" min="0" max="40" />
          </label>
        </div>
        <div class="chart-wrap">
          <canvas id="chart-anb"></canvas>
        </div>
      </section>
    </div>

    <footer>
      Fontes:
      <a href="https://www.tesourotransparente.gov.br/temas/divida-publica-federal/tesouro-direto">Tesouro Transparente</a>,
      B3 (DI1),
      <a href="https://www.anbima.com.br/informacoes/est-termo/">ANBIMA ETTJ</a>.
      Atualize os dados com <code>scripts/run_all.R</code>.
    </footer>
  </main>

  <script id="dados" type="application/json">',
json_txt,
'</script>
  <script>
    const DATA = JSON.parse(document.getElementById("dados").textContent);
    const U = DATA.ultimas || {};

    function renderUltimas() {
      const meta = document.getElementById("meta-ultimas");
      const hoje = DATA.hoje ? " (hoje: " + DATA.hoje.split("-").reverse().join("/") + ")" : "";
      const chips = [
        ["Tesouro", U.tesouro],
        ["DI fechamento (B3)", U.di],
        ["DI cotação (ADVFN)", U.di_vivo && U.di_vivo.coleta
          ? { br: (U.di_vivo.br || "—") + " · " + U.di_vivo.coleta }
          : U.di_vivo],
        ["ANBIMA", U.anbima]
      ];
      meta.innerHTML = chips.map(([nome, u]) => {
        const txt = u && u.br ? u.br : "—";
        return `<span class="chip"><strong>${nome}:</strong> até ${txt}</span>`;
      }).join("") + `<span class="chip">Calendário${hoje}</span>`;

      const setAba = (id, nome, u) => {
        const el = document.getElementById(id);
        if (!el) return;
        el.innerHTML = u && u.br
          ? `Última data disponível <strong>${nome}</strong> no pacote: <strong>${u.br}</strong>`
          : `Sem dados ${nome} no pacote.`;
      };
      const elDi = document.getElementById("ultima-di");
      if (elDi) {
        const b3 = U.di && U.di.br ? U.di.br : "—";
        const vivo = U.di_vivo && U.di_vivo.coleta
          ? ` Cotação intraday (ADVFN): <strong>${U.di_vivo.coleta}</strong>.`
          : "";
        elDi.innerHTML =
          `Fechamento B3 no pacote: <strong>${b3}</strong>.${vivo}`;
      }
      setAba("ultima-tes", "Tesouro", U.tesouro);
      setAba("ultima-anb", "ETTJ ANBIMA", U.anbima);
    }
    renderUltimas();

    const CORES = [
      "#0b5fff","#6366f1","#8b5cf6","#a855f7","#d946ef","#f97316","#ef4444",
      "#14b8a6","#84cc16","#eab308","#64748b","#0ea5e9"
    ];

    const fmt = (v, d = 2) =>
      v == null || Number.isNaN(v) ? "—" :
      Number(v).toLocaleString("pt-BR", { minimumFractionDigits: d, maximumFractionDigits: d });

    function filtrarPts(pts, xmin, xmax) {
      return pts.filter(p => p.x >= xmin && p.x <= xmax).sort((a, b) => a.x - b.x);
    }

    function medianaFaixa(pts, xmin, xmax) {
      const ys = filtrarPts(pts, xmin, xmax).map(p => p.y).filter(y => y != null && !Number.isNaN(y));
      if (!ys.length) return null;
      ys.sort((a, b) => a - b);
      const m = Math.floor(ys.length / 2);
      return ys.length % 2 ? ys[m] : (ys[m - 1] + ys[m]) / 2;
    }

    function labelCurva(c) {
      let t = c.data_br || c.data;
      if (c.rotulo) t += " · " + c.rotulo;
      return t;
    }

    // --- tabs ---
    document.querySelectorAll("#tabs button").forEach(btn => {
      btn.onclick = () => {
        document.querySelectorAll("#tabs button").forEach(b => b.classList.remove("active"));
        document.querySelectorAll(".panel").forEach(p => p.classList.remove("active"));
        btn.classList.add("active");
        document.getElementById("panel-" + btn.dataset.tab).classList.add("active");
      };
    });

    let chartDiCurva, chartDiNivel, chartTes, chartTesNivel, chartAnb;

    function mkLineChart(canvasId, datasets, title, xTitle, yTitle) {
      const el = document.getElementById(canvasId);
      const cfg = {
        type: "line",
        data: { datasets },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          interaction: { mode: "nearest", intersect: false },
          plugins: {
            title: { display: !!title, text: title || "" },
            legend: { position: "bottom" }
          },
          scales: {
            x: {
              type: "linear",
              title: { display: true, text: xTitle || "Prazo (anos)" },
              grid: { color: "#eef2f7" }
            },
            y: {
              title: { display: true, text: yTitle || "% a.a." },
              grid: { color: "#eef2f7" }
            }
          }
        }
      };
      const map = {
        "chart-di-curva": chartDiCurva,
        "chart-di-nivel": chartDiNivel,
        "chart-tes": chartTes,
        "chart-tes-nivel": chartTesNivel,
        "chart-anb": chartAnb
      };
      if (map[canvasId]) map[canvasId].destroy();
      const ch = new Chart(el, cfg);
      if (canvasId === "chart-di-curva") chartDiCurva = ch;
      if (canvasId === "chart-di-nivel") chartDiNivel = ch;
      if (canvasId === "chart-tes") chartTes = ch;
      if (canvasId === "chart-tes-nivel") chartTesNivel = ch;
      if (canvasId === "chart-anb") chartAnb = ch;
    }

    function mkTimeChart(canvasId, labels, values, title) {
      const el = document.getElementById(canvasId);
      const cfg = {
        type: "line",
        data: {
          labels,
          datasets: [{
            label: "Taxa mediana (% a.a.)",
            data: values,
            borderColor: "#0b5fff",
            backgroundColor: "rgba(11,95,255,0.12)",
            fill: true,
            tension: 0.15,
            pointRadius: 3,
            borderWidth: 2
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { title: { display: true, text: title }, legend: { display: false } },
          scales: {
            x: { ticks: { maxTicksLimit: 12 }, grid: { color: "#eef2f7" } },
            y: { title: { display: true, text: "% a.a." }, grid: { color: "#eef2f7" } }
          }
        }
      };
      if (canvasId === "chart-di-nivel" && chartDiNivel) chartDiNivel.destroy();
      if (canvasId === "chart-tes-nivel" && chartTesNivel) chartTesNivel.destroy();
      const ch = new Chart(el, cfg);
      if (canvasId === "chart-di-nivel") chartDiNivel = ch;
      if (canvasId === "chart-tes-nivel") chartTesNivel = ch;
    }

    function buildDateList(containerId, curvas, prefix, onChange) {
      const box = document.getElementById(containerId);
      box.innerHTML = "";
      curvas.forEach((c, i) => {
        const id = prefix + "-dt-" + c.id;
        const lab = document.createElement("label");
        lab.className = "row";
        lab.innerHTML = `<input type="checkbox" id="${id}" value="${c.id}" /> ${labelCurva(c)}`;
        lab.querySelector("input").onchange = onChange;
        box.appendChild(lab);
      });
    }

    function selectedIds(prefix, curvas) {
      return curvas
        .filter(c => {
          const el = document.getElementById(prefix + "-dt-" + c.id);
          return el && el.checked;
        })
        .map(c => c.id);
    }

    function setChecks(prefix, curvas, ids) {
      curvas.forEach(c => {
        const el = document.getElementById(prefix + "-dt-" + c.id);
        if (el) el.checked = ids.includes(c.id);
      });
    }

    // ========== DI ==========
    const diCurvas = (DATA.di && DATA.di.curvas) || [];
    const diDef = (DATA.di && DATA.di.defaults) || {};

    function initDi() {
      if (!diCurvas.length) {
        document.getElementById("panel-di").innerHTML =
          "<section><p>Nenhum dado DI. Rode <code>01_download_curva_di.R</code>.</p></section>";
        return;
      }
      document.getElementById("di-prazo-min").value = diDef.prazo_min ?? 0.25;
      document.getElementById("di-prazo-max").value = diDef.prazo_max ?? 15;
      document.getElementById("di-nivel-min").value = diDef.nivel_prazo_min ?? 4.5;
      document.getElementById("di-nivel-max").value = diDef.nivel_prazo_max ?? 5.5;

      const redraw = () => { drawDiCurva(); drawDiNivel(); };
      buildDateList("di-dates", diCurvas, "di", redraw);

      const liveId = diCurvas.find(c => c.id === "ao-vivo-advfn");
      const marcos = diCurvas.filter(c => c.rotulo && c.id !== "ao-vivo-advfn").map(c => c.id);
      let prefer = marcos.length ? marcos : diCurvas.slice(0, 3).map(c => c.id);
      if (liveId && !prefer.includes(liveId.id)) {
        prefer = [liveId.id, ...prefer.slice(0, 2)];
      }
      setChecks("di", diCurvas, prefer);

      const btnBox = document.getElementById("di-date-btns");
      btnBox.innerHTML = "";
      [
        ["Marcos / padrão", () => setChecks("di", diCurvas, prefer)],
        ["Todas", () => setChecks("di", diCurvas, diCurvas.map(c => c.id))],
        ["Nenhuma", () => setChecks("di", diCurvas, [])],
        ["Só mais recente", () => {
          const ult = U.di && U.di.iso;
          const id = ult && diCurvas.find(c => c.data === ult)
            ? ult
            : diCurvas[0].id;
          setChecks("di", diCurvas, [id]);
        }]
      ].forEach(([txt, fn]) => {
        const b = document.createElement("button");
        b.type = "button";
        b.textContent = txt;
        b.onclick = () => { fn(); redraw(); };
        btnBox.appendChild(b);
      });

      ["di-prazo-min","di-prazo-max","di-nivel-min","di-nivel-max"].forEach(id => {
        document.getElementById(id).oninput = redraw;
      });

      const liveJson = (DATA.github && DATA.github.curva_json) || "data/curva_advfn.json";
      const st = document.getElementById("di-refresh-status");
      const btnRef = document.getElementById("btn-di-refresh-advfn");
      const btnSrv = document.getElementById("btn-di-server-advfn");
      if (btnRef) {
        btnRef.onclick = async () => {
          btnRef.disabled = true;
          if (st) st.textContent = "Carregando cotação publicada…";
          try {
            const r = await fetch(liveJson + "?t=" + Date.now(), { cache: "no-store" });
            if (!r.ok) throw new Error("HTTP " + r.status);
            const j = await r.json();
            if (!j.pts || !j.pts.length) throw new Error("JSON vazio");
            let live = diCurvas.find(c => c.id === "ao-vivo-advfn");
            if (!live) {
              live = {
                id: "ao-vivo-advfn",
                data: j.data,
                data_br: j.data_br || j.data,
                rotulo: "cotação ULT",
                fonte: j.fonte || "advfn_ult",
                pts: j.pts
              };
              diCurvas.unshift(live);
              buildDateList("di-dates", diCurvas, "di", redraw);
              const el = document.getElementById("di-dt-ao-vivo-advfn");
              if (el) el.checked = true;
            } else {
              live.pts = j.pts;
              live.data_br = j.data_br || live.data_br;
            }
            if (st) st.textContent = "ADVFN: " + (j.coleta_em || "—");
            redraw();
          } catch (err) {
            if (st) st.textContent = "";
            alert("Falha ao atualizar ADVFN: " + err.message);
          } finally {
            btnRef.disabled = false;
          }
        };
      }
      if (btnSrv) {
        btnSrv.onclick = () => {
          const repo = DATA.github && DATA.github.repo;
          const wf = (DATA.github && DATA.github.workflow_advfn) || "refresh-advfn.yml";
          if (repo) {
            window.open("https://github.com/" + repo + "/actions/workflows/" + wf, "_blank");
            if (st) st.textContent = "Workflow aberto — aguarde ~1–2 min e clique em Atualizar.";
          } else {
            alert("GitHub Actions: curvas-refresh-advfn.yml → Run workflow.");
          }
        };
      }

      redraw();
    }

    function drawDiCurva() {
      const xmin = +document.getElementById("di-prazo-min").value || 0;
      const xmax = +document.getElementById("di-prazo-max").value || 30;
      const ids = selectedIds("di", diCurvas);
      const datasets = diCurvas
        .filter(c => ids.includes(c.id))
        .map((c, i) => {
          const pts = filtrarPts(c.pts || [], xmin, xmax);
          return {
            label: labelCurva(c),
            data: pts.map(p => ({ x: p.x, y: p.y })),
            borderColor: CORES[i % CORES.length],
            backgroundColor: CORES[i % CORES.length] + "22",
            tension: 0.15,
            pointRadius: 3,
            borderWidth: 2
          };
        });
      mkLineChart("chart-di-curva", datasets, "Curva DI1", "Prazo (anos)", "Taxa DI (% a.a.)");
    }

    function drawDiNivel() {
      const xmin = +document.getElementById("di-nivel-min").value || 4.5;
      const xmax = +document.getElementById("di-nivel-max").value || 5.5;
      const ordered = [...diCurvas].sort((a, b) => a.data.localeCompare(b.data));
      const labels = [];
      const vals = [];
      ordered.forEach(c => {
        const m = medianaFaixa(c.pts || [], xmin, xmax);
        if (m != null) {
          labels.push(c.data);
          vals.push(m);
        }
      });
      mkTimeChart(
        "chart-di-nivel",
        labels,
        vals,
        `Nível DI (mediana ${fmt(xmin,1)}–${fmt(xmax,1)} anos)`
      );
    }

    // ========== Tesouro ==========
    const tesCurvas = (DATA.tesouro && DATA.tesouro.curvas) || [];
    const tesTipos = (DATA.tesouro && DATA.tesouro.tipos) || [];
    const tesDef = (DATA.tesouro && DATA.tesouro.defaults) || {};

    function initTes() {
      if (!tesCurvas.length) {
        document.getElementById("panel-tes").innerHTML =
          "<section><p>Sem dados Tesouro comparativos.</p></section>";
        return;
      }
      const sel = document.getElementById("tes-tipo");
      tesTipos.forEach(t => {
        const o = document.createElement("option");
        o.value = t; o.textContent = t;
        sel.appendChild(o);
      });
      document.getElementById("tes-prazo-min").value = tesDef.prazo_min ?? 0.5;
      document.getElementById("tes-prazo-max").value = tesDef.prazo_max ?? 22;
      document.getElementById("tes-nivel-min").value = 4.5;
      document.getElementById("tes-nivel-max").value = 5.5;

      const redraw = () => { drawTesCurva(); drawTesNivel(); };
      buildDateList("tes-dates", tesCurvas, "tes", redraw);
      setChecks("tes", tesCurvas, tesCurvas.map(c => c.id));

      const btnBox = document.getElementById("tes-date-btns");
      [
        ["Todas", () => setChecks("tes", tesCurvas, tesCurvas.map(c => c.id))],
        ["Atual + 12m + 36m", () => {
          const want = ["Atual", "12m atrás", "36m atrás"];
          setChecks("tes", tesCurvas, tesCurvas.filter(c => want.includes(c.rotulo)).map(c => c.id));
        }],
        ["Nenhuma", () => setChecks("tes", tesCurvas, [])]
      ].forEach(([txt, fn]) => {
        const b = document.createElement("button");
        b.type = "button";
        b.textContent = txt;
        b.onclick = () => { fn(); redraw(); };
        btnBox.appendChild(b);
      });

      sel.onchange = redraw;
      ["tes-prazo-min","tes-prazo-max","tes-nivel-min","tes-nivel-max"].forEach(id => {
        document.getElementById(id).oninput = redraw;
      });
      redraw();
    }

    function drawTesCurva() {
      const tipo = document.getElementById("tes-tipo").value;
      const xmin = +document.getElementById("tes-prazo-min").value || 0;
      const xmax = +document.getElementById("tes-prazo-max").value || 40;
      const ids = selectedIds("tes", tesCurvas);
      const datasets = tesCurvas
        .filter(c => ids.includes(c.id))
        .map((c, i) => {
          const pts = filtrarPts((c.series && c.series[tipo]) || [], xmin, xmax);
          return {
            label: labelCurva(c),
            data: pts.map(p => ({ x: p.x, y: p.y })),
            borderColor: CORES[i % CORES.length],
            tension: 0.15,
            pointRadius: 3,
            borderWidth: 2
          };
        });
      mkLineChart("chart-tes", datasets, tipo, "Prazo (anos)", "Taxa compra (% a.a.)");
    }

    function drawTesNivel() {
      const tipo = document.getElementById("tes-tipo").value;
      const xmin = +document.getElementById("tes-nivel-min").value || 4.5;
      const xmax = +document.getElementById("tes-nivel-max").value || 5.5;
      const ordered = [...tesCurvas].sort((a, b) => a.data.localeCompare(b.data));
      const labels = [];
      const vals = [];
      ordered.forEach(c => {
        const m = medianaFaixa((c.series && c.series[tipo]) || [], xmin, xmax);
        if (m != null) {
          labels.push(c.data);
          vals.push(m);
        }
      });
      mkTimeChart(
        "chart-tes-nivel",
        labels,
        vals,
        `${tipo} — mediana ${fmt(xmin,1)}–${fmt(xmax,1)} a`
      );
    }

    // ========== ANBIMA ==========
    const anbCurvas = (DATA.anbima && DATA.anbima.curvas) || [];
    const anbRefs = (DATA.anbima && DATA.anbima.refs) || [];
    const anbSeries = (DATA.anbima && DATA.anbima.series) || [];

    function initAnb() {
      if (!anbCurvas.length) {
        document.getElementById("panel-anb").innerHTML =
          "<section><p>Sem ETTJ ANBIMA no cache.</p></section>";
        return;
      }
      const selRef = document.getElementById("anb-ref");
      const selSer = document.getElementById("anb-serie");
      anbRefs.forEach(r => {
        const o = document.createElement("option");
        o.value = r; o.textContent = r;
        selRef.appendChild(o);
      });
      anbSeries.forEach(s => {
        const o = document.createElement("option");
        o.value = s; o.textContent = s;
        selSer.appendChild(o);
      });
      document.getElementById("anb-prazo-min").value = 1;
      document.getElementById("anb-prazo-max").value = 15;
      const redraw = () => drawAnb();
      selRef.onchange = redraw;
      selSer.onchange = redraw;
      ["anb-prazo-min","anb-prazo-max"].forEach(id => {
        document.getElementById(id).oninput = redraw;
      });
      redraw();
    }

    function drawAnb() {
      const ref = document.getElementById("anb-ref").value;
      const serie = document.getElementById("anb-serie").value;
      const xmin = +document.getElementById("anb-prazo-min").value || 0;
      const xmax = +document.getElementById("anb-prazo-max").value || 40;
      const hit = anbCurvas.find(c => c.ref === ref && c.serie === serie);
      const pts = hit ? filtrarPts(hit.pts || [], xmin, xmax) : [];
      mkLineChart(
        "chart-anb",
        [{
          label: serie + " · " + ref,
          data: pts.map(p => ({ x: p.x, y: p.y })),
          borderColor: "#0b5fff",
          tension: 0.15,
          pointRadius: 2,
          borderWidth: 2
        }],
        "ETTJ ANBIMA",
        "Prazo (~anos)",
        "% a.a."
      );
    }

    initDi();
    initTes();
    initAnb();
  </script>
</body>
</html>'
)

writeLines(html, "curvas_juros.html", useBytes = TRUE)
message("HTML interativo: curvas_juros.html")
