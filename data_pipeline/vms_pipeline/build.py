"""Build data/vms_data.json from manual seeds + mf.gov.md publications.

Usage:
    python -m vms_pipeline.build            # online: scrape, validate, write
    python -m vms_pipeline.build --offline  # only merge manual seeds (no network)

Exit code 0 always when the published file is consistent; scraping problems
are recorded in data/validation_log.json instead of breaking the dataset.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
import time
import traceback
from pathlib import Path
from typing import Any

from . import parsers

ROOT = Path(__file__).resolve().parents[2]          # repository root
MANUAL = ROOT / "data_pipeline" / "manual"
OUT_DIR = ROOT / "data"
OUT = OUT_DIR / "vms_data.json"
STATE = OUT_DIR / "state.json"
LOG = OUT_DIR / "validation_log.json"
EVENTS = OUT_DIR / "events.json"
SCRAPED = OUT_DIR / "scraped"                       # raw parsed records, kept for audit
DEBUG = OUT_DIR / "debug"                           # text of PDFs the parsers could not read
RESULTS_PARSER_VERSION = 2
PLACEMENT_PARSER_VERSION = 2   # crește-l când schimbi parse_placement: comunicatele OS se recitesc
SCHEMA = 1


def load(path: Path, default: Any) -> Any:
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return default


def dump(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def bucket(days: int) -> int:
    return 91 if days <= 120 else 182 if days <= 250 else 364


# --------------------------------------------------------------------------
def scrape(state: dict, log: list, budget_s: float = 420) -> dict[str, list]:
    """Download new publications. Returns parsed (unvalidated) records.

    Limits that keep every run short (GitHub stops the job after 15 minutes):
      * a time budget: when it runs out we stop and continue on the next run;
      * at most MAX_NEW documents per run, newest first;
      * treasury bills and results older than BT_WINDOW days are skipped
        (they are already matured); bonds are fetched for the whole archive;
      * a document that fails 3 times is skipped and reported in the log.
    """
    from . import sources

    MAX_NEW = 15
    BT_WINDOW = 400
    deadline = time.monotonic() + budget_s
    got: dict[str, list] = {"securities": [], "results": [], "details": [], "calendar": []}
    processed: set[str] = set(state.setdefault("processed", []))
    attempts: dict[str, int] = state.setdefault("attempts", {})
    if state.get("results_parser") != RESULTS_PARSER_VERSION:
        # parser nou: rezultatele marcate anterior se citesc din nou
        processed = {u for u in processed if "rezultatele" not in u.lower() and "/content/licita" not in u}
        for u in [u for u in attempts if "rezultatele" in u.lower()]:
            del attempts[u]
        state["results_parser"] = RESULTS_PARSER_VERSION
    if state.get("placement_parser") != PLACEMENT_PARSER_VERSION:
        # parser nou de plasare: comunicatele de obligațiuni (OS) se recitesc, ca să recuperăm
        # cupoanele necitite anterior; titlurile deja publicate nu se pierd (merge păstrează datele vechi)
        retry = set(state.get("placement_retry", [])) | {u for u in processed if "os-" in u.lower() and "plasare" in u.lower()}
        processed -= retry
        for u in retry:
            attempts.pop(u, None)
        state["placement_retry"] = sorted(retry & set(state.get("placement_retry", [])))
        state["placement_parser"] = PLACEMENT_PARSER_VERSION
    today = dt.date.today()
    cutoff = today - dt.timedelta(days=BT_WINDOW)
    budget_hit = False

    def out_of_time() -> bool:
        nonlocal budget_hit
        if time.monotonic() > deadline:
            if not budget_hit:
                log.append({"level": "info", "msg": "buget de timp atins – continuă la rularea următoare"})
            budget_hit = True
        return budget_hit

    def failed(url: str, msg: str) -> None:
        attempts[url] = attempts.get(url, 0) + 1
        log.append({"level": "error", "url": url, "msg": msg, "attempt": attempts[url]})

    def dated(items: list[tuple[str, str]]) -> list[tuple[dt.date, str, str]]:
        out = []
        for url, title in items:
            m = sources.DATE_IN_NAME.search(title) or sources.DATE_IN_NAME.search(url)
            if not m:
                continue
            try:
                d = dt.date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
            except ValueError:
                continue
            out.append((d, url, title))
        return sorted(out, reverse=True)  # cele mai noi întâi

    try:
        _scrape_steps(sources, state, log, got, processed, attempts, today, cutoff, MAX_NEW, out_of_time, failed, dated)
    except Exception:
        log.append({"level": "error", "msg": "pas de preluare întrerupt", "trace": traceback.format_exc()[-1500:]})
    finally:
        state["processed"] = sorted(processed)  # progresul nu se pierde la eroare
    return got


def save_debug(url: str, text: str) -> None:
    """Păstrează textul extras dintr-un PDF necitit, pentru ajustarea parserului."""
    DEBUG.mkdir(parents=True, exist_ok=True)
    name = "".join(ch if ch.isalnum() else "_" for ch in url.rsplit("/", 1)[-1])[:80]
    target = DEBUG / f"{name}.txt"
    target.write_text(text, encoding="utf-8")
    # păstrăm cele mai recente 20 de fișiere
    existing = sorted(DEBUG.glob("*.txt"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in existing[20:]:
        old.unlink(missing_ok=True)


def _scrape_steps(sources, state, log, got, processed, attempts, today, cutoff, MAX_NEW, out_of_time, failed, dated) -> None:
    placements, results = sources.placement_and_result_pdfs()
    todo = [(d, u, t) for d, u, t in dated(placements)
            if u not in processed and attempts.get(u, 0) < 3
            and (d >= cutoff or "os-" in u.lower() or "os-" in t.lower())]
    for auction, url, _ in todo[:MAX_NEW]:
        if out_of_time():
            break
        try:
            data = sources.pdf_bytes(url)
            if not data[:1024].lstrip().startswith(b"%PDF"):
                raise ValueError("răspunsul nu este PDF")
            text = sources.pdf_text(data)
            recs = parsers.parse_placement(text, auction, url)
            got["securities"].extend(recs)
            no_coupon = [r["isin"] for r in recs if "rata cuponului lipsă" in r.get("_issues", [])]
            if no_coupon:
                # nu marcăm ca procesat: se reîncearcă (max. 3 ori, resetat la o versiune nouă de parser);
                # textul rămâne în data/debug pentru diagnostic
                save_debug(url, text)
                needs = state.setdefault("placement_retry", [])
                if url not in needs:
                    needs.append(url)
                failed(url, f"plasare: cupon necitit pentru {', '.join(no_coupon)} (text salvat în data/debug)")
            else:
                processed.add(url)
                if url in state.get("placement_retry", []):
                    state["placement_retry"].remove(url)
        except Exception as e:  # keep going, record the problem
            failed(url, f"plasare: {e}")
    if len(todo) > MAX_NEW:
        log.append({"level": "info", "msg": f"{len(todo) - MAX_NEW} comunicate de plasare rămase pentru rulările următoare"})

    todo = [(d, u, t) for d, u, t in dated(results) if u not in processed and attempts.get(u, 0) < 3 and d >= cutoff]
    for auction, url, _ in todo[:MAX_NEW]:
        if out_of_time():
            break
        try:
            data = sources.pdf_bytes(url)
            if not data[:1024].lstrip().startswith(b"%PDF"):
                raise ValueError("răspunsul nu este PDF")
            text = sources.pdf_text(data)
            recs = parsers.parse_results_bt(text, auction, url)
            if recs:
                got["results"].extend(recs)
                processed.add(url)
            elif "zile" not in text:
                processed.add(url)  # doar obligațiuni: volumele vin din paginile de detaliu
            else:
                save_debug(url, text)
                failed(url, "rezultate: niciun rând recunoscut (text salvat în data/debug)")
        except Exception as e:
            failed(url, f"rezultate: {e}")

    if not out_of_time():
        for url in sources.auction_detail_links(limit=12):
            if url in processed or attempts.get(url, 0) >= 3:
                continue
            if out_of_time():
                break
            try:
                rec = parsers.parse_auction_detail(sources.page_text(url))
                rec["source"] = url
                if "auction_date" in rec and "rate_avg" in rec:
                    got["details"].append(rec)
                    processed.add(url)
                else:
                    failed(url, "detaliu: câmpuri lipsă")
            except Exception as e:
                failed(url, f"detaliu: {e}")

    _scrape_coupon_notices(sources, state, log, processed, attempts, today, out_of_time, failed)

    q = (today.month - 1) // 3 + 1
    for year, quarter in sorted({(today.year, q), (today.year + (q == 4), 1 if q == 4 else q + 1)}):
        if out_of_time():
            break
        for url in (parsers.calendar_url(year, quarter), parsers.calendar_url(year, quarter, www=True)):
            if not sources.exists(url):
                continue
            try:
                data = sources.pdf_bytes(url)
            except Exception as e:
                failed(url, f"calendar: {e}")
                break
            if not data[:1024].lstrip().startswith(b"%PDF"):
                continue  # site-ul răspunde cu o pagină HTML: calendarul nu este (încă) publicat
            digest = hashlib.sha256(data).hexdigest()
            key = f"{year}-Q{quarter}"
            if state.setdefault("calendar_hash", {}).get(key) == digest:
                break
            try:
                rows = [r for t in sources.pdf_tables(data) for r in t]
                entries = parsers.parse_calendar_rows(rows, key, url)
            except Exception as e:
                failed(url, f"calendar: {e}")
                break
            if entries:
                got["calendar"].append({"quarter": key, "source_url": url, "entries": entries})
            else:
                log.append({"level": "warn", "url": url,
                            "msg": "calendar găsit dar tabelul nu a putut fi citit – completează manual/calendar.json"})
            state["calendar_hash"][key] = digest
            break


def _scrape_coupon_notices(sources, state, log, processed, attempts, today, out_of_time, failed) -> None:
    """Ratele cupoanelor anunțate pentru obligațiunile cu dobândă flotantă.

    Se păstrează în state["coupon_notices"] (istoric complet) și se aplică la fiecare rulare.
    Surse: link-urile de pe paginile MF + denumirile uzuale ale fișierelor (verificate o dată pe zi).
    """
    if out_of_time():
        return
    notices: list[dict] = state.setdefault("coupon_notices", [])
    urls = [u for u, _ in sources.coupon_notice_pdfs()]
    found_links = len(urls)
    if state.get("notice_guess_day") != today.isoformat():
        state["notice_guess_day"] = today.isoformat()
        for isin in state.get("floating_isins", []):
            if out_of_time():
                break
            for u in sources.guess_coupon_notice_urls(isin):
                if u not in processed and u not in urls and sources.exists(u):
                    urls.append(u)
    new = 0
    for url in urls:
        if url in processed or attempts.get(url, 0) >= 3 or out_of_time() or new >= 25:
            continue
        try:
            data = sources.pdf_bytes(url)
            if not data[:1024].lstrip().startswith(b"%PDF"):
                raise ValueError("răspunsul nu este PDF")
            text = sources.pdf_text(data)
            rec = parsers.parse_coupon_notice(text, url)
            if not rec:
                save_debug(url, text)
                failed(url, "cupon flotant: comunicat necitit (text salvat în data/debug)")
                continue
            if rec.get("_issues"):
                log.append({"level": "warn", "isin": rec["isin"], "msg": "cupon flotant: " + "; ".join(rec["_issues"]), "record": rec})
            else:
                notices[:] = [n for n in notices if not (n["isin"] == rec["isin"] and n["date"] == rec["date"])] + [rec]
                new += 1
            processed.add(url)
        except Exception as e:
            failed(url, f"cupon flotant: {e}")
    log.append({"level": "info", "msg": f"cupoane flotante: {found_links} link-uri pe paginile MF, "
                                         f"{len(urls)} comunicate candidate, {new} noi, {len(notices)} în total"})


def apply_coupon_notices(secs: dict[str, dict], notices: list[dict]) -> None:
    """Adaugă la obligațiunile flotante istoricul ratelor anunțate și marja."""
    for n in sorted(notices, key=lambda n: n["date"]):
        s = secs.get(n["isin"])
        if not s or s.get("type") != "OS":
            continue
        s = secs[n["isin"]] = {**s, "coupon_type": "flotant"}
        hist = {h["date"]: h for h in s.get("coupon_history", [])}
        hist[n["date"]] = {k: n[k] for k in ("date", "rate", "base", "margin") if k in n}
        s["coupon_history"] = [hist[k] for k in sorted(hist)]
        if n.get("margin") is not None:
            s["margin"] = n["margin"]


# --------------------------------------------------------------------------
def merge(prev: dict, manual: dict, scraped: dict, log: list) -> dict:
    # arhiva 2009–2026 (manual/history.json) este stratul de bază: completează doar ce lipsește,
    # orice valoare publicată anterior / preluată automat / manuală are prioritate
    hist = manual.get("history") or {}
    hist_secs = {s["isin"]: s for s in hist.get("securities", [])}
    # securities: arhivă + previous published + scraped + manual (manual wins)
    secs: dict[str, dict] = dict(hist_secs)
    for s in prev.get("securities", []):
        secs[s["isin"]] = {**hist_secs.get(s["isin"], {}), **s}
    # cupoane cunoscute din orice sursă (publicat anterior, manual, alte comunicate – ex. redeschideri)
    known_coupon: dict[str, float] = {}
    for s in [*prev.get("securities", []), *scraped.get("securities", []), *manual["securities"]]:
        if s.get("coupon_rate"):
            known_coupon[s["isin"]] = s["coupon_rate"]
    for s in scraped.get("securities", []):
        if s.get("_issues"):
            issues = list(s["_issues"])
            if "rata cuponului lipsă" in issues and s["isin"] in known_coupon:
                s = {**s, "coupon_rate": known_coupon[s["isin"]]}
                issues.remove("rata cuponului lipsă")
                log.append({"level": "info", "isin": s["isin"],
                            "msg": f"cupon completat automat ({s['coupon_rate']}%) din altă sursă pentru același ISIN"})
            if issues:
                log.append({"level": "warn", "isin": s["isin"], "msg": "; ".join(issues), "record": s})
            if not s.get("issue_date") or not s.get("maturity"):
                continue
            if s["type"] == "OS" and not s.get("coupon_rate") and s.get("coupon_type") != "flotant":
                # carantină: titlul nu se publică până nu se află cuponul (reîncercare automată /
                # manual/securities.json), dar restul datelor se actualizează normal
                log.append({"level": "warn", "isin": s["isin"],
                            "msg": "carantină: obligațiune fără cupon – nepublicată până la confirmare"})
                continue
            s = {k: v for k, v in s.items() if k != "_issues"}
            if issues:
                s["unverified"] = True
        old = secs.get(s["isin"])
        if old and s["type"] == "OS" and old.get("issue_date") and old["issue_date"] < s["issue_date"]:
            # reopening of an existing bond: keep the original issue date and schedule
            s = {**s, "issue_date": old["issue_date"], "coupon_dates": old.get("coupon_dates") or s["coupon_dates"]}
        secs[s["isin"]] = {**(old or {}), **s}
    for s in manual["securities"]:
        secs[s["isin"]] = s
    apply_coupon_notices(secs, scraped.get("coupon_notices", []))
    by_isin = secs

    # rates history (settlement-date keyed, like the original app)
    rates = {(r["date"], r["days"]): r for r in hist.get("rates", [])}
    rates.update({(r["date"], r["days"]): r for r in prev.get("rates", [])})
    for r in manual["rates"]:
        rates[(r["date"], r["days"])] = r

    # auction results
    hist_res = {(a["auction_date"], a["isin"]): a for a in hist.get("auctions", [])}
    res: dict[tuple[str, str], dict] = dict(hist_res)
    for a in prev.get("auctions", []):
        key = (a["auction_date"], a["isin"])
        res[key] = {**hist_res.get(key, {}), **a}

    def put_result(rec: dict) -> None:
        key = (rec["auction_date"], rec["isin"])
        res[key] = {**res.get(key, {}), **{k: v for k, v in rec.items() if v is not None}}

    # 1. derive from rates history + securities
    for s in by_isin.values():
        if s["type"] != "BT" or not s.get("issue_date"):
            continue
        if (s["auction_date"], s["isin"]) in hist_res:
            continue  # arhiva are ratele exacte ale licitației (în 2015 – două licitații pe aceeași decontare)
        r = rates.get((s["issue_date"], bucket(s["term_days"])))
        if r:
            put_result({"auction_date": s["auction_date"], "isin": s["isin"], "type": "BT",
                        "term_label": s["term_label"], "rate_min": r["min"], "rate_avg": r["avg"],
                        "rate_max": r["max"], "settlement_date": s["issue_date"], "maturity": s["maturity"]})
    # 2. PDF results (min/avg/max + volumes)
    for r in scraped.get("results", []):
        if r.get("_issues"):
            log.append({"level": "warn", "isin": r["isin"], "msg": "; ".join(r["_issues"]), "record": r})
            continue
        put_result({k: v for k, v in r.items() if k != "source"})
        s = by_isin.get(r["isin"])
        if s:
            rates[(s["issue_date"], bucket(s["term_days"]))] = {
                "date": s["issue_date"], "days": bucket(s["term_days"]),
                "max": r["rate_max"], "avg": r["rate_avg"], "min": r["rate_min"]}
    # 3. detail pages (volumes + average) matched to a security by date/type/term
    for d in scraped.get("details", []):
        # MF datează unele pagini cu ziua licitației, altele cu ziua decontării
        cands = [s for s in by_isin.values()
                 if d["auction_date"] in (s["auction_date"], s.get("issue_date")) and s["type"] == d.get("type")]
        term_num = "".join(ch for ch in str(d.get("term_raw", "")) if ch.isdigit())
        if d.get("type") == "BT" and term_num:
            cands = [s for s in cands if bucket(s["term_days"]) == bucket(int(term_num))]
        elif term_num:
            cands = [s for s in cands if s["term_label"].startswith(term_num + " ")]
        if len(cands) != 1:
            log.append({"level": "warn", "msg": "detaliu licitație fără ISIN unic", "record": d})
            continue
        s = cands[0]
        put_result({"auction_date": s["auction_date"], "isin": s["isin"], "type": s["type"],
                    "term_label": s["term_label"], "announced": d.get("announced"), "demand": d.get("demand"),
                    "placed_nominal": d.get("placed_nominal"), "placed_price": d.get("placed_price"),
                    "rate_avg": d.get("rate_avg"), "settlement_date": s["issue_date"], "maturity": s["maturity"],
                    "unit": "mii lei"})
    # 4. manual volumes win
    for v in manual["volumes"]:
        s = by_isin.get(v["isin"], {})
        put_result({**v, "type": s.get("type"), "term_label": s.get("term_label"),
                    "settlement_date": s.get("issue_date"), "maturity": s.get("maturity")})
    for a in res.values():
        a.pop("source", None)

    # calendar: previous + scraped + manual (manual wins per quarter)
    cal = {q["quarter"]: q for q in prev.get("calendar", [])}
    for q in scraped.get("calendar", []):
        bad = [e for e in q["entries"] if e.get("_issues")]
        if bad:
            log.append({"level": "warn", "msg": f"calendar {q['quarter']}: {len(bad)} rânduri neclare – necesită verificare",
                        "url": q["source_url"]})
            continue
        cal[q["quarter"]] = q
    for q in manual["calendar"]:
        cal[q["quarter"]] = q

    return {
        "schema": SCHEMA,
        "rates": sorted(rates.values(), key=lambda r: (r["date"], r["days"])),
        "securities": sorted(by_isin.values(), key=lambda s: (s["auction_date"], s["isin"])),
        "auctions": sorted(res.values(), key=lambda a: (a["auction_date"], a["isin"])),
        "calendar": [cal[k] for k in sorted(cal)],
    }


# --------------------------------------------------------------------------
def validate(data: dict) -> list[str]:
    """Hard errors: if any, the previous dataset stays published."""
    errs = []
    if len(data["rates"]) < 100:
        errs.append("istoric de rate prea scurt")
    for r in data["rates"]:
        if not (0 < r["min"] <= r["avg"] <= r["max"] < 40):
            errs.append(f"rată invalidă {r}")
    for s in data["securities"]:
        if not s["isin"].startswith("MD") or len(s["isin"]) != 12:
            errs.append(f"ISIN invalid {s['isin']}")
        if s.get("issue_date") and s.get("maturity") and s["issue_date"] >= s["maturity"]:
            errs.append(f"{s['isin']}: emitere după scadență")
        if s["type"] == "OS" and not s.get("coupon_rate") and s.get("coupon_type") != "flotant":
            errs.append(f"{s['isin']}: obligațiune fără cupon")
        for h in s.get("coupon_history", []):
            if not 0 < h["rate"] < 40:
                errs.append(f"{s['isin']}: rată cupon flotant neplauzibilă {h}")
    for a in data["auctions"]:
        mn, av, mx = a.get("rate_min"), a.get("rate_avg"), a.get("rate_max")
        if None not in (mn, av, mx) and not (mn <= av <= mx):
            errs.append(f"{a['isin']} {a['auction_date']}: min/medie/max inconsistente")
    for q in data["calendar"]:
        for e in q["entries"]:
            ad = dt.date.fromisoformat(e["auction_date"])
            sd = dt.date.fromisoformat(e["settlement_date"])
            if not (0 < (sd - ad).days <= 7):
                errs.append(f"calendar {e['auction_date']}: decontare neplauzibilă")
    return errs


def events_for(prev: dict, new: dict) -> list[dict]:
    """Deduplicated notification events (ids are stable)."""
    ev = []
    prev_q = {q["quarter"] for q in prev.get("calendar", [])}
    for q in new["calendar"]:
        if q["quarter"] not in prev_q:
            ev.append({"id": f"calendar:{q['quarter']}", "kind": "calendar", "title": f"Calendar nou {q['quarter']}"})
    prev_sec = {s["isin"] for s in prev.get("securities", [])}
    for d in sorted({s["auction_date"] for s in new["securities"] if s["isin"] not in prev_sec}):
        ev.append({"id": f"launch:{d}", "kind": "launch", "title": f"Licitație anunțată {d}"})
    prev_res = {(a["auction_date"], a["isin"]) for a in prev.get("auctions", []) if a.get("placed_nominal") is not None}
    for d in sorted({a["auction_date"] for a in new["auctions"]
                     if a.get("placed_nominal") is not None and (a["auction_date"], a["isin"]) not in prev_res}):
        ev.append({"id": f"integrated:{d}", "kind": "integrated", "title": f"Rezultate integrate {d}"})
    # rezultate (rata medie publicată) – pentru notificarea „rezultate”
    prev_rate = {a["auction_date"] for a in prev.get("auctions", []) if a.get("rate_avg") is not None}
    for d in sorted({a["auction_date"] for a in new["auctions"] if a.get("rate_avg") is not None} - prev_rate):
        ev.append({"id": f"results:{d}", "kind": "results", "title": f"Rezultate licitație {d}"})
    return ev


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true")
    ap.add_argument("--asset", type=Path, help="also copy the dataset here (Flutter asset)")
    args = ap.parse_args(argv)

    prev = load(OUT, {})
    state = load(STATE, {})
    log: list[dict] = []
    manual = {
        "securities": load(MANUAL / "securities.json", []),
        "rates": load(MANUAL / "rates_history.json", []),
        "volumes": load(MANUAL / "auction_volumes.json", []),
        "calendar": load(MANUAL / "calendar.json", {"quarters": []})["quarters"],
        "history": load(MANUAL / "history.json", {}),
    }
    scraped: dict[str, list] = {}
    if not args.offline:
        try:
            scraped = scrape(state, log)
            dump(SCRAPED / f"{dt.date.today().isoformat()}.json", scraped)
        except Exception:
            log.append({"level": "error", "msg": "scrape eșuat", "trace": traceback.format_exc()[-2000:]})

    scraped["coupon_notices"] = state.get("coupon_notices", [])
    new = merge(prev, manual, scraped, log)
    state["floating_isins"] = sorted(s["isin"] for s in new["securities"]
                                     if s.get("coupon_type") == "flotant" and s.get("maturity", "") >= dt.date.today().isoformat())
    errs = validate(new)
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    log_entry = {"run": now, "offline": args.offline, "errors": errs, "warnings": log}
    hist = load(LOG, [])
    dump(LOG, ([log_entry] + hist)[:200])
    if errs:
        print("VALIDARE EȘUATĂ – datele publicate rămân neschimbate:", *errs[:20], sep="\n  ")
        dump(STATE, state)
        return 1

    body_old = {k: v for k, v in prev.items() if k != "generated_at"}
    changed = body_old != new
    if changed or not OUT.exists():
        new_ev = events_for(prev, new) if prev else []
        new["generated_at"] = now
        dump(OUT, new)
        if new_ev:
            ledger = load(EVENTS, [])
            seen = {e["id"] for e in ledger}
            fresh = [{**e, "at": now} for e in new_ev if e["id"] not in seen]
            dump(EVENTS, (fresh + ledger)[:300])
            for e in fresh:
                print("EVENT", e["id"], e["title"])
        print(f"dataset actualizat: {len(new['rates'])} rate, {len(new['securities'])} ISIN, "
              f"{len(new['auctions'])} rezultate, {len(new['calendar'])} trimestre")
    else:
        print("fără modificări")
    if not args.offline:
        # notificări push (doar evenimente relevante, o singură dată fiecare)
        from . import notify
        try:
            notify.run(load(EVENTS, []), load(OUT, {}), state, log_entry["warnings"])
        except Exception:
            log_entry["warnings"].append({"level": "error", "msg": "notificări: eroare neprevăzută",
                                          "trace": traceback.format_exc()[-1500:]})
        dump(LOG, ([log_entry] + hist)[:200])
    if args.asset:
        dump(args.asset, load(OUT, {}))
    dump(STATE, state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
