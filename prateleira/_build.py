# -*- coding: utf-8 -*-
"""Build Prateleira Tática hub + operation pages."""
from __future__ import annotations

import math
import shutil
import unicodedata
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
OPS = ROOT / "ops"
REF = date(2026, 9, 1)
PDF_NAME = "Material-Prateleira-Tatica-31082026.pdf"


def months_label(fixing: date) -> str:
    days = (fixing - REF).days
    if days <= 0:
        return "1 mês"
    m = max(1, math.floor(days / 30.44 + 0.5))
    return f"{m} mês" if m == 1 else f"{m} meses"


def slugify(*parts: str) -> str:
    s = unicodedata.normalize("NFKD", "-".join(parts).lower().replace(" ", "-"))
    s = s.encode("ascii", "ignore").decode("ascii")
    return "".join(c if c.isalnum() or c == "-" else "-" for c in s).strip("-")


def copy_pdf() -> bool:
    downloads = Path(r"C:\Users\PIMENTPA\Downloads")
    cands = [p for p in downloads.glob("Material Prateleira*.pdf") if "31082026" in p.name]
    if not cands:
        cands = list(downloads.glob("Material Prateleira*.pdf"))
    if not cands:
        return False
    dest = ROOT / PDF_NAME
    shutil.copy2(cands[0], dest)
    return dest.exists()


# ---- data ----
SOC = [
    ("NVDC34", date(2026, 9, 30), 103.14, 90.0, 0.80),
    ("TEND3", date(2026, 9, 18), 104.0, 90.0, 1.00),
    ("RDOR3", date(2026, 9, 30), 103.42, 90.0, 0.80),
    ("AXIA3", date(2026, 10, 14), 104.33, 90.0, 1.00),
    ("WEGE3", date(2026, 9, 30), 103.31, 92.0, 0.70),
    ("PRIO3", date(2026, 10, 15), 105.87, 90.0, 0.70),
    ("SPCX34", date(2026, 9, 18), 104.75, 87.0, 0.80),
    ("TOTS3", date(2026, 9, 29), 104.72, 90.0, 1.20),
    ("B3SA3", date(2026, 9, 29), 105.43, 90.0, 1.00),
    ("MRVE3", date(2026, 10, 14), 109.99, 88.0, 1.00),
]

SMART = [
    ("ITUB4", date(2027, 8, 27), 90.0, 110.0, 144.32, 4.60),
    ("AXIA3", date(2027, 8, 27), 90.0, 110.0, 151.78, 4.00),
    ("PETR4", date(2027, 8, 27), 90.0, 110.0, 151.08, 3.40),
    ("BBSE3", date(2027, 8, 31), 100.0, 110.0, 136.83, 3.00),
    ("SPCX34", date(2027, 8, 30), 90.0, 114.0, 190.0, 5.00),
    ("SPCX34", date(2028, 8, 30), 100.0, 130.0, 280.0, 4.72),
    ("PETR4", date(2027, 8, 31), 100.0, 110.0, 134.70, 5.00),
    ("VALE3", date(2028, 8, 31), 110.0, 110.0, 174.35, 7.00),
    ("AXIA3", date(2028, 8, 31), 110.0, 110.0, 177.35, 7.00),
    ("ITUB4", date(2028, 8, 28), 90.0, 130.0, 166.0, 6.00),
    ("EMBJ3", date(2027, 8, 27), 100.0, 110.0, 145.96, 4.10),
    ("PETR4", date(2028, 8, 30), 110.0, 110.0, 158.28, 7.00),
]

ACEL = [
    ("ITLC34", date(2028, 1, 26), 170.0, 40.0, 9.50),
    ("TSMC34", date(2026, 11, 27), 114.0, 90.0, 2.50),
    ("SPCX34", date(2027, 3, 2), 145.0, 80.0, 3.20),
    ("LILY34", date(2027, 8, 30), 135.0, 85.0, 4.50),
    ("HASH11", date(2027, 8, 31), 144.0, 80.0, 4.00),
]

TRIPLO = [
    ("ROXO34", date(2027, 8, 30), 115.0, 150.0, 80.0, 4.50),
    ("ROXO34", date(2027, 3, 1), 106.0, 134.0, 80.0, 2.50),
    ("NVDC34", date(2027, 8, 30), 115.0, 154.0, 80.0, 4.50),
    ("GOGL34", date(2027, 8, 30), 115.0, 145.0, 80.0, 4.50),
    ("LILY34", date(2027, 8, 30), 115.0, 150.0, 80.0, 4.50),
    ("B3SA3", date(2027, 8, 30), 115.0, 142.0, 80.0, 4.50),
    ("SMFT3", date(2027, 8, 30), 115.0, 149.0, 80.0, 4.50),
    ("CYRE3", date(2027, 8, 30), 115.0, 148.0, 80.0, 4.50),
    ("RENT3", date(2027, 8, 30), 115.0, 142.0, 80.0, 4.50),
]

