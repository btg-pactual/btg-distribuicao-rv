# -*- coding: utf-8 -*-
"""Máx./mín. 52 semanas (até o Dia D) por ticker — Yahoo (.SA) + PTAX Bacen."""
from __future__ import annotations

import json
import ssl
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "ops" / "range_52w.json"
SSL_CTX = ssl.create_default_context()
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; btg-distribuicao-rv/52w)"}

# Tickers Dia D (equity/ETF B3). PTAX tratado à parte.
DIA_D_TICKERS = [
    "VALE3",
    "PETR4",
    "AXIA3",
    "ROXO34",
    "ITUB4",
    "EMBJ3",
    "EQTL3",
    "PACB11",
]


def yahoo_symbol(ticker: str) -> str:
    t = ticker.upper().strip()
    if t.endswith(".SA"):
        return t
    return f"{t}.SA"


def _http_json(url: str) -> dict:
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=45, context=SSL_CTX) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_yahoo_52w(ticker: str) -> dict | None:
    sym = yahoo_symbol(ticker)
    url = (
        f"https://query1.finance.yahoo.com/v8/finance/chart/{urllib.parse.quote(sym)}"
        f"?range=1y&interval=1d"
    )
    try:
        data = _http_json(url)
    except Exception as exc:  # noqa: BLE001
        print("yahoo_fail", ticker, exc)
        return None
    results = (data.get("chart") or {}).get("result") or []
    if not results:
        return None
    res = results[0]
    quote = ((res.get("indicators") or {}).get("quote") or [{}])[0]
    highs = [x for x in (quote.get("high") or []) if x is not None]
    lows = [x for x in (quote.get("low") or []) if x is not None]
    closes = [x for x in (quote.get("close") or []) if x is not None]
    if not highs or not lows or not closes:
        return None
    high = float(max(highs))
    low = float(min(lows))
    last = float(closes[-1])
    return {
        "ticker": ticker.upper(),
        "source": f"Yahoo Finance {sym}",
        "high": round(high, 4),
        "low": round(low, 4),
        "last": round(last, 4),
        "n_days": len(closes),
        "as_of": date.today().isoformat(),
        "as_of_br": date.today().strftime("%d/%m/%Y"),
    }


def fetch_ptax_52w() -> dict | None:
    end = date.today()
    start = end - timedelta(days=370)
    params = {
        "@moeda": "'USD'",
        "@dataInicial": f"'{start.month:02d}-{start.day:02d}-{start.year}'",
        "@dataFinalCotacao": f"'{end.month:02d}-{end.day:02d}-{end.year}'",
        "$format": "json",
        "$top": "2000",
    }
    base = (
        "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/"
        "CotacaoMoedaPeriodo(moeda=@moeda,dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)"
    )
    url = f"{base}?{urllib.parse.urlencode(params)}"
    try:
        data = _http_json(url)
    except Exception as exc:  # noqa: BLE001
        print("ptax_52w_fail", exc)
        return None
    rows = [
        r
        for r in (data.get("value") or [])
        if "Fechamento" in str(r.get("tipoBoletim") or "")
    ]
    if not rows:
        return None
    vendas = [float(r["cotacaoVenda"]) for r in rows if r.get("cotacaoVenda") is not None]
    if not vendas:
        return None
    return {
        "ticker": "PTAX",
        "source": "BCB Olinda PTAX",
        "high": round(max(vendas), 4),
        "low": round(min(vendas), 4),
        "last": round(vendas[-1], 4),
        "n_days": len(vendas),
        "as_of": end.isoformat(),
        "as_of_br": end.strftime("%d/%m/%Y"),
    }


def fetch_all(tickers: list[str] | None = None) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for t in tickers or DIA_D_TICKERS:
        hit = fetch_yahoo_52w(t)
        if hit:
            out[t.upper()] = hit
            print(f"52w {t} high={hit['high']} low={hit['low']}")
    ptax = fetch_ptax_52w()
    if ptax:
        out["PTAX"] = ptax
        print(f"52w PTAX high={ptax['high']} low={ptax['low']}")
    return out


