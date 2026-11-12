"""Network access to mf.gov.md. Kept separate so parsers stay testable offline."""
from __future__ import annotations

import io
import re
import time
from urllib.parse import urljoin, unquote

import requests
from bs4 import BeautifulSoup

BASE = "https://mf.gov.md"
PLACEMENT_PAGE = BASE + "/ro/datoria-sectorului-public/pia%C8%9Ba-primar%C4%83-a-vms/comunicate-privind-plasarea-vms"
AUCTIONS_PAGE = BASE + "/ro/datoria-sectorului-public/pia%C8%9Ba-primar%C4%83-a-vms/licita%C8%9Bii-vms"
HEADERS = {"User-Agent": "VMS-Moldova-data-bot/1.0 (+https://github.com/; contact in README)"}

_session = requests.Session()
_session.headers.update(HEADERS)


def get(url: str, retries: int = 3, pause: float = 2.0) -> requests.Response:
    last: Exception | None = None
    for attempt in range(retries):
        try:
            r = _session.get(url, timeout=30)
            if r.status_code == 404:
                r.raise_for_status()
            r.raise_for_status()
            time.sleep(0.7)  # be polite with the ministry server
            return r
        except requests.HTTPError as e:
            if e.response is not None and e.response.status_code == 404:
                raise
            last = e
        except requests.RequestException as e:
            last = e
        time.sleep(pause * (attempt + 1))
    raise RuntimeError(f"GET {url} failed: {last}")


def exists(url: str) -> bool:
    try:
        r = _session.head(url, timeout=20, allow_redirects=True)
        return r.status_code == 200
    except requests.RequestException:
        return False


def links(page_url: str) -> list[tuple[str, str]]:
    """Return (absolute_url, link_text) for every anchor on a page."""
    html = get(page_url).text
    soup = BeautifulSoup(html, "html.parser")
    out = []
    for a in soup.find_all("a", href=True):
        out.append((urljoin(page_url, a["href"]), " ".join(a.get_text(" ").split())))
    return out


def placement_and_result_pdfs() -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Split the communiqués page into placement PDFs and result PDFs."""
    placements, results = [], []
    for url, text in links(PLACEMENT_PAGE):
        name = unquote(url).lower()
        if not name.endswith(".pdf"):
            continue
        if "comunicat plasare" in name and "-rom" in name:
            placements.append((url, text))
        elif "rezultatele licitatie" in name and "rom" in name:
            results.append((url, text))
    return placements, results


def auction_detail_links(limit: int = 30) -> list[str]:
    out = []
    for url, _ in links(AUCTIONS_PAGE):
        if "/content/licita" in url and "termenul" in url:
            if url not in out:
                out.append(url)
    return out[:limit]


def page_text(url: str) -> str:
    soup = BeautifulSoup(get(url).text, "html.parser")
    main = soup.find("main") or soup.find(id="content") or soup.body or soup
    for t in main.find_all(["script", "style", "nav"]):
        t.decompose()
    # keep table rows on one line: "label value"
    for tr in main.find_all("tr"):
        tr.replace_with(" ".join(c.get_text(" ", strip=True) for c in tr.find_all(["td", "th"])) + "\n")
    return main.get_text("\n")


def pdf_bytes(url: str) -> bytes:
    return get(url).content


def pdf_text(data: bytes) -> str:
    import pdfplumber

    with pdfplumber.open(io.BytesIO(data)) as pdf:
        return "\n".join((p.extract_text() or "") for p in pdf.pages)


def pdf_tables(data: bytes) -> list[list[list[str | None]]]:
    import pdfplumber

    tables = []
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        for p in pdf.pages:
            tables.extend(p.extract_tables())
    return tables


DATE_IN_NAME = re.compile(r"(\d{2})[.\-](\d{2})[.\-](\d{4})")
