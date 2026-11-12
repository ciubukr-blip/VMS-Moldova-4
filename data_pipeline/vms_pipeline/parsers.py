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
    s = s.strip().replace("%", "").replace("\u00a0", "").replace(" ", "")
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


# Coupon wording seen (or plausible) in MF communiqués across years:
#   "7,75 la sută anual", "7,75 la suta", "7.75 %", "7,75% anual", "8 la sută",
#   "rata dobânzii/cuponului: 7,75", "dobânda 7,75 procente"
_PCT = r"(\d{1,2}(?:[.,]\d{1,4})?)"
COUPON_RES = [
    re.compile(_PCT + r"\s*(?:la\s*sut|procent|%)", re.IGNORECASE),
    re.compile(r"(?:cupon\w*|dob[aâ]nd\w*|dobinz\w*)[^\d]{0,40}?" + _PCT + r"(?!\d)(?![.,]\d)(?!\s*(?:zile|ani|an)\b)",
               re.IGNORECASE),
]
FLOATING_RE = re.compile(r"flotant|variabil|rata\s+de\s+baz", re.IGNORECASE)


def parse_coupon(text: str) -> float | None:
    """First plausible annual coupon (0 < x < 40) in the text after an ISIN."""
    for rx in COUPON_RES:
        for m in rx.finditer(text):
            try:
                v = float(m.group(1).replace(",", "."))
            except ValueError:
                continue
            if 0 < v < 40 and v != 100:
                return v
    return None


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
        # la dobânda flotantă cifra din rând e marja, nu cuponul – nu o citim drept cupon
        floating = is_bond and bool(FLOATING_RE.search(before[-60:] + " " + after))
        coupon = None if floating else parse_coupon(after)
        if len(ds) < 2:
            issues.append("date emitere/scadență lipsă")
            issue_d = mat = None
            coupon_dates: list[str] = []
        else:
            issue_d, mat = ds[0], ds[1]
            coupon_dates = sorted({d.isoformat() for d in ds[2:] if issue_d < d <= mat}) if is_bond else []
        if is_bond and coupon is None and not floating:
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
        if is_bond and floating:
            rec["coupon_type"] = "flotant"
        if "redeschid" in flat.lower() and is_bond:
            # la redeschidere comunicatul conține maturitatea reziduală și dobânda acumulată,
            # nu datele emisiunii inițiale: nu actualizăm automat titlul
            rec["note"] = "Redeschidere – se confirmă manual"
            rec["issue_date"] = rec["maturity"] = rec["term_days"] = None
            issues.append("redeschidere: datele emisiunii inițiale se confirmă manual")
        if issues:
            rec["_issues"] = issues
        out.append(rec)
    return out


# --------------------------------------------------------------------------
# Results communiqués ("Rezultatele licitatie 04-08-2026 - rom.pdf")
# --------------------------------------------------------------------------
def parse_results_bt(text: str, auction_date: dt.date, source: str) -> list[dict[str, Any]]:
    """Parse BT results rows.

    Every row is cross-checked: min <= avg <= max and the average rate implied
    by the volumes (Regulament pct. 72) must be within 0.15 p.p. of AVG.
    """
    out = []
    flat = re.sub(r"\s+", " ", text)
    num = r"([\d.,]+)"
    # format actual MF: termen ISIN anunțat cerere nominal preț MIN MAX MEDIE scadență
    current = re.compile(
        rf"(\d{{1,3}})\s*zile\s+(MD\d{{10}})\s+{num}\s+{num}\s+{num}\s+{num}\s+{num}\s+{num}\s+{num}\s+(\d{{2}}\.\d{{2}}\.\d{{4}})"
    )
    # format vechi (text extras altfel): termen anunțat cerere nominal preț MIN ISIN MAX MEDIE scadență
    legacy = re.compile(
        rf"(\d{{1,3}})\s*zile\s+{num}\s+{num}\s+{num}\s+{num}\s+{num}\s+(MD\d{{10}})\s+{num}\s+{num}\s+(\d{{2}}\.\d{{2}}\.\d{{4}})"
    )
    rows = []
    for m in current.finditer(flat):
        g = m.groups()
        rows.append((int(g[0]), g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9]))
    if not rows:
        for m in legacy.finditer(flat):
            g = m.groups()
            rows.append((int(g[0]), g[6], g[1], g[2], g[3], g[4], g[5], g[7], g[8], g[9]))
    for days, isin, ann_s, dem_s, nom_s, pr_s, min_s, max_s, avg_s, mat_s in rows:
        ann, dem, nom, pr = (parse_number(x) for x in (ann_s, dem_s, nom_s, pr_s))
        rmin, rmax, ravg = parse_number(min_s), parse_number(max_s), parse_number(avg_s)
        mat = parse_date(mat_s)
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