CSS = """
:root {
  --ink:#0b1f3a; --muted:#5c6b7a; --line:#d0d8e2; --bg:#eef2f6; --card:#ffffff;
  --brand:BRAND; --btg:#0b1f3a; --success:#0f7a4a; --danger:#c0392b; --dash:#8b83a0;
}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Segoe UI,-apple-system,BlinkMacSystemFont,Helvetica,Arial,sans-serif;color:var(--ink);background:var(--bg);min-height:100vh;line-height:1.45}
.page{max-width:1280px;margin:0 auto;padding:28px 24px 48px}
.back-link{margin-bottom:16px;font-size:13px}
.back-link a{color:#1a66b3;text-decoration:none;font-weight:600}
.back-link a:hover{text-decoration:underline}
.topbar{display:flex;justify-content:space-between;align-items:flex-start;gap:24px;margin-bottom:28px;padding-bottom:20px;border-bottom:1px solid var(--line)}
.brand-block{display:flex;flex-direction:column;gap:10px}
.logos{display:flex;align-items:center;gap:14px}
.logo-btg{font-weight:700;font-size:13px;letter-spacing:.04em;color:var(--btg);background:#eef2f7;padding:6px 10px;border-radius:4px}
.logo-co{display:inline-flex;align-items:center;gap:8px;font-weight:700;color:var(--brand);font-size:15px}
.logo-co .dot{width:22px;height:22px;border-radius:50%;background:var(--brand);display:grid;place-items:center;color:#fff;font-size:9px;font-weight:700}
h1{font-weight:700;font-size:clamp(24px,3vw,34px);letter-spacing:-.02em;line-height:1.15}
h1 span{color:var(--brand)}
.subtitle{color:var(--muted);font-size:14px;max-width:580px}
.meta-pills{display:flex;flex-wrap:wrap;gap:8px;justify-content:flex-end}
.pill{background:var(--card);border:1px solid var(--line);border-radius:999px;padding:8px 14px;font-size:12px;color:var(--muted)}
.pill strong{color:var(--ink);font-weight:600;margin-right:4px}
.highlights{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:24px}
.hi{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;border-top:3px solid var(--brand)}
.hi h3{font-size:11px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.04em;margin-bottom:6px}
.hi p{font-size:15px;font-weight:700}
.hi p span{display:block;font-weight:400;color:var(--muted);font-size:12px;margin-top:3px}
.main{display:grid;grid-template-columns:280px 1fr 300px;gap:18px;align-items:start}
.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px}
.panel h2{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--brand);margin-bottom:14px}
.struct-table{width:100%;border-collapse:collapse;font-size:12px}
.struct-table th{text-align:left;font-weight:600;color:var(--muted);padding:0 6px 10px;border-bottom:1px solid var(--line);font-size:11px;text-transform:uppercase}
.struct-table td{padding:10px 6px;border-bottom:1px solid var(--line)}
.struct-table tr:last-child td{border-bottom:none}
.tag{display:inline-block;font-weight:700;font-size:11px;padding:2px 7px;border-radius:4px;margin-right:4px}
.tag.s{background:#fde8e8;color:var(--danger)}
.tag.b{background:#e8f8ef;color:var(--success)}
.legend-note{margin-top:14px;font-size:11px;color:var(--muted);line-height:1.5}
.chart-panel{padding:16px}
.chart-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;margin-bottom:10px}
.chart-caption{font-size:12px;color:var(--muted)}
.chart-legend{display:flex;gap:14px;font-size:12px;color:var(--muted);flex-wrap:wrap}
.chart-legend span{display:inline-flex;align-items:center;gap:6px}
.swatch{width:18px;height:3px;border-radius:2px;background:var(--brand);display:inline-block}
.swatch.asset{background:transparent;border-top:2px dashed var(--dash);height:0}
.chart-box{width:100%;background:#f8fafc;border:1px solid var(--line);border-radius:10px;overflow:hidden;position:relative;user-select:none}
.chart-box svg{display:block;width:100%;height:auto;min-height:360px;pointer-events:none}
.chart-overlay{position:absolute;inset:0;z-index:3;touch-action:none;cursor:crosshair}
.chart-touch-hint{display:block;font-size:12px;color:var(--muted);margin-top:8px;text-align:center}
@media (hover:hover) and (pointer:fine){.chart-touch-hint{display:none}}
.mobile-sim{display:block;margin-top:12px;padding:12px;background:var(--bg);border:1px solid var(--line);border-radius:10px}
.mobile-sim input[type=range]{width:100%;height:44px;accent-color:var(--brand)}
.tooltip{position:absolute;pointer-events:none;background:var(--ink);color:#fff;padding:10px 12px;border-radius:8px;font-size:12px;min-width:170px;opacity:0;z-index:5;transform:translate(-50%,-120%)}
.tooltip.on{opacity:1}
.tooltip .t-title{font-weight:600;margin-bottom:6px;opacity:.85;font-size:11px}
.tooltip .row{display:flex;justify-content:space-between;gap:16px;margin-top:3px}
.zones{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:12px}
.zone{border:1px solid var(--line);border-radius:8px;padding:10px;background:var(--bg)}
.zone strong{display:block;font-size:12px;color:var(--brand);margin-bottom:4px}
.zone p{font-size:11px;color:var(--muted);line-height:1.4}
.sim-label{display:flex;justify-content:space-between;align-items:baseline;font-size:12px;color:var(--muted);margin-bottom:8px}
.sim-label output{font-weight:700;color:var(--ink);font-size:14px}
input[type=range]{width:100%;accent-color:var(--brand);margin-bottom:14px}
.sim-cards{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:12px}
.sim-card{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:12px}
.sim-card .lbl{font-size:11px;color:var(--muted);margin-bottom:4px}
.sim-card .val{font-size:18px;font-weight:700}
.sim-card .val.pos{color:var(--success)}
.sim-card .val.neg{color:var(--danger)}
.regime{font-size:12px;color:var(--ink);background:#fff7ef;border:1px solid #f0d4b8;border-radius:8px;padding:10px 12px;line-height:1.45}
.speech-box{margin-top:22px;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:22px 24px;border-top:3px solid var(--brand)}
.speech-box h2{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--brand);margin-bottom:14px}
.speech-label{font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--brand);margin:14px 0 6px}
.speech-box p{font-size:14px;color:var(--ink);max-width:70em}
.footer{margin-top:28px;font-size:11px;color:var(--muted);text-align:center;line-height:1.55}
.footer-alert{margin-top:10px;text-align:center;font-size:11px;color:var(--btg);font-weight:700}
@media (max-width:1100px){.main{grid-template-columns:1fr}.highlights{grid-template-columns:1fr 1fr}.zones{grid-template-columns:1fr}}
@media (max-width:640px){.page{padding:16px 14px 40px}.topbar{flex-direction:column}.meta-pills{justify-content:flex-start}.highlights{grid-template-columns:1fr}}
"""


