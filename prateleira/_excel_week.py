# -*- coding: utf-8 -*-
"""Carrega a última aba de operacoes/operacoes.xlsx (semana corrente)."""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

XLSX = Path(__file__).resolve().parent / "operacoes" / "operacoes.xlsx"

TICKER_RE = re.compile(r"^[A-Z0-9]{4,6}\d?$", re.I)


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"\s+", " ", s.strip().upper())


def sheet_to_ref(name: str) -> date | None:
    m = re.match(r"(\d{2})\.(\d{2})\.(\d{2})$", name.strip())
    if not m:
        return None
    d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
    return date(2000 + y, mo, d)


def as_date(v) -> date | None:
    if isinstance(v, datetime):
        return v.date()
    if isinstance(v, date):
        return v
    return None


def pct(v) -> float | None:
    if v is None:
        return None
    if isinstance(v, str):
        s = v.strip().replace("%", "").replace(",", ".")
        if not s:
            return None
        return round(float(s), 4)
    if isinstance(v, (int, float)):
        x = float(v)
        if abs(x) <= 2.5:
            return round(abs(x) * 100, 4)
        return round(x, 4)
    return None


def bid_pct(v) -> float | None:
    p = pct(v)
    return p


def offer_abs(v) -> float | None:
    if v is None:
        return None
    if isinstance(v, (int, float)):
        x = float(v)
        if x < 0:
            return round(abs(x) * 100, 2)
        if x <= 2.5:
            return round(abs(x) * 100, 2)
        return round(abs(x), 2)
    if isinstance(v, str):
        s = v.strip().replace(",", ".")
        x = float(s)
        if x < 0:
            return round(abs(x) * 100, 2)
        return round(abs(x), 2)
    return None


def _section_key(cell0: str | None) -> str | None:
    if not cell0:
        return None
    n = _norm(str(cell0))
    if n == "SOC":
        return "soc"
    if "SMART HEDGE" in n:
        return "smart"
    if "ACELERADORA KO" in n and "ATIVO" in n:
        return "acel_ko"
    if "ACELERADORA DIN" in n:
        return "acel_dyn"
    if "CALL KO" in n and "REBATE" in n:
        return "call_ko"
    if "TRIPLO" in n:
        return "triplo"
    if "COMPRA DE CS" in n or "CALL SPREAD" in n:
        return "call_spread"
    if n == "COLLAR":
        return "collar"
    if n == "POP":
        return "pop"
    if "ONE TOUCH" in n:
        return "one_touch"
    return None


@dataclass
class WeekData:
    sheet: str
    ref: date
    SOC: list
    SMART: list
    ACEL_KO: list
    TRIPLO: list
    CALL_SPREAD: list
    COLLAR: list
    CALL_KO: list
    POP: tuple | None
    ONE_TOUCH: list


