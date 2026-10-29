# =============================================================================
# gerar_swap_simulador.R — Swap CDI × Pré (local, uso interno)
# Gera swap_simulador.html com curva DI embutida (futuros CDI).
# =============================================================================

raiz <- if (requireNamespace("rstudioapi", quietly = TRUE) &&
            rstudioapi::isAvailable()) {
  dirname(rstudioapi::getActiveDocumentContext()$path)
} else {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1L) {
    dirname(normalizePath(sub("^--file=", "", file_arg)))
  } else {
    getwd()
  }
}
setwd(raiz)
projeto <- normalizePath(file.path(raiz, ".."), winslash = "/", mustWork = TRUE)

pkgs <- c("readr", "dplyr", "jsonlite", "lubridate")
for (p in pkgs) {
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p, repos = "https://cloud.r-project.org")
  }
}

path_hist <- file.path(projeto, "data/processed/curvas_di_futuros_historico.csv")
if (!file.exists(path_hist)) {
  stop(
    "Arquivo não encontrado: ", path_hist,
    "\nRode antes scripts/01_download_curva_di.R em curvas-juros/"
  )
}

di_raw <- readr::read_csv(
  path_hist,
  col_types = readr::cols(
    data = readr::col_date(),
    prazo_anos = readr::col_double(),
    taxa_aa = readr::col_double(),
    fonte = readr::col_character(),
    rotulo = readr::col_character(),
    .default = readr::col_guess()
  )
)

montar_pts <- function(df) {
  df <- df[is.finite(df$prazo_anos) & is.finite(df$taxa_aa), , drop = FALSE]
  df <- df[order(df$prazo_anos), , drop = FALSE]
  lapply(seq_len(nrow(df)), function(i) {
    list(x = df$prazo_anos[i], y = df$taxa_aa[i])
  })
}

datas_ord <- di_raw |>
  dplyr::distinct(.data$data, .data$fonte) |>
  dplyr::arrange(dplyr::desc(.data$data))

curva_atual_dt <- datas_ord$data[1]
curva_atual_fonte <- datas_ord$fonte[1]
curva_atual_br <- format(curva_atual_dt, "%d/%m/%Y")
coleta_em <- NA_character_

curva_base <- di_raw |>
  dplyr::filter(.data$data == curva_atual_dt) |>
  dplyr::select(.data$prazo_anos, .data$taxa_aa)

wd_prev <- getwd()
setwd(projeto)
source("scripts/R/b3_di_curva.R")
source("scripts/R/advfn_di_curva.R")
curva_advfn <- tryCatch(
  obter_curva_di1_advfn(Sys.Date()),
  error = function(e) {
    message("ADVFN indisponível (fallback B3): ", conditionMessage(e))
    NULL
  }
)
setwd(wd_prev)

if (!is.null(curva_advfn) && nrow(curva_advfn) >= 5L) {
  fetched <- attr(curva_advfn, "fetched_at")
  curva_atual_dt <- Sys.Date()
  curva_atual_fonte <- "advfn_ult"
  curva_atual_br <- paste0(
    format(curva_atual_dt, "%d/%m/%Y"),
    " · cotação ADVFN"
  )
  coleta_em <- if (!is.null(fetched)) {
    format(fetched, "%d/%m/%Y %H:%M")
  } else {
    format(Sys.time(), "%d/%m/%Y %H:%M")
  }
  curva_base <- curva_advfn |>
    dplyr::select(.data$prazo_anos, .data$taxa_aa)
  message(
    "Curva atual: ADVFN (", nrow(curva_advfn), " vértices) · histórico: B3"
  )
  source(file.path(projeto, "scripts/R/export_viva_json.R"))
  export_curva_advfn_json(
    curva_advfn,
    path = file.path(projeto, "data/curva_advfn.json"),
    coleta_em = if (!is.null(fetched)) fetched else Sys.time(),
    data_ref = curva_atual_dt
  )
} else {
  message("Curva atual: última data B3 no histórico (", curva_atual_br, ")")
}

pts_base <- montar_pts(curva_base)