def op_page(cfg: dict) -> str:
    brand = cfg["brand"]
    css = CSS.replace("BRAND", brand)
    rows = "".join(
        f"<tr><td>{a}</td><td>{b}</td></tr>" for a, b in cfg["struct"]
    )
    his = "".join(
        f'<div class="hi"><h3>{h}</h3><p>{p}<span>{s}</span></p></div>'
        for h, p, s in cfg["highlights"]
    )
    zones = "".join(
        f'<div class="zone"><strong>{t}</strong><p>{b}</p></div>' for t, b in cfg["zones"]
    )
    speech = "".join(
        f'<p class="speech-label">{lab}</p><p>{txt}</p>' for lab, txt in cfg["speech"]
    )
    pills = "".join(
        f'<div class="pill"><strong>{k}</strong> {v}</div>' for k, v in cfg["pills"]
    )
    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>{cfg['title']} | BTG Pactual</title>
<style>{css}</style>
</head>
<body>
<div class="page">
<p class="back-link"><a href="../../index.html">← Prateleira Tática</a></p>
<header class="topbar">
  <div class="brand-block">
    <div class="logos">
      <span class="logo-btg">BTG PACTUAL</span>
      <span class="logo-co"><span class="dot">{cfg['dot']}</span> {cfg['ticker']}</span>
    </div>
    <h1>{cfg['h1']} <span>{cfg['ticker']}</span></h1>
    <p class="subtitle">{cfg['subtitle']}</p>
  </div>
  <div class="meta-pills">{pills}</div>
</header>
<section class="highlights">{his}</section>
<div class="main">
<aside class="panel">
  <h2>Estrutura</h2>
  <table class="struct-table"><thead><tr><th>Perna</th><th>Nível</th></tr></thead><tbody>{rows}</tbody></table>
  <p class="legend-note">Payoff ilustrativo no vencimento. Condições oficiais no DIE.</p>
</aside>
<section class="panel chart-panel">
  <div class="chart-head">
    <div><h2>Payoff ilustrativo</h2><p class="chart-caption">Retorno vs. variação do ativo</p></div>
    <div class="chart-legend"><span><i class="swatch"></i> Estrutura</span><span><i class="swatch asset"></i> Ativo</span></div>
  </div>
  <div class="chart-box" id="chartBox">
    <div class="tooltip" id="tooltip"></div>
    <div class="chart-overlay" id="chartOverlay"></div>
    <svg id="payoffSvg" viewBox="0 0 600 400" preserveAspectRatio="xMidYMid meet">
      <g id="grid"></g>
      <line id="axisZeroX" x1="0" y1="0" x2="0" y2="400" stroke="#c5ced8" stroke-width="1"/>
      <line id="axisZeroY" x1="48" y1="0" x2="552" y2="0" stroke="#c5ced8" stroke-width="1"/>
      <polyline id="assetPath" fill="none" stroke="#8b83a0" stroke-width="2" stroke-dasharray="6 5"/>
      <path id="structPath" fill="none" stroke="{brand}" stroke-width="2.5"/>
      <g id="xLabels"></g><g id="yLabels"></g>
      <line id="hoverLine" x1="0" y1="24" x2="0" y2="376" stroke="{brand}" stroke-width="1" opacity="0"/>
      <circle id="hoverStruct" r="5" fill="{brand}" opacity="0"/>
      <circle id="hoverAsset" r="4" fill="#8b83a0" opacity="0"/>
    </svg>
  </div>
  <p class="chart-touch-hint">Arraste no gráfico para simular</p>
  <div class="mobile-sim">
    <div class="sim-label"><span>Spot final</span><output id="spotOutMobile">0%</output></div>
    <input type="range" id="spotSliderMobile" min="-50" max="80" step="0.5" value="0"/>
  </div>
  <div class="zones">{zones}</div>
</section>
aside class="panel panel-sim">
  <h2>Simulador</h2>
  <div class="sim-label"><span>Variação do ativo</span><output id="spotOut">0%</output></div>
  <input type="range" id="spotSlider" min="-50" max="80" step="0.5" value="0"/>
  <div class="sim-cards">
    <div class="sim-card"><div class="lbl">Ativo</div><div class="val" id="assetVal">0,0%</div></div>
    <div class="sim-card"><div class="lbl">Estrutura</div><div class="val" id="structVal">0,0%</div></div>
  </div>
  <div class="regime" id="regimeText">{cfg['regime0']}</div>
</aside>
</div>
<section class="speech-box">
  <h2>Speech comercial</h2>
  {speech}
