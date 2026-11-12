"""Parsers for Ministry of Finance (mf.gov.md) VMS publications.

Each parser receives plain text (extracted from PDF or HTML) and returns
plain dicts. Parsers never guess: when a value cannot be read reliably the
record is returned with ``"_issues"`` filled, and the validator keeps it out
of the published dataset until it is fixed by hand in ``manual/``.
"""
from __future__ import annotations

import datetime as dt
import re
from typing import Any

ISIN_RE = re.compile(r"\bMD\d{10}\b")
DATE_RE = re.compile(r"\b(\d{2})\.(\d{2})\.(\d{4})\b")
TERM_RE = re.compile(r"(\d{1,3})\s*(zile|ani|an)\b", re.IGNORECASE)
NUM_RE = re.compile(r"^-?\d{1,3}(?:\.\d{3})*(?:,\d+)?$|^-?\d+(?:,\d+)?$")
ROMAN = {1: "I", 2: "II", 3: "III", 4: "IV"}


def parse_date(s: str) -> dt.date:
    d, m, y = s.split(".")
    return dt.date(int(y), int(m), int(d))


def parse_number(s: str) -> float:
    """'1.400.000,00' -> 1400000.0 ; '11,63' -> 11.63 ; '11,63%' -> 11.63"""
    s = s.strip().replace("%", "").replace(" ", "").replace(" ", "")
    if not s:
        raise ValueError("empty number")
    return float(s.replace(".", "").replace(",", "."))


def dates_in(text: str) -> list[dt.date]:
    out = []
    for d, m, y in DATE_RE.findall(text):
        try:
            out.append(dt.date(int(y), int(m), int(d)))
        except ValueError:
            pass
    return out


def term_label(n: int, unit: str) -> str:
    unit = unit.lower()
    return f"{n} zile" if unit.startswith("zil") else f"{n} ani"


# --------------------------------------------------------------------------
# Placement communiqués ("Comunicat plasare BT-03.11.2026-rom.pdf")
# --------------------------------------------------------------------------
def parse_placement(text: str, auction_date: dt.date, source: str) -> list[dict[str, Any]]:
    """Return one security per ISIN found in a placement communiqué.

    Observed layout (one row per instrument, possibly wrapped on lines):
      BT: "Bonuri de trezorerie 91 zile MD4003005270 100 60 cu scont 05.11.2026 04.02.2027"
      OS: "2 ani MD4004002763 100 30,0 cu scont, la valoarea nominală 7,75 la sută anual
           09.10.2026 09.10.2028 09.04.2027 09.10.2027 09.04.2028 09.10.2028"
    """
    flat = re.sub(r"\s+", " ", text)
    matches = list(ISIN_RE.finditer(flat))
    out: list[dict[str, Any]] = []
    for i, m in enumerate(matches):
        isin = m.group(0)
        before = flat[max(0, m.start() - 120): m.start()]
        end = matches[i + 1].start() if i + 1 < len(matches) else len(flat)
        after = flat[m.end(): end]
        issues: list[str] = []
        terms = TERM_RE.findall(before)
        if not terms:
            issues.append("termen negăsit")
            n, unit = 0, "zile"
        else:
            n, unit = int(terms[-1][0]), terms[-1][1]
        is_bond = isin.startswith("MD4004") or unit.lower().startswith("an")
        ds = [d for d in dates_in(after) if d > auction_date - dt.timedelta(days=3650 * 2)]
        coupon = None
        cm = re.search(r"(\d{1,2},\d{1,2})\s*la\s*sut", after)
        if cm:
            coupon = parse_number(cm.group(1))
        if len(ds) < 2:
            issues.append("date emitere/scadență lipsă")
            issue_d = mat = None
            coupon_dates: list[str] = []
        else:
            issue_d, mat = ds[0], ds[1]
            coupon_dates = sorted({d.isoformat() for d in ds[2:] if issue_d < d <= mat}) if is_bond else []
        if is_bond and coupon is None:
            issues.append("rata cuponului lipsă")
        rec: dict[str, Any] = {
            "isin": isin,
            "type": "OS" if is_bond else "BT",
            "term_label": term_label(n, unit),
            "term_days": (mat - issue_d).days if issue_d and mat else None,
            "auction_date": auction_date.isoformat(),
            "issue_date": issue_d.isoformat() if issue_d else None,
            "maturity": mat.isoformat() if mat else None,
            "coupon_rate": coupon if is_bond else None,
            "coupon_dates": coupon_dates,
            "source": source,
        }
        if "redeschid" in flat.lower() and is_bond:
            rec["note"] = "Redeschidere – verifică data emisiei inițiale"
            issues.append("redeschidere: data emisiei inițiale trebuie confirmată")
        if issues:
            rec["_issues"] = issues
        out.append(rec)
    return out