gh_repo <- Sys.getenv("GITHUB_REPOSITORY", unset = "")
if (!nzchar(gh_repo)) {
  gh_repo <- "btg-pactual/btg-distribuicao-rv"
}

hist_curvas <- lapply(seq_len(nrow(datas_ord)), function(i) {
  dt <- datas_ord$data[i]
  df <- di_raw |>
    dplyr::filter(.data$data == dt)
  list(
    data = format(dt, "%Y-%m-%d"),
    data_br = format(dt, "%d/%m/%Y"),
    fonte = datas_ord$fonte[i],
    pts = montar_pts(df)
  )
})

payload <- list(
  gerado_em = format(Sys.time(), "%d/%m/%Y %H:%M"),
  aviso = "Simulação educacional — não substitui marcação ou precificação oficial.",
  curva_atual = list(
    data = format(curva_atual_dt, "%Y-%m-%d"),
    data_br = curva_atual_br,
    fonte = curva_atual_fonte,
    coleta_em = if (is.na(coleta_em)) NULL else coleta_em,
    pts = pts_base
  ),
  historico = hist_curvas,
  defaults = list(
    notional = 1000000,
    pct_cdi = 100,
    prazo_anos = 5,
    prazo_max = 10,
    shift_bps = 0
  ),
  github = list(
    repo = gh_repo,
    curva_json = "../data/curva_advfn.json",
    workflow_advfn = "curvas-refresh-advfn.yml"
  )
)

json_txt <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", digits = 8)
json_html <- gsub("<", "\\u003c", json_txt, fixed = TRUE)
d_notional <- sprintf("%.0f", payload$defaults$notional)
d_pct <- as.character(payload$defaults$pct_cdi)
d_prazo <- as.character(payload$defaults$prazo_anos)
d_prazo_max <- payload$defaults$prazo_max