</section>
<p class="footer">Material ilustrativo para uso interno. Não constitui oferta, recomendação ou garantia de rentabilidade.</p>
<p class="footer-alert">MATERIAL DE USO INTERNO, NÃO ENVIAR AOS CLIENTES</p>
</div>
<script>
(function(){{
  var X_MIN=-50,X_MAX=80,Y_MIN=-50,Y_MAX=80;
  var PAD={{l:48,t:24,r:48,b:24}},VW=600,VH=400;
  var PLOT_W=VW-PAD.l-PAD.r,PLOT_H=VH-PAD.t-PAD.b;
  {cfg['js_const']}
  function structureReturn(x){{ {cfg['js_fn']} }}
  function regimeFor(x){{ {cfg['js_regime']} }}
  function fmtPct(v,d){{ d=d==null?1:d; var s=v.toFixed(d).replace('.',','); return (v>0?'+':'')+s+'%'; }}
  function xToSvg(x){{ return PAD.l+((x-X_MIN)/(X_MAX-X_MIN))*PLOT_W; }}
  function yToSvg(y){{ return PAD.t+((Y_MAX-y)/(Y_MAX-Y_MIN))*PLOT_H; }}
  function svgToX(px){{ return X_MIN+((px-PAD.l)/PLOT_W)*(X_MAX-X_MIN); }}
  function buildStructD(){{
    var d='',first=true;
    function add(x,y){{ var c=first?'M':'L'; first=false; d+=c+' '+xToSvg(x).toFixed(2)+' '+yToSvg(y).toFixed(2)+' '; }}
    for(var x=X_MIN;x<=X_MAX;x+=0.5) add(x, structureReturn(x));
    return d.trim();
  }}
  function buildAsset(){{
    var pts=[];
    for(var x=X_MIN;x<=X_MAX;x+=2){{
      var y=Math.max(Y_MIN,Math.min(Y_MAX,x));
      pts.push(xToSvg(x).toFixed(1)+','+yToSvg(y).toFixed(1));
    }}
    return pts.join(' ');
  }}
  var grid=document.getElementById('grid'),xL=document.getElementById('xLabels'),yL=document.getElementById('yLabels');
  for(var y=-40;y<=60;y+=20){{
    var py=yToSvg(y);
    grid.innerHTML+='<line x1="48" y1="'+py+'" x2="552" y2="'+py+'" stroke="#e8edf2"/>';
    yL.innerHTML+='<text x="42" y="'+(py+3)+'" font-size="11" text-anchor="end" fill="#5c6b7a">'+y+'%</text>';
  }}
  for(var x=-40;x<=80;x+=20){{
    var px=xToSvg(x);
    grid.innerHTML+='<line x1="'+px+'" y1="24" x2="'+px+'" y2="376" stroke="#e8edf2"/>';
    xL.innerHTML+='<text x="'+px+'" y="392" font-size="11" text-anchor="middle" fill="#5c6b7a">'+x+'%</text>';
  }}
  document.getElementById('axisZeroX').setAttribute('x1',xToSvg(0));
  document.getElementById('axisZeroX').setAttribute('x2',xToSvg(0));
  document.getElementById('axisZeroY').setAttribute('y1',yToSvg(0));
  document.getElementById('axisZeroY').setAttribute('y2',yToSvg(0));
  document.getElementById('structPath').setAttribute('d',buildStructD());
  document.getElementById('assetPath').setAttribute('points',buildAsset());
  function showAt(x){{
    x=Math.max(X_MIN,Math.min(X_MAX,x));
    var ys=structureReturn(x);
    document.getElementById('spotOut').textContent=fmtPct(x);
    document.getElementById('spotOutMobile').textContent=fmtPct(x);
    document.getElementById('spotSlider').value=x;
    document.getElementById('spotSliderMobile').value=x;
    var av=document.getElementById('assetVal'),sv=document.getElementById('structVal');
    av.textContent=fmtPct(x); av.className='val '+(x>0?'pos':x<0?'neg':'');
    sv.textContent=fmtPct(ys); sv.className='val '+(ys>0?'pos':ys<0?'neg':'');
    document.getElementById('regimeText').textContent=regimeFor(x);
    var px=xToSvg(x);
    document.getElementById('hoverLine').setAttribute('x1',px);
    document.getElementById('hoverLine').setAttribute('x2',px);
    document.getElementById('hoverLine').setAttribute('opacity','1');
    document.getElementById('hoverStruct').setAttribute('cx',px);
    document.getElementById('hoverStruct').setAttribute('cy',yToSvg(ys));
    document.getElementById('hoverStruct').setAttribute('opacity','1');
    document.getElementById('hoverAsset').setAttribute('cx',px);
    document.getElementById('hoverAsset').setAttribute('cy',yToSvg(Math.max(Y_MIN,Math.min(Y_MAX,x))));
    document.getElementById('hoverAsset').setAttribute('opacity','1');
    var tip=document.getElementById('tooltip');
    tip.innerHTML='<div class="t-title">Spot '+fmtPct(x)+'</div><div class="row"><span>Ativo</span><span>'+fmtPct(x)+'</span></div><div class="row"><span>Estrutura</span><span>'+fmtPct(ys)+'</span></div>';
    tip.className='tooltip on';
    tip.style.left=px+'px'; tip.style.top=yToSvg(ys)+'px';
  }}
  document.getElementById('spotSlider').addEventListener('input',function(e){{ showAt(+e.target.value); }});
  document.getElementById('spotSliderMobile').addEventListener('input',function(e){{ showAt(+e.target.value); }});
  var ov=document.getElementById('chartOverlay');
  function fromEvt(e){{
    var r=ov.getBoundingClientRect();
    var cx=(e.touches?e.touches[0].clientX:e.clientX)-r.left;
    showAt(svgToX(cx/r.width*VW));
  }}
  ov.addEventListener('pointerdown',fromEvt);
  ov.addEventListener('pointermove',function(e){{ if(e.buttons||e.pressure) fromEvt(e); else fromEvt(e); }});
  showAt(0);
}})();
</script>
</body>
</html>
""".replace("aside class=\"panel panel-sim\">", "<aside class=\"panel panel-sim\">")


def make_soc(t, fixing, strike, ko, bid):
    prazo = months_label(fixing)
    ko_var = ko - 100
    slug = slugify("soc", t, prazo.replace(" ", ""))
    return slug, {
        "title": f"SOC {t}",
        "h1": "SOC",
        "ticker": t,
        "dot": "SOC",
        "brand": "#0d6e6e",
        "subtitle": f"Stock or Coupon sobre {t}: cupom se a barreira de queda não for atingida; se KO, acompanha o ativo.",
        "pills": [("Ativo", t), ("Prazo", prazo), ("Strike", f"{strike:.2f}%"), ("KO", f"{ko:.0f}%"), ("Cupom", f"{bid:.2f}%")],
        "highlights": [
            ("Prazo", prazo, "Horizonte em meses"),
            ("Cupom", f"+{bid:.2f}%", "Se barreira não for atingida"),
            ("KO", f"{ko:.0f}%", f"Abaixo de {ko_var:.0f}%: acompanha o ativo"),
            ("Strike", f"{strike:.2f}%", "Put KO / Call KO"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Put KO', f"{strike:.2f}% · barreira {ko:.0f}%"),
            ('<span class="tag s">S</span> Call KO', f"{strike:.2f}% · barreira {ko:.0f}%"),
        ],
        "zones": [
            (f"≤ {ko_var:.0f}%", "Put/Call KO nocauteados — acompanha o ativo 1:1."),
            (f"> {ko_var:.0f}%", f"Cupom fixo +{bid:.2f}% (SOC)."),
            ("Ideia", "Fluxo de cupom com risco de conversão se cair forte."),
        ],
        "regime0": f"Acima da barreira: cupom +{bid:.2f}%.",
        "speech": [
            ("Para quem", f"Cliente que quer cupom curto em {t}, aceitando risco de exposição se o papel cair além da barreira."),
            ("Como encaixa", f"SOC · prazo {prazo}. Sem KO: cupom +{bid:.2f}%. Com KO ({ko:.0f}%): acompanha o ativo."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "js_const": f"var KO_VAR={ko_var}, CUPON={bid};",
        "js_fn": "if (x <= KO_VAR) return x; return CUPON;",
        "js_regime": f"if (x <= KO_VAR) return 'KO: acompanha o ativo.'; return 'Cupom SOC +{bid:.2f}%.';",
    }


def make_sh(t, fixing, put, call, ki, bid):
    prazo = months_label(fixing)
    floor = put - 100
    cap = call - 100
    ki_var = ki - 100
    slug = slugify("smart-hedge", t, f"put{int(put)}", prazo.replace(" ", ""))
    return slug, {
        "title": f"Smart Hedge {t}",
        "h1": "Smart Hedge",
        "ticker": t,
        "dot": "SH",
        "brand": "#007e33",
        "subtitle": f"Smart Hedge sobre {t}: piso na queda, participação 1:1 até a barreira KI; se KI, retorno limitado ao strike da call.",
        "pills": [("Ativo", t), ("Prazo", prazo), ("Put", f"{put:.0f}%"), ("Call", f"{call:.0f}%"), ("KI", f"{ki:.2f}%"), ("Bid", f"{bid:.2f}%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Piso", f"{floor:+.0f}%", f"Put {put:.0f}%"),
            ("Barreira KI", f"{ki:.2f}%", f"+{ki_var:.1f}%"),
            ("Teto se KI", f"{cap:+.0f}%", f"Call {call:.0f}%"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Put', f"{put:.2f}%"),
            ('<span class="tag s">S</span> Call KI', f"{call:.2f}% · barreira {ki:.2f}%"),
        ],
        "zones": [
            ("Queda", f"Piso {floor:+.0f}% (put)."),
            (f"Até +{ki_var:.0f}%", "Acompanha o ativo 1:1."),
            (f"≥ +{ki_var:.0f}%", f"KI: retorno limitado a {cap:+.0f}%."),
        ],
        "regime0": "Entre o piso e a barreira: participa 1:1.",
        "speech": [
            ("Para quem", f"Cliente construtivo em {t} no horizonte de {prazo}, com proteção na queda."),
            ("Como encaixa", f"Put {put:.0f}% · call {call:.0f}% KI em {ki:.2f}% · prazo {prazo}. Bid ref. {bid:.2f}%."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "js_const": f"var PUT={put}, CALL={call}, KI={ki};",
        "js_fn": "var st=100+x; var r=st+Math.max(PUT-st,0)-(st>=KI?Math.max(st-CALL,0):0)-100; return r;",
        "js_regime": f"var st=100+x; if(st>=KI) return 'KI: teto {cap:+.0f}%.'; if(x<=(PUT-100)) return 'Piso da put.'; return 'Participa 1:1.';",
    }


def make_acel(t, fixing, ko_h, ko_l, bid):
    prazo = months_label(fixing)
    H, L = ko_h - 100, ko_l - 100
    slug = slugify("aceleradora", t, prazo.replace(" ", ""))
    return slug, {
        "title": f"Aceleradora {t}",
        "h1": "Aceleradora Dinâmica",
        "ticker": t,
        "dot": "AC",
        "brand": "#5a4a8a",
        "subtitle": f"Participa da alta até a barreira; proteção na queda moderada; fora das barreiras acompanha ou limita.",
        "pills": [("Ativo", t), ("Prazo", prazo), ("KO alta", f"{ko_h:.0f}%"), ("KO baixa", f"{ko_l:.0f}%"), ("Bid", f"{bid:.2f}%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("KO alta", f"{ko_h:.0f}%", f"+{H:.0f}%"),
            ("KO baixa", f"{ko_l:.0f}%", f"{L:.0f}%"),
            ("Bid", f"{bid:.2f}%", "Referência"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Call KO', f"100% · barreira {ko_h:.0f}%"),
            ('<span class="tag s">S</span> Call', f"{ko_h:.0f}%"),
            ('<span class="tag b">B</span> Put KO', f"100% · barreira {ko_l:.0f}%"),
        ],
        "zones": [
            (f"≤ {L:.0f}%", "KO baixa: acompanha o ativo."),
            (f"{L:.0f}% → +{H:.0f}%", "Queda: 0%; alta: 1:1 até a barreira."),
            (f"≥ +{H:.0f}%", f"Limite +{H:.0f}%."),
        ],
        "regime0": "Na faixa central: upside 1:1 / downside protegido em 0%.",
        "speech": [
            ("Para quem", f"Cliente tático em {t} ({prazo}) que quer upside com proteção na queda moderada."),
            ("Como encaixa", f"Call KO {ko_h:.0f}% + put KO {ko_l:.0f}% · bid ref. {bid:.2f}%."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "js_const": f"var L={L}, H={H};",
        "js_fn": "if (x <= L) return x; if (x >= H) return H; if (x < 0) return 0; return x;",
        "js_regime": "if (x <= L) return 'KO baixa: acompanha.'; if (x >= H) return 'Teto da barreira alta.'; if (x < 0) return 'Proteção 0%.'; return 'Alta 1:1.';",
    }


def make_triplo(t, fixing, sold, ko_h, ko_l, bid):
    prazo = months_label(fixing)
    H, L, CAP = ko_h - 100, ko_l - 100, sold - 100
    slug = slugify("triplo", t, f"ki{int(ko_h)}", prazo.replace(" ", ""))
    return slug, {
        "title": f"Triplo Retorno KO {t}",
        "h1": "Triplo Retorno KO",
        "ticker": t,
        "dot": "3x",
        "brand": "#820ad1",
        "subtitle": f"3× na alta até a barreira, ganho na queda moderada, teto se KO de alta.",
        "pills": [("Ativo", t), ("Prazo", prazo), ("Teto", f"{CAP:+.0f}%"), ("KO alta", f"{ko_h:.0f}%"), ("KO baixa", f"{ko_l:.0f}%"), ("Bid", f"{bid:.2f}%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Alta", "3×", f"Até +{H:.0f}%"),
            ("Queda", "|x|", f"Até {L:.0f}%"),
            ("Teto KO", f"{CAP:+.0f}%", f"Call vendida {sold:.0f}%"),
        ],
        "struct": [
            ('<span class="tag s">S</span> Call KI (100×)', f"{sold:.0f}% · KI {ko_h:.0f}%"),
            ('<span class="tag b">B</span> Call KO (200×)', f"100% · KO {ko_h:.0f}%"),
            ('<span class="tag b">B</span> Put KO (200×)', f"100% · KO {ko_l:.0f}%"),
        ],
        "zones": [
            (f"< {L:.0f}%", "Acompanha o ativo."),
            (f"{L:.0f}% → 0%", "Ganho ≈ |queda|."),
            (f"0% → +{H:.0f}%", "3× a alta; acima: teto."),
        ],
        "regime0": "Entre as barreiras: 3× na alta ou |x| na queda.",
        "speech": [
            ("Para quem", f"Cliente construtivo em {t} ({prazo}) que quer assimetria 3× com proteção na queda moderada."),
            ("Como encaixa", f"Triplo KO · alta até {ko_h:.0f}% · queda até {ko_l:.0f}% · teto {CAP:+.0f}% · bid {bid:.2f}%."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "js_const": f"var L={L}, H={H}, CAP={CAP};",
        "js_fn": "if (x < L) return x; if (x < 0) return -x; if (x < H) return 3*x; return CAP;",
        "js_regime": "if (x < L) return 'Abaixo do put KO: acompanha.'; if (x < 0) return 'Queda moderada: |x|.'; if (x < H) return 'Alta: 3×.'; return 'KO alta: teto.';",
    }


def make_call_ko():
    t, fixing = "PRIO3", date(2026, 10, 30)
    prazo = months_label(fixing)
    cost, rebate, ko = 3.80, 5.50, 21.0
    slug = slugify("call-ko-rebate", t, prazo.replace(" ", ""))
    return slug, {
        "title": f"Call KO c/ Rebate {t}",
        "h1": "Call KO com Rebate",
        "ticker": t,
        "dot": "CK",
        "brand": "#c0392b",
        "subtitle": f"Call up-and-out: participa da alta até a barreira; no KO recebe rebate líquido.",
        "pills": [("Ativo", t), ("Prazo", prazo), ("KO", "121%"), ("Rebate", "5,50%"), ("Preço", "3,80%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Sem KO", "Alta − 3,80%", "Call ATM"),
            ("No KO", f"+{rebate-cost:.2f}%".replace(".", ","), "Rebate − preço"),
            ("Risco", "−3,80%", "Preço pago"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Call KO', "100% · barreira 121%"),
            ("Rebate", "5,50%"),
            ("Preço (offer)", "3,80%"),
        ],
        "zones": [
            ("< +21%", "Call: max(alta,0) − 3,80%."),
            ("≥ +21%", f"Rebate líquido +{rebate-cost:.2f}%."),
            ("Risco", "Perda máxima = preço 3,80%."),
        ],
        "regime0": "Sem KO: participa da alta menos o preço.",
        "speech": [
            ("Para quem", f"Cliente construtivo em {t} no curto prazo ({prazo}) que quer call com rebate se KO."),
            ("Como encaixa", "Call KO 121% · rebate 5,50% · preço 3,80%."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "js_const": f"var KO={ko}, REB={rebate}, COST={cost};",
        "js_fn": "if (x >= KO) return REB - COST; return Math.max(x, 0) - COST;",
        "js_regime": "if (x >= KO) return 'KO: rebate líquido.'; if (x > 0) return 'Call ITM menos preço.'; return 'OTM: −preço.';",
    }


def make_put_ko():
    t, fixing = "EMBJ3", date(2026, 11, 27)
    prazo = months_label(fixing)
    cost, rebate, ko = 2.0, 5.50, -20.0
    slug = slugify("put-ko-rebate", t, prazo.replace(" ", ""))
    return slug, {
        "title": f"Put KO c/ Rebate {t}",
        "h1": "Put KO com Rebate",
        "ticker": t,
        "dot": "PK",
        "brand": "#2f6b5a",
        "subtitle": f"Put down-and-out: ganha na queda até a barreira; no KO recebe rebate líquido.",
        "pills": [("Ativo", t), ("Prazo", prazo), ("KO", "80%"), ("Rebate", "5,50%"), ("Preço", "2,00%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Sem KO", "|queda| − 2%", "Put ATM"),
            ("No KO", f"+{rebate-cost:.2f}%".replace(".", ","), "Rebate − preço"),
            ("Risco", "−2,00%", "Preço pago"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Put KO', "100% · barreira 80%"),
            ("Rebate", "5,50%"),
            ("Preço (offer)", "2,00%"),
        ],
        "zones": [
            ("> −20%", "Put: max(|queda|,0) − 2%."),
            ("≤ −20%", f"Rebate líquido +{rebate-cost:.2f}%."),
            ("Risco", "Perda máxima = preço 2%."),
        ],
        "regime0": "Sem KO: participa da queda menos o preço.",
        "speech": [
            ("Para quem", f"Cliente que quer proteção/tática de queda em {t} ({prazo}) com rebate se KO."),
            ("Como encaixa", "Put KO 80% · rebate 5,50% · preço 2,00%."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "js_const": f"var KO={ko}, REB={rebate}, COST={cost};",
        "js_fn": "if (x <= KO) return REB - COST; return Math.max(-x, 0) - COST;",
        "js_regime": "if (x <= KO) return 'KO: rebate líquido.'; if (x < 0) return 'Put ITM menos preço.'; return 'OTM: −preço.';",
    }


def make_twip():
    t, fixing = "GOLD11", date(2027, 8, 30)
    prazo = months_label(fixing)
    slug = slugify("twip", t, prazo.replace(" ", ""))
    return slug, {
        "title": f"TWIP {t}",
        "h1": "TWIP",
        "ticker": t,
        "dot": "TW",
        "brand": "#b8860b",
        "subtitle": "Twin Win Protected: ganha na alta e na queda moderada; fora das barreiras retorno 0% (capital protegido).",
        "pills": [("Ativo", t), ("Prazo", prazo), ("Put", "100%"), ("KI", "140%"), ("Put KO", "80%"), ("Bid", "4,51%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Faixa", "|x|", "Entre −20% e +40%"),
            ("Fora", "0%", "Capital protegido"),
            ("Bid", "4,51%", "Referência"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Put', "100%"),
            ('<span class="tag s">S</span> Call KI', "100% · barreira 140%"),
            ('<span class="tag b">B</span> Put KO', "100% · barreira 80%"),
        ],
        "zones": [
            ("< −20%", "Retorno 0% (proteção)."),
            ("−20% → +40%", "Retorno = |variação|."),
            ("> +40%", "Retorno 0% (KI)."),
        ],
        "regime0": "Entre barreiras: retorno absoluto |x|.",
        "speech": [
            ("Para quem", f"Cliente construtivo em ouro via {t} ({prazo}) que quer payoff bidirecional com proteção."),
            ("Como encaixa", "TWIP · put KO 80% · call KI 140% · bid 4,51%."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "js_const": "var L=-20, H=40;",
        "js_fn": "if (x < L || x > H) return 0; return Math.abs(x);",
        "js_regime": "if (x < L || x > H) return 'Fora da faixa: 0%.'; return 'Twin: |x|.';",
    }


def make_ot():
    t, fixing = "BOVA11", date(2026, 11, 3)
    prazo = months_label(fixing)
    cost, rebate, barrier = 0.75, 5.0, 20.0
    slug = slugify("one-touch", t, prazo.replace(" ", ""))
    return slug, {
        "title": f"One Touch Alta {t}",
        "h1": "One Touch de Alta",
        "ticker": t,
        "dot": "OT",
        "brand": "#1e4d7b",
        "subtitle": "Paga rebate se o ativo atingir a barreira de alta; caso contrário, perde só o preço.",
        "pills": [("Ativo", t), ("Prazo", prazo), ("Barreira", "120%"), ("Rebate", "5,00%"), ("Preço", "0,75%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Se tocar +20%", f"+{rebate-cost:.2f}%".replace(".", ","), "Rebate − preço"),
            ("Se não tocar", "−0,75%", "Preço"),
            ("Barreira", "120%", "One touch"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Call KO', "120% · barreira 120%"),
            ("Rebate", "5,00%"),
            ("Preço (offer)", "0,75%"),
        ],
        "zones": [
            ("< +20%", "Não tocou: −0,75%."),
            ("≥ +20%", f"One touch: +{rebate-cost:.2f}%."),
            ("Ideia", "Aposta tática de alta com custo baixo."),
        ],
        "regime0": "Abaixo da barreira: −preço.",
        "speech": [
            ("Para quem", f"Cliente tático em {t} ({prazo}) que espera alta suficiente para tocar +20%."),
            ("Como encaixa", "One touch 120% · rebate 5% · preço 0,75%."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "js_const": f"var B={barrier}, REB={rebate}, COST={cost};",
        "js_fn": "if (x >= B) return REB - COST; return -COST;",
        "js_regime": "if (x >= B) return 'One touch: rebate líquido.'; return 'Não tocou: −preço.';",
    }


def hub_html(sections: list[tuple[str, list[tuple[str, dict]]]]) -> str:
    blocks = []
    for title, items in sections:
        cards = []
        for slug, cfg in items:
            pills = " ".join(f'<span class="pill">{k}: {v}</span>' for k, v in cfg["pills"])
            cards.append(f"""
