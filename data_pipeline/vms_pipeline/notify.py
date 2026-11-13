"""Notificări push prin Firebase Cloud Messaging (HTTP v1).

Robotul trimite pe trei subiecte, la care aplicația se abonează după comutatoarele
din ecranul Alerte:
  * ``licitatii`` – comunicat de plasare nou (licitație viitoare);
  * ``rezultate`` – rezultatele licitației, rata medie pe fiecare termen;
  * ``calendar``  – calendar trimestrial nou.

Fără spam: se notifică doar licitațiile viitoare, rezultatele din ultimele 3 zile și
calendarele care conțin licitații viitoare. Arhiva recuperată nu trimite nimic.
Fiecare eveniment (id stabil) se trimite o singură dată (``state["notified"]``).

Configurare: secretul GitHub ``FIREBASE_SERVICE_ACCOUNT`` (cheia JSON a contului de
serviciu). Fără el, pasul este sărit și restul robotului funcționează normal.
"""
from __future__ import annotations

import datetime as dt
import json
import os
from typing import Any, Callable
from zoneinfo import ZoneInfo

TOPIC = {"launch": "licitatii", "results": "rezultate", "calendar": "calendar"}
RESULTS_WINDOW_DAYS = 3
ROMAN = {"1": "I", "2": "II", "3": "III", "4": "IV"}


def today_chisinau() -> dt.date:
    return dt.datetime.now(ZoneInfo("Europe/Chisinau")).date()


def _ro(d: str) -> str:
    y, m, day = d.split("-")
    return f"{day}.{m}.{y}"


def _pct(v: float) -> str:
    return f"{v:.2f}".replace(".", ",") + "%"


def _term_num(label: str) -> int:
    digits = "".join(ch for ch in label if ch.isdigit())
    return int(digits) if digits else 0


def _terms(securities: list[dict]) -> str:
    parts = []
    for typ in ("BT", "OS"):
        labels = sorted({s["term_label"] for s in securities if s["type"] == typ and s.get("term_label")}, key=_term_num)
        if not labels:
            continue
        if typ == "BT":
            parts.append("BT " + ", ".join(str(_term_num(x)) for x in labels) + " zile")
        else:
            parts.append("OS " + ", ".join(labels))
    return " · ".join(parts)


def build_message(event: dict, data: dict, today: dt.date) -> dict[str, Any] | None:
    """Mesajul pentru un eveniment, sau None dacă nu (mai) e relevant."""
    kind = event.get("kind")
    key = event["id"].split(":", 1)[1]
    if kind == "launch":
        if key < today.isoformat():
            return None
        secs = [s for s in data["securities"] if s["auction_date"] == key]
        if not secs:
            return None
        body = _terms(secs)
        settle = sorted({s["issue_date"] for s in secs if s.get("issue_date")})
        if settle:
            body += f". Decontare {_ro(settle[0])}."
        return {"topic": TOPIC[kind], "title": f"Licitație VMS anunțată: {_ro(key)}", "body": body}
    if kind == "results":
        if key < (today - dt.timedelta(days=RESULTS_WINDOW_DAYS)).isoformat():
            return None
        res = [a for a in data["auctions"] if a["auction_date"] == key and a.get("rate_avg") is not None]
        if not res:
            return None
        res.sort(key=lambda a: (a.get("type") != "BT", _term_num(a.get("term_label", ""))))
        body = " · ".join(f"{a.get('term_label') or a['isin']} {_pct(a['rate_avg'])}" for a in res)
        return {"topic": TOPIC[kind], "title": f"Rezultatele licitației din {_ro(key)}", "body": "Rata medie: " + body}
    if kind == "calendar":
        q = next((c for c in data["calendar"] if c["quarter"] == key), None)
        if not q:
            return None
        upcoming = sorted(e["auction_date"] for e in q["entries"] if e["auction_date"] >= today.isoformat())
        if not upcoming:
            return None
        year, _, n = key.partition("-Q")
        return {"topic": TOPIC[kind], "title": f"Calendarul MF pentru trim. {ROMAN.get(n, n)} {year}",
                "body": f"{len(upcoming)} licitații programate, prima pe {_ro(upcoming[0])}."}
    return None


def pending(ledger: list[dict], data: dict, notified: set[str], today: dt.date) -> list[tuple[dict, dict]]:
    """Evenimentele de trimis acum: netrimise și încă relevante."""
    out = []
    for e in sorted(ledger, key=lambda e: e["id"]):
        if e["id"] in notified or e.get("kind") not in TOPIC:
            continue
        msg = build_message(e, data, today)
        if msg:
            out.append((e, msg))
    return out


def _access_token(info: dict) -> str:
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    creds = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/firebase.messaging"])
    creds.refresh(Request())
    return creds.token


def _fcm_sender(info: dict) -> Callable[[dict, str], None]:
    import requests

    token = _access_token(info)
    url = f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send"

    def send(msg: dict, event_id: str) -> None:
        payload = {"message": {
            "topic": msg["topic"],
            "notification": {"title": msg["title"], "body": msg["body"]},
            "android": {"priority": "high", "notification": {"channel_id": msg["topic"], "tag": event_id}},
            # generated_at: versiunea datelor care conține evenimentul – aplicația o așteaptă
            "data": {"event": event_id, "generated_at": msg.get("generated_at", "")},
        }}
        r = requests.post(url, json=payload, timeout=30, headers={"Authorization": f"Bearer {token}"})
        if r.status_code != 200:
            raise RuntimeError(f"FCM {r.status_code}: {r.text[:300]}")

    return send


def run(ledger: list[dict], data: dict, state: dict, log: list,
        sender: Callable[[dict, str], None] | None = None, today: dt.date | None = None) -> int:
    """Trimite notificările în așteptare. Returnează câte au fost trimise."""
    notified: list[str] = state.setdefault("notified", [])
    todo = pending(ledger, data, set(notified), today or today_chisinau())
    if not todo:
        return 0
    if sender is None:
        raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
        if not raw:
            log.append({"level": "info", "msg": f"notificări: {len(todo)} în așteptare, dar FIREBASE_SERVICE_ACCOUNT "
                                                 "nu este configurat – nu s-a trimis nimic"})
            return 0
        try:
            sender = _fcm_sender(json.loads(raw))
        except Exception as e:  # cheie invalidă / rețea
            log.append({"level": "error", "msg": f"notificări: autentificare Firebase eșuată: {e}"})
            return 0
    sent = 0
    generated_at = str(data.get("generated_at") or "")
    for event, msg in todo:
        msg = {**msg, "generated_at": generated_at}
        try:
            sender(msg, event["id"])
        except Exception as e:
            log.append({"level": "error", "msg": f"notificare {event['id']} netrimisă (se reîncearcă): {e}"})
            continue
        notified.append(event["id"])
        sent += 1
        print("NOTIFICARE", msg["topic"], "|", msg["title"], "|", msg["body"])
    del notified[:-500]
    log.append({"level": "info", "msg": f"notificări trimise: {sent} din {len(todo)}"})
    return sent