html <- paste0(
'<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Swap CDI × Pré — simulador</title>
<style>
:root{--ink:#0b1f3a;--muted:#5c6b7a;--line:#d0d8e2;--bg:#eef2f6;--card:#fff;--brand:#0d6e6e;--accent:#0b5fff;--ok:#0f7a4a;--bad:#c0392b}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Segoe UI,system-ui,sans-serif;color:var(--ink);background:var(--bg);line-height:1.45}
.page{max-width:1280px;margin:0 auto;padding:24px 20px 48px}
.banner{background:linear-gradient(135deg,#0b1f3a,#0d6e6e);color:#fff;padding:20px 22px;border-radius:14px;margin-bottom:18px}
.banner h1{font-size:1.35rem;margin-bottom:6px}
.banner p{font-size:.9rem;opacity:.92}
.pills{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.pill{background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.35);border-radius:999px;padding:6px 12px;font-size:.78rem}
.btn-refresh{margin-top:8px;padding:8px 12px;border:1px solid rgba(255,255,255,.5);background:rgba(255,255,255,.15);color:#fff;border-radius:8px;font-size:.78rem;font-weight:600;cursor:pointer;width:100%}
.btn-refresh:disabled{opacity:.55;cursor:wait}
.btn-refresh-sub{margin-top:6px;background:transparent;font-weight:500;opacity:.9}
.main{display:grid;grid-template-columns:300px 1fr 300px;gap:16px;align-items:start}
.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px}
.panel h2{font-size:.72rem;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--brand);margin-bottom:12px}
label{display:grid;gap:4px;font-size:.78rem;color:var(--muted);margin-bottom:10px}
input,select{padding:8px 10px;border:1px solid var(--line);border-radius:8px;font-size:.92rem;width:100%}
input[type=range]{padding:0;height:32px}
.sim-row{display:flex;justify-content:space-between;font-size:.78rem;color:var(--muted);margin:-4px 0 8px}
.sim-row output{font-weight:700;color:var(--ink)}
.kpi{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px}
.kpi .box{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:10px}
.kpi .lbl{font-size:.68rem;color:var(--muted);text-transform:uppercase;margin-bottom:4px}
.kpi .val{font-size:1.05rem;font-weight:700;font-variant-numeric:tabular-nums}
.kpi .val.pos{color:var(--ok)} .kpi .val.neg{color:var(--bad)}
.chart-wrap{position:relative;height:360px}
.chart-wrap.tall{height:420px}
.hint{font-size:.78rem;color:var(--muted);margin-bottom:10px}
.footer{margin-top:20px;font-size:.75rem;color:var(--muted);padding:12px;border:1px dashed var(--line);border-radius:10px;background:#fff}
@media(max-width:1050px){.main{grid-template-columns:1fr}}
</style>
</head>
<body>
<div class="page">
  <div class="banner">
    <h1>Simulador Swap — CDI × Pré</h1>
    <p>Perna flutuante: % do CDI · Perna fixa: taxa pré (% a.a.) · Curva atual: ADVFN (ULT) · Histórico: B3</p>
    <div class="pills" id="pills-meta"></div>
    <button type="button" class="btn-refresh" id="btn-refresh-advfn">Atualizar cotação ADVFN</button>
    <button type="button" class="btn-refresh btn-refresh-sub" id="btn-server-advfn">Forçar coleta no GitHub (Actions)</button>
    <p class="hint" id="refresh-status" style="color:rgba(255,255,255,.85);margin-top:8px;font-size:.75rem"></p>
  </div>

  <div class="main">
    <aside class="panel">
      <h2>Estrutura do swap</h2>
      <label>Notional (R$)
        <input type="number" id="notional" min="1000" step="1000" value="', d_notional, '"/>
      </label>
      <label>% do CDI (perna flutuante)
        <input type="number" id="pct-cdi" min="0" max="200" step="0.01" value="', d_pct, '"/>
      </label>
      <label>Taxa pré contratada (% a.a.)
        <input type="number" id="taxa-pre" min="0" max="30" step="0.0001"/>
      </label>
      <label>Prazo (anos)
        <input type="number" id="prazo" min="0.25" max="10" step="0.25" value="', d_prazo, '"/>
      </label>
      <button type="button" id="btn-fair" style="width:100%;padding:10px;border:1px solid var(--brand);background:#fff;color:var(--brand);border-radius:8px;font-weight:700;cursor:pointer;margin-bottom:8px">Pré ≈ CDI no prazo (100%)</button>
      <p class="hint">Recebe pré · Paga %CDI. Prazo máximo 10 anos.</p>
    </aside>

    <section class="panel chart-panel">
      <h2>Curva DI — base vs choque</h2>
      <p class="hint">Linha sólida: curva atual. Tracejada: curva após choque. Linha horizontal: taxa pré.</p>
      <div class="sim-row"><span>Choque paralelo</span><output id="out-shift">0 bp</output></div>
      <input type="range" id="shift-bps" min="-200" max="200" step="5" value="0"/>
      <div class="chart-wrap">
        <canvas id="chart-curva"></canvas>
      </div>
    </section>

    <aside class="panel">
      <h2>Marcação (estimada)</h2>
      <div class="kpi">
        <div class="box"><div class="lbl">CDI DI no prazo</div><div class="val" id="kpi-cdi">—</div></div>
        <div class="box"><div class="lbl">CDI × %</div><div class="val" id="kpi-cdi-pct">—</div></div>
        <div class="box"><div class="lbl">Spread pré − CDI</div><div class="val" id="kpi-spread">—</div></div>
        <div class="box"><div class="lbl">Líquido no venc. (bullet)</div><div class="val" id="kpi-payoff">—</div></div>
        <div class="box"><div class="lbl">Fator PV (DI no prazo)</div><div class="val" id="kpi-df">—</div></div>
        <div class="box wide" style="grid-column:1/-1"><div class="lbl">MTM — valor presente</div><div class="val" id="kpi-mtm">—</div></div>
      </div>
      <p class="hint" style="margin-top:10px">Bullet: juros acumulados no vencimento com pré vs %CDI×CDI (taxa única forward), depois descontados pela DI no prazo. Se contratou “na curva” hoje (pré = %CDI×CDI), MTM ≈ 0.</p>
    </aside>
  </div>

  <section class="panel" style="margin-top:16px">
    <h2>Histórico CDI futuro (DI1)</h2>
    <p class="hint">Acima: série da taxa DI no prazo do swap. Abaixo: sobrepor curvas DI de datas históricas.</p>
    <div class="chart-wrap" style="height:300px;margin-bottom:14px">
      <canvas id="chart-hist"></canvas>
    </div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px;margin-bottom:10px">
      <label>Prazo mín. (anos)
        <input type="number" id="hist-prazo-min" value="0.25" step="0.1" min="0"/>
      </label>
      <label>Prazo máx. (anos)
        <input type="number" id="hist-prazo-max" value="10" step="0.5" min="0.5"/>
      </label>
    </div>
    <div class="btn-row" id="hist-btns" style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px"></div>
    <div id="hist-dates" style="max-height:140px;overflow:auto;border:1px solid var(--line);border-radius:8px;padding:8px;background:#fafbfc"></div>
    <div class="chart-wrap tall" style="margin-top:12px">
      <canvas id="chart-hist-curvas"></canvas>
    </div>
  </section>

  <p class="footer" id="footer-aviso"></p>
</div>

<script id="dados" type="application/json">', json_html, '</script>
<script src="../vendor/chart.umd.min.js"></script>
<script>
function showBootErr(msg){
  const box=document.createElement("p");
  box.id="boot-err";
  box.style.cssText="color:#c0392b;font-weight:700;padding:12px;margin:0 0 12px;background:#fff3f3;border:1px solid #f5c6cb;border-radius:8px";
  box.textContent="Erro ao carregar simulador: "+msg;
  const page=document.querySelector(".page");
  if(page) page.prepend(box);
}
async function loadDataAsync(){
  const el=document.getElementById("dados");
  if(el&&el.textContent.trim()){
    try{ return JSON.parse(el.textContent); }catch(e){ console.warn("JSON inline:", e); }
  }
  const r=await fetch("dados.json?t="+Date.now(),{cache:"no-store"});
  if(!r.ok) throw new Error("dados.json HTTP "+r.status);
  return r.json();
}
function loadChartJs(){
  return new Promise((resolve,reject)=>{
    if(typeof Chart!=="undefined") return resolve();
    const s=document.createElement("script");
    s.src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js";
    s.onload=()=>resolve();
    s.onerror=()=>reject(new Error("Chart.js não carregou (rede ou CDN bloqueado)."));
    document.head.appendChild(s);
  });
}
let DATA=null;
let chartCurva = null, chartHist = null, chartHistCurvas = null;
const fmt = (v,d=2)=> v==null||Number.isNaN(v)?"—":Number(v).toLocaleString("pt-BR",{minimumFractionDigits:d,maximumFractionDigits:d});
const fmtBRL = v => v==null||Number.isNaN(v)?"—":Number(v).toLocaleString("pt-BR",{style:"currency",currency:"BRL",maximumFractionDigits:0});

function ensureChart(){
  if(typeof Chart==="undefined"){
    throw new Error("Chart.js não carregou. Verifique internet ou CDN.");
  }
}

function interp(pts,x){
  if(!pts||!pts.length) return null;
  const p=pts.slice().sort((a,b)=>a.x-b.x);
  if(x<=p[0].x) return p[0].y;
  if(x>=p[p.length-1].x) return p[p.length-1].y;
  for(let i=0;i<p.length-1;i++){
    if(x>=p[i].x&&x<=p[i+1].x){
      const t=(x-p[i].x)/(p[i+1].x-p[i].x);
      return p[i].y+t*(p[i+1].y-p[i].y);
    }
  }
  return null;
}
function shiftPts(pts,bps){ return pts.map(p=>({x:p.x,y:p.y+bps/100})); }

/** Juros bullet: N × [(1 + taxa/100)^T − 1] — taxa anual efetiva simplificada */
function fvJurosBullet(N, taxaAa, T){
  if(taxaAa==null||T<=0) return null;
  return N * (Math.pow(1 + taxaAa/100, T) - 1);
}
/** Desconto zero-coupon: 1 / (1 + DI/100)^T (DI no prazo como taxa de desconto) */
function fatorPV(taxaAa, T){
  if(taxaAa==null||T<=0) return null;
  return 1 / Math.pow(1 + taxaAa/100, T);
}

const elNotional=document.getElementById("notional");
const elPct=document.getElementById("pct-cdi");
const elPre=document.getElementById("taxa-pre");
const elPrazo=document.getElementById("prazo");
const elShift=document.getElementById("shift-bps");
let basePts=[];

function liveJsonUrl(){
  return (DATA&&DATA.github&&DATA.github.curva_json)||"../data/curva_advfn.json";
}

function updateCurvaPills(){
  if(!DATA||!DATA.curva_atual) return;
  const coletaPill = DATA.curva_atual.coleta_em
    ? `<span class="pill">Coleta ADVFN: ${DATA.curva_atual.coleta_em}</span>` : "";
  document.getElementById("pills-meta").innerHTML =
    `<span class="pill">Curva DI: ${DATA.curva_atual.data_br} (${DATA.curva_atual.fonte})</span>`+
    coletaPill+
    `<span class="pill">Histórico B3: ${(DATA.historico||[]).length} datas</span>`+
    `<span class="pill">Gerado: ${DATA.gerado_em||"—"}</span>`;
}

async function refreshAdvfnFromJson(){
  const btn=document.getElementById("btn-refresh-advfn");
  const st=document.getElementById("refresh-status");
  if(btn) btn.disabled=true;
  if(st) st.textContent="Buscando última cotação publicada…";
  try{
    const r=await fetch(liveJsonUrl()+"?t="+Date.now(),{cache:"no-store"});
    if(!r.ok) throw new Error("HTTP "+r.status);
    const j=await r.json();
    if(!j.pts||!j.pts.length) throw new Error("arquivo sem vértices");
    basePts=j.pts;
    DATA.curva_atual=Object.assign({},DATA.curva_atual,j);
    updateCurvaPills();
    setFairPre(true);
    if(st) st.textContent="Cotação carregada: "+(j.coleta_em||"—")+".";
  }catch(err){
    if(st) st.textContent="";
    alert(["Não foi possível atualizar a cotação ADVFN.", "", err.message, "",
      "No GitHub Pages use o botão após o workflow; localmente regere o HTML."
    ].join(String.fromCharCode(10)));
  }finally{
    if(btn) btn.disabled=false;
  }
}

function cdiNoPrazo(pts,T){ return interp(pts,T); }

function setFairPre(runRecalc){
  const T=+elPrazo.value;
  const cdi=cdiNoPrazo(basePts,T);
  if(cdi!=null) elPre.value=(cdi*(+elPct.value/100)).toFixed(4);
  if(runRecalc!==false) recalc();
}
document.getElementById("btn-fair").onclick=()=>setFairPre(true);

function dsXY(label, pts, extra){
  return Object.assign({
    label: label,
    data: pts.map(p=>({x:p.x,y:p.y})),
    parsing: false,
    tension: 0.15,
    pointRadius: 2,
    borderWidth: 2
  }, extra||{});
}

function recalc(){
  ensureChart();
  const N=+elNotional.value, pct=+elPct.value, pre=+elPre.value, T=+elPrazo.value;
  const bps=+elShift.value;
  document.getElementById("out-shift").textContent=(bps>0?"+":"")+bps+" bp";
  const stressed=shiftPts(basePts,bps);
  const cdi=cdiNoPrazo(stressed,T);
  const cdiPct=cdi==null?null:cdi*pct/100;
  const spread=cdiPct==null?null:pre-cdiPct;
  /* Recebe pré, paga %CDI: no vencimento entra juros bullet da pré e sai o da flutuante */
  const fvPre=fvJurosBullet(N, pre, T);
  const fvCdi=fvJurosBullet(N, cdiPct, T);
  const payoffT=(fvPre==null||fvCdi==null)?null:fvPre-fvCdi;
  const df=fatorPV(cdi, T);
  const mtm=(payoffT==null||df==null)?null:payoffT*df;
  document.getElementById("kpi-cdi").textContent=fmt(cdi,3)+"%";
  document.getElementById("kpi-cdi-pct").textContent=fmt(cdiPct,3)+"%";
  const spEl=document.getElementById("kpi-spread");
  spEl.textContent=fmt(spread,3)+" pp";
  spEl.className="val "+(spread>0?"pos":spread<0?"neg":"");
  const payEl=document.getElementById("kpi-payoff");
  payEl.textContent=fmtBRL(payoffT);
  payEl.className="val "+(payoffT>0?"pos":payoffT<0?"neg":"");
  document.getElementById("kpi-df").textContent=df==null?"—":fmt(df,5);
  const mtmEl=document.getElementById("kpi-mtm");
  mtmEl.textContent=fmtBRL(mtm);
  mtmEl.className="val "+(mtm>0?"pos":mtm<0?"neg":"");

  const ds=[
    dsXY("DI atual", basePts, {borderColor:"#0b5fff"}),
    dsXY("DI choque", stressed, {borderColor:"#f97316", borderDash:[6,4], pointRadius:0}),
    dsXY("Pré", [{x:0.1,y:pre},{x:10,y:pre}], {borderColor:"#0d6e6e", borderDash:[2,2], pointRadius:0, tension:0})
  ];
  const cfg={
    type:"line",data:{datasets:ds},
    options:{
      responsive:true,maintainAspectRatio:false,
      plugins:{legend:{position:"bottom"}},
      scales:{
        x:{type:"linear",title:{display:true,text:"Prazo (anos)"},min:0,max:10},
        y:{title:{display:true,text:"Taxa (% a.a.)"}}
      }
    }
  };
  if(chartCurva) chartCurva.destroy();
  chartCurva=new Chart(document.getElementById("chart-curva"),cfg);

  drawHist(T);
  drawHistCurvas();
}

function drawHist(T){
  const series=DATA.historico.slice().sort((a,b)=>a.data.localeCompare(b.data));
  const labels=[], vals=[];
  series.forEach(h=>{
    const y=interp(h.pts,T);
    if(y!=null){ labels.push(h.data); vals.push(y); }
  });
  const cfg={
    type:"line",
    data:{labels,datasets:[{
      label:"CDI DI no prazo "+T.toFixed(2)+"a",
      data:vals,borderColor:"#0b5fff",backgroundColor:"rgba(11,95,255,.1)",
      fill:true,tension:.15,pointRadius:2,borderWidth:2
    }]},
    options:{
      responsive:true,maintainAspectRatio:false,
      plugins:{title:{display:true,text:"Histórico da taxa forward (DI1) no prazo do swap"}},
      scales:{x:{ticks:{maxTicksLimit:14}},y:{title:{display:true,text:"% a.a."}}}
    }
  };
  if(chartHist) chartHist.destroy();
  chartHist=new Chart(document.getElementById("chart-hist"),cfg);
}

function buildHistDates(){
  const box=document.getElementById("hist-dates");
  box.innerHTML="";
  DATA.historico.forEach((h,i)=>{
    const id="hist-dt-"+h.data;
    const lab=document.createElement("label");
    lab.style.cssText="display:flex;align-items:center;gap:6px;font-size:.82rem;margin:3px 0;cursor:pointer";
    lab.innerHTML=`<input type="checkbox" id="${id}" data-i="${i}"/> ${h.data_br}`;
    lab.querySelector("input").onchange=drawHistCurvas;
    box.appendChild(lab);
  });
  const def=[0, DATA.historico.length-1];
  def.forEach(i=>{
    const h=DATA.historico[i];
    const el=document.getElementById("hist-dt-"+h.data);
    if(el) el.checked=true;
  });
  const btns=document.getElementById("hist-btns");
  btns.innerHTML="";
  [["Atual + mais antiga",()=>{DATA.historico.forEach((h,i)=>{const el=document.getElementById("hist-dt-"+h.data);if(el) el.checked=(i===0||i===DATA.historico.length-1);});drawHistCurvas();}],
   ["Todas",()=>{DATA.historico.forEach(h=>{const el=document.getElementById("hist-dt-"+h.data);if(el) el.checked=true;});drawHistCurvas();}],
   ["Nenhuma",()=>{DATA.historico.forEach(h=>{const el=document.getElementById("hist-dt-"+h.data);if(el) el.checked=false;});drawHistCurvas();}]
  ].forEach(([t,fn])=>{const b=document.createElement("button");b.type="button";b.textContent=t;b.style.cssText="padding:6px 10px;border:1px solid var(--line);border-radius:8px;background:#fff;cursor:pointer;font-size:.78rem";b.onclick=fn;btns.appendChild(b);});
}

function drawHistCurvas(){
  const xmin=+document.getElementById("hist-prazo-min").value||0;
  const xmax=+document.getElementById("hist-prazo-max").value||10;
  const CORES=["#0b5fff","#6366f1","#8b5cf6","#f97316","#ef4444","#14b8a6","#eab308","#64748b"];
  const datasets=[];
  DATA.historico.forEach((h,i)=>{
    const el=document.getElementById("hist-dt-"+h.data);
    if(!el||!el.checked) return;
    const pts=h.pts.filter(p=>p.x>=xmin&&p.x<=xmax);
    datasets.push(dsXY(h.data_br, pts, {
      borderColor:CORES[datasets.length%CORES.length],
      pointRadius:1, borderWidth:1.5
    }));
  });
  const cfg={
    type:"line",data:{datasets},
    options:{
      responsive:true,maintainAspectRatio:false,
      plugins:{title:{display:true,text:"Curvas DI históricas (sobreposição)"},legend:{position:"bottom"}},
      scales:{
        x:{type:"linear",title:{display:true,text:"Prazo (anos)"},min:xmin,max:xmax},
        y:{title:{display:true,text:"Taxa (% a.a.)"}}
      }
    }
  };
  if(!datasets.length){
    if(chartHistCurvas){ chartHistCurvas.destroy(); chartHistCurvas=null; }
    return;
  }
  if(chartHistCurvas) chartHistCurvas.destroy();
  chartHistCurvas=new Chart(document.getElementById("chart-hist-curvas"),cfg);
}

async function boot(){
  try{
    await loadChartJs();
    DATA=await loadDataAsync();
    if(!DATA||!DATA.curva_atual||!DATA.curva_atual.pts||!DATA.curva_atual.pts.length){
      throw new Error("Curva DI ausente nos dados.");
    }
    document.getElementById("footer-aviso").textContent=DATA.aviso||"";
    elNotional.value=DATA.defaults.notional;
    elPct.value=DATA.defaults.pct_cdi;
    elPrazo.value=DATA.defaults.prazo_anos;
    elPrazo.max=DATA.defaults.prazo_max;
    basePts=DATA.curva_atual.pts;
    updateCurvaPills();
    document.getElementById("btn-refresh-advfn").onclick=()=>refreshAdvfnFromJson();
    document.getElementById("btn-server-advfn").onclick=()=>{
      const repo=DATA.github&&DATA.github.repo;
      const wf=DATA.github&&DATA.github.workflow_advfn||"curvas-refresh-advfn.yml";
      if(!repo){ alert("GitHub → Actions → curvas-refresh-advfn → Run workflow."); return; }
      window.open("https://github.com/"+repo+"/actions/workflows/"+wf,"_blank");
      const st=document.getElementById("refresh-status");
      if(st) st.textContent="Workflow aberto. Em ~1–2 min clique em Atualizar cotação ADVFN.";
    };
    setFairPre(false);
    buildHistDates();
    [elNotional,elPct,elPre,elPrazo,elShift].forEach(el=>el.addEventListener("input",recalc));
    document.getElementById("hist-prazo-min").addEventListener("input",()=>{drawHistCurvas();});
    document.getElementById("hist-prazo-max").addEventListener("input",()=>{drawHistCurvas();});
    recalc();
  }catch(err){
    console.error(err);
    showBootErr(err.message);
  }
}
boot();
</script>
</body>
</html>'
)

out <- file.path(raiz, "swap_simulador.html")
writeLines(html, out, useBytes = TRUE)
writeLines(json_txt, file.path(raiz, "dados.json"), useBytes = TRUE)
writeLines(json_txt, file.path(projeto, "swap/dados.json"), useBytes = TRUE)
message("Simulador gerado: ", out)
message("Dados: swap/dados.json")
message("Publicação: Rscript scripts/ci_publish.R")
