"""Offline tests for the MF parsers, built on text extracted from real
publications (Nov 2026). Run: python -m unittest discover -s tests"""
import datetime as dt
import unittest

from vms_pipeline import parsers

PLACEMENT_BT = """Bonuri de trezorerie 91 zile MD4003005270 100 60 cu scont 05.11.2026 04.02.2027
Bonuri de trezorerie 182 zile MD4003005288 100 1400 cu scont 05.11.2026 06.05.2027
Bonuri de trezorerie 364 zile MD4003005296 100 1800 cu scont 05.11.2026 04.11.2027"""

PLACEMENT_OS = """Obligațiuni de stat cu dobândă fixă
2 ani MD4004002763 100 30,0 cu scont, la
valoarea
nominală
7,75 la sută anual
09.10.2026 09.10.2028 09.04.2027 09.10.2027
09.04.2028 09.10.2028
Obligațiuni de stat cu dobândă fixă
3 ani MD4004002771 100 30,0 cu scont, la
7,85 la sută anual
09.10.2026 09.10.2029 09.04.2027 09.10.2027
09.04.2028 09.10.2028
09.04.2029 09.10.2029"""

RESULTS_BT = """91 zile 50.000,0 32.725,0 32.725,0 32.479,6 3,03 MD4003005098 3,03 3,03 05.11.2026
182 zile 1.300.000,0 1.901.551,6 1.300.000,4 1.238.431,5 9,47 MD4003005106 9,98 9,98 04.02.2027
364 zile 1.700.000,0 1.469.123,1 1.380.451,6 1.253.650,2 9,80 MD4003005114 10,15 10,15 05.08.2027
Total x x x 3.050.000,0 3.403.399,7 2.713.177,0 2.524.561,2 9,98 x"""

DETAIL = """Licitație VMS: 03.11.2026, Termenul: 182
Data licitatiei:
03.11.2026
Tipul VMS:
Bonuri de trezorerie
Termenul:
182
Rata nominala a dobinzii:
11,63%
Volum MDL (mii lei)
Volumul ofertei (anunțat de Ministerul Finanțelor) 1.400.000,00
Volumul cererii 1.808.799,70
Realizat la prețul nominal 1.765.710,40
Realizat la prețul de realizare 1.668.885,52"""


class ParserTests(unittest.TestCase):
    def test_numbers(self):
        self.assertEqual(parsers.parse_number("1.400.000,00"), 1400000.0)
        self.assertEqual(parsers.parse_number("11,63%"), 11.63)

    def test_placement_bt(self):
        recs = parsers.parse_placement(PLACEMENT_BT, dt.date(2026, 11, 3), "x")
        self.assertEqual([r["isin"] for r in recs], ["MD4003005270", "MD4003005288", "MD4003005296"])
        self.assertEqual(recs[1]["term_days"], 182)
        self.assertEqual(recs[2]["maturity"], "2027-11-04")
        self.assertTrue(all("_issues" not in r for r in recs))

    def test_placement_os(self):
        recs = parsers.parse_placement(PLACEMENT_OS, dt.date(2026, 10, 7), "x")
        self.assertEqual(len(recs), 2)
        self.assertEqual(recs[0]["type"], "OS")
        self.assertEqual(recs[0]["coupon_rate"], 7.75)
        self.assertEqual(recs[0]["coupon_dates"], ["2027-04-09", "2027-10-09", "2028-04-09", "2028-10-09"])
        self.assertEqual(recs[1]["coupon_rate"], 7.85)
        self.assertEqual(recs[1]["maturity"], "2029-10-09")
        self.assertEqual(len(recs[1]["coupon_dates"]), 6)

    def test_results(self):
        recs = parsers.parse_results_bt(RESULTS_BT, dt.date(2026, 8, 4), "x")
        self.assertEqual(len(recs), 3)
        r = recs[1]
        self.assertEqual((r["rate_min"], r["rate_avg"], r["rate_max"]), (9.47, 9.98, 9.98))
        self.assertEqual(r["isin"], "MD4003005106")
        self.assertTrue(all("_issues" not in x for x in recs), recs)

    def test_detail(self):
        r = parsers.parse_auction_detail(DETAIL)
        self.assertEqual(r["auction_date"], "2026-11-03")
        self.assertEqual(r["rate_avg"], 11.63)
        self.assertEqual(r["placed_price"], 1668885.52)
        self.assertEqual(r["announced"], 1400000.0)

    def test_calendar_url(self):
        self.assertEqual(parsers.calendar_url(2026, 4),
                         "https://mf.gov.md/sites/default/files/trimestrul%20IV-2026%20web-rom.pdf")


