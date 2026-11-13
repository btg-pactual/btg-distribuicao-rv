"""Baixa fechamentos mensais e grava coes/series.js. Não entra no HTML do hub."""
import json
import urllib.parse
import urllib.request
from pathlib import Path

SYMBOLS = {
    "ndx": "^NDX",
    "spx": "^GSPC",
    "ewz": "EWZ",
    "ouro": "GLD",
    "sx5e": "^STOXX50E",
}


def fetch(sym: str) -> dict:
    url = (
        "https://query1.finance.yahoo.com/v8/finance/chart/"
        + urllib.parse.quote(sym)
        + "?interval=1mo&range=15y"
    )
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=40) as resp:
        return json.load(resp)


def closes_of(payload: dict, use_adj: bool) -> tuple[list, list]:
    res = payload["chart"]["result"][0]
    ts = res["timestamp"]
    quote = res["indicators"]["quote"][0]["close"]
    adj = res["indicators"]["adjclose"][0]["adjclose"]
    use = adj if use_adj else quote
    times = []
    vals = []
    for t, c in zip(ts, use):
        if c is None:
            continue
        times.append(int(t))
        vals.append(round(float(c), 2))
    return times, vals


def main() -> None:
    pack: dict = {}
    shared: list | None = None
    for key, sym in SYMBOLS.items():
        times, vals = closes_of(fetch(sym), use_adj=(key == "ewz"))
        if shared is None:
            shared = times
        pack[key] = vals
        print(key, len(vals), vals[0], vals[-1])
    pack = {"t": shared, "ndx": pack["ndx"], "spx": pack["spx"], "ewz": pack["ewz"], "ouro": pack["ouro"], "sx5e": pack["sx5e"]}
    dest = Path(__file__).resolve().parent / "series.js"
    dest.write_text("window.COE_PACK=" + json.dumps(pack, separators=(",", ":")) + ";\n", encoding="utf-8")
    print("wrote", dest, "bytes", dest.stat().st_size)


if __name__ == "__main__":
    main()
