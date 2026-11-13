"""Importă arhiva completă a licitațiilor VMS (BT + OS, 2009–2026) dintr-un fișier Excel.

Fișierul sursă are foile „Rezultate licitatii BT” și „Rezultate licitatii OS”
(compilate din rapoartele MF). Rezultatul este data_pipeline/manual/history.json,
folosit de build.py ca strat de bază: datele publicate/preluate automat au prioritate,
arhiva doar completează ce lipsește.

Bonurile de 21 de zile (categoria „0”) sunt ignorate.

Utilizare (necesită openpyxl, nu face parte din requirements.txt):
    python -m tools.import_history_xlsx Rezultate_licitatii_VMS_BT_OS_2009-2026.xlsx
"""
from __future__ import annotations

import calendar
import datetime as dt
import json
import re
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data_pipeline" / "manual" / "history.json"
STANDARD_YEARS = (2, 3, 5, 7, 10)


def bucket(days: int) -> int:
    return 91 if days <= 120 else 182 if days <= 250 else 364


def iso(v) -> str | None:
    if v is None:
        return None
    if isinstance(v, dt.datetime):
        return v.date().isoformat()
    if isinstance(v, dt.date):
        return v.isoformat()
    return str(v)


def add_months(d: dt.date, n: int) -> dt.date:
    m = d.month - 1 + n
    y, m = d.year + m // 12, m % 12 + 1
    return dt.date(y, m, min(d.day, calendar.monthrange(y, m)[1]))


def coupon_dates(issue: dt.date, maturity: dt.date) -> list[str]:
    out, k = [], 1
    while True:
        c = add_months(issue, 6 * k)
        if c >= maturity - dt.timedelta(days=10):
            out.append(maturity.isoformat())
            return out
        out.append(c.isoformat())
        k += 1


def years_of(label: str) -> float:
    return float(re.sub(r"[^0-9.,]", "", label).replace(",", "."))


def rnd(v, n=2):
    return None if v is None else round(float(v), n)


def rows(ws, start: int):
    for r in ws.iter_rows(min_row=start, values_only=True):
        if r[0] is not None:
            yield r


def import_bt(ws, src: str):
    securities, auctions, raw_rates = [], [], {}
    for r in rows(ws, 3):
        (issue, cat, _name, term, isin, announced, demand, _dem_nc, participants, pmin, pmax, pavg,
         placed, _pl_nc, rmin, rmax, ravg, _emin, _emax, _eavg, maturity, auction, fname) = r[:23]
        if str(cat).strip() == "0":          # 21 de zile – ignorate
            continue
        days = int(str(term).split()[0])
        issue_s, mat_s, auc_s = iso(issue), iso(maturity), iso(auction)
        securities.append({
            "isin": isin, "type": "BT", "term_label": f"{days} zile", "term_days": days,
            "auction_date": auc_s, "issue_date": issue_s, "maturity": mat_s,
            "coupon_rate": None, "coupon_dates": [], "source": f"{src}: {fname}",
        })
        auctions.append({
            "auction_date": auc_s, "isin": isin, "type": "BT", "term_label": f"{days} zile",
            "rate_min": rnd(rmin), "rate_avg": rnd(ravg), "rate_max": rnd(rmax),
            "settlement_date": issue_s, "maturity": mat_s,
            "announced": rnd(announced, 1), "demand": rnd(demand, 1), "placed_nominal": rnd(placed, 1),
            "placed_price": rnd(placed * pavg / 100) if placed is not None and pavg else None,
            "participants": participants, "unit": "mii lei",
        })
        raw_rates.setdefault((issue_s, bucket(days)), []).append((rmin, ravg, rmax, placed or 0))
    rates = []
    for (date, days), lst in sorted(raw_rates.items()):
        # 2015: două licitații cu aceeași dată de decontare – combinăm (medie ponderată cu volumul)
        vol = sum(x[3] for x in lst)
        avg = sum(x[1] * x[3] for x in lst) / vol if vol else sum(x[1] for x in lst) / len(lst)
        rates.append({"date": date, "days": days, "max": rnd(max(x[2] for x in lst)),
                      "avg": rnd(avg), "min": rnd(min(x[0] for x in lst))})
    return securities, auctions, rates