# --------------------------------------------------------------------------
# Results communiqués ("Rezultatele licitatie 04-08-2026 - rom.pdf")
# --------------------------------------------------------------------------
def parse_results_bt(text: str, auction_date: dt.date, source: str) -> list[dict[str, Any]]:
    """Parse BT results rows.

    pdf text flattens the table as:
      term announced demand placed_nominal placed_price MIN ISIN MAX AVG maturity
      "182 zile 1.300.000,0 1.901.551,6 1.300.000,4 1.238.431,5 9,47 MD4003005106 9,98 9,98 04.02.2027"
    Every row is cross-checked: min <= avg <= max and the average rate implied
    by the volumes (Regulament pct. 72) must be within 0.15 p.p. of AVG.
    """
    out = []
    row_re = re.compile(
        r"(\d{1,3})\s*zile\s+([\d.,]+)\s+([\d.,]+)\s+([\d.,]+)\s+([\d.,]+)\s+([\d.,]+)\s+"
        r"(MD\d{10})\s+([\d.,]+)\s+([\d.,]+)\s+(\d{2}\.\d{2}\.\d{4})"
    )
    for m in row_re.finditer(re.sub(r"\s+", " ", text)):
        days = int(m.group(1))
        ann, dem, nom, pr, rmin = (parse_number(m.group(k)) for k in range(2, 7))
        isin = m.group(7)
        rmax, ravg = parse_number(m.group(8)), parse_number(m.group(9))
        mat = parse_date(m.group(10))
        rec = {
            "auction_date": auction_date.isoformat(), "isin": isin, "type": "BT",
            "term_label": f"{days} zile", "announced": ann, "demand": dem,
            "placed_nominal": nom, "placed_price": pr, "rate_min": rmin,
            "rate_avg": ravg, "rate_max": rmax, "maturity": mat.isoformat(),
            "unit": "mii lei", "source": source,
        }
        issues = []
        if not (rmin <= ravg <= rmax):
            issues.append("ordinea ratelor min/medie/max nu se verifică")
        if nom > 0 and pr > 0:
            price = pr / nom * 100
            implied = 100 * (100 - price) / price * 365 / days
            if abs(implied - ravg) > 0.15:
                issues.append(f"rata implicită {implied:.2f}% diferă de media {ravg:.2f}%")
        if issues:
            rec["_issues"] = issues
        out.append(rec)
    return out


# --------------------------------------------------------------------------
# Auction detail pages (HTML) "Licitație VMS: 03.11.2026, Termenul: 182"
# --------------------------------------------------------------------------
_DETAIL_LABELS = {
    "volumul ofertei": "announced",
    "volumul cererii": "demand",
    "realizat la prețul nominal": "placed_nominal",
    "realizat la pretul nominal": "placed_nominal",
    "realizat la prețul de realizare": "placed_price",
    "realizat la pretul de realizare": "placed_price",
}


