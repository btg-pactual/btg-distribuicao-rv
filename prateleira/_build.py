# -*- coding: utf-8 -*-
"""Build Prateleira Tática hub + operation pages."""
from __future__ import annotations

import json
import math
import re
import shutil
import ssl
import unicodedata
import urllib.error
import urllib.request
from datetime import date, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
OPS = ROOT / "ops"
REF = date(2026, 9, 1)
PDF_NAME = "Material-Prateleira-Tatica-31082026.pdf"
RESEARCH_REC = "https://content.btgpactual.com/api/research/content-hub/recommendations/ticker/{ticker}?includeInstitutionalData=true"
RESEARCH_QUOTES = "https://content.btgpactual.com/api/research/research/public/asset/quotes"
RESEARCH_SUMMARY = "https://content.btgpactual.com/api/research/content-hub-assets/v1/asset/summary/{ticker}"
RESEARCH_PAGE = "https://content.btgpactual.com/research/ativo/{ticker}"
RESEARCH_SNAP = ROOT / "research_targets.json"
SSL_CTX = ssl.create_default_context()
HTTP_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
    "Origin": "https://content.btgpactual.com",
    "Referer": "https://content.btgpactual.com/research/home/acoes",
    "Content-Type": "application/json",
}


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


def fmt_brl(n: float) -> str:
    s = f"{n:,.2f}"
    return "R$ " + s.replace(",", "X").replace(".", ",").replace("X", ".")


def fmt_pct(n: float) -> str:
    s = f"{n:.2f}".replace(".", ",")
    return f"+{s}%" if n > 0 else f"{s}%"


def rec_label(raw: str | None) -> str:
    if not raw:
        return ""
    key = raw.strip().upper()
    return {
        "COMPRA": "Compra",
        "NEUTRO": "Neutro",
        "VENDA": "Venda",
        "REVISAO": "Em revisão",
        "REVISÃO": "Em revisão",
    }.get(key, raw.title())


def fmt_date(raw) -> str:
    if not raw:
        return ""
    try:
        dt = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        return dt.strftime("%d/%m/%Y")
    except ValueError:
        return ""