<li class="op-block">
  <div class="op-bar" style="background:{cfg['brand']}"></div>
  <a class="op" href="./ops/{slug}/index.html">
    <div class="op-top"><span class="op-title">{cfg['h1']} {cfg['ticker']}</span><span class="op-ticker">{cfg['ticker']}</span></div>
    <p class="op-blurb">{cfg['subtitle']}</p>
    <div class="op-meta">{pills}</div>
    <div class="op-cta">Abrir material →</div>
  </a>
</li>""")
        blocks.append(f"<h2>{title}</h2><ul class=\"ops\">{''.join(cards)}</ul>")
    body = "\n".join(blocks)
    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Prateleira Tática — Distribuição Renda Variável | BTG Pactual</title>
<style>
:root{{--btg:#0b1f3a;--btg-mid:#163a5f;--btg-blue:#1e4d7b;--link:#1a66b3;--ink:#0b1f3a;--muted:#5c6b7a;--line:#d0d8e2;--bg:#eef2f6;--card:#ffffff}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:Segoe UI,-apple-system,BlinkMacSystemFont,Helvetica,Arial,sans-serif;color:var(--ink);background:var(--bg);min-height:100vh;line-height:1.45}}
.hero{{background:linear-gradient(135deg,var(--btg) 0%,var(--btg-mid) 55%,var(--btg-blue) 100%);color:#fff;padding:36px 24px 40px}}
.hero-inner{{max-width:960px;margin:0 auto}}
.logo-btg{{display:inline-block;font-weight:700;font-size:12px;letter-spacing:.1em;border:1px solid rgba(255,255,255,.35);padding:7px 12px;border-radius:2px;margin-bottom:22px}}
.hero-row{{display:flex;justify-content:space-between;align-items:flex-end;gap:24px}}
h1{{font-size:clamp(28px,4.5vw,40px);font-weight:700;letter-spacing:-.02em;line-height:1.15}}
.lede{{margin-top:12px;font-size:15px;color:rgba(255,255,255,.82);max-width:40em}}
.badge{{font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;border:1px solid rgba(255,255,255,.35);padding:8px 12px;border-radius:2px;white-space:nowrap}}
.page{{max-width:960px;margin:0 auto;padding:28px 24px 56px}}
.pdf-box{{background:var(--card);border:1px solid var(--line);border-radius:4px;padding:16px 18px;margin-bottom:22px}}
.pdf-box a{{color:var(--link);font-weight:700;text-decoration:none}}
.pdf-box a:hover{{text-decoration:underline}}
.pdf-box p{{font-size:13px;color:var(--muted);margin-top:6px}}
h2{{font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--btg-blue);margin:28px 0 14px}}
h2:first-of-type{{margin-top:0}}
.ops{{list-style:none;display:flex;flex-direction:column;gap:16px}}
.op-block{{background:var(--card);border:1px solid var(--line);border-radius:4px;overflow:hidden}}
.op-bar{{height:6px}}
.op{{display:block;text-decoration:none;color:inherit;padding:20px 22px 18px;transition:background .12s}}
.op:hover,.op:focus-visible{{background:#f5f8fc;outline:none}}
.op-top{{display:flex;justify-content:space-between;align-items:baseline;gap:12px;margin-bottom:8px}}
.op-title{{font-size:18px;font-weight:700;color:var(--btg)}}
.op-ticker{{font-size:12px;font-weight:700;color:var(--link);letter-spacing:.04em}}
.op-blurb{{font-size:14px;color:var(--muted);max-width:48em}}
.op-meta{{margin-top:12px;display:flex;flex-wrap:wrap;gap:8px}}
.pill{{background:#eef2f6;border:1px solid var(--line);border-radius:2px;padding:4px 10px;color:var(--btg-mid);font-size:11px;font-weight:600}}
.op-cta{{margin-top:12px;font-size:12px;font-weight:700;color:var(--link)}}
.footer{{margin-top:32px;padding-top:16px;border-top:1px solid var(--line);font-size:11px;color:var(--muted);text-align:center;line-height:1.55}}
.footer strong{{display:block;margin-top:10px;color:var(--btg)}}
@media (max-width:640px){{.hero{{padding:28px 16px 32px}}.page{{padding:20px 16px 48px}}.hero-row{{flex-direction:column;align-items:flex-start}}}}
</style>
</head>
<body>
<header class="hero">
  <div class="hero-inner">
    <div class="logo-btg">BTG PACTUAL</div>
    <div class="hero-row">
      <div>
        <h1>Prateleira Tática</h1>
        <p class="lede">Distribuição Renda Variável</p>
      </div>
      <div class="badge">Uso interno</div>
    </div>
  </div>
</header>
<main class="page">
  <div class="pdf-box">
    <a href="./{PDF_NAME}" target="_blank" rel="noopener noreferrer">Abrir material PDF da prateleira ↗</a>
    <p>Atualização semanal</p>
  </div>
  {body}
  <p class="footer">Material ilustrativo para uso interno. Não constitui oferta, recomendação ou garantia de rentabilidade.
  <strong>MATERIAL DE USO INTERNO, NÃO ENVIAR AOS CLIENTES</strong></p>
</main>
</body>
</html>
"""


