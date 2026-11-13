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
    """Preço de compra em pontos percentuais. '-4,50%' e -0,045 viram 4,50."""
    if v is None:
        return None
    as_percent = False
    if isinstance(v, str):
        as_percent = "%" in v
        s = v.strip().replace("%", "").replace(",", ".")
        if not s:
            return None
        x = float(s)
    elif isinstance(v, (int, float)):
        x = float(v)
    else:
        return None
    if as_percent or abs(x) > 2.5:
        return round(abs(x), 2)
    return round(abs(x) * 100, 2)


def _section_key(cell0: str | None) -> str | None:
    if not cell0:
        return None
    n = _norm(str(cell0))
    if n == "SOC":
        return "soc"
    if "SMART UP" in n:
        return "smart_up"
    if "SMART HEDGE" in n:
        return "smart"
    if n == "TWIP" or n.startswith("TWIP "):
        return "twip"
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
    if "PUT FINANCIADA" in n:
        return "put_fin"
    if "CUPOM ALTO" in n or n.endswith(" CAR") or n == "CAR":
        return "car"
    return None


@dataclass
class WeekData:
    sheet: str
    ref: date
    SOC: list
    SMART: list
    ACEL_KO: list
    ACEL_DYN: list
    TRIPLO: list
    CALL_SPREAD: list
    COLLAR: list
    CALL_KO: list
    POP: tuple | None
    ONE_TOUCH: list
    PUT_FIN: list
    CAR: list
    SMART_UP: list
    TWIP: list