def html_esc(s: str) -> str:
    return (
        str(s)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def rec_class(raw: str | None) -> str:
    key = (raw or "").strip().upper()
    if key == "COMPRA":
        return "buy"
    if key == "VENDA":
        return "sell"
    if key in {"NEUTRO", "REVISAO", "REVISÃO"}:
        return "hold"
    return ""


def summary_bullets(text: str, n: int = 3) -> list[str]:
    """Extrai até n bullets a partir do Insights BTG (fullSummary)."""
    text = re.sub(r"\s+", " ", (text or "").strip())
    if not text:
        return []

    parts = [p.strip(" ;.") for p in text.split(";") if p.strip()]
    if len(parts) < n:
        parts = re.split(r"(?<=[.!?])\s+(?=[A-ZÀ-Ü])", text)
        parts = [p.strip(" ;.") for p in parts if p.strip()]

    bullets: list[str] = []
    for part in parts:
        if len(part) < 35:
            continue
        if len(part) > 240:
            cut = part[:237].rsplit(" ", 1)[0].rstrip(",;:")
            part = cut + "…"
        if part and part[0].islower():
            part = part[0].upper() + part[1:]
        if not part.endswith((".", "…", "!", "?")):
            part += "."
        bullets.append(part)
        if len(bullets) >= n:
            break
    return bullets


def _http_json(url: str, payload: object | None = None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=HTTP_HEADERS, method="GET" if data is None else "POST")
    with urllib.request.urlopen(req, timeout=25, context=SSL_CTX) as resp:
        raw = resp.read()
        if not raw:
            return None
        return json.loads(raw.decode("utf-8"))


def fetch_research(tickers: list[str]) -> dict[str, dict]:
    uniq = list(dict.fromkeys(tickers))
    quotes: dict[str, dict] = {}
    try:
        rows = _http_json(RESEARCH_QUOTES, uniq) or []
        for row in rows:
            t = str(row.get("ticker") or "").upper()
            if t and row.get("price") is not None:
                quotes[t] = {
                    "price": float(row["price"]),
                    "last_trade": row.get("lastTrade"),
                }
    except Exception as exc:
        print("research_quotes_fail", exc)

    out: dict[str, dict] = {}
    for t in uniq:
        q = quotes.get(t) or {}
        item: dict = {
            "ticker": t,
            "url": RESEARCH_PAGE.format(ticker=t),
            "price": q.get("price"),
            "last_trade": q.get("last_trade"),
        }
        try:
            rec = _http_json(RESEARCH_REC.format(ticker=t))
        except urllib.error.HTTPError as exc:
            rec = None
            item["http"] = exc.code
        except Exception as exc:
            rec = None
            item["error"] = str(exc)
        if rec and rec.get("recommendation"):
            item["rec"] = rec.get("recommendation")
            item["rec_lbl"] = rec_label(rec.get("recommendation"))
            item["rec_cls"] = rec_class(rec.get("recommendation"))
            item["date"] = rec.get("recommendationDate")
            item["company"] = (rec.get("asset") or {}).get("company")
            try:
                item["target"] = float(rec.get("targetPrice"))
            except (TypeError, ValueError):
                item["target"] = None
            try:
                summary = _http_json(RESEARCH_SUMMARY.format(ticker=t)) or {}
                bullets = summary_bullets(summary.get("fullSummary") or "")
                if bullets:
                    item["bullets"] = bullets
                    item["summary_date"] = summary.get("summaryGenerationDate")
            except Exception as exc:
                item["summary_error"] = str(exc)
        price = item.get("price")
        target = item.get("target")
        if price and target:
            item["upside"] = (target / price - 1.0) * 100.0
        out[t] = item

    RESEARCH_SNAP.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    n_ok = sum(1 for v in out.values() if v.get("target"))
    n_bullets = sum(1 for v in out.values() if v.get("bullets"))
    print("research", n_ok, "/", len(uniq), "bullets", n_bullets)
    return out


def research_html(cfg: dict) -> str:
    t = cfg["ticker"]
    rs = cfg.get("research") or {}
    url = rs.get("url") or RESEARCH_PAGE.format(ticker=t)
    cells = []
    if rs.get("price") is not None:
        cells.append(("Preço atual", fmt_brl(rs["price"]), ""))
    rec_lbl = rs.get("rec_lbl")
    if rec_lbl:
        cells.append(("Recomendação", rec_lbl, rs.get("rec_cls") or ""))
    if rs.get("target") is not None:
        cells.append(("Preço-alvo", fmt_brl(rs["target"]), ""))
    if rs.get("upside") is not None:
        up = rs["upside"]
        cls = "buy" if up > 0 else ("sell" if up < 0 else "")
        cells.append(("Potencial", fmt_pct(up), cls))
    if not cells:
        body = '<p class="research-note">Sem cobertura de preço-alvo no Research BTG para este ticker.</p>'
    else:
        grid = "".join(
            f'<div><div class="lbl">{lab}</div><div class="val {cls}">{val}</div></div>'
            for lab, val, cls in cells
        )
        bits = []
        spot_d = fmt_date(rs.get("last_trade"))
        alvo_d = fmt_date(rs.get("date"))
        if spot_d:
            bits.append(f"Spot do fechamento anterior ({spot_d})")
        else:
            bits.append("Spot do fechamento anterior")
        if not rs.get("target"):
            bits.append("sem preço-alvo publicado para este ticker")
        elif alvo_d:
            bits.append(f"alvo em {alvo_d}")
        bits.append("atualizado às 18h30 · fonte Research BTG")
        note = f'<p class="research-note">{ " · ".join(bits) }.</p>'
        bullets_html = ""
        bullets = rs.get("bullets") or []
        if bullets:
            lis = "".join(f"<li>{html_esc(b)}</li>" for b in bullets)
            sum_d = fmt_date(rs.get("summary_date"))
            sum_note = f"Insights BTG{f' · {sum_d}' if sum_d else ''}."
            bullets_html = (
                f'<ul class="research-bullets">{lis}</ul>'
                f'<p class="research-note">{sum_note}</p>'
            )
        btn = ""
        if rs.get("upside") is not None:
            btn = (
                '<div class="research-actions">'
                '<button type="button" class="research-btn" id="btnResearchTarget">'
                "Ver preço-alvo no gráfico"
                "</button></div>"
            )
        body = f'<div class="research-grid">{grid}</div>{note}{bullets_html}{btn}'
    return f"""
<section class="research">
  <div class="research-head">
    <h2>Research BTG</h2>
    <a href="{url}" target="_blank" rel="noopener">Abrir {t} no Research →</a>
  </div>
  {body}
</section>
"""


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
.research{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin-bottom:18px}
.research-head{display:flex;justify-content:space-between;align-items:baseline;gap:12px;margin-bottom:12px;flex-wrap:wrap}
.research-head h2{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--brand);margin:0}
.research-head a{color:#1a66b3;font-weight:700;text-decoration:none;font-size:13px}
.research-head a:hover{text-decoration:underline}
.research-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
.research-grid .lbl{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);margin-bottom:4px}
.research-grid .val{font-size:18px;font-weight:700}
.research-grid .val.buy{color:var(--success)}
.research-grid .val.hold{color:#b8860b}
.research-grid .val.sell{color:var(--danger)}
.research-note{font-size:12px;color:var(--muted);margin-top:10px}
.research-bullets{margin:14px 0 0;padding:0;list-style:none;display:flex;flex-direction:column;gap:8px}
.research-bullets li{position:relative;padding:10px 12px 10px 28px;background:var(--bg);border:1px solid var(--line);border-radius:8px;font-size:13px;line-height:1.45;color:var(--ink)}
.research-bullets li::before{content:"";position:absolute;left:12px;top:16px;width:6px;height:6px;border-radius:50%;background:var(--brand)}
.research-actions{margin-top:12px}
.research-btn{appearance:none;border:1px solid var(--brand);background:#fff;color:var(--brand);font-size:12px;font-weight:700;padding:9px 14px;border-radius:8px;cursor:pointer}
.research-btn:hover{background:color-mix(in srgb,var(--brand) 8%,#fff)}
.research-btn:disabled{opacity:.45;cursor:not-allowed}
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
.zones{display:grid;grid-template-columns:repeat(2,1fr);gap:8px;margin-top:12px}
.zone{border:1px solid var(--line);border-radius:8px;padding:10px;background:var(--bg)}
.zone strong{display:block;font-size:12px;color:var(--brand);margin-bottom:4px}
.zone p{font-size:11px;color:var(--muted);line-height:1.4}
.sim-label{display:flex;justify-content:space-between;align-items:baseline;font-size:12px;color:var(--muted);margin-bottom:8px}
.sim-label output{font-weight:700;color:var(--ink);font-size:14px}
input[type=range]{width:100%;accent-color:var(--brand);margin-bottom:14px}
.sim-cards{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:12px}
.sim-card{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:12px}
.sim-card.wide{grid-column:1 / -1}
.sim-card .lbl{font-size:11px;color:var(--muted);margin-bottom:4px}
.sim-card .val{font-size:18px;font-weight:700}
.matrix-wrap{margin-top:16px}
.matrix-wrap h2{margin-top:4px}
.matrix-note{font-size:11px;color:var(--muted);margin:0 0 10px;line-height:1.4}
.sim-card .val.pos{color:var(--success)}
.sim-card .val.neg{color:var(--danger)}
.regime{font-size:12px;color:var(--ink);background:#fff7ef;border:1px solid #f0d4b8;border-radius:8px;padding:10px 12px;line-height:1.45}
.speech-box{margin-top:22px;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:22px 24px;border-top:3px solid var(--brand)}
.speech-box h2{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--brand);margin-bottom:14px}
.speech-label{font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--brand);margin:14px 0 6px}
.speech-box p{font-size:14px;color:var(--ink);max-width:70em}
.footer{margin-top:28px;font-size:11px;color:var(--muted);text-align:center;line-height:1.55}
.footer-alert{margin-top:10px;text-align:center;font-size:11px;color:var(--btg);font-weight:700}
@media (max-width:1100px){.main{grid-template-columns:1fr}.highlights,.research-grid{grid-template-columns:1fr 1fr}}
@media (max-width:640px){.page{padding:16px 14px 40px}.topbar{flex-direction:column}.meta-pills{justify-content:flex-start}.highlights{grid-template-columns:1fr}.zones{grid-template-columns:1fr}}
@media (min-width:1101px){.mobile-sim{display:none}}
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
    rs = cfg.get("research") or {}
    research_x = rs.get("upside")
    if research_x is None:
        js_research = "var RESEARCH_X=null;"
    else:
        js_research = f"var RESEARCH_X={float(research_x):.4f};"
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
{cfg.get('research_html', '')}
<div class="main">
<aside class="panel">
  <h2>Estrutura</h2>
  <table class="struct-table"><thead><tr><th>Perna</th><th>Nível</th></tr></thead><tbody>{rows}</tbody></table>
  <p class="legend-note">Payoff ilustrativo no vencimento. Condições oficiais no DIE.</p>
</aside>
<section class="panel chart-panel">
  <div class="chart-head">
    <div><h2>Payoff ilustrativo</h2><p class="chart-caption">Retorno vs. variação do ativo</p></div>
    <div class="chart-legend"><span><i class="swatch"></i> Estrutura</span><span><i class="swatch asset"></i> Ativo</span><span><i class="swatch" style="background:#1a66b3;border-top:none;height:2px;background:repeating-linear-gradient(90deg,#1a66b3 0 4px,transparent 4px 7px)"></i> PA Research</span></div>
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
      <line id="putKoGap" x1="0" y1="0" x2="0" y2="0" stroke="#0f7a4a" stroke-width="2" stroke-dasharray="4 3" opacity="0"/>
      <line id="callKoGap" x1="0" y1="0" x2="0" y2="0" stroke="{brand}" stroke-width="2" stroke-dasharray="4 3" opacity="0"/>
      <text id="putKoLabel" font-size="11" fill="#0f7a4a" font-weight="700" opacity="0">Put KO</text>
      <text id="callKoLabel" font-size="11" fill="{brand}" font-weight="700" opacity="0">Call vendida</text>
      <line id="researchTargetLine" x1="0" y1="24" x2="0" y2="376" stroke="#1a66b3" stroke-width="1.5" stroke-dasharray="5 4" opacity="0"/>
      <text id="researchTargetLabel" font-size="11" fill="#1a66b3" font-weight="700" opacity="0">PA Research</text>
      <g id="xLabels"></g><g id="yLabels"></g>
      <line id="hoverLine" x1="0" y1="24" x2="0" y2="376" stroke="{brand}" stroke-width="1" opacity="0"/>
      <circle id="hoverStruct" r="5" fill="{brand}" opacity="0"/>
      <circle id="hoverAsset" r="4" fill="#8b83a0" opacity="0"/>
    </svg>
  </div>
  <p class="chart-touch-hint">Arraste no gráfico para simular</p>
      <div class="mobile-sim">
    <div class="sim-label"><span>Spot final</span><output id="spotOutMobile">0%</output></div>
    <input type="range" id="spotSliderMobile" min="{cfg.get('x_min', -50)}" max="{cfg.get('x_max', 80)}" step="0.5" value="0"/>
  </div>
  <div class="zones">{zones}</div>
</section>
<aside class="panel panel-sim">
  <h2>Simulador</h2>
  <div class="sim-label"><span>Variação do ativo</span><output id="spotOut">0%</output></div>
  <input type="range" id="spotSlider" min="{cfg.get('x_min', -50)}" max="{cfg.get('x_max', 80)}" step="0.5" value="0"/>
  <div class="sim-cards">
    <div class="sim-card"><div class="lbl">Ativo</div><div class="val" id="assetVal">0,0%</div></div>
    <div class="sim-card"><div class="lbl">{cfg.get('struct_lbl', 'Estrutura')}</div><div class="val" id="structVal">0,0%</div></div>
    {cfg.get('sim_extra_html', '')}
  </div>
  <div class="regime" id="regimeText">{cfg['regime0']}</div>
  {cfg.get('matrix_html', '')}
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
  var X_MIN={cfg.get('x_min', -50)},X_MAX={cfg.get('x_max', 80)},Y_MIN={cfg.get('y_min', -50)},Y_MAX={cfg.get('y_max', 80)};
  var PAD={{l:48,t:24,r:48,b:24}},VW=600,VH=400;
  var PLOT_W=VW-PAD.l-PAD.r,PLOT_H=VH-PAD.t-PAD.b;
  {js_research}
  {cfg['js_const']}
  function structureReturn(x){{ {cfg['js_fn']} }}
  function regimeFor(x){{ {cfg['js_regime']} }}
  function fmtPct(v,d){{ d=d==null?1:d; var s=v.toFixed(d).replace('.',','); return (v>0?'+':'')+s+'%'; }}
  function xToSvg(x){{ return PAD.l+((x-X_MIN)/(X_MAX-X_MIN))*PLOT_W; }}
  function yToSvg(y){{ return PAD.t+((Y_MAX-y)/(Y_MAX-Y_MIN))*PLOT_H; }}
  function svgToX(px){{ return X_MIN+((px-PAD.l)/PLOT_W)*(X_MAX-X_MIN); }}
  function placeResearchMarker(){{
    if (RESEARCH_X==null) return;
    var x=Math.max(X_MIN,Math.min(X_MAX,RESEARCH_X));
    var px=xToSvg(x);
    var line=document.getElementById('researchTargetLine');
    var lab=document.getElementById('researchTargetLabel');
    line.setAttribute('x1',px); line.setAttribute('x2',px); line.setAttribute('opacity','1');
    lab.setAttribute('x', Math.min(VW-PAD.r-8, px+6));
    lab.setAttribute('y', PAD.t+14);
    lab.textContent = 'PA Research '+fmtPct(RESEARCH_X,1);
    lab.setAttribute('opacity','1');
  }}
  function buildStructD(){{
    var d='',first=true;
    function add(x,y){{ var c=first?'M':'L'; first=false; d+=c+' '+xToSvg(x).toFixed(2)+' '+yToSvg(y).toFixed(2)+' '; }}
    function move(x,y){{ first=true; add(x,y); }}
    {cfg.get('js_build', 'for(var x=X_MIN;x<=X_MAX;x+=0.5) add(x, structureReturn(x));')}
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
  var yStep = Y_MAX - Y_MIN > 120 ? 40 : 20;
  var xStep = X_MAX - X_MIN > 120 ? 40 : 20;
  for(var y=Math.ceil(Y_MIN/yStep)*yStep;y<=Y_MAX;y+=yStep){{
    var py=yToSvg(y);
    grid.innerHTML+='<line x1="48" y1="'+py+'" x2="552" y2="'+py+'" stroke="#e8edf2"/>';
    yL.innerHTML+='<text x="42" y="'+(py+3)+'" font-size="11" text-anchor="end" fill="#5c6b7a">'+y+'%</text>';
  }}
  for(var x=Math.ceil(X_MIN/xStep)*xStep;x<=X_MAX;x+=xStep){{
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
  {"if (true) {" if cfg.get("ko_markers") else "if (false) {"}
    if (typeof L === 'number') {{
      var pL=document.getElementById('putKoGap'), pT=document.getElementById('putKoLabel');
      pL.setAttribute('x1', xToSvg(L)); pL.setAttribute('x2', xToSvg(L));
      pL.setAttribute('y1', yToSvg(L)); pL.setAttribute('y2', yToSvg(0));
      pL.setAttribute('opacity', '1');
      pT.setAttribute('x', xToSvg(L) + 6); pT.setAttribute('y', yToSvg(0) - 8);
      pT.textContent = 'Put KO · proteção 0%';
      pT.setAttribute('opacity', '1');
    }}
    if (typeof H === 'number') {{
      var cL=document.getElementById('callKoGap'), cT=document.getElementById('callKoLabel');
      var peakY = 2 * (H - 0.01);
      cL.setAttribute('x1', xToSvg(H)); cL.setAttribute('x2', xToSvg(H));
      cL.setAttribute('y1', yToSvg(peakY)); cL.setAttribute('y2', yToSvg(0));
      cL.setAttribute('opacity', '1');
      cT.setAttribute('x', Math.max(48, xToSvg(H) - 72)); cT.setAttribute('y', yToSvg(peakY) - 8);
      cT.textContent = 'Call vendida / KO';
      cT.setAttribute('opacity', '1');
    }}
  }}
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
    var pv=document.getElementById('premVal');
    if (pv && typeof COST === 'number' && COST !== 0) {{
      var rp = (ys / COST) * 100;
      pv.textContent = fmtPct(rp, 0);
      pv.className = 'val ' + (rp > 0 ? 'pos' : rp < 0 ? 'neg' : '');
    }}
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
    tip.innerHTML='<div class="t-title">Spot '+fmtPct(x)+'</div><div class="row"><span>Ativo</span><span>'+fmtPct(x)+'</span></div><div class="row"><span>{cfg.get('struct_lbl', 'Estrutura')}</span><span>'+fmtPct(ys)+'</span></div>'+(typeof COST==='number' && COST!==0 ? '<div class="row"><span>Sobre o prêmio</span><span>'+fmtPct((ys/COST)*100,0)+'</span></div>' : '');
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
  placeResearchMarker();
  var btnPa=document.getElementById('btnResearchTarget');
  if (btnPa && RESEARCH_X!=null) {{
    btnPa.addEventListener('click', function(){{
      showAt(RESEARCH_X);
      placeResearchMarker();
      var box=document.getElementById('chartBox');
      if (box) box.scrollIntoView({{behavior:'smooth',block:'center'}});
    }});
  }}
  showAt(0);
}})();
</script>
</body>
</html>
"""


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
        "pills": [("Ativo", t), ("Prazo", prazo), ("Put", f"{put:.0f}%"), ("Call", f"{call:.0f}%"), ("KI", f"{ki:.2f}%")],
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
            ("Como encaixa", f"Put {put:.0f}% · call {call:.0f}% KI em {ki:.2f}% · prazo {prazo}."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "x_min": min(-50, int(floor) - 15),
        "x_max": max(80, int(ki_var) + 25),
        "y_min": min(-50, int(floor) - 15),
        "y_max": max(80, int(ki_var) + 25, int(cap) + 20),
        "js_const": f"var PUT={put}, CALL={call}, KI={ki};",
        "js_fn": "var st=100+x; var r=st+Math.max(PUT-st,0)-(st>=KI?Math.max(st-CALL,0):0)-100; return r;",
        "js_regime": f"var st=100+x; if(st>=KI) return 'KI: teto {cap:+.0f}%.'; if(x<=(PUT-100)) return 'Piso da put.'; return 'Participa 1:1.';",
    }


def make_acel(t, fixing, ko_h, ko_l, bid):
    prazo = months_label(fixing)
    H, L = ko_h - 100, ko_l - 100
    peak = 2 * H  # pico 2× logo antes de atingir a call vendida
    slug = slugify("aceleradora", t, prazo.replace(" ", ""))
    return slug, {
        "title": f"Aceleradora {t}",
        "h1": "Aceleradora Dinâmica",
        "ticker": t,
        "dot": "AC",
        "brand": "#5a4a8a",
        "subtitle": (
            f"Ganho dobrado (2×) na alta enquanto não atingir a call vendida ({ko_h:.0f}%). "
            f"Ao atingir esse strike, a call KO (mesmo nível) nocauteia e vira pó — retorno 0%. "
            f"Proteção parcial na queda até a barreira {ko_l:.0f}%."
        ),
        "pills": [
            ("Ativo", t),
            ("Prazo", prazo),
            ("Alta", "2×"),
            ("Call vendida", f"{ko_h:.0f}%"),
            ("KO baixa", f"{ko_l:.0f}%"),
        ],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Alta", "2×", f"Enquanto não atingir call vendida {ko_h:.0f}%"),
            ("Se atingir", "0%", f"Call KO no strike {ko_h:.0f}% vira pó"),
            ("Proteção", "Parcial", f"Piso 0% até KO {ko_l:.0f}%; abaixo acompanha"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Call KO', f"100% · barreira {ko_h:.0f}%"),
            ('<span class="tag s">S</span> Call', f"{ko_h:.0f}%"),
            ('<span class="tag b">B</span> Put KO', f"100% · barreira {ko_l:.0f}%"),
        ],
        "zones": [
            (f"≤ {L:.0f}%", "Put KO nocauteada — acompanha o ativo."),
            (f"{L:.0f}% → 0%", "Proteção parcial: retorno 0%."),
            (f"0% → +{H:.0f}%", "Ganho dobrado: retorno = 2× a alta (ainda não atingiu a call vendida)."),
            (f"≥ +{H:.0f}%", f"Atingiu call vendida {ko_h:.0f}%: call KO vira pó → retorno 0%."),
        ],
        "regime0": f"Na alta até +{H:.0f}%: 2×. Se atingir a call vendida: call KO vira pó (0%).",
        "speech": [
            ("Para quem", f"Cliente tático em {t} ({prazo}) que quer ganho dobrado na alta com proteção parcial na queda."),
            (
                "Como encaixa",
                f"Aceleradora Dinâmica: 2× enquanto não atingir a call vendida {ko_h:.0f}%. "
                f"Ao atingir esse nível, a call KO no mesmo strike nocauteia e vira pó (retorno 0%). "
                f"Put KO {ko_l:.0f}%: piso 0% na queda moderada; abaixo do KO, acompanha o ativo.",
            ),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "x_min": min(-50, int(L) - 10),
        "x_max": max(80, int(H) + 30),
        "y_min": min(-50, int(L) - 10),
        "y_max": max(80, int(peak) + 20),
        "ko_markers": True,
        "js_const": f"var L={L}, H={H};",
        # Put KO viva (x > L): piso 0% na queda. Atingiu KO (x <= L): acompanha.
        # Alta 2× enquanto x < H; ao atingir call vendida: 0%.
        "js_fn": "if (x <= L) return x; if (x < 0) return 0; if (x < H) return 2*x; return 0;",
        "js_regime": (
            "if (x <= L) return 'Put KO atingida: perde a proteção e acompanha o ativo.'; "
            "if (x < 0) return 'Put KO viva: proteção até a barreira — piso 0%.'; "
            "if (x < H) return 'Alta acelerada: 2× (ainda não atingiu a call vendida).'; "
            "return 'Atingiu call vendida: call KO vira pó → 0%.';"
        ),
        # Path com cliffs explícitos na Put KO e na call vendida
        "js_build": """
    for (var x = X_MIN; x <= L; x += 0.5) add(x, x);
    add(L, 0);
    for (var x2 = L + 0.5; x2 <= 0; x2 += 0.5) add(x2, 0);
    for (var x3 = 0.5; x3 < H; x3 += 0.5) add(x3, 2 * x3);
    add(H - 0.01, 2 * (H - 0.01));
    move(H, 0);
    for (var x4 = H + 0.5; x4 <= X_MAX; x4 += 0.5) add(x4, 0);
""",
    }


def make_triplo(t, fixing, sold, ko_h, ko_l, bid):
    prazo = months_label(fixing)
    H, L, CAP = ko_h - 100, ko_l - 100, sold - 100
    peak = 3 * H
    slug = slugify("triplo", t, f"ki{int(ko_h)}", prazo.replace(" ", ""))
    return slug, {
        "title": f"Triplo Retorno KO {t}",
        "h1": "Triplo Retorno KO",
        "ticker": t,
        "dot": "3x",
        "brand": "#820ad1",
        "subtitle": f"3× na alta até a barreira, ganho na queda moderada, teto se KO de alta.",
        "pills": [("Ativo", t), ("Prazo", prazo), ("Teto", f"{CAP:+.0f}%"), ("KO alta", f"{ko_h:.0f}%"), ("KO baixa", f"{ko_l:.0f}%")],
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
            ("Como encaixa", f"Triplo KO · alta até {ko_h:.0f}% · queda até {ko_l:.0f}% · teto {CAP:+.0f}%."),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "x_min": min(-50, int(L) - 15),
        "x_max": max(80, int(H) + 30),
        "y_min": min(-50, int(L) - 15),
        "y_max": max(100, int(math.ceil(peak / 10.0) * 10) + 20),
        "js_const": f"var L={L}, H={H}, CAP={CAP};",
        "js_fn": "if (x < L) return x; if (x < 0) return -x; if (x < H) return 3*x; return CAP;",
        "js_regime": "if (x < L) return 'Abaixo do put KO: acompanha.'; if (x < 0) return 'Queda moderada: |x|.'; if (x < H) return 'Alta: 3×.'; return 'KO alta: teto.';",
    }


def make_call_ko():
    t, fixing = "PRIO3", date(2026, 10, 30)
    prazo = months_label(fixing)
    cost, rebate, ko = 3.80, 5.50, 21.0
    slug = slugify("call-ko-rebate", t, prazo.replace(" ", ""))

    def net_at(x: float) -> float:
        if x >= ko:
            return rebate - cost
        return max(x, 0.0) - cost

    def prem_at(x: float) -> float:
        return (net_at(x) / cost) * 100.0

    spots = [-10.0, 0.0, 5.0, 10.0, 15.0, 20.0, 21.0, 30.0, 40.0]
    matrix_rows = []
    for s in spots:
        n, p = net_at(s), prem_at(s)
        note = "KO · rebate" if s >= ko else ("OTM" if s <= 0 else "ITM")
        ns = f"{n:+.1f}".replace(".", ",")
        ps = f"{p:+.0f}"
        ss = f"{s:+.0f}"
        matrix_rows.append(
            f"<tr><td>{ss}%</td><td>{ns}%</td><td><strong>{ps}%</strong></td><td>{note}</td></tr>"
        )
    ko_net = rebate - cost
    ko_prem = (ko_net / cost) * 100
    ko_net_s = f"{ko_net:.2f}".replace(".", ",")
    cost_s = f"{cost:.2f}".replace(".", ",")

    matrix_html = f"""
  <div class="matrix-wrap">
    <h2>Matriz de ganho (só prêmio)</h2>
    <p class="matrix-note">
      Retorno <strong>sobre o prêmio pago ({cost_s}%)</strong> =
      (resultado no nocional ÷ {cost_s}%) × 100.
      No KO: líquido +{ko_net_s}% no nocional → <strong>+{ko_prem:.0f}%</strong> sobre o prêmio.
    </p>
    <table class="struct-table">
      <thead><tr><th>Spot</th><th>Nocional</th><th>Sobre prêmio</th><th></th></tr></thead>
      <tbody>
        {''.join(matrix_rows)}
      </tbody>
    </table>
  </div>
"""

    return slug, {
        "title": f"Call KO c/ Rebate {t}",
        "h1": "Call KO com Rebate",
        "ticker": t,
        "dot": "CK",
        "brand": "#c0392b",
        "subtitle": (
            f"Call up-and-out {t}: participa da alta até a barreira; no KO recebe rebate. "
            f"Matriz também em retorno % só sobre o prêmio ({cost_s}%)."
        ),
        "pills": [("Ativo", t), ("Prazo", prazo), ("KO", "121%"), ("Rebate", "5,50%"), ("Preço", f"{cost_s}%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Sem KO", f"Alta − {cost_s}%", "Call ATM no nocional"),
            ("No KO", f"+{ko_net_s}%", f"+{ko_prem:.0f}% sobre o prêmio"),
            ("Risco", "−100%", "Sobre o prêmio (OTM)"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Call KO', "100% · barreira 121%"),
            ("Rebate", "5,50%"),
            ("Preço (offer)", f"{cost_s}%"),
        ],
        "zones": [
            ("< +21%", f"Call ITM: (alta − {cost_s}%) no nocional; ÷{cost_s}% = ganho sobre o prêmio."),
            ("≥ +21%", f"Rebate líquido +{ko_net_s}% no nocional → +{ko_prem:.0f}% sobre o prêmio."),
            ("Queda / 0%", f"OTM: −{cost_s}% nocional = −100% sobre o prêmio."),
        ],
        "regime0": "Sem KO: participa da alta menos o preço. Veja também o ganho % só sobre o prêmio.",
        "speech": [
            ("Para quem", f"Cliente construtivo em {t} no curto prazo ({prazo}) que quer call com rebate se KO."),
            (
                "Como encaixa",
                f"Call KO 121% · rebate 5,50% · preço {cost_s}%. "
                f"No KO: +{ko_net_s}% no nocional = +{ko_prem:.0f}% sobre o prêmio. "
                f"Na queda, perda limitada a −100% do prêmio.",
            ),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "sim_extra_html": (
            f'<div class="sim-card wide">'
            f'<div class="lbl">Retorno sobre o prêmio ({cost_s}%)</div>'
            f'<div class="val" id="premVal">−100%</div>'
            f"</div>"
        ),
        "matrix_html": matrix_html,
        "struct_lbl": "Call (nocional)",
        "js_const": f"var KO={ko}, REB={rebate}, COST={cost};",
        "js_fn": "if (x >= KO) return REB - COST; return Math.max(x, 0) - COST;",
        "js_regime": (
            "var rp=(structureReturn(x)/COST)*100; "
            "if (x >= KO) return 'KO: rebate líquido +'+(REB-COST).toFixed(2).replace('.',',')+'% no nocional · '+rp.toFixed(0)+'% sobre o prêmio.'; "
            "if (x > 0) return 'Call ITM: '+structureReturn(x).toFixed(1).replace('.',',')+'% nocional · '+rp.toFixed(0)+'% sobre o prêmio.'; "
            "return 'OTM: −'+COST.toFixed(2).replace('.',',')+'% nocional · −100% sobre o prêmio.';"
        ),
    }


def make_put_ko():
    t, fixing = "EMBJ3", date(2026, 11, 27)
    prazo = months_label(fixing)
    cost, rebate, ko = 2.0, 5.50, -20.0
    slug = slugify("put-ko-rebate", t, prazo.replace(" ", ""))

    def net_at(x: float) -> float:
        if x <= ko:
            return rebate - cost
        return max(-x, 0.0) - cost

    def prem_at(x: float) -> float:
        return (net_at(x) / cost) * 100.0

    spots = [10.0, 0.0, -5.0, -10.0, -15.0, -19.0, -20.0, -30.0, -40.0]
    matrix_rows = []
    for s in spots:
        n, p = net_at(s), prem_at(s)
        note = "KO · rebate" if s <= ko else ("OTM" if s >= 0 else "ITM")
        ns = f"{n:+.1f}".replace(".", ",")
        ps = f"{p:+.0f}"
        ss = f"{s:+.0f}"
        matrix_rows.append(
            f"<tr><td>{ss}%</td><td>{ns}%</td><td><strong>{ps}%</strong></td><td>{note}</td></tr>"
        )
    ko_net = rebate - cost
    ko_prem = (ko_net / cost) * 100
    ko_net_s = f"{ko_net:.2f}".replace(".", ",")

    matrix_html = f"""
  <div class="matrix-wrap">
    <h2>Matriz de ganho (só prêmio)</h2>
    <p class="matrix-note">
      Retorno <strong>sobre o prêmio pago (2,00%)</strong> =
      (resultado no nocional ÷ 2,00%) × 100.
      No KO: líquido +{ko_net_s}% no nocional → <strong>+{ko_prem:.0f}%</strong> sobre o prêmio.
    </p>
    <table class="struct-table">
      <thead><tr><th>Spot</th><th>Nocional</th><th>Sobre prêmio</th><th></th></tr></thead>
      <tbody>
        {''.join(matrix_rows)}
      </tbody>
    </table>
  </div>
"""

    return slug, {
        "title": f"Put KO c/ Rebate {t}",
        "h1": "Put KO com Rebate",
        "ticker": t,
        "dot": "PK",
        "brand": "#2f6b5a",
        "subtitle": (
            f"Put down-and-out EMBJ3: ganha na queda até a barreira; no KO recebe rebate. "
            f"Matriz também em retorno % só sobre o prêmio (2,00%)."
        ),
        "pills": [("Ativo", t), ("Prazo", prazo), ("KO", "80%"), ("Rebate", "5,50%"), ("Preço", "2,00%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Sem KO", "|queda| − 2%", "Put ATM no nocional"),
            ("No KO", f"+{ko_net:.2f}%".replace(".", ","), f"+{ko_prem:.0f}% sobre o prêmio"),
            ("Risco", "−100%", "Sobre o prêmio (OTM)"),
        ],
        "struct": [
            ('<span class="tag b">B</span> Put KO', "100% · barreira 80%"),
            ("Rebate", "5,50%"),
            ("Preço (offer)", "2,00%"),
        ],
        "zones": [
            ("> −20%", "Put ITM: (|queda| − 2%) no nocional; ÷2% = ganho sobre o prêmio."),
            ("≤ −20%", f"Rebate líquido +{ko_net:.2f}% no nocional → +{ko_prem:.0f}% sobre o prêmio.".replace(".", ",")),
            ("Alta / 0%", "OTM: −2% nocional = −100% sobre o prêmio."),
        ],
        "regime0": "Sem KO: participa da queda menos o preço. Veja também o ganho % só sobre o prêmio.",
        "speech": [
            ("Para quem", f"Cliente tático em queda de {t} ({prazo}) — put com rebate se KO."),
            (
                "Como encaixa",
                f"Put KO 80% · rebate 5,50% · preço 2,00%. "
                f"No KO: +{ko_net_s}% no nocional = +{ko_prem:.0f}% sobre o prêmio. "
                f"Na alta, perda limitada a −100% do prêmio.",
            ),
            ("Fechamento", "Material de uso interno — condições no DIE."),
        ],
        "sim_extra_html": (
            '<div class="sim-card wide">'
            '<div class="lbl">Retorno sobre o prêmio (2,00%)</div>'
            '<div class="val" id="premVal">−100%</div>'
            "</div>"
        ),
        "matrix_html": matrix_html,
        "struct_lbl": "Put (nocional)",
        "js_const": f"var KO={ko}, REB={rebate}, COST={cost};",
        "js_fn": "if (x <= KO) return REB - COST; return Math.max(-x, 0) - COST;",
        "js_regime": (
            "var rp=(structureReturn(x)/COST)*100; "
            "if (x <= KO) return 'KO: rebate líquido +'+(REB-COST).toFixed(2).replace('.',',')+'% no nocional · '+rp.toFixed(0)+'% sobre o prêmio.'; "
            "if (x < 0) return 'Put ITM: '+structureReturn(x).toFixed(1).replace('.',',')+'% nocional · '+rp.toFixed(0)+'% sobre o prêmio.'; "
            "return 'OTM: −2% nocional · −100% sobre o prêmio.';"
        ),
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
        "pills": [("Ativo", t), ("Prazo", prazo), ("Put", "100%"), ("KI", "140%"), ("Put KO", "80%")],
        "highlights": [
            ("Prazo", prazo, ""),
            ("Faixa", "|x|", "Entre −20% e +40%"),
            ("Fora", "0%", "Capital protegido"),
            ("Ideia", "Twin Win", "Ganha na alta e na queda"),
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
            ("Como encaixa", "TWIP · put KO 80% · call KI 140%."),
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
        "struct_lbl": "One Touch (nocional)",
        "js_const": f"var B={barrier}, REB={rebate}, COST={cost};",
        "js_fn": "if (x >= B) return REB - COST; return -COST;",
        "js_regime": "if (x >= B) return 'One touch: rebate líquido.'; return 'Não tocou: −preço.';",
    }


SECTION_META = {
    "SOC": {
        "id": "soc",
        "blurb": "Stock or Coupon — cupom se a barreira não for atingida.",
        "color": "#0d6e6e",
    },
    "Smart Hedge": {
        "id": "smart-hedge",
        "blurb": "Piso na queda, 1:1 até a barreira KI.",
        "color": "#007e33",
    },
    "Aceleradora Dinâmica": {
        "id": "aceleradora",
        "blurb": "2× na alta até a call vendida; se atingir, call KO vira pó (0%). Proteção parcial.",
        "color": "#5a4a8a",
    },
    "Triplo Retorno KO": {
        "id": "triplo",
        "blurb": "3× na alta, ganho na queda moderada, teto no KO.",
        "color": "#820ad1",
    },
    "Call KO com Rebate": {
        "id": "call-ko",
        "blurb": "Call up-and-out com rebate se bater a barreira.",
        "color": "#c0392b",
    },
    "Put KO com Rebate": {
        "id": "put-ko",
        "blurb": "Put down-and-out com rebate se bater a barreira.",
        "color": "#2f6b5a",
    },
    "TWIP": {
        "id": "twip",
        "blurb": "Twin Win Protected — |x| entre barreiras, 0% fora.",
        "color": "#b8860b",
    },
    "One Touch de Alta": {
        "id": "one-touch",
        "blurb": "Paga rebate se tocar a barreira de alta.",
        "color": "#1e4d7b",
    },
}


def hub_html(sections: list[tuple[str, list[tuple[str, dict]]]]) -> str:
    cat_cards = []
    sections_html = []

    for title, items in sections:
        meta = SECTION_META.get(title, {"id": slugify(title), "blurb": title, "color": "#1e4d7b"})
        sid = meta["id"]
        color = meta["color"]
        n = len(items)
        tickers = ", ".join(dict.fromkeys(cfg["ticker"] for _, cfg in items))
        cat_cards.append(
            f"""
<button type="button" class="cat-card" data-target="{sid}" style="--cat:{color}">
  <span class="cat-bar"></span>
  <span class="cat-body">
    <span class="cat-title">{title}</span>
    <span class="cat-count">{n} operaç{'ão' if n == 1 else 'ões'}</span>
    <span class="cat-blurb">{meta['blurb']}</span>
    <span class="cat-tickers">{tickers}</span>
  </span>
</button>"""
        )

        ops = []
        for slug, cfg in items:
            extra = ""
            rs = cfg.get("research") or {}
            if rs.get("rec_lbl"):
                extra += f'<span class="pill">Research: {rs["rec_lbl"]}</span>'
            if rs.get("target") is not None:
                extra += f'<span class="pill">PA: {fmt_brl(rs["target"])}</span>'
            pills = " ".join(f'<span class="pill">{k}: {v}</span>' for k, v in cfg["pills"]) + extra
            ops.append(
                f"""
<li class="op-block">
  <div class="op-bar" style="background:{cfg['brand']}"></div>
  <a class="op" href="./ops/{slug}/index.html">
    <div class="op-top"><span class="op-title">{cfg['h1']} {cfg['ticker']}</span><span class="op-ticker">{cfg['ticker']}</span></div>
    <p class="op-blurb">{cfg['subtitle']}</p>
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

    cats = "\n".join(cat_cards)
    body = "\n".join(sections_html)
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
.cat-grid{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin-bottom:8px}}
.cat-card{{appearance:none;border:1px solid var(--line);background:var(--card);border-radius:6px;overflow:hidden;text-align:left;cursor:pointer;padding:0;display:flex;flex-direction:column;transition:transform .12s ease,box-shadow .12s ease,border-color .12s}}
.cat-card:hover,.cat-card:focus-visible{{transform:translateY(-2px);box-shadow:0 8px 20px rgba(11,31,58,.08);border-color:#b8c6d6;outline:none}}
.cat-card.active{{border-color:var(--cat);box-shadow:0 0 0 2px color-mix(in srgb,var(--cat) 28%,transparent)}}
.cat-bar{{display:block;height:6px;background:var(--cat)}}
.cat-body{{display:flex;flex-direction:column;gap:6px;padding:16px 18px 18px}}
.cat-title{{font-size:17px;font-weight:700;color:var(--btg)}}
.cat-count{{font-size:11px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--cat)}}
.cat-blurb{{font-size:13px;color:var(--muted);line-height:1.4}}
.cat-tickers{{font-size:11px;color:#7a8796;line-height:1.35;margin-top:2px}}
.cat-section-head{{display:flex;justify-content:space-between;align-items:center;gap:12px;margin:8px 0 14px}}
.cat-section h2{{font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--btg-blue);margin:0}}
.cat-back{{appearance:none;border:1px solid var(--line);background:#fff;color:var(--link);font-size:12px;font-weight:700;padding:8px 12px;border-radius:4px;cursor:pointer}}
.cat-back:hover{{background:#f5f8fc}}
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
@media (max-width:720px){{.cat-grid{{grid-template-columns:1fr}}}}
@media (max-width:640px){{.hero{{padding:28px 16px 32px}}.page{{padding:20px 16px 48px}}.hero-row{{flex-direction:column;align-items:flex-start}}.cat-section-head{{flex-direction:column;align-items:flex-start}}}}
</style>
</head>
<body>
<header class="hero">
  <div class="hero-inner">
    <div class="logo-btg">BTG PACTUAL</div>
    <div class="hero-row">
      <div>
        <h1>Prateleira Tática</h1>
        <p class="lede">Distribuição Renda Variável · escolha um card para ver as operações</p>
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
  <div class="cat-grid" id="catGrid">{cats}</div>
  {body}
  <p class="footer">Material ilustrativo para uso interno. Não constitui oferta, recomendação ou garantia de rentabilidade.
  <strong>MATERIAL DE USO INTERNO, NÃO ENVIAR AOS CLIENTES</strong></p>
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

    tickers = [cfg["ticker"] for _, cfg in all_ops]
    try:
        research = fetch_research(tickers)
    except Exception as exc:
        print("research_fail", exc)
        if RESEARCH_SNAP.exists():
            research = json.loads(RESEARCH_SNAP.read_text(encoding="utf-8"))
        else:
            research = {}
    for slug, cfg in all_ops:
        cfg["research"] = research.get(cfg["ticker"], {})
        rs = cfg["research"]
        up = rs.get("upside")
        if up is not None:
            xmax = cfg.get("x_max", 80)
            xmin = cfg.get("x_min", -50)
            ymax = cfg.get("y_max", 80)
            ymin = cfg.get("y_min", -50)
            if up > xmax - 8:
                xmax = int(math.ceil((up + 10) / 10.0) * 10)
            if up < xmin + 8:
                xmin = int(math.floor((up - 10) / 10.0) * 10)
            # Expande só o eixo do ativo p/ caber o PA; não achata o Y do payoff (ex.: Triplo 3×).
            cfg["x_max"] = xmax
            cfg["x_min"] = xmin
            cfg["y_max"] = max(ymax, int(math.ceil(abs(up) / 10.0) * 10) + 10)
            cfg["y_min"] = min(ymin, xmin)
        cfg["research_html"] = research_html(cfg)

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
