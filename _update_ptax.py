# -*- coding: utf-8 -*-
"""Atualiza PTAX (venda fechamento) via API Olinda do Banco Central."""
from __future__ import annotations

import json
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "ops" / "ptax_spot.json"
OLINDA = "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoMoedaDia"


def _fetch_day(day: date) -> dict | None:
    # API espera MM-DD-AAAA
    ds = f"{day.month:02d}-{day.day:02d}-{day.year}"
    params = {
        "@moeda": "'USD'",
        "@dataCotacao": f"'{ds}'",
        "$format": "json",
        "$top": "100",
    }
    url = f"{OLINDA}(moeda=@moeda,dataCotacao=@dataCotacao)?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "btg-distribuicao-rv/ptax-daily"})
    with urllib.request.urlopen(req, timeout=45) as resp:
        payload = json.load(resp)
    rows = payload.get("value") or []
    fech = [r for r in rows if "Fechamento" in str(r.get("tipoBoletim") or "")]
    if not fech:
        return None
    row = fech[-1]
    venda = float(row["cotacaoVenda"])
    return {
        "spot": round(venda, 4),
        "date": day.isoformat(),
        "date_br": day.strftime("%d/%m/%Y"),
        "tipo": row.get("tipoBoletim"),
        "data_hora": row.get("dataHoraCotacao"),
        "source": "BCB Olinda PTAX CotacaoMoedaDia",
        "updated_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def fetch_latest(max_lookback: int = 10) -> dict:
    today = date.today()
    last_err: Exception | None = None
    for i in range(max_lookback):
        day = today - timedelta(days=i)
        try:
            hit = _fetch_day(day)
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            continue
        if hit:
            return hit
    raise RuntimeError(f"Não foi possível obter PTAX nos últimos {max_lookback} dias: {last_err}")


def main() -> None:
    data = fetch_latest()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"ptax {data['date_br']} venda R$ {data['spot']:.4f} -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