def _parse_ws(ws, sheet_name: str, ref: date) -> WeekData:
    section: str | None = None
    soc: list = []
    smart: list = []
    acel_ko: list = []
    acel_dyn: list = []
    triplo: list = []
    call_spread: list = []
    collar: list = []
    call_ko: list = []
    pop: tuple | None = None
    one_touch: list = []
    put_fin: list = []
    car: list = []
    smart_up: list = []
    twip: list = []

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
            # B PUT KO | S CALL KO | KO | BID — barreira é a 3ª coluna, não a call.
            if len(rest) < 4:
                continue
            soc.append(
                (ticker, fixing, pct(rest[0]), pct(rest[2]), bid_pct(rest[3]), None, None)
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
        elif section == "acel_dyn":
            # B CALL KO | KO | S CALL | B PUT KO | KO | BID
            if len(rest) < 6:
                continue
            ko_h, ko_l = pct(rest[1]), pct(rest[4])
            if ko_h is None or ko_l is None:
                continue
            acel_dyn.append((ticker, fixing, ko_h, ko_l, bid_pct(rest[5])))
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
        elif section == "put_fin":
            # B CALL | B PUT | S CALL | BID — bid não vai para o HTML.
            if len(rest) < 4:
                continue
            put_fin.append(
                (ticker, fixing, pct(rest[0]), pct(rest[1]), pct(rest[2]), bid_pct(rest[3]))
            )
        elif section == "car":
            # B PUT KO | KO | S CALL KO | KO | B CALL KO | KO | BID — bid não vai para o HTML.
            if len(rest) < 7:
                continue
            put_k, ko_dn = pct(rest[0]), pct(rest[1])
            call_k, ko_up = pct(rest[4]), pct(rest[5])
            if None in (put_k, ko_dn, call_k, ko_up):
                continue
            car.append((ticker, fixing, put_k, ko_dn, call_k, ko_up, bid_pct(rest[6])))
        elif section == "smart_up":
            # B PUT | S CALL KI | KI | B CALL KO | KO | BID — bid não vai para o HTML.
            if len(rest) < 6:
                continue
            up_put, up_call_ki, up_ki = pct(rest[0]), pct(rest[1]), pct(rest[2])
            up_call, up_ko = pct(rest[3]), pct(rest[4])
            if None in (up_put, up_call_ki, up_ki, up_call, up_ko):
                continue
            smart_up.append((ticker, fixing, up_put, up_call_ki, up_ki, up_call, up_ko, bid_pct(rest[5])))
        elif section == "twip":
            # B PUT | S CALL KI | KI | B PUT KO | KO | BID — bid não vai para o HTML.
            if len(rest) < 6:
                continue
            put_k, call_ki, ki = pct(rest[0]), pct(rest[1]), pct(rest[2])
            put_ko, ko = pct(rest[3]), pct(rest[4])
            if None in (put_k, call_ki, ki, put_ko, ko):
                continue
            twip.append((ticker, fixing, put_k, call_ki, ki, put_ko, ko, bid_pct(rest[5])))

    return WeekData(
        sheet=sheet_name,
        ref=ref,
        SOC=soc,
        SMART=smart,
        ACEL_KO=acel_ko,
        ACEL_DYN=acel_dyn,
        TRIPLO=triplo,
        CALL_SPREAD=call_spread,
        COLLAR=collar,
        CALL_KO=call_ko,
        POP=pop,
        ONE_TOUCH=one_touch,
        PUT_FIN=put_fin,
        CAR=car,
        SMART_UP=smart_up,
        TWIP=twip,
    )


def _open_wb():
    if not XLSX.exists():
        return None
    try:
        from openpyxl import load_workbook
    except ImportError:
        return None
    return load_workbook(XLSX, data_only=True)


def dated_sheetnames(wb) -> list[str]:
    return [n for n in wb.sheetnames if sheet_to_ref(n)]


def _load_named(sheet_name: str) -> WeekData | None:
    wb = _open_wb()
    if wb is None or sheet_name not in wb.sheetnames:
        return None
    ref = sheet_to_ref(sheet_name)
    if ref is None:
        return None
    return _parse_ws(wb[sheet_name], sheet_name, ref)


def load_excel_week() -> WeekData | None:
    wb = _open_wb()
    if wb is None:
        return None
    names = dated_sheetnames(wb)
    if not names:
        return None
    return _load_named(names[-1])


def load_previous_week() -> WeekData | None:
    wb = _open_wb()
    if wb is None:
        return None
    names = dated_sheetnames(wb)
    if len(names) < 2:
        return None
    return _load_named(names[-2])


_KIND_ORDER = (
    ("SOC", "SOC", "SOC"),
    ("CAR", "Cupom Alto Retorno", "CAR"),
    ("SMART", "Smart Hedge", "SMART"),
    ("SMART_UP", "Smart Up", "SMART_UP"),
    ("TWIP", "TWIP", "TWIP"),
    ("ACEL_DYN", "Aceleradora Dinâmica", "ACEL_DYN"),
    ("ACEL_KO", "Aceleradora KO com Ativo", "ACEL_KO"),
    ("TRIPLO", "Triplo Retorno KO", "TRIPLO"),
    ("CALL_SPREAD", "Compra de Call Spread", "CALL_SPREAD"),
    ("COLLAR", "Collar", "COLLAR"),
    ("CALL_KO", "Call KO com Rebate", "CALL_KO"),
    ("POP", "POP", "POP"),
    ("ONE_TOUCH", "One Touch de Alta", "ONE_TOUCH"),
    ("PUT_FIN", "Put Financiada com Ativo", "PUT_FIN"),
)


def _shelf_rows(w: WeekData) -> list[tuple[str, str, str, date]]:
    rows: list[tuple[str, str, str, date]] = []
    for key, label, attr in _KIND_ORDER:
        val = getattr(w, attr)
        items = [val] if key == "POP" and val else (val or [])
        if key == "POP" and not val:
            continue
        for row in items:
            if not row or row[1] is None:
                continue
            rows.append((key, label, row[0], row[1]))
    return rows


def week_moves(curr: WeekData, prev: WeekData) -> dict:
    """Linha some ou aparece. Troca só de vencimento, no mesmo produto e ticker, não conta."""
    from collections import defaultdict

    def bucket(rows):
        g = defaultdict(list)
        for key, label, ticker, fixing in rows:
            g[(key, ticker)].append((label, fixing))
        return g

    gc = bucket(_shelf_rows(curr))
    gp = bucket(_shelf_rows(prev))
    order = {k: i for i, (k, _label, _attr) in enumerate(_KIND_ORDER)}
    entered: list[tuple] = []
    left: list[tuple] = []
    for key in set(gc) | set(gp):
        cs = sorted(gc.get(key, []), key=lambda x: x[1])
        ps = sorted(gp.get(key, []), key=lambda x: x[1])
        used: set[int] = set()
        keep_c = []
        for label, fixing in cs:
            match = next((i for i, (_pl, pf) in enumerate(ps) if i not in used and pf == fixing), None)
            if match is None:
                keep_c.append((label, fixing))
            else:
                used.add(match)
        keep_p = [item for i, item in enumerate(ps) if i not in used]
        n_roll = min(len(keep_c), len(keep_p))
        ticker = key[1]
        for label, fixing in keep_c[n_roll:]:
            entered.append((order[key[0]], label, ticker, fixing))
        for label, fixing in keep_p[n_roll:]:
            left.append((order[key[0]], label, ticker, fixing))
    entered.sort()
    left.sort()
    return {
        "prev_sheet": prev.sheet,
        "prev_ref": prev.ref,
        "curr_ref": curr.ref,
        "entered": [{"struct": lb, "ticker": tk, "fixing": fx} for _o, lb, tk, fx in entered],
        "left": [{"struct": lb, "ticker": tk, "fixing": fx} for _o, lb, tk, fx in left],
    }


def moves_summary(moves: dict) -> str:
    lines = [
        f"prev={moves['prev_sheet']}",
        f"entrou={len(moves['entered'])}",
        f"saiu={len(moves['left'])}",
    ]
    for row in moves["entered"]:
        lines.append(f"ENTROU\t{row['struct']}\t{row['ticker']}\t{row['fixing'].isoformat()}")
    for row in moves["left"]:
        lines.append(f"SAIU\t{row['struct']}\t{row['ticker']}\t{row['fixing'].isoformat()}")
    return "\n".join(lines)


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
        f"ACEL_DYN={len(w.ACEL_DYN)}",
        f"TRIPLO={len(w.TRIPLO)}",
        f"CALL_SPREAD={len(w.CALL_SPREAD)}",
        f"COLLAR={len(w.COLLAR)}",
        f"CALL_KO={len(w.CALL_KO)}",
        f"POP={1 if w.POP else 0}",
        f"ONE_TOUCH={len(w.ONE_TOUCH)}",
        f"PUT_FIN={len(w.PUT_FIN)}",
        f"CAR={len(w.CAR)}",
        f"SMART_UP={len(w.SMART_UP)}",
        f"TWIP={len(w.TWIP)}",
    ]
    for t, fixing, strike, ko, *_rest in w.SOC:
        lines.append(f"SOC\t{t} {fixing.isoformat()} strike={strike} ko={ko}")
    for t, fixing, buy, ko, sell, *_rest in w.ACEL_KO:
        lines.append(f"ACEL_KO\t{t} {fixing.isoformat()} call={buy} ko={ko} sell={sell}")
    for t, fixing, ko_h, ko_l, *_rest in w.ACEL_DYN:
        lines.append(f"ACEL_DYN\t{t} {fixing.isoformat()} ko_alta={ko_h} ko_baixa={ko_l}")
    for t, fixing, stk, ko, rebate, offer in w.CALL_KO:
        lines.append(f"CALL_KO\t{t} {fixing.isoformat()} stk={stk} ko={ko} rebate={rebate} offer={offer}")
    for t, fixing, put_k, call_ki, ki, call_ko, ko, _bid in w.SMART_UP:
        lines.append(
            f"SMART_UP\t{t} {fixing.isoformat()} put={put_k} callki={call_ki} ki={ki} callko={call_ko} ko={ko}"
        )
    for t, fixing, put_k, call_ki, ki, put_ko, ko, _bid in w.TWIP:
        lines.append(
            f"TWIP\t{t} {fixing.isoformat()} put={put_k} callki={call_ki} ki={ki} putko={put_ko} ko={ko}"
        )
    for t, fixing, put_k, ko_dn, call_k, ko_up, _bid in w.CAR:
        lines.append(
            f"CAR\t{t} {fixing.isoformat()} put={put_k} ko_baixa={ko_dn} call={call_k} ko_alta={ko_up}"
        )
    for t, fixing, buy_call, buy_put, sell_call, _bid in w.PUT_FIN:
        lines.append(
            f"PUT_FIN\t{t} {fixing.isoformat()} call={buy_call} put={buy_put} sell={sell_call}"
        )
    return "\n".join(lines)


def ensure_put_financiada_bova11() -> bool:
    """Grava BOVA11 na aba 03.11.26 uma vez. Não replica em semanas novas."""
    if not XLSX.exists():
        return False
    try:
        from openpyxl import load_workbook
    except ImportError:
        return False
    wb = load_workbook(XLSX)
    if "03.11.26" not in wb.sheetnames:
        return False
    ws = wb["03.11.26"]
    section = None
    for row in ws.iter_rows(values_only=True):
        cells = [c for c in row if c is not None and str(c).strip() != ""]
        if not cells:
            continue
        sk = _section_key(str(row[0]) if row and row[0] is not None else "")
        if sk:
            section = sk
        if section == "put_fin" and any(str(c).strip().upper() == "BOVA11" for c in row if c is not None):
            return False
    ws.append(["Put Financiada com Ativo", "Ativo", "Fixing", "B CALL", "B PUT", "S CALL", "BID"])
    ws.append([None, "BOVA11", datetime(2027, 11, 5), 100, 90, 90, 4])
    wb.save(XLSX)
    return True


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