def save(data: dict[str, dict]) -> Path:
    payload = {
        "updated_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "as_of_br": date.today().strftime("%d/%m/%Y"),
        "tickers": data,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return OUT


def load() -> dict[str, dict]:
    if not OUT.exists():
        return {}
    try:
        raw = json.loads(OUT.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return raw.get("tickers") or {}


def fmt_br(n: float, digits: int = 2) -> str:
    return f"{n:.{digits}f}".replace(".", ",")


MARKER_OPEN = "<!-- RANGE_52W -->"
MARKER_CLOSE = "<!-- /RANGE_52W -->"


def range_block_html(
    ticker: str,
    spot: float | None = None,
    currency: str = "R$",
    as_of_phrase: str | None = None,
) -> str:
    """Bloco HTML abaixo da estrutura — máx/mín 52 semanas vs spot."""
    data = load().get(ticker.upper())
    if not data:
        return ""
    high = float(data["high"])
    low = float(data["low"])
    last = float(data.get("last") or 0) or None
    ref = float(spot) if spot is not None else last
    as_of = data.get("as_of_br") or ""
    dig = 4 if ticker.upper() == "PTAX" else 2
    when = as_of_phrase or (f"até {as_of}" if as_of else "últimos ~12 meses")

    def vs(level: float) -> str:
        if not ref:
            return "—"
        pct = (level / ref - 1.0) * 100.0
        sign = "+" if pct > 0 else ""
        return f"{sign}{fmt_br(pct, 1)}%"

    inner = f"""
        <div class="range-52w" style="margin-top:16px">
          <h2>Faixa 52 semanas</h2>
          <table class="struct-table">
            <thead><tr><th></th><th>{currency}</th><th>vs spot</th></tr></thead>
            <tbody>
              <tr><td>Máximo</td><td><strong>{fmt_br(high, dig)}</strong></td><td>{vs(high)}</td></tr>
              <tr><td>Mínimo</td><td><strong>{fmt_br(low, dig)}</strong></td><td>{vs(low)}</td></tr>
            </tbody>
          </table>
          <p class="legend-note">
            Máx./mín. dos últimos ~12 meses ({when}).
            Fonte: {data.get('source') or 'mercado'}.
          </p>
        </div>"""
    return f"{MARKER_OPEN}{inner}\n        {MARKER_CLOSE}"


def inject_into_html(html: str, ticker: str, spot: float | None = None, currency: str = "R$") -> str:
    """Substitui ou anexa o bloco 52w (páginas estáticas, ex. PACB11)."""
    block = range_block_html(ticker, spot=spot, currency=currency)
    if not block:
        return html
    if MARKER_OPEN in html and MARKER_CLOSE in html:
        start = html.index(MARKER_OPEN)
        end = html.index(MARKER_CLOSE) + len(MARKER_CLOSE)
        return html[:start] + block + html[end:]
    # Anexa após o legend-note da estrutura (primeiro painel).
    needle = '</p>\n\n        <div class="thesis">'
    if needle in html:
        return html.replace(needle, f"</p>\n\n        {block}\n\n        <div class=\"thesis\">", 1)
    needle2 = "</p>\n\n        <div class=\"thesis\""
    if needle2 in html:
        return html.replace(needle2, f"</p>\n\n        {block}\n\n        <div class=\"thesis\"", 1)
    return html


def patch_pacb11(spot: float | None = None) -> None:
    path = ROOT / "ops" / "pacb11-put-hedge" / "index.html"
    if not path.exists():
        return
    html = path.read_text(encoding="utf-8")
    new = inject_into_html(html, "PACB11", spot=spot)
    if new != html:
        path.write_text(new, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)} (52w)")


def main() -> None:
    data = fetch_all()
    path = save(data)
    print(f"wrote {path.relative_to(ROOT)} ({len(data)} tickers)")
    patch_pacb11(spot=(data.get("PACB11") or {}).get("last"))


if __name__ == "__main__":
    main()
