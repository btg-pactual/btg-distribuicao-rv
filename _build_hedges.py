# -*- coding: utf-8 -*-
"""Gera factsheets Smart Hedge / Twin Coupon e hub Operações dia D (Research Content API)."""
from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load_prat():
    """Reusa fetch/HTML de Research da prateleira semanal."""
    path = ROOT / "prateleira" / "_build.py"
    spec = importlib.util.spec_from_file_location("prat_build", path)
    mod = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod


def write(rel: str, content: str) -> None:
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    print(f"wrote {rel} ({p.stat().st_size})")


def fmt_br(n: float, digits: int = 2) -> str:
    return f"{n:.{digits}f}".replace(".", ",")


def smart_hedge_html(cfg: dict, prat=None) -> str:
    ticker = cfg["ticker"]
    name = cfg["name"]
    brand = cfg["brand"]
    brand_soft = cfg["brand_soft"]
    put = cfg["put"]
    call = cfg["call"]
    barrier = cfg["barrier"]
    prazo = cfg["prazo"]
    initials = cfg.get("initials", ticker[:2])
    rs = cfg.get("research") or {}
    research_block = ""
    insights_block = ""
    if prat is not None:
        research_block = prat.research_html({"ticker": ticker, "research": rs})
        insights_block = prat.research_insights_html({"ticker": ticker, "research": rs})

    floor = put - 100
    cap = call - 100
    ki_var = barrier - 100
    if floor > 0:
        floor_label = f"+{floor:.0f}%"
    elif floor == 0:
        floor_label = "0%"
    else:
        floor_label = f"{floor:.0f}%"
    floor_put_label = f"{fmt_br(put)}%"
    barrier_label = f"{fmt_br(barrier)}%"

    spots = [-40, -20, floor, 0, 20, 40]
    if abs(ki_var - round(ki_var)) > 0.01:
        spots.append(round(ki_var, 2))
    else:
        spots.append(int(round(ki_var)))
    spots.extend([round(ki_var + 20, 2), 90])
    spots = sorted(set(spots))

    def struct_ret(x: float) -> float:
        st = 100 + x
        put_pay = max(put - st, 0)
        call_pay = max(st - call, 0) if st >= barrier else 0
        return st + put_pay - call_pay - 100

    rows = []
    for x in spots:
        if x < -50 or x > 100:
            continue
        y = struct_ret(x)
        dig = 2 if abs(x - round(x)) > 0.01 else 0
        xs = ("+" if x > 0 else "") + fmt_br(x, dig) + "%"
        ys = ("+" if y > 0 else "") + fmt_br(y, 1) + "%"
        rows.append(f"<tr><td>{xs}</td><td>{xs}</td><td><strong>{ys}</strong></td></tr>")

    y_min = min(-5, floor - 15)
    y_max = max(55, int(ki_var + 10))
    x_min = -40
    x_max = max(90, int(ki_var + 30))
    up = rs.get("upside")
    if up is not None and up > x_max - 8:
        x_max = int(math.ceil((up + 10) / 10.0) * 10)
    if up is not None:
        js_research = f"var RESEARCH_X={float(up):.4f};"
    else:
        js_research = "var RESEARCH_X=null;"

    prot_blurb = f"Piso {floor_label}<span>Put strike {floor_put_label}</span>"
    zone_low = f"Proteção: retorno limitado a {floor_label}."
    regime_low = f"Em/abaixo de {floor_label}: proteção — retorno limitado a {floor_label}."

    subtitle = (
        f"Estrutura sobre {ticker} com participação 1:1 até a barreira, "
        f"proteção com piso em {floor_label}, e teto de +{cap:.0f}% se o ativo atingir a barreira."
    )
    regime_low_js = regime_low.replace("\\", "\\\\").replace('"', '\\"')

    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Smart Hedge {name} — {ticker} | BTG Pactual</title>
  <style>
    :root {{
      --ink: #0b1f3a; --muted: #5c6b7a; --line: #d0d8e2; --bg: #eef2f6; --card: #ffffff;
      --brand: {brand}; --brand-soft: {brand_soft}; --btg: #0b1f3a; --accent: {brand};
      --success: #0f7a4a; --danger: #c0392b; --dash: #8b83a0;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: Segoe UI, -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif; color: var(--ink); background: var(--bg); min-height: 100vh; line-height: 1.45; }}
    .page {{ max-width: 1280px; margin: 0 auto; padding: 28px 24px 48px; }}
    .back-link {{ margin-bottom: 16px; font-size: 13px; }}
    .back-link a {{ color: #1a66b3; text-decoration: none; font-weight: 600; }}
    .back-link a:hover {{ text-decoration: underline; }}
    .topbar {{ display: flex; justify-content: space-between; align-items: flex-start; gap: 24px; margin-bottom: 28px; padding-bottom: 20px; border-bottom: 1px solid var(--line); }}
    .brand-block {{ display: flex; flex-direction: column; gap: 10px; }}
    .logos {{ display: flex; align-items: center; gap: 14px; }}
    .logo-btg {{ font-weight: 700; font-size: 13px; letter-spacing: 0.04em; color: var(--btg); background: #eef2f7; padding: 6px 10px; border-radius: 4px; }}
    .logo-co {{ display: inline-flex; align-items: center; gap: 8px; font-weight: 700; color: var(--brand); font-size: 15px; }}
    .logo-co .dot {{ width: 22px; height: 22px; border-radius: 50%; background: var(--brand); display: grid; place-items: center; color: #fff; font-size: 9px; font-weight: 700; }}
    h1 {{ font-weight: 700; font-size: clamp(24px, 3vw, 34px); letter-spacing: -0.02em; color: var(--ink); line-height: 1.15; }}
    h1 span {{ color: var(--brand); }}
    .subtitle {{ color: var(--muted); font-size: 14px; max-width: 560px; }}
    .meta-pills {{ display: flex; flex-wrap: wrap; gap: 8px; justify-content: flex-end; }}
    .pill {{ background: var(--card); border: 1px solid var(--line); border-radius: 999px; padding: 8px 14px; font-size: 12px; color: var(--muted); }}
    .pill strong {{ color: var(--ink); font-weight: 600; margin-right: 4px; }}
    .highlights {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 24px; }}
    .hi {{ background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 16px; border-top: 3px solid var(--brand); }}
    .hi h3 {{ font-size: 11px; font-weight: 700; color: var(--muted); text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 6px; }}
    .hi p {{ font-size: 15px; font-weight: 700; color: var(--ink); }}
    .hi p span {{ display: block; font-weight: 400; color: var(--muted); font-size: 12px; margin-top: 3px; }}

    .research{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin-bottom:18px}}
    .research-head{{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:12px;flex-wrap:wrap}}
    .research-head h2{{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--brand);margin:0}}
    .research-link{{display:inline-flex;align-items:center;gap:8px;background:var(--brand);color:#fff !important;text-decoration:none !important;font-weight:700;font-size:13px;padding:10px 14px;border-radius:8px}}
    .research-grid{{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}}
    .research-grid .lbl{{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);margin-bottom:4px}}
    .research-grid .val{{font-size:18px;font-weight:700}}
    .research-grid .val.buy{{color:var(--success)}}
    .research-grid .val.hold{{color:#b8860b}}
    .research-grid .val.sell{{color:var(--danger)}}
    .research-note{{font-size:12px;color:var(--muted);margin-top:10px}}
    .research-actions{{margin-top:12px}}
    .research-btn{{appearance:none;border:1px solid var(--brand);background:#fff;color:var(--brand);font-size:12px;font-weight:700;padding:9px 14px;border-radius:8px;cursor:pointer}}
    .research-bullets{{margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:8px}}
    .research-bullets li{{position:relative;padding:10px 12px 10px 28px;background:var(--bg);border:1px solid var(--line);border-radius:8px;font-size:13px;line-height:1.45}}
    .research-bullets li::before{{content:"";position:absolute;left:12px;top:16px;width:6px;height:6px;border-radius:50%;background:var(--brand)}}
    .insights-box .research-note{{margin-top:12px}}

    .main {{ display: grid; grid-template-columns: 280px 1fr 300px; gap: 18px; align-items: start; }}
    .panel {{ background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 18px; }}
    .panel h2 {{ font-size: 12px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--brand); margin-bottom: 14px; }}
    .struct-table {{ width: 100%; border-collapse: collapse; font-size: 12px; }}
    .struct-table th {{ text-align: left; font-weight: 600; color: var(--muted); padding: 0 6px 10px; border-bottom: 1px solid var(--line); font-size: 11px; text-transform: uppercase; }}
    .struct-table td {{ padding: 10px 6px; border-bottom: 1px solid var(--line); }}
    .struct-table tr:last-child td {{ border-bottom: none; }}
    .tag {{ display: inline-block; font-weight: 700; font-size: 11px; padding: 2px 7px; border-radius: 4px; margin-right: 4px; }}
    .tag.s {{ background: #fde8e8; color: var(--danger); }}
    .tag.b {{ background: #e8f8ef; color: var(--success); }}
    .strike-green {{ color: var(--success); font-weight: 700; }}
    .legend-note {{ margin-top: 14px; font-size: 11px; color: var(--muted); line-height: 1.5; }}
    .chart-panel {{ padding: 16px; }}
    .chart-head {{ display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; margin-bottom: 10px; }}
    .chart-caption {{ font-size: 12px; color: var(--muted); }}
    .chart-legend {{ display: flex; gap: 14px; font-size: 12px; color: var(--muted); flex-wrap: wrap; }}
    .chart-legend span {{ display: inline-flex; align-items: center; gap: 6px; }}
    .swatch {{ width: 18px; height: 3px; border-radius: 2px; background: var(--brand); display: inline-block; }}
    .swatch.asset {{ background: transparent; border-top: 2px dashed var(--dash); height: 0; }}
    .chart-box {{ width: 100%; background: #f8fafc; border: 1px solid var(--line); border-radius: 10px; overflow: hidden; position: relative; user-select: none; }}
    .chart-box svg {{ display: block; width: 100%; height: auto; min-height: 360px; pointer-events: none; }}
    .chart-overlay {{ position: absolute; inset: 0; z-index: 3; touch-action: none; cursor: crosshair; }}
    .chart-touch-hint {{ display: block; font-size: 12px; color: var(--muted); margin-top: 8px; text-align: center; }}
    @media (hover: hover) and (pointer: fine) {{ .chart-touch-hint {{ display: none; }} }}
    .mobile-sim {{ display: block; margin-top: 12px; padding: 12px; background: var(--bg); border: 1px solid var(--line); border-radius: 10px; }}
    .mobile-sim input[type="range"] {{ width: 100%; height: 44px; accent-color: var(--brand); margin-bottom: 0; }}
    .tooltip {{ position: absolute; pointer-events: none; background: var(--ink); color: #fff; padding: 10px 12px; border-radius: 8px; font-size: 12px; min-width: 170px; opacity: 0; z-index: 5; transform: translate(-50%, -120%); }}
    .tooltip.on {{ opacity: 1; }}
    .tooltip .t-title {{ font-weight: 600; margin-bottom: 6px; opacity: 0.85; font-size: 11px; }}
    .tooltip .row {{ display: flex; justify-content: space-between; gap: 16px; margin-top: 3px; }}
    .zones {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 12px; }}
    .zone {{ border: 1px solid var(--line); border-radius: 8px; padding: 10px; background: var(--bg); }}
    .zone strong {{ display: block; font-size: 12px; color: var(--brand); margin-bottom: 4px; }}
    .zone p {{ font-size: 11px; color: var(--muted); line-height: 1.4; }}
    .sim-label {{ display: flex; justify-content: space-between; align-items: baseline; font-size: 12px; color: var(--muted); margin-bottom: 8px; }}
    .sim-label output {{ font-weight: 700; color: var(--ink); font-size: 14px; }}
    input[type="range"] {{ width: 100%; accent-color: var(--brand); margin-bottom: 14px; }}
    .sim-cards {{ display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 12px; }}
    .sim-card {{ background: var(--bg); border: 1px solid var(--line); border-radius: 8px; padding: 12px; }}
    .sim-card .lbl {{ font-size: 11px; color: var(--muted); margin-bottom: 4px; }}
    .sim-card .val {{ font-size: 18px; font-weight: 700; color: var(--ink); }}
    .sim-card .val.pos {{ color: var(--success); }}
    .sim-card .val.neg {{ color: var(--danger); }}
    .regime {{ font-size: 12px; color: var(--ink); background: var(--brand-soft); border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; line-height: 1.45; }}
    .speech-box {{ margin-top: 22px; background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 22px 24px; border-top: 3px solid var(--brand); }}
    .speech-box h2 {{ font-size: 12px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--brand); margin-bottom: 14px; }}
    .speech-label {{ font-size: 11px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--brand); margin: 14px 0 6px; }}
    .speech-box p {{ font-size: 14px; color: var(--ink); max-width: 70em; }}
    .footer {{ margin-top: 28px; font-size: 11px; color: var(--muted); text-align: center; line-height: 1.55; }}
    .footer-alert {{ margin-top: 10px; text-align: center; font-size: 11px; color: var(--btg); font-weight: 700; line-height: 1.5; }}
    .visit-pixel {{ position: absolute; width: 1px; height: 1px; opacity: 0; pointer-events: none; }}
    @media (max-width: 1100px) {{ .main {{ grid-template-columns: 1fr; }} .highlights {{ grid-template-columns: 1fr 1fr; }} .zones {{ grid-template-columns: 1fr; }} .research-grid{{grid-template-columns:1fr 1fr}} }}
    @media (max-width: 640px) {{ .page {{ padding: 16px 14px 40px; }} .topbar {{ flex-direction: column; }} .meta-pills {{ justify-content: flex-start; }} .highlights {{ grid-template-columns: 1fr; }} }}
  </style>
</head>
<body>
  <div class="page">
    <p class="back-link"><a href="../../prateleira-tatica/index.html">← Operações dia D</a></p>
    <header class="topbar">
      <div class="brand-block">
        <div class="logos">
          <span class="logo-btg">BTG PACTUAL</span>
          <span class="logo-co"><span class="dot">{initials}</span> {name}</span>
        </div>
        <h1>Smart Hedge <span>{ticker}</span></h1>
        <p class="subtitle">{subtitle}</p>
      </div>
      <div class="meta-pills">
        <div class="pill"><strong>Ativo</strong> {ticker}</div>
        <div class="pill"><strong>Prazo</strong> {prazo}</div>
        <div class="pill"><strong>Moeda</strong> BRL</div>
        <div class="pill"><strong>Custo inicial</strong> 0%</div>
      </div>
    </header>

    <section class="highlights">
      <div class="hi"><h3>Retorno potencial</h3><p>Acompanha o ativo<span>1:1 até a barreira {barrier_label}</span></p></div>
      <div class="hi"><h3>Proteção</h3><p>{prot_blurb}</p></div>
      <div class="hi"><h3>Se atingir a barreira</h3><p>Teto +{cap:.0f}%<span>Call vendida {fmt_br(call)}%</span></p></div>
      <div class="hi"><h3>Prazo</h3><p>{prazo}</p></div>
    </section>
    {research_block}

    <div class="main">
      <aside class="panel">
        <h2>Estrutura da operação</h2>
        <table class="struct-table">
          <thead><tr><th>Perna</th><th>Strike</th><th>Barreira</th></tr></thead>
          <tbody>
            <tr><td><span class="tag b">B</span> Put {floor_put_label}</td><td class="strike-green">{floor_put_label}</td><td>—</td></tr>
            <tr><td><span class="tag s">S</span> Call {fmt_br(call)}%</td><td>{fmt_br(call)}%</td><td>{barrier_label}</td></tr>
          </tbody>
        </table>
        <p class="legend-note"><strong>B</strong> = Compra · <strong>S</strong> = Venda<br />Payoff = long + put {floor_put_label} + short call {fmt_br(call)}% se spot ≥ barreira.</p>
      </aside>

      <section class="panel chart-panel">
        <div class="chart-head">
          <div>
            <h2>Payoff da estrutura</h2>
            <p class="chart-caption">Retorno no vencimento vs. variação do {ticker}</p>
          </div>
          <div class="chart-legend">
            <span><i class="swatch"></i> Estrutura</span>
            <span><i class="swatch asset"></i> Ativo</span>
            <span><i class="swatch" style="background:#1a66b3;border-top:none;height:2px;background:repeating-linear-gradient(90deg,#1a66b3 0 4px,transparent 4px 7px)"></i> PA Research</span>
          </div>
        </div>
        <div class="chart-box" id="chartBox">
          <div class="tooltip" id="tooltip"></div>
          <svg id="payoffSvg" viewBox="0 0 600 400" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Payoff {ticker}">
            <rect x="48" y="24" width="504" height="352" fill="#f8fafc" />
            <g id="gridLines" stroke="#e2e8f0" stroke-width="1"></g>
            <line id="axisZeroX" x1="154" y1="24" x2="154" y2="376" stroke="#c5d0dc" stroke-width="1.25"/>
            <line id="axisZeroY" x1="48" y1="300" x2="552" y2="300" stroke="#c5d0dc" stroke-width="1.25"/>
            <g id="yLabels" fill="#8b83a0" font-size="11" font-family="Segoe UI, Arial, sans-serif" text-anchor="end"></g>
            <g id="xLabels" fill="#8b83a0" font-size="11" font-family="Segoe UI, Arial, sans-serif" text-anchor="middle"></g>
            <text x="300" y="16" fill="#5c6b7a" font-size="11" font-family="Segoe UI, Arial, sans-serif" text-anchor="middle">Variação do {ticker} no vencimento (%)</text>
            <text x="14" y="200" fill="#5c6b7a" font-size="11" font-family="Segoe UI, Arial, sans-serif" text-anchor="middle" transform="rotate(-90 14 200)">Retorno da estrutura (%)</text>
            <polyline id="assetPath" fill="none" stroke="#8b83a0" stroke-width="1.75" stroke-dasharray="6 5" points="" />
            <line id="koGap" x1="0" y1="0" x2="0" y2="0" stroke="#c0392b" stroke-width="1.25" stroke-dasharray="3 3" opacity="0.75"/>
            <path id="structPath" d="" fill="none" stroke="{brand}" stroke-width="2.75" stroke-linejoin="round" stroke-linecap="round"/>
            <circle id="floorDot" cx="0" cy="0" r="5" fill="#0f7a4a"/>
            <text id="floorLabel" x="0" y="0" fill="#0f7a4a" font-size="11" font-weight="600" font-family="Segoe UI, Arial, sans-serif">Piso {floor_label}</text>
            <circle id="kiDot" cx="0" cy="0" r="5" fill="#c0392b"/>
            <text id="kiLabel" x="0" y="0" fill="#c0392b" font-size="11" font-weight="600" font-family="Segoe UI, Arial, sans-serif">Barreira {barrier_label}</text>
            <circle id="capDot" cx="0" cy="0" r="4" fill="{brand}"/>
            <text id="capLabel" x="0" y="0" fill="{brand}" font-size="11" font-weight="600" font-family="Segoe UI, Arial, sans-serif">Teto +{cap:.0f}%</text>
            <line id="researchTargetLine" x1="0" y1="24" x2="0" y2="376" stroke="#1a66b3" stroke-width="1.5" stroke-dasharray="5 4" opacity="0"/>
            <text id="researchTargetLabel" font-size="11" fill="#1a66b3" font-weight="700" opacity="0">PA Research</text>
            <line id="hoverLine" x1="0" y1="24" x2="0" y2="376" stroke="rgba(0,0,0,0.25)" stroke-width="1.25" stroke-dasharray="4 4" visibility="hidden"/>
            <circle id="hoverStruct" r="5.5" fill="{brand}" visibility="hidden"/>
            <circle id="hoverAsset" r="4" fill="#8b83a0" visibility="hidden"/>
          </svg>
          <div class="chart-overlay" id="chartOverlay"></div>
        </div>
        <p class="chart-touch-hint">Toque e arraste no gráfico · ou use o controle abaixo</p>
        <div class="mobile-sim">
          <div class="sim-label"><span>Variação do {ticker}</span><output id="spotOutMobile">+20%</output></div>
          <input type="range" id="spotSliderMobile" min="{x_min}" max="{x_max}" step="0.5" value="20" />
        </div>
        <div class="zones">
          <div class="zone"><strong>≤ {floor_label}</strong><p>{zone_low}</p></div>
          <div class="zone"><strong>{floor_label} → barreira</strong><p>Acompanha o ativo 1:1.</p></div>
          <div class="zone"><strong>≥ barreira</strong><p>Retorno limitado a +{cap:.0f}%.</p></div>
        </div>
      </section>

      <aside class="panel">
        <h2>Simulador no vencimento</h2>
        <div class="sim-label"><span>Variação do {ticker}</span><output id="spotOut">+20%</output></div>
        <input type="range" id="spotSlider" min="{x_min}" max="{x_max}" step="0.5" value="20" />
        <div class="sim-cards">
          <div class="sim-card"><div class="lbl">Retorno do ativo</div><div class="val" id="assetVal">+20,0%</div></div>
          <div class="sim-card"><div class="lbl">Retorno da estrutura</div><div class="val" id="structVal">+20,0%</div></div>
        </div>
        <div class="regime" id="regimeText">Entre o piso e a barreira: acompanha o ativo 1:1.</div>
        <div style="margin-top:18px">
          <h2>Pontos-chave</h2>
          <table class="struct-table">
            <thead><tr><th>Spot</th><th>Ativo</th><th>Estrutura</th></tr></thead>
            <tbody>
              {''.join(rows)}
            </tbody>
          </table>
        </div>
      </aside>
    </div>

    <section class="speech-box">
      <h2>Speech comercial</h2>
      <p class="speech-label">Para quem</p>
      <p>Cliente construtivo em {name} ({ticker}) no horizonte de {prazo}, que quer exposição com colchão na queda.</p>
      <p class="speech-label">Como encaixa a estrutura</p>
      <p>
        Custo inicial <strong>zero</strong>.
        Até a barreira ({barrier_label}), participa <strong>1:1</strong> da variação do {ticker}.
        Na queda, o piso fica em <strong>{floor_label}</strong> (put {floor_put_label}).
        Se o ativo atingir a barreira, o retorno fica limitado a <strong>+{cap:.0f}%</strong> (call vendida {fmt_br(call)}%).
      </p>
      <p class="speech-label">Fechamento</p>
      <p>Payoff fácil de explicar no vencimento. Material de uso interno — condições oficiais no DIE (Admin BTG).</p>
    </section>
    {insights_block}

    <p class="footer">Material ilustrativo. Payoff intrínseco no vencimento. Não constitui oferta, recomendação ou garantia de rentabilidade. Produto estruturado envolve risco de perda de capital.</p>
    <p class="footer-alert"><strong>MATERIAL DE USO INTERNO, NÃO ENVIAR AOS CLIENTES</strong><br /><strong>PARA INFORMAÇÕES OFICIAIS, ACESSAR O DIE DA OPERAÇÃO DISPONIBILIZADO NO ADMIN BTG</strong></p>
  </div>

  <script>
    (function () {{
      var X_MIN = {x_min}, X_MAX = {x_max};
      var Y_MIN = {y_min}, Y_MAX = {y_max};
      var PAD = {{ l: 48, t: 24, r: 48, b: 24 }};
      var VW = 600, VH = 400;
      var PLOT_W = VW - PAD.l - PAD.r;
      var PLOT_H = VH - PAD.t - PAD.b;
      var PUT = {put}, CALL = {call}, BARRIER = {barrier};
      var FLOOR = {floor}, CAP = {cap}, KI_VAR = {ki_var};
      {js_research}

      function structureReturn(x) {{
        var st = 100 + x;
        var put = Math.max(PUT - st, 0);
        var call = st >= BARRIER ? Math.max(st - CALL, 0) : 0;
        return st + put - call - 100;
      }}
      function regimeFor(x) {{
        if (x <= FLOOR) return "{regime_low_js}";
        if (x < KI_VAR) return "Entre o piso e a barreira: acompanha o ativo 1:1.";
        return "Ativo atingiu a barreira (spot ≥ " + BARRIER.toFixed(2).replace(".", ",") + "%): retorno limitado a +" + CAP + "%.";
      }}
      function fmtPct(n, digits) {{
        if (digits == null) digits = 1;
        var sign = n > 0 ? "+" : "";
        return sign + n.toFixed(digits).replace(".", ",") + "%";
      }}
      function xToSvg(x) {{ return PAD.l + ((x - X_MIN) / (X_MAX - X_MIN)) * PLOT_W; }}
      function yToSvg(y) {{
        var yy = Math.max(Y_MIN, Math.min(Y_MAX, y));
        return PAD.t + (1 - (yy - Y_MIN) / (Y_MAX - Y_MIN)) * PLOT_H;
      }}
      function svgToX(px) {{ return X_MIN + ((px - PAD.l) / PLOT_W) * (X_MAX - X_MIN); }}

      function placeResearchMarker() {{
        if (RESEARCH_X == null) return;
        var x = Math.max(X_MIN, Math.min(X_MAX, RESEARCH_X));
        var px = xToSvg(x);
        var line = document.getElementById("researchTargetLine");
        var lab = document.getElementById("researchTargetLabel");
        if (!line || !lab) return;
        line.setAttribute("x1", px); line.setAttribute("x2", px); line.setAttribute("opacity", "1");
        lab.setAttribute("x", Math.min(VW - PAD.r - 8, px + 6));
        lab.setAttribute("y", PAD.t + 14);
        lab.textContent = "PA Research " + fmtPct(RESEARCH_X, 1);
        lab.setAttribute("opacity", "1");
      }}

      function buildStructD() {{
        var d = "", first = true;
        function move(x, y) {{ first = true; add(x, y); }}
        function add(x, y) {{
          var cmd = first ? "M" : "L"; first = false;
          d += cmd + " " + xToSvg(x).toFixed(3) + " " + yToSvg(y).toFixed(3) + " ";
        }}
        for (var x = X_MIN; x <= FLOOR; x += 0.5) add(x, FLOOR);
        for (var x2 = FLOOR + 0.5; x2 < KI_VAR; x2 += 0.5) add(x2, x2);
        add(KI_VAR - 0.01, structureReturn(KI_VAR - 0.01));
        move(KI_VAR, CAP);
        for (var x3 = KI_VAR + 0.5; x3 <= X_MAX; x3 += 0.5) add(x3, CAP);
        return d.trim();
      }}
      function buildAssetPoints() {{
        var pts = [];
        for (var x = X_MIN; x <= X_MAX; x += 1) {{
          var y = Math.max(Y_MIN, Math.min(Y_MAX, x));
          pts.push(xToSvg(x).toFixed(3) + "," + yToSvg(y).toFixed(3));
        }}
        return pts.join(" ");
      }}

      var grid = document.getElementById("gridLines");
      var yLabels = document.getElementById("yLabels");
      var xLabels = document.getElementById("xLabels");
      if (grid && yLabels && xLabels) {{
        grid.innerHTML = ""; yLabels.innerHTML = ""; xLabels.innerHTML = "";
        for (var y = Math.ceil(Y_MIN / 10) * 10; y <= Y_MAX; y += 10) {{
          var py = yToSvg(y);
          grid.innerHTML += '<line x1="48" y1="' + py + '" x2="552" y2="' + py + '"/>';
          yLabels.innerHTML += '<text x="42" y="' + (py + 3) + '">' + y + "%</text>";
        }}
        var xStep = (X_MAX - X_MIN) > 100 ? 20 : 10;
        for (var x = Math.ceil(X_MIN / xStep) * xStep; x <= X_MAX; x += xStep) {{
          var px = xToSvg(x);
          grid.innerHTML += '<line x1="' + px + '" y1="24" x2="' + px + '" y2="376"/>';
          xLabels.innerHTML += '<text x="' + px + '" y="392">' + x + "%</text>";
        }}
      }}
      document.getElementById("axisZeroX").setAttribute("x1", xToSvg(0));
      document.getElementById("axisZeroX").setAttribute("x2", xToSvg(0));
      document.getElementById("axisZeroY").setAttribute("y1", yToSvg(0));
      document.getElementById("axisZeroY").setAttribute("y2", yToSvg(0));
      document.getElementById("structPath").setAttribute("d", buildStructD());
      document.getElementById("assetPath").setAttribute("points", buildAssetPoints());
      placeResearchMarker();

      var floorX = xToSvg(FLOOR), kiX = xToSvg(KI_VAR);
      document.getElementById("floorDot").setAttribute("cx", floorX);
      document.getElementById("floorDot").setAttribute("cy", yToSvg(FLOOR));
      document.getElementById("floorLabel").setAttribute("x", floorX + 8);
      document.getElementById("floorLabel").setAttribute("y", yToSvg(FLOOR) - 8);
      document.getElementById("koGap").setAttribute("x1", kiX);
      document.getElementById("koGap").setAttribute("x2", kiX);
      document.getElementById("koGap").setAttribute("y1", yToSvg(Math.min(KI_VAR, Y_MAX)));
      document.getElementById("koGap").setAttribute("y2", yToSvg(CAP));
      document.getElementById("kiDot").setAttribute("cx", kiX);
      document.getElementById("kiDot").setAttribute("cy", yToSvg(CAP));
      document.getElementById("kiLabel").setAttribute("x", Math.max(48, kiX - 110));
      document.getElementById("kiLabel").setAttribute("y", yToSvg(CAP) - 10);
      document.getElementById("capDot").setAttribute("cx", Math.min(552, kiX + 40));
      document.getElementById("capDot").setAttribute("cy", yToSvg(CAP));
      document.getElementById("capLabel").setAttribute("x", Math.min(520, kiX + 48));
      document.getElementById("capLabel").setAttribute("y", yToSvg(CAP) + 14);

      var hoverLine = document.getElementById("hoverLine");
      var hoverStruct = document.getElementById("hoverStruct");
      var hoverAsset = document.getElementById("hoverAsset");
      var overlay = document.getElementById("chartOverlay");
      var tooltip = document.getElementById("tooltip");
      var svg = document.getElementById("payoffSvg");
      var slider = document.getElementById("spotSlider");
      var sliderMobile = document.getElementById("spotSliderMobile");
      var spotOut = document.getElementById("spotOut");
      var spotOutMobile = document.getElementById("spotOutMobile");
      var assetVal = document.getElementById("assetVal");
      var structVal = document.getElementById("structVal");
      var regimeText = document.getElementById("regimeText");
      var activePointer = null;

      function showAt(x) {{
        x = Math.max(X_MIN, Math.min(X_MAX, x));
        var ys = structureReturn(x);
        var sx = xToSvg(x), sy = yToSvg(ys), ay = yToSvg(Math.max(Y_MIN, Math.min(Y_MAX, x)));
        hoverLine.setAttribute("x1", sx); hoverLine.setAttribute("x2", sx); hoverLine.setAttribute("visibility", "visible");
        hoverStruct.setAttribute("cx", sx); hoverStruct.setAttribute("cy", sy); hoverStruct.setAttribute("visibility", "visible");
        hoverAsset.setAttribute("cx", sx); hoverAsset.setAttribute("cy", ay); hoverAsset.setAttribute("visibility", "visible");
        tooltip.innerHTML = '<div class="t-title">Spot final ' + fmtPct(x) + "</div>" +
          '<div class="row"><span>{ticker}</span><strong>' + fmtPct(x) + "</strong></div>" +
          '<div class="row"><span>Estrutura</span><strong>' + fmtPct(ys) + "</strong></div>";
        tooltip.classList.add("on");
        var svgRect = svg.getBoundingClientRect();
        tooltip.style.left = Math.max(70, Math.min(svgRect.width - 70, sx * svgRect.width / VW)) + "px";
        tooltip.style.top = Math.max(40, sy * svgRect.height / VH) + "px";
        if (slider) slider.value = String(x);
        if (sliderMobile) sliderMobile.value = String(x);
        var label = fmtPct(x, x % 1 === 0 ? 0 : 1);
        if (spotOut) spotOut.textContent = label;
        if (spotOutMobile) spotOutMobile.textContent = label;
        if (assetVal) {{ assetVal.textContent = fmtPct(x); assetVal.className = "val " + (x > 0 ? "pos" : x < 0 ? "neg" : ""); }}
        if (structVal) {{ structVal.textContent = fmtPct(ys); structVal.className = "val " + (ys > 0 ? "pos" : ys < 0 ? "neg" : ""); }}
        if (regimeText) regimeText.textContent = regimeFor(x);
      }}
      function clientToSvgX(clientX) {{
        var rect = svg.getBoundingClientRect();
        if (!rect.width) return 0;
        return svgToX(((clientX - rect.left) / rect.width) * VW);
      }}
      function updateFromEvent(e) {{ showAt(clientToSvgX(e.clientX)); }}
      overlay.addEventListener("pointerdown", function (e) {{ activePointer = e.pointerId; overlay.setPointerCapture(e.pointerId); updateFromEvent(e); }});
      overlay.addEventListener("pointermove", function (e) {{
        if (activePointer !== null && e.pointerId !== activePointer) return;
        if (e.pointerType === "mouse" || activePointer !== null) updateFromEvent(e);
      }});
      function endPointer(e) {{
        if (activePointer !== null && e.pointerId !== activePointer) return;
        activePointer = null;
        try {{ overlay.releasePointerCapture(e.pointerId); }} catch (err) {{}}
      }}
      overlay.addEventListener("pointerup", endPointer);
      overlay.addEventListener("pointercancel", endPointer);
      overlay.addEventListener("pointerleave", function (e) {{
        if (e.pointerType === "mouse" && activePointer === null) {{
          hoverLine.setAttribute("visibility", "hidden");
          hoverStruct.setAttribute("visibility", "hidden");
          hoverAsset.setAttribute("visibility", "hidden");
          tooltip.classList.remove("on");
        }}
      }});
      function onSliderInput(e) {{ showAt(Number(e.target.value)); }}
      if (slider) slider.addEventListener("input", onSliderInput);
      if (sliderMobile) {{ sliderMobile.addEventListener("input", onSliderInput); sliderMobile.addEventListener("change", onSliderInput); }}
      var btnPa = document.getElementById("btnResearchTarget");
      if (btnPa && RESEARCH_X != null) {{
        btnPa.addEventListener("click", function () {{ showAt(RESEARCH_X); }});
      }} else if (btnPa) {{
        btnPa.disabled = true;
      }}
      showAt(20);
    }})();
  </script>
</body>
</html>
"""


def twin_coupon_html(prat=None, research=None) -> str:
    """Twin Coupon ITUB4 — approximation for illustration."""
    rs = research or {}
    research_block = ""
    insights_block = ""
    if prat is not None:
        research_block = prat.research_html({"ticker": "ITUB4", "research": rs})
        insights_block = prat.research_insights_html({"ticker": "ITUB4", "research": rs})
    brand = "#ec7000"
    brand_soft = "rgba(236,112,0,0.12)"
    ticker = "ITUB4"
    down_barrier = 70.0  # -30%
    up_barrier = 153.0  # +53%
    put = 110.0
    strike = 110.0
    floor = 10.0
    cap = 10.0
    down_var = down_barrier - 100  # -30
    up_var = up_barrier - 100  # 53

    def struct_ret(x: float) -> float:
        # Below down barrier: lose enhanced protection → follow asset
        if x <= down_var:
            return x
        # Up barrier hit: strike 110% → cap +10%
        if x >= up_var:
            return cap
        # Between barriers: twin-style with floor related to 110%
        return max(abs(x), floor)

    spots = [-50, -40, -30, -20, -10, 0, 10, 20, 40, 53, 60, 80]
    rows = []
    for x in spots:
        y = struct_ret(float(x))
        xs = ("+" if x > 0 else "") + fmt_br(x, 0) + "%"
        ys = ("+" if y > 0 else "") + fmt_br(y, 1) + "%"
        rows.append(f"<tr><td>{xs}</td><td>{xs}</td><td><strong>{ys}</strong></td></tr>")

    x_min, x_max = -50, 80
    y_min, y_max = -45, 60
    up = rs.get("upside")
    if up is not None and up > x_max - 8:
        x_max = int(math.ceil((up + 10) / 10.0) * 10)
    if up is not None:
        js_research = f"var RESEARCH_X={float(up):.4f};"
    else:
        js_research = "var RESEARCH_X=null;"

    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Twin Coupon Itaú — ITUB4 | BTG Pactual</title>
  <style>
    :root {{
      --ink: #0b1f3a; --muted: #5c6b7a; --line: #d0d8e2; --bg: #eef2f6; --card: #ffffff;
      --brand: {brand}; --brand-soft: {brand_soft}; --btg: #0b1f3a;
      --success: #0f7a4a; --danger: #c0392b; --dash: #8b83a0;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: Segoe UI, -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif; color: var(--ink); background: var(--bg); min-height: 100vh; line-height: 1.45; }}
    .page {{ max-width: 1280px; margin: 0 auto; padding: 28px 24px 48px; }}
    .back-link {{ margin-bottom: 16px; font-size: 13px; }}
    .back-link a {{ color: #1a66b3; text-decoration: none; font-weight: 600; }}
    .back-link a:hover {{ text-decoration: underline; }}
    .topbar {{ display: flex; justify-content: space-between; align-items: flex-start; gap: 24px; margin-bottom: 28px; padding-bottom: 20px; border-bottom: 1px solid var(--line); }}
    .brand-block {{ display: flex; flex-direction: column; gap: 10px; }}
    .logos {{ display: flex; align-items: center; gap: 14px; }}
    .logo-btg {{ font-weight: 700; font-size: 13px; letter-spacing: 0.04em; color: var(--btg); background: #eef2f7; padding: 6px 10px; border-radius: 4px; }}
    .logo-co {{ display: inline-flex; align-items: center; gap: 8px; font-weight: 700; color: var(--brand); font-size: 15px; }}
    .logo-co .dot {{ width: 22px; height: 22px; border-radius: 50%; background: var(--brand); display: grid; place-items: center; color: #fff; font-size: 9px; font-weight: 700; }}
    h1 {{ font-weight: 700; font-size: clamp(24px, 3vw, 34px); letter-spacing: -0.02em; color: var(--ink); line-height: 1.15; }}
    h1 span {{ color: var(--brand); }}
    .subtitle {{ color: var(--muted); font-size: 14px; max-width: 580px; }}
    .meta-pills {{ display: flex; flex-wrap: wrap; gap: 8px; justify-content: flex-end; }}
    .pill {{ background: var(--card); border: 1px solid var(--line); border-radius: 999px; padding: 8px 14px; font-size: 12px; color: var(--muted); }}
    .pill strong {{ color: var(--ink); font-weight: 600; margin-right: 4px; }}
    .highlights {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 24px; }}
    .hi {{ background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 16px; border-top: 3px solid var(--brand); }}
    .hi h3 {{ font-size: 11px; font-weight: 700; color: var(--muted); text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 6px; }}
    .hi p {{ font-size: 15px; font-weight: 700; color: var(--ink); }}
    .hi p span {{ display: block; font-weight: 400; color: var(--muted); font-size: 12px; margin-top: 3px; }}

    .research{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin-bottom:18px}}
    .research-head{{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:12px;flex-wrap:wrap}}
    .research-head h2{{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--brand);margin:0}}
    .research-link{{display:inline-flex;align-items:center;gap:8px;background:var(--brand);color:#fff !important;text-decoration:none !important;font-weight:700;font-size:13px;padding:10px 14px;border-radius:8px}}
    .research-grid{{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}}
    .research-grid .lbl{{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);margin-bottom:4px}}
    .research-grid .val{{font-size:18px;font-weight:700}}
    .research-grid .val.buy{{color:var(--success)}}
    .research-grid .val.hold{{color:#b8860b}}
    .research-grid .val.sell{{color:var(--danger)}}
    .research-note{{font-size:12px;color:var(--muted);margin-top:10px}}
    .research-actions{{margin-top:12px}}
    .research-btn{{appearance:none;border:1px solid var(--brand);background:#fff;color:var(--brand);font-size:12px;font-weight:700;padding:9px 14px;border-radius:8px;cursor:pointer}}
    .research-bullets{{margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:8px}}
    .research-bullets li{{position:relative;padding:10px 12px 10px 28px;background:var(--bg);border:1px solid var(--line);border-radius:8px;font-size:13px;line-height:1.45}}
    .research-bullets li::before{{content:"";position:absolute;left:12px;top:16px;width:6px;height:6px;border-radius:50%;background:var(--brand)}}
    .insights-box .research-note{{margin-top:12px}}

    .main {{ display: grid; grid-template-columns: 280px 1fr 300px; gap: 18px; align-items: start; }}
    .panel {{ background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 18px; }}
    .panel h2 {{ font-size: 12px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--brand); margin-bottom: 14px; }}
    .struct-table {{ width: 100%; border-collapse: collapse; font-size: 12px; }}
    .struct-table th {{ text-align: left; font-weight: 600; color: var(--muted); padding: 0 6px 10px; border-bottom: 1px solid var(--line); font-size: 11px; text-transform: uppercase; }}
    .struct-table td {{ padding: 10px 6px; border-bottom: 1px solid var(--line); }}
    .struct-table tr:last-child td {{ border-bottom: none; }}
    .tag {{ display: inline-block; font-weight: 700; font-size: 11px; padding: 2px 7px; border-radius: 4px; margin-right: 4px; }}
    .tag.s {{ background: #fde8e8; color: var(--danger); }}
    .tag.b {{ background: #e8f8ef; color: var(--success); }}
    .strike-green {{ color: var(--success); font-weight: 700; }}
    .legend-note {{ margin-top: 14px; font-size: 11px; color: var(--muted); line-height: 1.5; }}
    .chart-panel {{ padding: 16px; }}
    .chart-head {{ display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; margin-bottom: 10px; }}
    .chart-caption {{ font-size: 12px; color: var(--muted); }}
    .chart-legend {{ display: flex; gap: 14px; font-size: 12px; color: var(--muted); flex-wrap: wrap; }}
    .chart-legend span {{ display: inline-flex; align-items: center; gap: 6px; }}
    .swatch {{ width: 18px; height: 3px; border-radius: 2px; background: var(--brand); display: inline-block; }}
    .swatch.asset {{ background: transparent; border-top: 2px dashed var(--dash); height: 0; }}
    .chart-box {{ width: 100%; background: #f8fafc; border: 1px solid var(--line); border-radius: 10px; overflow: hidden; position: relative; user-select: none; }}
    .chart-box svg {{ display: block; width: 100%; height: auto; min-height: 360px; pointer-events: none; }}
    .chart-overlay {{ position: absolute; inset: 0; z-index: 3; touch-action: none; cursor: crosshair; }}
    .chart-touch-hint {{ display: block; font-size: 12px; color: var(--muted); margin-top: 8px; text-align: center; }}
    @media (hover: hover) and (pointer: fine) {{ .chart-touch-hint {{ display: none; }} }}
    .mobile-sim {{ display: block; margin-top: 12px; padding: 12px; background: var(--bg); border: 1px solid var(--line); border-radius: 10px; }}
    .mobile-sim input[type="range"] {{ width: 100%; height: 44px; accent-color: var(--brand); margin-bottom: 0; }}
    .tooltip {{ position: absolute; pointer-events: none; background: var(--ink); color: #fff; padding: 10px 12px; border-radius: 8px; font-size: 12px; min-width: 170px; opacity: 0; z-index: 5; transform: translate(-50%, -120%); }}
    .tooltip.on {{ opacity: 1; }}
    .tooltip .t-title {{ font-weight: 600; margin-bottom: 6px; opacity: 0.85; font-size: 11px; }}
    .tooltip .row {{ display: flex; justify-content: space-between; gap: 16px; margin-top: 3px; }}
    .zones {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 12px; }}
    .zone {{ border: 1px solid var(--line); border-radius: 8px; padding: 10px; background: var(--bg); }}
    .zone strong {{ display: block; font-size: 12px; color: var(--brand); margin-bottom: 4px; }}
    .zone p {{ font-size: 11px; color: var(--muted); line-height: 1.4; }}
    .sim-label {{ display: flex; justify-content: space-between; align-items: baseline; font-size: 12px; color: var(--muted); margin-bottom: 8px; }}
    .sim-label output {{ font-weight: 700; color: var(--ink); font-size: 14px; }}
    input[type="range"] {{ width: 100%; accent-color: var(--brand); margin-bottom: 14px; }}
    .sim-cards {{ display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 12px; }}
    .sim-card {{ background: var(--bg); border: 1px solid var(--line); border-radius: 8px; padding: 12px; }}
    .sim-card .lbl {{ font-size: 11px; color: var(--muted); margin-bottom: 4px; }}
    .sim-card .val {{ font-size: 18px; font-weight: 700; color: var(--ink); }}
    .sim-card .val.pos {{ color: var(--success); }}
    .sim-card .val.neg {{ color: var(--danger); }}
    .regime {{ font-size: 12px; color: var(--ink); background: #fff7ef; border: 1px solid #f0d4b8; border-radius: 8px; padding: 10px 12px; line-height: 1.45; }}
    .speech-box {{ margin-top: 22px; background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 22px 24px; border-top: 3px solid var(--brand); }}
    .speech-box h2 {{ font-size: 12px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--brand); margin-bottom: 14px; }}
    .speech-label {{ font-size: 11px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--brand); margin: 14px 0 6px; }}
    .speech-box p {{ font-size: 14px; color: var(--ink); max-width: 70em; }}
    .footer {{ margin-top: 28px; font-size: 11px; color: var(--muted); text-align: center; line-height: 1.55; }}
    .footer-alert {{ margin-top: 10px; text-align: center; font-size: 11px; color: var(--btg); font-weight: 700; line-height: 1.5; }}
    @media (max-width: 1100px) {{ .main {{ grid-template-columns: 1fr; }} .highlights {{ grid-template-columns: 1fr 1fr; }} .zones {{ grid-template-columns: 1fr; }} }}
    @media (max-width: 640px) {{ .page {{ padding: 16px 14px 40px; }} .topbar {{ flex-direction: column; }} .meta-pills {{ justify-content: flex-start; }} .highlights {{ grid-template-columns: 1fr; }} }}
  </style>
</head>
<body>
  <div class="page">
    <p class="back-link"><a href="../../prateleira-tatica/index.html">← Operações dia D</a></p>
    <header class="topbar">
      <div class="brand-block">
        <div class="logos">
          <span class="logo-btg">BTG PACTUAL</span>
          <span class="logo-co"><span class="dot">IT</span> Itaú</span>
        </div>
        <h1>Twin Coupon <span>ITUB4</span></h1>
        <p class="subtitle">
          Estrutura sobre ITUB4 com proteção 110%, barreira de queda 70%, strike 110% e barreira alta 153%.
          Payoff ilustrativo (twin + proteção); cupons conforme DIE.
        </p>
      </div>
      <div class="meta-pills">
        <div class="pill"><strong>Ativo</strong> ITUB4</div>
        <div class="pill"><strong>Prazo</strong> 2 anos</div>
        <div class="pill"><strong>Moeda</strong> BRL</div>
        <div class="pill"><strong>Cupons</strong> ver DIE</div>
      </div>
    </header>

    <section class="highlights">
      <div class="hi"><h3>Proteção</h3><p>110%<span>Piso +10% se barreira de queda não for atingida</span></p></div>
      <div class="hi"><h3>Barreira de queda</h3><p>70%<span>−30% — perde proteção reforçada</span></p></div>
      <div class="hi"><h3>Strike / barreira alta</h3><p>110% / 153%<span>Se barreira alta: teto +10%</span></p></div>
      <div class="hi"><h3>Prazo</h3><p>2 anos<span>Cupons: detalhes no DIE</span></p></div>
    </section>
    {research_block}

    <div class="main">
      <aside class="panel">
        <h2>Estrutura da operação</h2>
        <table class="struct-table">
          <thead><tr><th>Perna / parâmetro</th><th>Nível</th></tr></thead>
          <tbody>
            <tr><td><span class="tag b">B</span> Proteção (put)</td><td class="strike-green">110,00%</td></tr>
            <tr><td>Barreira de queda</td><td>70,00%</td></tr>
            <tr><td><span class="tag s">S</span> Strike (call)</td><td>110,00%</td></tr>
            <tr><td>Barreira alta</td><td>153,00%</td></tr>
          </tbody>
        </table>
        <p class="legend-note">
          <strong>B</strong> = Compra · <strong>S</strong> = Venda<br />
          Gráfico aproxima o payoff no vencimento. Cupons periódicos: consultar DIE.
        </p>
      </aside>

      <section class="panel chart-panel">
        <div class="chart-head">
          <div>
            <h2>Payoff ilustrativo</h2>
            <p class="chart-caption">Retorno no vencimento vs. variação do ITUB4 (aprox.)</p>
          </div>
          <div class="chart-legend">
            <span><i class="swatch"></i> Estrutura</span>
            <span><i class="swatch asset"></i> Ativo</span>
            <span><i class="swatch" style="background:#1a66b3;border-top:none;height:2px;background:repeating-linear-gradient(90deg,#1a66b3 0 4px,transparent 4px 7px)"></i> PA Research</span>
          </div>
        </div>
        <div class="chart-box" id="chartBox">
          <div class="tooltip" id="tooltip"></div>
          <svg id="payoffSvg" viewBox="0 0 600 400" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Payoff Twin Coupon ITUB4">
            <rect x="48" y="24" width="504" height="352" fill="#f8fafc" />
            <g id="gridLines" stroke="#e2e8f0" stroke-width="1"></g>
            <line id="axisZeroX" x1="154" y1="24" x2="154" y2="376" stroke="#c5d0dc" stroke-width="1.25"/>
            <line id="axisZeroY" x1="48" y1="300" x2="552" y2="300" stroke="#c5d0dc" stroke-width="1.25"/>
            <g id="yLabels" fill="#8b83a0" font-size="11" font-family="Segoe UI, Arial, sans-serif" text-anchor="end"></g>
            <g id="xLabels" fill="#8b83a0" font-size="11" font-family="Segoe UI, Arial, sans-serif" text-anchor="middle"></g>
            <text x="300" y="16" fill="#5c6b7a" font-size="11" font-family="Segoe UI, Arial, sans-serif" text-anchor="middle">Variação do ITUB4 no vencimento (%)</text>
            <text x="14" y="200" fill="#5c6b7a" font-size="11" font-family="Segoe UI, Arial, sans-serif" text-anchor="middle" transform="rotate(-90 14 200)">Retorno da estrutura (%)</text>
            <polyline id="assetPath" fill="none" stroke="#8b83a0" stroke-width="1.75" stroke-dasharray="6 5" points="" />
            <line id="downGap" x1="0" y1="0" x2="0" y2="0" stroke="#c0392b" stroke-width="1.25" stroke-dasharray="3 3" opacity="0.75"/>
            <line id="upGap" x1="0" y1="0" x2="0" y2="0" stroke="#c0392b" stroke-width="1.25" stroke-dasharray="3 3" opacity="0.75"/>
            <path id="structPath" d="" fill="none" stroke="{brand}" stroke-width="2.75" stroke-linejoin="round" stroke-linecap="round"/>
            <circle id="downDot" cx="0" cy="0" r="5" fill="#c0392b"/>
            <text id="downLabel" x="0" y="0" fill="#c0392b" font-size="11" font-weight="600" font-family="Segoe UI, Arial, sans-serif">Queda 70%</text>
            <circle id="floorDot" cx="0" cy="0" r="5" fill="#0f7a4a"/>
            <text id="floorLabel" x="0" y="0" fill="#0f7a4a" font-size="11" font-weight="600" font-family="Segoe UI, Arial, sans-serif">Piso +10%</text>
            <circle id="upDot" cx="0" cy="0" r="5" fill="#c0392b"/>
            <text id="upLabel" x="0" y="0" fill="#c0392b" font-size="11" font-weight="600" font-family="Segoe UI, Arial, sans-serif">Alta 153%</text>
            <line id="hoverLine" x1="0" y1="24" x2="0" y2="376" stroke="rgba(236,112,0,0.4)" stroke-width="1.25" stroke-dasharray="4 4" visibility="hidden"/>
            <circle id="hoverStruct" r="5.5" fill="{brand}" visibility="hidden"/>
            <circle id="hoverAsset" r="4" fill="#8b83a0" visibility="hidden"/>
          </svg>
          <div class="chart-overlay" id="chartOverlay"></div>
        </div>
        <p class="chart-touch-hint">Toque e arraste no gráfico · ou use o controle abaixo</p>
        <div class="mobile-sim">
          <div class="sim-label"><span>Variação do ITUB4</span><output id="spotOutMobile">+20%</output></div>
          <input type="range" id="spotSliderMobile" min="{x_min}" max="{x_max}" step="0.5" value="20" />
        </div>
        <div class="zones">
          <div class="zone"><strong>≤ −30% (70%)</strong><p>Barreira de queda: perde a proteção reforçada — acompanha o ativo.</p></div>
          <div class="zone"><strong>−30% → +53%</strong><p>Twin / proteção: piso +10% (110%); na alta/queda moderada, estilo twin com |variação|.</p></div>
          <div class="zone"><strong>≥ +53% (153%)</strong><p>Barreira alta: aplica strike 110% — teto +10%.</p></div>
        </div>
      </section>

      <aside class="panel">
        <h2>Simulador no vencimento</h2>
        <div class="sim-label"><span>Variação do ITUB4</span><output id="spotOut">+20%</output></div>
        <input type="range" id="spotSlider" min="{x_min}" max="{x_max}" step="0.5" value="20" />
        <div class="sim-cards">
          <div class="sim-card"><div class="lbl">Retorno do ativo</div><div class="val" id="assetVal">+20,0%</div></div>
          <div class="sim-card"><div class="lbl">Retorno da estrutura</div><div class="val" id="structVal">+20,0%</div></div>
        </div>
        <div class="regime" id="regimeText">Entre as barreiras: twin com piso +10%.</div>
        <div style="margin-top:18px">
          <h2>Pontos-chave</h2>
          <table class="struct-table">
            <thead><tr><th>Spot</th><th>Ativo</th><th>Estrutura</th></tr></thead>
            <tbody>
              {''.join(rows)}
            </tbody>
          </table>
        </div>
      </aside>
    </div>

    <section class="speech-box">
      <h2>Speech comercial</h2>
      <p class="speech-label">Parâmetros</p>
      <p>
        <strong>Proteção 110%</strong> (piso +10% enquanto a barreira de queda não for atingida),
        <strong>barreira de queda 70%</strong> (−30%),
        <strong>strike 110%</strong> e <strong>barreira alta 153%</strong> (+53%),
        prazo <strong>2 anos</strong>.
      </p>
      <p class="speech-label">Zonas de payoff (ilustrativo)</p>
      <p>
        Abaixo de −30%: perde a proteção reforçada e passa a acompanhar o ativo.
        Entre −30% e +53%: caminho twin / protegido com piso ligado à proteção 110%.
        Se a barreira alta for atingida: aplica o strike 110% (teto +10%).
      </p>
      <p class="speech-label">Cupons</p>
      <p>
        Detalhes de cupom (frequência, taxa, condições de pagamento) conforme o <strong>DIE</strong> da operação no Admin BTG —
        este material não fixa cupom quando o documento oficial não estiver confirmado.
      </p>
      <p class="speech-label">Fechamento</p>
      <p>Material de uso interno. Payoff aproximado para conversa comercial — condições oficiais no DIE.</p>
    </section>
    {insights_block}

    <p class="footer">Material ilustrativo. Payoff aproximado no vencimento, sem carrego/juros/cupons. Não constitui oferta, recomendação ou garantia de rentabilidade.</p>
    <p class="footer-alert"><strong>MATERIAL DE USO INTERNO, NÃO ENVIAR AOS CLIENTES</strong><br /><strong>PARA INFORMAÇÕES OFICIAIS, ACESSAR O DIE DA OPERAÇÃO DISPONIBILIZADO NO ADMIN BTG</strong></p>
  </div>

  <script>
    (function () {{
      var X_MIN = {x_min}, X_MAX = {x_max};
      var Y_MIN = {y_min}, Y_MAX = {y_max};
      var PAD = {{ l: 48, t: 24, r: 48, b: 24 }};
      var VW = 600, VH = 400;
      var PLOT_W = VW - PAD.l - PAD.r;
      var PLOT_H = VH - PAD.t - PAD.b;
      var DOWN_VAR = {down_var}, UP_VAR = {up_var}, FLOOR = {floor}, CAP = {cap};
      {js_research}

      function structureReturn(x) {{
        if (x <= DOWN_VAR) return x;
        if (x >= UP_VAR) return CAP;
        return Math.max(Math.abs(x), FLOOR);
      }}
      function regimeFor(x) {{
        if (x <= DOWN_VAR) return "Barreira de queda (≤ −30% / spot 70%): perde proteção reforçada — acompanha o ativo.";
        if (x >= UP_VAR) return "Barreira alta (≥ +53% / spot 153%): aplica strike 110% — retorno limitado a +10%.";
        return "Entre as barreiras: twin com piso +10% (proteção 110%).";
      }}
      function fmtPct(n, digits) {{
        if (digits == null) digits = 1;
        var sign = n > 0 ? "+" : "";
        return sign + n.toFixed(digits).replace(".", ",") + "%";
      }}
      function xToSvg(x) {{ return PAD.l + ((x - X_MIN) / (X_MAX - X_MIN)) * PLOT_W; }}
      function yToSvg(y) {{
        var yy = Math.max(Y_MIN, Math.min(Y_MAX, y));
        return PAD.t + (1 - (yy - Y_MIN) / (Y_MAX - Y_MIN)) * PLOT_H;
      }}
      function svgToX(px) {{ return X_MIN + ((px - PAD.l) / PLOT_W) * (X_MAX - X_MIN); }}

      function placeResearchMarker() {{
        if (RESEARCH_X == null) return;
        var x = Math.max(X_MIN, Math.min(X_MAX, RESEARCH_X));
        var px = xToSvg(x);
        var line = document.getElementById("researchTargetLine");
        var lab = document.getElementById("researchTargetLabel");
        if (!line || !lab) return;
        line.setAttribute("x1", px); line.setAttribute("x2", px); line.setAttribute("opacity", "1");
        lab.setAttribute("x", Math.min(VW - PAD.r - 8, px + 6));
        lab.setAttribute("y", PAD.t + 14);
        lab.textContent = "PA Research " + fmtPct(RESEARCH_X, 1);
        lab.setAttribute("opacity", "1");
      }}

      function buildStructD() {{
        var d = "", first = true;
        function move(x, y) {{ first = true; add(x, y); }}
        function add(x, y) {{
          var cmd = first ? "M" : "L"; first = false;
          d += cmd + " " + xToSvg(x).toFixed(3) + " " + yToSvg(y).toFixed(3) + " ";
        }}
        // Follow asset below down barrier
        for (var x = X_MIN; x <= DOWN_VAR; x += 0.5) add(x, x);
        // Cliff into protected/twin zone
        move(DOWN_VAR + 0.01, structureReturn(DOWN_VAR + 0.01));
        for (var x2 = DOWN_VAR + 0.5; x2 < UP_VAR; x2 += 0.5) add(x2, structureReturn(x2));
        add(UP_VAR - 0.01, structureReturn(UP_VAR - 0.01));
        // Cap at up barrier
        move(UP_VAR, CAP);
        for (var x3 = UP_VAR + 0.5; x3 <= X_MAX; x3 += 0.5) add(x3, CAP);
        return d.trim();
      }}
      function buildAssetPoints() {{
        var pts = [];
        for (var x = X_MIN; x <= X_MAX; x += 1) {{
          var y = Math.max(Y_MIN, Math.min(Y_MAX, x));
          pts.push(xToSvg(x).toFixed(3) + "," + yToSvg(y).toFixed(3));
        }}
        return pts.join(" ");
      }}

      var grid = document.getElementById("gridLines");
      var yLabels = document.getElementById("yLabels");
      var xLabels = document.getElementById("xLabels");
      if (grid && yLabels && xLabels) {{
        grid.innerHTML = ""; yLabels.innerHTML = ""; xLabels.innerHTML = "";
        for (var y = -40; y <= 60; y += 10) {{
          var py = yToSvg(y);
          grid.innerHTML += '<line x1="48" y1="' + py + '" x2="552" y2="' + py + '"/>';
          yLabels.innerHTML += '<text x="42" y="' + (py + 3) + '">' + y + "%</text>";
        }}
        for (var x = -40; x <= 80; x += 20) {{
          var px = xToSvg(x);
          grid.innerHTML += '<line x1="' + px + '" y1="24" x2="' + px + '" y2="376"/>';
          xLabels.innerHTML += '<text x="' + px + '" y="392">' + x + "%</text>";
        }}
      }}
      document.getElementById("axisZeroX").setAttribute("x1", xToSvg(0));
      document.getElementById("axisZeroX").setAttribute("x2", xToSvg(0));
      document.getElementById("axisZeroY").setAttribute("y1", yToSvg(0));
      document.getElementById("axisZeroY").setAttribute("y2", yToSvg(0));
      document.getElementById("structPath").setAttribute("d", buildStructD());
      document.getElementById("assetPath").setAttribute("points", buildAssetPoints());
      placeResearchMarker();

      var dX = xToSvg(DOWN_VAR), uX = xToSvg(UP_VAR);
      document.getElementById("downGap").setAttribute("x1", dX);
      document.getElementById("downGap").setAttribute("x2", dX);
      document.getElementById("downGap").setAttribute("y1", yToSvg(DOWN_VAR));
      document.getElementById("downGap").setAttribute("y2", yToSvg(FLOOR));
      document.getElementById("upGap").setAttribute("x1", uX);
      document.getElementById("upGap").setAttribute("x2", uX);
      document.getElementById("upGap").setAttribute("y1", yToSvg(UP_VAR));
      document.getElementById("upGap").setAttribute("y2", yToSvg(CAP));
      document.getElementById("downDot").setAttribute("cx", dX);
      document.getElementById("downDot").setAttribute("cy", yToSvg(FLOOR));
      document.getElementById("downLabel").setAttribute("x", dX + 8);
      document.getElementById("downLabel").setAttribute("y", yToSvg(FLOOR) - 8);
      document.getElementById("floorDot").setAttribute("cx", xToSvg(0));
      document.getElementById("floorDot").setAttribute("cy", yToSvg(FLOOR));
      document.getElementById("floorLabel").setAttribute("x", xToSvg(0) + 8);
      document.getElementById("floorLabel").setAttribute("y", yToSvg(FLOOR) - 8);
      document.getElementById("upDot").setAttribute("cx", uX);
      document.getElementById("upDot").setAttribute("cy", yToSvg(CAP));
      document.getElementById("upLabel").setAttribute("x", Math.max(48, uX - 80));
      document.getElementById("upLabel").setAttribute("y", yToSvg(CAP) - 10);

      var hoverLine = document.getElementById("hoverLine");
      var hoverStruct = document.getElementById("hoverStruct");
      var hoverAsset = document.getElementById("hoverAsset");
      var overlay = document.getElementById("chartOverlay");
      var tooltip = document.getElementById("tooltip");
      var svg = document.getElementById("payoffSvg");
      var slider = document.getElementById("spotSlider");
      var sliderMobile = document.getElementById("spotSliderMobile");
      var spotOut = document.getElementById("spotOut");
      var spotOutMobile = document.getElementById("spotOutMobile");
      var assetVal = document.getElementById("assetVal");
      var structVal = document.getElementById("structVal");
      var regimeText = document.getElementById("regimeText");
      var activePointer = null;

      function showAt(x) {{
        x = Math.max(X_MIN, Math.min(X_MAX, x));
        var ys = structureReturn(x);
        var sx = xToSvg(x), sy = yToSvg(ys), ay = yToSvg(Math.max(Y_MIN, Math.min(Y_MAX, x)));
        hoverLine.setAttribute("x1", sx); hoverLine.setAttribute("x2", sx); hoverLine.setAttribute("visibility", "visible");
        hoverStruct.setAttribute("cx", sx); hoverStruct.setAttribute("cy", sy); hoverStruct.setAttribute("visibility", "visible");
        hoverAsset.setAttribute("cx", sx); hoverAsset.setAttribute("cy", ay); hoverAsset.setAttribute("visibility", "visible");
        tooltip.innerHTML = '<div class="t-title">Spot final ' + fmtPct(x) + "</div>" +
          '<div class="row"><span>ITUB4</span><strong>' + fmtPct(x) + "</strong></div>" +
          '<div class="row"><span>Estrutura</span><strong>' + fmtPct(ys) + "</strong></div>";
        tooltip.classList.add("on");
        var svgRect = svg.getBoundingClientRect();
        tooltip.style.left = Math.max(70, Math.min(svgRect.width - 70, sx * svgRect.width / VW)) + "px";
        tooltip.style.top = Math.max(40, sy * svgRect.height / VH) + "px";
        if (slider) slider.value = String(x);
        if (sliderMobile) sliderMobile.value = String(x);
        var label = fmtPct(x, x % 1 === 0 ? 0 : 1);
        if (spotOut) spotOut.textContent = label;
        if (spotOutMobile) spotOutMobile.textContent = label;
        if (assetVal) {{ assetVal.textContent = fmtPct(x); assetVal.className = "val " + (x > 0 ? "pos" : x < 0 ? "neg" : ""); }}
        if (structVal) {{ structVal.textContent = fmtPct(ys); structVal.className = "val " + (ys > 0 ? "pos" : ys < 0 ? "neg" : ""); }}
        if (regimeText) regimeText.textContent = regimeFor(x);
      }}
      function clientToSvgX(clientX) {{
        var rect = svg.getBoundingClientRect();
        if (!rect.width) return 0;
        return svgToX(((clientX - rect.left) / rect.width) * VW);
      }}
      function updateFromEvent(e) {{ showAt(clientToSvgX(e.clientX)); }}
      overlay.addEventListener("pointerdown", function (e) {{ activePointer = e.pointerId; overlay.setPointerCapture(e.pointerId); updateFromEvent(e); }});
      overlay.addEventListener("pointermove", function (e) {{
        if (activePointer !== null && e.pointerId !== activePointer) return;
        if (e.pointerType === "mouse" || activePointer !== null) updateFromEvent(e);
      }});
      function endPointer(e) {{
        if (activePointer !== null && e.pointerId !== activePointer) return;
        activePointer = null;
        try {{ overlay.releasePointerCapture(e.pointerId); }} catch (err) {{}}
      }}
      overlay.addEventListener("pointerup", endPointer);
      overlay.addEventListener("pointercancel", endPointer);
      overlay.addEventListener("pointerleave", function (e) {{
        if (e.pointerType === "mouse" && activePointer === null) {{
          hoverLine.setAttribute("visibility", "hidden");
          hoverStruct.setAttribute("visibility", "hidden");
          hoverAsset.setAttribute("visibility", "hidden");
          tooltip.classList.remove("on");
        }}
      }});
      function onSliderInput(e) {{ showAt(Number(e.target.value)); }}
      if (slider) slider.addEventListener("input", onSliderInput);
      if (sliderMobile) {{ sliderMobile.addEventListener("input", onSliderInput); sliderMobile.addEventListener("change", onSliderInput); }}
      var btnPa = document.getElementById("btnResearchTarget");
      if (btnPa && RESEARCH_X != null) {{
        btnPa.addEventListener("click", function () {{ showAt(RESEARCH_X); }});
      }} else if (btnPa) {{
        btnPa.disabled = true;
      }}
      showAt(20);
    }})();
  </script>
</body>
</html>
"""



def research_pills(rs: dict, prat) -> str:
    extra = ""
    if rs.get("rec_lbl"):
        extra += f'<span class="pill">Research: {rs["rec_lbl"]}</span>'
    if rs.get("target") is not None:
        extra += f'<span class="pill">PA: {prat.fmt_brl(rs["target"])}</span>'
    return extra


def hub_html(research: dict, prat) -> str:
    """Hub Operações dia D — mesma dinâmica da prateleira semanal (cards → seções)."""
    sections = [
        (
            "Câmbio e renda fixa",
            "cambio",
            "#0d6e6e",
            "FX e hedge de duration",
            [
                {
                    "href": "../ops/ptax-call-up-out-ko/index.html",
                    "title": "Call Up and Out PTAX",
                    "ticker": "PTAX",
                    "brand": "#0d6e6e",
                    "blurb": "Call KO 110% · participa da alta até a barreira; no KO líquido +2% (rebate 5% − preço 3%).",
                    "pills": ["Câmbio", "Fixing 26/10", "Preço 3%", "Rebate 5%"],
                    "research": {},
                },
                {
                    "href": "../ops/pacb11-put-hedge/index.html",
                    "title": "Put ATM PACB11",
                    "ticker": "PACB11",
                    "brand": "#2f6b5a",
                    "blurb": "Compra de put ATM para hedge de duration (NTN-Bs / PACB11). Prazo 1 ano · prêmio 2,9%.",
                    "pills": ["Renda fixa / ETF", "1 ano", "Prêmio 2,9%", "ATM"],
                    "research": {},
                },
            ],
        ),
        (
            "Smart Hedge",
            "smart-hedge",
            "#1e4d7b",
            "Participação 1:1 com piso e teto na barreira",
            [
                {
                    "href": f"../ops/{cfg['slug']}/index.html",
                    "title": f"Smart Hedge {cfg['name']}",
                    "ticker": cfg["ticker"],
                    "brand": cfg["brand"],
                    "blurb": (
                        f"Proteção {fmt_br(cfg['put'])}% · strike {fmt_br(cfg['call'])}% · "
                        f"barreira {fmt_br(cfg['barrier'])}% · prazo {cfg['prazo']}."
                    ),
                    "pills": [
                        "Equity",
                        cfg["prazo"],
                        f"Prot. {fmt_br(cfg['put'])}%",
                        f"Barreira {fmt_br(cfg['barrier'])}%",
                    ],
                    "research": research.get(cfg["ticker"]) or {},
                }
                for cfg in OPS
            ],
        ),
        (
            "Twin Coupon",
            "twin-coupon",
            "#ec7000",
            "Twin com proteção reforçada e barreiras",
            [
                {
                    "href": "../ops/twin-coupon-itub4/index.html",
                    "title": "Twin Coupon Itaú",
                    "ticker": "ITUB4",
                    "brand": "#ec7000",
                    "blurb": "Proteção 110% · barreira de queda 70% · strike 110% · barreira 153% · prazo 2 anos.",
                    "pills": ["Equity", "2 anos", "Prot. 110%", "Down 70% · Up 153%"],
                    "research": research.get("ITUB4") or {},
                },
            ],
        ),
    ]

    cat_cards = []
    sections_html = []
    for title, sid, color, blurb, items in sections:
        tickers = ", ".join(dict.fromkeys(it["ticker"] for it in items))
        n = len(items)
        cat_cards.append(
            f"""
<button type="button" class="cat-card" data-target="{sid}" style="--cat:{color}">
  <span class="cat-bar"></span>
  <span class="cat-body">
    <span class="cat-title">{title}</span>
    <span class="cat-count">{n} operaç{"ão" if n == 1 else "ões"}</span>
    <span class="cat-blurb">{blurb}</span>
    <span class="cat-tickers">{tickers}</span>
  </span>
</button>"""
        )
        ops = []
        for it in items:
            pills = "".join(f'<span class="pill">{p}</span>' for p in it["pills"])
            pills += research_pills(it.get("research") or {}, prat)
            ops.append(
                f"""
<li class="op-block">
  <div class="op-bar" style="background:{it['brand']}"></div>
  <a class="op" href="{it['href']}">
    <div class="op-top"><span class="op-title">{it['title']}</span><span class="op-ticker">{it['ticker']}</span></div>
    <p class="op-blurb">{it['blurb']}</p>
    <div class="op-meta">{pills}</div>
    <div class="op-cta">Abrir material →</div>
  </a>
</li>"""
            )
        sections_html.append(
            f"""
<section class="cat-section" id="{sid}" hidden>
  <div class="cat-section-head">
    <h2>{title}</h2>
    <button type="button" class="cat-back" data-back>← Voltar aos cards</button>
  </div>
  <ul class="ops">{''.join(ops)}</ul>
</section>"""
        )

    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Operações dia D — Distribuição Renda Variável | BTG Pactual</title>
  <style>
    :root {{
      --btg: #0b1f3a; --btg-mid: #163a5f; --btg-blue: #1e4d7b; --link: #1a66b3;
      --ink: #0b1f3a; --muted: #5c6b7a; --line: #d0d8e2; --bg: #eef2f6; --card: #ffffff;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: Segoe UI, -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif; color: var(--ink); background: var(--bg); min-height: 100vh; line-height: 1.45; }}
    .hero {{ background: linear-gradient(135deg, var(--btg) 0%, var(--btg-mid) 55%, var(--btg-blue) 100%); color: #fff; padding: 36px 24px 40px; }}
    .hero-inner {{ max-width: 960px; margin: 0 auto; }}
    .logo-btg {{ display: inline-block; font-weight: 700; font-size: 12px; letter-spacing: 0.1em; border: 1px solid rgba(255,255,255,0.35); padding: 7px 12px; border-radius: 2px; margin-bottom: 22px; }}
    .hero-row {{ display: flex; justify-content: space-between; align-items: flex-end; gap: 24px; }}
    h1 {{ font-size: clamp(28px, 4.5vw, 40px); font-weight: 700; letter-spacing: -0.02em; line-height: 1.15; }}
    .lede {{ margin-top: 12px; font-size: 15px; color: rgba(255,255,255,.82); max-width: 40em; }}
    .lede-strong {{ display: inline; font-size: 18px; font-weight: 700; color: #fff; }}
    .badge {{ font-size: 11px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; border: 1px solid rgba(255,255,255,0.35); padding: 8px 12px; border-radius: 2px; white-space: nowrap; }}
    .page {{ max-width: 960px; margin: 0 auto; padding: 28px 24px 56px; }}
    .cat-grid {{ display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; margin-bottom: 8px; }}
    .cat-card {{ appearance: none; border: 1px solid var(--line); background: var(--card); border-radius: 6px; overflow: hidden; text-align: left; cursor: pointer; padding: 0; display: flex; flex-direction: column; transition: transform .12s ease, box-shadow .12s ease, border-color .12s; }}
    .cat-card:hover, .cat-card:focus-visible {{ transform: translateY(-2px); box-shadow: 0 8px 20px rgba(11,31,58,.08); border-color: #b8c6d6; outline: none; }}
    .cat-card.active {{ border-color: var(--cat); box-shadow: 0 0 0 2px color-mix(in srgb, var(--cat) 28%, transparent); }}
    .cat-bar {{ display: block; height: 6px; background: var(--cat); }}
    .cat-body {{ display: flex; flex-direction: column; gap: 6px; padding: 16px 18px 18px; }}
    .cat-title {{ font-size: 17px; font-weight: 700; color: var(--btg); }}
    .cat-count {{ font-size: 11px; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; color: var(--cat); }}
    .cat-blurb {{ font-size: 13px; color: var(--muted); line-height: 1.4; }}
    .cat-tickers {{ font-size: 11px; color: #7a8796; line-height: 1.35; margin-top: 2px; }}
    .cat-section-head {{ display: flex; justify-content: space-between; align-items: center; gap: 12px; margin: 8px 0 14px; }}
    .cat-section h2 {{ font-size: 12px; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: var(--btg-blue); margin: 0; }}
    .cat-back {{ appearance: none; border: 1px solid var(--line); background: #fff; color: var(--link); font-size: 12px; font-weight: 700; padding: 8px 12px; border-radius: 4px; cursor: pointer; }}
    .cat-back:hover {{ background: #f5f8fc; }}
    .ops {{ list-style: none; display: flex; flex-direction: column; gap: 16px; }}
    .op-block {{ background: var(--card); border: 1px solid var(--line); border-radius: 4px; overflow: hidden; }}
    .op-bar {{ height: 6px; }}
    .op {{ display: block; text-decoration: none; color: inherit; padding: 20px 22px 18px; transition: background .12s; }}
    .op:hover, .op:focus-visible {{ background: #f5f8fc; outline: none; }}
    .op-top {{ display: flex; justify-content: space-between; align-items: baseline; gap: 12px; margin-bottom: 8px; }}
    .op-title {{ font-size: 18px; font-weight: 700; color: var(--btg); }}
    .op-ticker {{ font-size: 12px; font-weight: 700; color: var(--link); letter-spacing: 0.04em; }}
    .op-blurb {{ font-size: 14px; color: var(--muted); max-width: 48em; }}
    .op-meta {{ margin-top: 12px; display: flex; flex-wrap: wrap; gap: 8px; }}
    .pill {{ background: #eef2f6; border: 1px solid var(--line); border-radius: 2px; padding: 4px 10px; color: var(--btg-mid); font-size: 11px; font-weight: 600; }}
    .op-cta {{ margin-top: 12px; font-size: 12px; font-weight: 700; color: var(--link); }}
    .footer {{ margin-top: 32px; padding-top: 16px; border-top: 1px solid var(--line); font-size: 11px; color: var(--muted); text-align: center; line-height: 1.55; }}
    .footer strong {{ display: block; margin-top: 10px; color: var(--btg); }}
    @media (max-width: 720px) {{ .cat-grid {{ grid-template-columns: 1fr; }} }}
    @media (max-width: 640px) {{ .hero {{ padding: 28px 16px 32px; }} .page {{ padding: 20px 16px 48px; }} .hero-row {{ flex-direction: column; align-items: flex-start; }} .cat-section-head {{ flex-direction: column; align-items: flex-start; }} }}
  </style>
</head>
<body>
  <header class="hero">
    <div class="hero-inner">
      <div class="logo-btg">BTG PACTUAL</div>
      <div class="hero-row">
        <div>
          <h1>Operações dia D</h1>
          <p class="lede"><span class="lede-strong">Distribuição Renda Variável</span> · escolha um card para ver as operações</p>
        </div>
        <div class="badge">Uso interno</div>
      </div>
    </div>
  </header>
  <main class="page">
    <div class="cat-grid" id="catGrid">{''.join(cat_cards)}</div>
    {''.join(sections_html)}
    <p class="footer">
      Material ilustrativo para uso interno. Não constitui oferta, recomendação ou garantia de rentabilidade.
      <strong>MATERIAL DE USO INTERNO, NÃO ENVIAR AOS CLIENTES</strong>
    </p>
  </main>
<script>
(function(){{
  var grid=document.getElementById('catGrid');
  var cards=[].slice.call(document.querySelectorAll('.cat-card'));
  var sections=[].slice.call(document.querySelectorAll('.cat-section'));
  function show(id){{
    cards.forEach(function(c){{ c.classList.toggle('active', c.getAttribute('data-target')===id); }});
    sections.forEach(function(s){{
      var on=s.id===id;
      if(on) s.removeAttribute('hidden'); else s.setAttribute('hidden','');
    }});
    if(id){{
      grid.style.display='none';
      var el=document.getElementById(id);
      if(el) el.scrollIntoView({{behavior:'smooth',block:'start'}});
      history.replaceState(null,'','#'+id);
    }} else {{
      grid.style.display='';
      history.replaceState(null,'',location.pathname);
      window.scrollTo({{top:0,behavior:'smooth'}});
    }}
  }}
  cards.forEach(function(c){{
    c.addEventListener('click',function(){{ show(c.getAttribute('data-target')); }});
  }});
  document.querySelectorAll('[data-back]').forEach(function(b){{
    b.addEventListener('click',function(){{ show(null); }});
  }});
  var hash=(location.hash||'').replace('#','');
  if(hash && document.getElementById(hash)) show(hash);
}})();
</script>
</body>
</html>
"""



OPS = [
    {
        "slug": "smart-hedge-vale3",
        "ticker": "VALE3",
        "name": "Vale",
        "brand": "#007e33",
        "brand_soft": "rgba(0,126,51,0.12)",
        "put": 110.0,
        "call": 110.0,
        "barrier": 174.35,
        "prazo": "2 anos",
        "initials": "VA",
    },
    {
        "slug": "smart-hedge-petr4",
        "ticker": "PETR4",
        "name": "Petrobras",
        "brand": "#00665b",
        "brand_soft": "rgba(0,102,91,0.12)",
        "put": 100.0,
        "call": 110.0,
        "barrier": 134.0,
        "prazo": "1 ano",
        "initials": "PE",
    },
    {
        "slug": "smart-hedge-axia3",
        "ticker": "AXIA3",
        "name": "Axia",
        "brand": "#5a4a8a",
        "brand_soft": "rgba(90,74,138,0.12)",
        "put": 100.0,
        "call": 110.0,
        "barrier": 135.0,
        "prazo": "1 ano",
        "initials": "AX",
    },
    {
        "slug": "smart-hedge-roxo34",
        "ticker": "ROXO34",
        "name": "Nubank",
        "brand": "#820ad1",
        "brand_soft": "rgba(130,10,209,0.12)",
        "put": 90.0,
        "call": 104.0,
        "barrier": 137.5,
        "prazo": "6 meses",
        "initials": "NU",
    },
    {
        "slug": "smart-hedge-itub4",
        "ticker": "ITUB4",
        "name": "Itaú",
        "brand": "#ec7000",
        "brand_soft": "rgba(236,112,0,0.12)",
        "put": 90.0,
        "call": 104.0,
        "barrier": 128.0,
        "prazo": "6 meses",
        "initials": "IT",
    },
]


if __name__ == "__main__":
    prat = load_prat()
    tickers = [cfg["ticker"] for cfg in OPS] + ["ITUB4"]
    try:
        research = prat.fetch_research(tickers)
    except Exception as exc:
        print("research_fail", exc)
        snap = ROOT / "prateleira" / "research_targets.json"
        research = json.loads(snap.read_text(encoding="utf-8")) if snap.exists() else {}

    for cfg in OPS:
        cfg = dict(cfg)
        cfg["research"] = research.get(cfg["ticker"]) or {}
        write(f"ops/{cfg['slug']}/index.html", smart_hedge_html(cfg, prat))

    twin_rs = research.get("ITUB4") or {}
    write("ops/twin-coupon-itub4/index.html", twin_coupon_html(prat, twin_rs))
    write("prateleira-tatica/index.html", hub_html(research, prat))
    print("done")