def parse_auction_detail(text: str) -> dict[str, Any]:
    """Parse the text of an auction detail page (already converted to text)."""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    rec: dict[str, Any] = {}

    def value_after(label: str) -> str | None:
        for i, ln in enumerate(lines):
            low = ln.lower()
            if low.startswith(label):
                rest = ln.split(":", 1)[1].strip() if ":" in ln else ""
                if rest:
                    return rest
                return lines[i + 1] if i + 1 < len(lines) else None
        return None

    d = value_after("data licitatiei") or value_after("data licitației")
    if d and DATE_RE.search(d):
        rec["auction_date"] = parse_date(DATE_RE.search(d).group(0)).isoformat()
    t = value_after("tipul vms")
    if t:
        rec["type"] = "OS" if "oblig" in t.lower() else "BT"
    term = value_after("termenul")
    if term:
        rec["term_raw"] = term
    rate = value_after("rata nominala a dobinzii") or value_after("rata nominală a dobânzii")
    if rate:
        try:
            rec["rate_avg"] = parse_number(rate)
        except ValueError:
            pass
    for ln in lines:
        low = ln.lower()
        for label, key in _DETAIL_LABELS.items():
            if low.startswith(label):
                nums = re.findall(r"\d[\d.]*,\d+|\d[\d.]*", ln[len(label):])
                if nums:
                    rec[key] = parse_number(nums[-1])
    return rec


# --------------------------------------------------------------------------
# Quarterly calendar PDF ("trimestrul IV-2026 web-rom.pdf")
# --------------------------------------------------------------------------
BT_TERMS = ["91 zile", "182 zile", "364 zile"]


def calendar_url(year: int, quarter: int, www: bool = False) -> str:
    host = "www.mf.gov.md" if www else "mf.gov.md"
    return f"https://{host}/sites/default/files/trimestrul%20{ROMAN[quarter]}-{year}%20web-rom.pdf"


def parse_calendar_rows(rows: list[list[str | None]], quarter: str, source: str) -> list[dict[str, Any]]:
    """Parse table rows extracted with pdfplumber.

    A data row contains: auction date, settlement date, then volume cells per
    term column, optional bond volume and maturity dates. Column meaning is
    taken from the header row (cells containing '91', '182', '364', 'ani').
    Returned entries carry ``_issues`` when the layout is ambiguous; the
    validator then requires manual confirmation.
    """
    header_terms: dict[int, str] = {}
    entries: list[dict[str, Any]] = []
    for row in rows:
        cells = [(c or "").replace("\n", " ").strip() for c in row]
        joined = " ".join(cells)
        if not DATE_RE.search(joined):
            for idx, c in enumerate(cells):
                for t in ("91", "182", "364"):
                    if re.fullmatch(rf"{t}\s*zile?", c, re.IGNORECASE) or c == t:
                        header_terms[idx] = f"{t} zile"
                tm = re.fullmatch(r"(\d{1,2})\s*ani?", c, re.IGNORECASE)
                if tm:
                    header_terms[idx] = f"{tm.group(1)} ani"
            continue
        ds = dates_in(joined)
        if len(ds) < 2:
            continue
        auction, settle = ds[0], ds[1]
        maturities = ds[2:]
        found = []
        for idx, term in header_terms.items():
            if idx < len(cells) and cells[idx] and not DATE_RE.search(cells[idx]):
                found.append((term, cells[idx]))
        if not found:
            entries.append({"quarter": quarter, "auction_date": auction.isoformat(),
                            "settlement_date": settle.isoformat(), "type": None, "term": None,
                            "volume": None, "maturity": None, "source": source,
                            "_issues": ["coloane nerecunoscute"]})
            continue
        for k, (term, vol) in enumerate(found):
            entries.append({
                "quarter": quarter, "auction_date": auction.isoformat(),
                "settlement_date": settle.isoformat(),
                "type": "OS" if term.endswith("ani") else "BT", "term": term,
                "volume": vol, "maturity": maturities[k].isoformat() if k < len(maturities) else None,
                "source": source,
            })
    return entries