def load_excel_week() -> WeekData | None:
    if not XLSX.exists():
        return None
    try:
        from openpyxl import load_workbook
    except ImportError:
        return None

    wb = load_workbook(XLSX, data_only=True)
    sheet_name = wb.sheetnames[-1]
    ref = sheet_to_ref(sheet_name)
    if ref is None:
        return None

    ws = wb[sheet_name]
    section: str | None = None
    soc: list = []
    smart: list = []
    acel_ko: list = []
    triplo: list = []
    call_spread: list = []
    collar: list = []
    call_ko: list = []
    pop: tuple | None = None
    one_touch: list = []

    for row in ws.iter_rows(values_only=True):
        cells = [c for c in row if c is not None and str(c).strip() != ""]
        if not cells:
            continue
        row_full = list(row)

        # Linha só com nome da seção (formato antigo)
        if len(cells) == 1 or (len(cells) <= 2 and _section_key(str(cells[0]))):
            sk = _section_key(str(row_full[0]) if row_full[0] is not None else "")
            if sk:
                section = sk
            continue

        texts = [
            _norm(str(row_full[i])) if i < len(row_full) and row_full[i] is not None else ""
            for i in range(min(8, len(row_full)))
        ]
        if "ATIVO" in texts:
            sk = _section_key(str(row_full[0]) if row_full[0] is not None else "")
            if sk:
                section = sk
            continue

        ticker = None
        off = 0
        for i in range(min(3, len(row_full))):
            c = row_full[i]
            if isinstance(c, str) and TICKER_RE.match(c.strip().upper()):
                ticker = c.strip().upper()
                off = i
                break
        if not ticker or not section:
            continue

        fixing = as_date(row_full[off + 1] if off + 1 < len(row_full) else None)
        if not fixing:
            continue
        rest = [row_full[j] for j in range(off + 2, len(row_full))]

        if section == "soc":
            if len(rest) < 3:
                continue
            soc.append(
                (ticker, fixing, pct(rest[0]), pct(rest[1]), bid_pct(rest[2]), None, None)
            )
        elif section == "smart":
            if len(rest) < 4:
                continue
            smart.append((ticker, fixing, pct(rest[0]), pct(rest[1]), pct(rest[2]), bid_pct(rest[3])))
        elif section == "acel_ko":
            if len(rest) < 4:
                continue
            acel_ko.append(
                (ticker, fixing, pct(rest[0]), pct(rest[1]), pct(rest[2]), bid_pct(rest[3]))
            )
        elif section == "triplo":
            if len(rest) < 6:
                continue
            triplo.append(
                (
                    ticker,
                    fixing,
                    pct(rest[0]),
                    pct(rest[1]),
                    pct(rest[2]),
                    pct(rest[3]),
                    pct(rest[4]),
                    bid_pct(rest[5]),
                )
            )
        elif section == "call_spread":
            if len(rest) < 3:
                continue
            call_spread.append((ticker, fixing, pct(rest[0]), pct(rest[1]), offer_abs(rest[2])))
        elif section == "collar":
            if len(rest) < 3:
                continue
            collar.append((ticker, fixing, pct(rest[0]), pct(rest[1]), bid_pct(rest[2])))
        elif section == "call_ko":
            if len(rest) < 4:
                continue
            call_ko.append(
                (ticker, fixing, pct(rest[0]), pct(rest[1]), pct(rest[2]), offer_abs(rest[3]))
            )
        elif section == "pop":
            if len(rest) < 2:
                continue
            pop = (ticker, fixing, pct(rest[0]), pct(rest[1]))
        elif section == "one_touch":
            if len(rest) < 3:
                continue
            one_touch.append((ticker, fixing, pct(rest[0]), pct(rest[1]), offer_abs(rest[2])))

    return WeekData(
        sheet=sheet_name,
        ref=ref,
        SOC=soc,
        SMART=smart,
        ACEL_KO=acel_ko,
        TRIPLO=triplo,
        CALL_SPREAD=call_spread,
        COLLAR=collar,
        CALL_KO=call_ko,
        POP=pop,
        ONE_TOUCH=one_touch,
    )


def sheet_names_from_xlsx(path: Path | None = None) -> list[str]:
    """Lista abas sem openpyxl (stdlib)."""
    import zipfile
    import xml.etree.ElementTree as ET

    p = path or XLSX
    with zipfile.ZipFile(p) as z:
        root = ET.fromstring(z.read("xl/workbook.xml"))
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    return [s.get("name", "") for s in root.findall(".//m:sheet", ns)]


def summary(w: WeekData) -> str:
    lines = [
        f"sheet={w.sheet}",
        f"ref={w.ref.isoformat()}",
        f"SOC={len(w.SOC)}",
        f"SMART={len(w.SMART)}",
        f"ACEL_KO={len(w.ACEL_KO)}",
        f"TRIPLO={len(w.TRIPLO)}",
        f"CALL_SPREAD={len(w.CALL_SPREAD)}",
        f"COLLAR={len(w.COLLAR)}",
        f"CALL_KO={len(w.CALL_KO)}",
        f"POP={1 if w.POP else 0}",
        f"ONE_TOUCH={len(w.ONE_TOUCH)}",
    ]
    for t, fixing, strike, ko, *_rest in w.SOC:
        lines.append(f"SOC\t{t} {fixing.isoformat()} strike={strike} ko={ko}")
    for t, fixing, buy, ko, sell, *_rest in w.ACEL_KO:
        lines.append(f"ACEL_KO\t{t} {fixing.isoformat()} call={buy} ko={ko} sell={sell}")
    for t, fixing, stk, ko, rebate, offer in w.CALL_KO:
        lines.append(f"CALL_KO\t{t} {fixing.isoformat()} stk={stk} ko={ko} rebate={rebate} offer={offer}")
    return "\n".join(lines)


if __name__ == "__main__":
    dump = Path(__file__).resolve().parent / "_excel_week.txt"
    lines: list[str] = []
    lines.append(f"path {XLSX} exists {XLSX.exists()}")
    try:
        lines.append(f"sheets {sheet_names_from_xlsx()!r}")
    except Exception as exc:
        lines.append(f"sheets_fail {exc!r}")
    w = load_excel_week()
    lines.append(summary(w) if w else "load_fail")
    text = "\n".join(lines)
    dump.write_text(text, encoding="utf-8")
    print(text)
