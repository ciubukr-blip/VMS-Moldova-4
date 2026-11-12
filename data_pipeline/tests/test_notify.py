"""Notificări push: relevanță (fără spam), conținut, trimitere o singură dată."""
import datetime as dt
import unittest

from vms_pipeline import notify

TODAY = dt.date(2026, 11, 12)
DATA = {
    "securities": [
        {"isin": "MD4003005270", "type": "BT", "term_label": "91 zile", "auction_date": "2026-11-17", "issue_date": "2026-11-19"},
        {"isin": "MD4003005288", "type": "BT", "term_label": "182 zile", "auction_date": "2026-11-17", "issue_date": "2026-11-19"},
        {"isin": "MD4003005296", "type": "BT", "term_label": "364 zile", "auction_date": "2026-11-17", "issue_date": "2026-11-19"},
        {"isin": "MD4004000001", "type": "OS", "term_label": "3 ani", "auction_date": "2021-06-16", "issue_date": "2021-06-18"},
    ],
    "auctions": [
        {"auction_date": "2026-11-11", "isin": "MD4003005106", "type": "BT", "term_label": "182 zile", "rate_avg": 9.98},
        {"auction_date": "2026-11-11", "isin": "MD4003005098", "type": "BT", "term_label": "91 zile", "rate_avg": 3.03},
        {"auction_date": "2026-10-13", "isin": "MD4003000000", "type": "BT", "term_label": "91 zile", "rate_avg": 3.1},
    ],
    "calendar": [
        {"quarter": "2027-Q1", "entries": [{"auction_date": "2027-01-13"}, {"auction_date": "2027-01-27"}]},
        {"quarter": "2026-Q3", "entries": [{"auction_date": "2026-08-04"}]},
    ],
}
LEDGER = [
    {"id": "launch:2026-11-17", "kind": "launch"},
    {"id": "launch:2021-06-16", "kind": "launch"},          # arhivă – fără notificare
    {"id": "results:2026-11-11", "kind": "results"},
    {"id": "results:2026-10-13", "kind": "results"},        # prea vechi
    {"id": "calendar:2027-Q1", "kind": "calendar"},
    {"id": "calendar:2026-Q3", "kind": "calendar"},         # doar licitații trecute
    {"id": "integrated:2026-11-11", "kind": "integrated"},  # nu are subiect
]


class NotifyTests(unittest.TestCase):
    def test_only_relevant_events(self):
        ids = [e["id"] for e, _ in notify.pending(LEDGER, DATA, set(), TODAY)]
        self.assertEqual(ids, ["calendar:2027-Q1", "launch:2026-11-17", "results:2026-11-11"])

    def test_messages(self):
        msgs = {e["id"]: m for e, m in notify.pending(LEDGER, DATA, set(), TODAY)}
        launch = msgs["launch:2026-11-17"]
        self.assertEqual(launch["topic"], "licitatii")
        self.assertEqual(launch["title"], "Licitație VMS anunțată: 17.11.2026")
        self.assertEqual(launch["body"], "BT 91, 182, 364 zile. Decontare 19.11.2026.")
        res = msgs["results:2026-11-11"]
        self.assertEqual(res["topic"], "rezultate")
        self.assertEqual(res["body"], "Rata medie: 91 zile 3,03% · 182 zile 9,98%")
        cal = msgs["calendar:2027-Q1"]
        self.assertEqual((cal["topic"], cal["title"]), ("calendar", "Calendarul MF pentru trim. I 2027"))
        self.assertIn("2 licitații programate, prima pe 13.01.2027", cal["body"])

    def test_sent_once_and_retry_on_failure(self):
        state, log, sent = {}, [], []
        calls = {"n": 0}

        def sender(msg, eid):
            calls["n"] += 1
            if eid == "results:2026-11-11" and calls["n"] < 4:
                raise RuntimeError("temporar")
            sent.append(eid)

        self.assertEqual(notify.run(LEDGER, DATA, state, log, sender=sender, today=TODAY), 2)
        self.assertEqual(notify.run(LEDGER, DATA, state, log, sender=sender, today=TODAY), 1)  # reîncercare
        self.assertEqual(notify.run(LEDGER, DATA, state, log, sender=sender, today=TODAY), 0)  # nimic de două ori
        self.assertEqual(sorted(sent), ["calendar:2027-Q1", "launch:2026-11-17", "results:2026-11-11"])

    def test_without_secret_nothing_sent(self):
        import os
        os.environ.pop("FIREBASE_SERVICE_ACCOUNT", None)
        state, log = {}, []
        self.assertEqual(notify.run(LEDGER, DATA, state, log, today=TODAY), 0)
        self.assertEqual(state["notified"], [])
        self.assertIn("nu este configurat", log[-1]["msg"])


if __name__ == "__main__":
    unittest.main()