def import_os(ws, src: str):
    all_rows = sorted(rows(ws, 3), key=lambda r: (r[0], r[3]))
    first: dict[str, tuple] = {}
    for r in all_rows:
        first.setdefault(r[3], r)
    securities, auctions = {}, []
    for isin, r in first.items():
        issue, kind, term, _, *_rest = r
        maturity = r[16].date()
        issue_d = issue.date()
        years = years_of(term)
        if years not in STANDARD_YEARS:
            # prima apariție este o redeschidere: emiterea inițială = scadența − termenul standard
            std = min(STANDARD_YEARS, key=lambda y: abs(y - years) if y >= years else 99)
            issue_d = maturity.replace(year=maturity.year - std)
            years = std
        floating = "flot" in str(kind).lower()
        sec = {
            "isin": isin, "type": "OS", "term_label": f"{int(years)} ani",
            "term_days": (maturity - issue_d).days,
            "auction_date": iso(r[17]) if issue_d == issue.date() else (issue_d - dt.timedelta(days=2)).isoformat(),
            "issue_date": issue_d.isoformat(), "maturity": maturity.isoformat(),
            "coupon_rate": None if floating else rnd(r[13]),
            "coupon_dates": coupon_dates(issue_d, maturity),
            "source": f"{src}: {r[19]}",
        }
        if floating:
            sec["coupon_type"] = "flotant"
            if r[14] is not None:
                sec["margin"] = rnd(r[14])
            sec["coupon_history"] = []
        securities[isin] = sec
    for r in all_rows:
        (issue, kind, term, isin, announced, demand, _dem_nc, participants, pmin, pmax, pavg,
         placed, _pl_nc, rate, margin, _period, maturity, auction, _src_date, fname) = r[:20]
        sec = securities[isin]
        if sec.get("coupon_type") == "flotant":
            # rata cuponului în curs la data plasării, pe data plății următorului cupon
            nxt = next(c for c in sec["coupon_dates"] if c > iso(issue))
            hist = {h["date"]: h for h in sec["coupon_history"]}
            hist[nxt] = {"date": nxt, "rate": rnd(rate)} | ({"margin": rnd(margin)} if margin is not None else {})
            sec["coupon_history"] = [hist[k] for k in sorted(hist)]
        price = pavg if pavg else 100.0
        auctions.append({
            "auction_date": iso(auction), "isin": isin, "type": "OS", "term_label": str(term).replace(".", ","),
            "rate_avg": rnd(rate), "settlement_date": iso(issue), "maturity": iso(maturity),
            "announced": rnd(announced, 1), "demand": rnd(demand, 1), "placed_nominal": rnd(placed, 1),
            "placed_price": rnd(placed * price / 100) if placed is not None else None,
            "price_min": rnd(pmin), "price_avg": rnd(pavg), "price_max": rnd(pmax),
            "participants": participants, "unit": "mii lei",
        })
    return list(securities.values()), auctions


def main(argv: list[str]) -> int:
    path = Path(argv[0])
    wb = openpyxl.load_workbook(path, data_only=True, read_only=True)
    src = "Arhiva MF 2009–2026"
    bt_sec, bt_auc, rates = import_bt(wb["Rezultate licitatii BT"], src)
    os_sec, os_auc = import_os(wb["Rezultate licitatii OS"], src)
    strip = lambda d: {k: v for k, v in d.items() if v is not None or k == "coupon_rate"}
    out = {
        "source": path.name,
        "rates": rates,
        "securities": sorted(bt_sec + os_sec, key=lambda s: (s["auction_date"], s["isin"])),
        "auctions": [strip(a) for a in sorted(bt_auc + os_auc, key=lambda a: (a["auction_date"], a["isin"]))],
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{OUT}: {len(rates)} rate BT, {len(bt_sec)} BT + {len(os_sec)} OS ISIN, {len(out['auctions'])} rezultate")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
