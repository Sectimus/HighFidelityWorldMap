"""HTTP helpers for CASC / wago.tools downloads."""

from __future__ import annotations

import csv
import io
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from ..config.build import USER_AGENT
from ..config.endpoints import WAGO_CASC_PINNED_FMT


def _request(url: str) -> Request:
    return Request(url, headers={"User-Agent": USER_AGENT})


# wago.tools throttles bursts of requests (HTTP 429) and sometimes returns 5xx
# or drops connections. Those are transient, so retry with backoff.
RETRY_STATUSES = frozenset({429, 500, 502, 503, 504})
RETRY_ATTEMPTS = 6
RETRY_BASE_SECONDS = 2.0
RETRY_MAX_SECONDS = 60.0


def _retry_delay(attempt: int, err: HTTPError | None) -> float:
    """Seconds to wait before retry *attempt* (0-based). Honours Retry-After."""
    if err is not None and err.headers is not None:
        retry_after = err.headers.get("Retry-After", "").strip()
        if retry_after.isdigit():
            return min(float(retry_after), RETRY_MAX_SECONDS)
    return min(RETRY_BASE_SECONDS * (2 ** attempt), RETRY_MAX_SECONDS)


def fetch_url(url: str, *, timeout: int = 60) -> bytes:
    """HTTP GET with User-Agent header, retrying transient failures.

    Retries 429/5xx and network errors with exponential backoff. Other HTTP
    errors (e.g. 404, "not on this build") raise at once: retrying cannot
    change the answer.
    """
    for attempt in range(RETRY_ATTEMPTS):
        try:
            with urlopen(_request(url), timeout=timeout) as resp:
                return resp.read()
        except HTTPError as err:
            if err.code not in RETRY_STATUSES or attempt == RETRY_ATTEMPTS - 1:
                raise
            delay = _retry_delay(attempt, err)
        except (URLError, TimeoutError, ConnectionError):
            if attempt == RETRY_ATTEMPTS - 1:
                raise
            delay = _retry_delay(attempt, None)
        time.sleep(delay)
    raise AssertionError("unreachable")


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