def patch_root_index():
    idx = REPO / "index.html"
    text = idx.read_text(encoding="utf-8")
    if "./prateleira/" in text or "Prateleira Tática" in text and "prateleira/" in text:
        return
    block = """
      <li class="op-block">
        <a class="op" href="./prateleira/">
          <div class="op-top">
            <span class="op-title">Prateleira Tática</span>
            <span class="op-ticker">SEMANAL</span>
          </div>
          <p class="op-blurb">Hub semanal de operações (SOC, Smart Hedge, Aceleradora, Triplo, KO, TWIP, One Touch) + PDF da prateleira.</p>
          <div class="op-meta">
            <span class="pill">Atualização semanal</span>
            <span class="pill">PDF</span>
          </div>
          <div class="op-cta">Abrir hub →</div>
        </a>
      </li>
"""
    needle = '<ul class="ops">'
    if needle not in text:
        return
    text = text.replace(needle, needle + block, 1)
    idx.write_text(text, encoding="utf-8")


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    if OPS.exists():
        shutil.rmtree(OPS)
    OPS.mkdir(parents=True, exist_ok=True)
    ok_pdf = copy_pdf()
    print("pdf_copied", ok_pdf)

    sections: list[tuple[str, list]] = []
    all_ops = []

    soc_items = [make_soc(*r) for r in SOC]
    sections.append(("SOC", soc_items))
    all_ops.extend(soc_items)

    sh_items = [make_sh(*r) for r in SMART]
    sections.append(("Smart Hedge", sh_items))
    all_ops.extend(sh_items)

    acel_items = [make_acel(*r) for r in ACEL]
    sections.append(("Aceleradora Dinâmica", acel_items))
    all_ops.extend(acel_items)

    tri_items = [make_triplo(*r) for r in TRIPLO]
    sections.append(("Triplo Retorno KO", tri_items))
    all_ops.extend(tri_items)

    ck = make_call_ko()
    sections.append(("Call KO com Rebate", [ck]))
    all_ops.append(ck)

    pk = make_put_ko()
    sections.append(("Put KO com Rebate", [pk]))
    all_ops.append(pk)

    tw = make_twip()
    sections.append(("TWIP", [tw]))
    all_ops.append(tw)

    ot = make_ot()
    sections.append(("One Touch de Alta", [ot]))
    all_ops.append(ot)

    for slug, cfg in all_ops:
        d = OPS / slug
        d.mkdir(parents=True, exist_ok=True)
        (d / "index.html").write_text(op_page(cfg), encoding="utf-8")

    (ROOT / "index.html").write_text(hub_html(sections), encoding="utf-8")
    patch_root_index()
    print("ops", len(all_ops))
    for slug, cfg in all_ops[:5]:
        print(slug, cfg["pills"])


if __name__ == "__main__":
    main()
