"""HTTP helpers for CASC / wago.tools downloads."""

from __future__ import annotations

import csv
import io
from pathlib import Path
from urllib.request import Request, urlopen

from ..config.build import USER_AGENT
from ..config.endpoints import WAGO_CASC_PINNED_FMT


def _request(url: str) -> Request:
    return Request(url, headers={"User-Agent": USER_AGENT})


def fetch_url(url: str, *, timeout: int = 60) -> bytes:
    """Simple HTTP GET with User-Agent header."""
    with urlopen(_request(url), timeout=timeout) as resp:
        return resp.read()


def fetch_csv(url: str, *, timeout: int = 60) -> list[dict]:
    """Download a CSV from *url* and return rows as dicts."""
    data = fetch_url(url, timeout=timeout)
    text = data.decode("utf-8", errors="replace")
    return list(csv.DictReader(io.StringIO(text)))


def download_casc(fdid: int) -> bytes:
    """Download a raw file from the CASC endpoint by FileDataID, from the
    pinned build only. Unpinned, the endpoint serves whichever build wago.tools
    ingested last (another product's terrain, tiles and WMOs), so there is no
    unpinned mode (see :data:`hfwm.config.endpoints.WAGO_CASC_PINNED_FMT`)."""
    return fetch_url(WAGO_CASC_PINNED_FMT.format(fdid=fdid), timeout=30)


def download_casc_cached(fdid: int, cache_dir: Path) -> Path:
    """Download a CASC file, caching to *cache_dir*/{fdid}.blp."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    path = cache_dir / f"{fdid}.blp"
    if path.exists() and path.stat().st_size > 0:
        return path
    path.write_bytes(download_casc(fdid))
    return path


def casc_file_exists(fdid: int, *, timeout: int = 30) -> bool:
    """Whether *fdid* resolves on the pinned build.

    Must go through the pinned endpoint.  Unpinned, ``/api/casc/{fdid}``
    serves whichever build was ingested last, so a retail-only file
    answers 200 and would be baked into a table claiming to describe
    this build.
    """
    try:
        with urlopen(_request(WAGO_CASC_PINNED_FMT.format(fdid=fdid)), timeout=timeout) as resp:
            return len(resp.read(64)) > 0
    except OSError:  # includes HTTPError (a 404 means "not on this build")
        return False