class CouponFormatTests(unittest.TestCase):
    """Formulări ale cuponului care apar în comunicate din ani diferiți."""

    ROW = "7 ani MD4004001583 100 50,0 cu scont, la valoarea nominală {c} 13.03.2024 15.03.2024 15.03.2031 15.09.2024 15.03.2025"

    def rate(self, c):
        recs = parsers.parse_placement(self.ROW.format(c=c), dt.date(2024, 3, 13), "x")
        return recs[0]

    def test_variants(self):
        for c, want in [("7,75 la sută anual", 7.75), ("7,75 la suta", 7.75), ("7.75 %", 7.75),
                        ("7,75% anual", 7.75), ("8 la sută anual", 8.0), ("rata cuponului: 6,5", 6.5),
                        ("dobânda 6,25 procente", 6.25)]:
            r = self.rate(c)
            self.assertEqual(r["coupon_rate"], want, c)
            self.assertNotIn("_issues", r, c)

    def test_volume_and_price_not_taken_as_coupon(self):
        r = self.rate("")
        self.assertIsNone(r["coupon_rate"])
        self.assertIn("rata cuponului lipsă", r["_issues"])

    def test_floating_rate_bond(self):
        r = self.rate("dobândă flotantă (rata de bază + 1,0 p.p.)")
        self.assertEqual(r.get("coupon_type"), "flotant")
        self.assertNotIn("rata cuponului lipsă", r.get("_issues", []))


REOPENING_OS = """Ministerul Finanţelor anunță redeschiderea emisiunii de valori mobiliare de stat cu codul ISIN MD4004001740 în sumă de 50.000.000 (cincizeci
milioane ) lei.
Valorile mobiliare de stat vor fi plasate pe piaţa primară la licitaţiile, care vor fi desfăşurate la Banca Naţională a Moldovei la 11 martie 2026.
Tipul VMS Maturitatea Codul ISIN Data Valoarea Volumul Condițiile Rata anuală a Dobînda Data Data Termenele de
Obligațiuni de stat 8,76 MD4004001740 13.12.2024 100 50,0 la valoarea 8,00 la sută anual 1,9726027 13.03.2026 13.12.2034 La datele
cu dobândă fixă nominală către valoarea specificate în"""


class ReopeningTests(unittest.TestCase):
    def test_isin_in_intro_does_not_hide_coupon(self):
        recs = parsers.parse_placement(REOPENING_OS, dt.date(2026, 3, 11), "x")
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0]["coupon_rate"], 8.0)
        self.assertNotIn("rata cuponului lipsă", recs[0]["_issues"])


class MergeTests(unittest.TestCase):
    def setUp(self):
        from vms_pipeline import build
        self.build = build
        self.manual = {"securities": [], "rates": [], "volumes": [], "calendar": []}
        self.bad = {"isin": "MD4004001583", "type": "OS", "term_label": "7 ani", "term_days": 2556,
                    "auction_date": "2024-03-13", "issue_date": "2024-03-15", "maturity": "2031-03-15",
                    "coupon_rate": None, "coupon_dates": [], "source": "x", "_issues": ["rata cuponului lipsă"]}

    def test_missing_coupon_is_quarantined_not_fatal(self):
        log = []
        out = self.build.merge({}, self.manual, {"securities": [self.bad]}, log)
        self.assertEqual(out["securities"], [])
        self.assertTrue(any("carantină" in w["msg"] for w in log))
        self.assertFalse(any("fără cupon" in e for e in self.build.validate({**out, "rates": [{"min": 1, "avg": 2, "max": 3}] * 100})))

    def test_missing_coupon_filled_from_same_isin(self):
        reopening = {**self.bad, "auction_date": "2024-08-07", "issue_date": None, "maturity": None,
                     "coupon_rate": 6.5, "_issues": ["redeschidere"]}
        out = self.build.merge({}, self.manual, {"securities": [self.bad, reopening]}, [])
        self.assertEqual(out["securities"][0]["coupon_rate"], 6.5)


if __name__ == "__main__":
    unittest.main()
