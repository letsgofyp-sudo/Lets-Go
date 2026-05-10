import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional
import http.cookiejar
import hashlib

from .config import LETS_GO_API_BASE_URL


_COOKIE_JAR = http.cookiejar.CookieJar()
_HTTP_OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(_COOKIE_JAR))


_CACHE_ENABLED = str(os.getenv('LETS_GO_BOT_HTTP_CACHE', '')).strip().lower() in {'1', 'true', 'yes', 'on'}
_CACHE_MAX_ITEMS = int(os.getenv('LETS_GO_BOT_HTTP_CACHE_MAX', '256') or 256)
_CACHE_TTL_SEC = float(os.getenv('LETS_GO_BOT_HTTP_CACHE_TTL_SEC', '20') or 20)
_SLOW_DEBUG_ENABLED = str(os.getenv('LETS_GO_BOT_HTTP_DEBUG_SLOW', '')).strip().lower() in {'1', 'true', 'yes', 'on'}
_SLOW_DEBUG_MS = int(os.getenv('LETS_GO_BOT_HTTP_DEBUG_SLOW_MS', '10000') or 10000)


_GET_CACHE: dict[str, tuple[float, tuple[int, Any, bool]]] = {}


def reset_http_session() -> None:
    try:
        _GET_CACHE.clear()
    except Exception:
        pass
    try:
        _COOKIE_JAR.clear()
    except Exception:
        pass


def _cache_key(method: str, url: str, headers: dict, body_bytes: Optional[bytes]) -> str:
    m = (method or 'GET').upper()
    if m != 'GET':
        return ''
    # Include cookies implicitly via the global opener; for safety, only cache per-process.
    h = hashlib.sha256()
    h.update(m.encode('utf-8', errors='ignore'))
    h.update(b'\n')
    h.update(url.encode('utf-8', errors='ignore'))
    h.update(b'\n')
    # Accept header can affect content negotiation.
    h.update(str(headers.get('Accept') or '').encode('utf-8', errors='ignore'))
    h.update(b'\n')
    if body_bytes:
        h.update(body_bytes)
    return h.hexdigest()


def _cache_get(key: str) -> Optional[tuple[int, Any, bool]]:
    if not (_CACHE_ENABLED and key):
        return None
    item = _GET_CACHE.get(key)
    if not item:
        return None
    ts, val = item
    if (time.monotonic() - ts) > _CACHE_TTL_SEC:
        try:
            del _GET_CACHE[key]
        except Exception:
            pass
        return None
    return val


def _cache_set(key: str, val: tuple[int, Any, bool]) -> None:
    if not (_CACHE_ENABLED and key):
        return
    if len(_GET_CACHE) >= _CACHE_MAX_ITEMS:
        # Drop everything (simple + safe). This avoids O(n) LRU bookkeeping.
        _GET_CACHE.clear()
    _GET_CACHE[key] = (time.monotonic(), val)


def _maybe_print_slow(method: str, url: str, elapsed_ms: int, status: int) -> None:
    if not _SLOW_DEBUG_ENABLED:
        return
    if elapsed_ms < _SLOW_DEBUG_MS:
        return
    # Intentionally a plain print so it shows up during manage.py command runs.
    print(f'[bot-http][slow] {elapsed_ms}ms {method.upper()} {status} {url}')


def http_call_json(method: str, path: str, *, body: Optional[dict] = None, query: Optional[dict] = None) -> tuple[int, Any, bool]:
    try:
        url = urllib.parse.urljoin(LETS_GO_API_BASE_URL.rstrip('/') + '/', path.lstrip('/'))
        if query:
            qs = urllib.parse.urlencode({k: v for k, v in (query or {}).items() if v is not None}, doseq=True)
            if qs:
                url = url + ('&' if '?' in url else '?') + qs

        data_bytes = None
        headers = {'Accept': 'application/json'}
        m = (method or 'GET').upper()
        if m in {'POST', 'PUT', 'PATCH', 'DELETE'}:
            headers['Content-Type'] = 'application/json'
            data_bytes = json.dumps(body or {}).encode('utf-8')

        ck = _cache_key(m, url, headers, data_bytes)
        cached = _cache_get(ck)
        if cached is not None:
            return cached

        req = urllib.request.Request(url, data=data_bytes, headers=headers, method=m)
        t0 = time.monotonic()
        with _HTTP_OPENER.open(req, timeout=12) as resp:
            raw = resp.read()
            status = getattr(resp, 'status', None) or resp.getcode()
        elapsed_ms = int((time.monotonic() - t0) * 1000)
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        out = (int(status or 0), parsed, True)
        _cache_set(ck, out)
        _maybe_print_slow(m, url, elapsed_ms, int(status or 0))
        return out
    except urllib.error.HTTPError as e:
        t0 = time.monotonic()
        try:
            raw = e.read()
        except Exception:
            raw = b''
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        status = int(getattr(e, 'code', 500) or 500)
        elapsed_ms = int((time.monotonic() - t0) * 1000)
        _maybe_print_slow((method or 'GET').upper(), url, elapsed_ms, status)
        return status, parsed, True
    except Exception:
        return 0, None, False


def http_call_form(method: str, path: str, *, data: Optional[dict] = None, query: Optional[dict] = None) -> tuple[int, Any, bool]:
    try:
        url = urllib.parse.urljoin(LETS_GO_API_BASE_URL.rstrip('/') + '/', path.lstrip('/'))
        if query:
            qs = urllib.parse.urlencode({k: v for k, v in (query or {}).items() if v is not None}, doseq=True)
            if qs:
                url = url + ('&' if '?' in url else '?') + qs

        headers = {
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
        }
        payload = urllib.parse.urlencode({k: v for k, v in (data or {}).items() if v is not None}, doseq=True).encode('utf-8')
        m = (method or 'POST').upper()
        req = urllib.request.Request(url, data=payload, headers=headers, method=m)
        t0 = time.monotonic()
        with _HTTP_OPENER.open(req, timeout=12) as resp:
            raw = resp.read()
            status = getattr(resp, 'status', None) or resp.getcode()
        elapsed_ms = int((time.monotonic() - t0) * 1000)
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        _maybe_print_slow(m, url, elapsed_ms, int(status or 0))
        return int(status or 0), parsed, True
    except urllib.error.HTTPError as e:
        t0 = time.monotonic()
        try:
            raw = e.read()
        except Exception:
            raw = b''
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        status = int(getattr(e, 'code', 500) or 500)
        elapsed_ms = int((time.monotonic() - t0) * 1000)
        _maybe_print_slow((method or 'POST').upper(), url, elapsed_ms, status)
        return status, parsed, True
    except Exception:
        return 0, None, False


def call_view(method: str, path: str, *, body: Optional[dict] = None, query: Optional[dict] = None):
    status, content, ok = http_call_json(method, path, body=body, query=query)
    if ok:
        return status, content
    return 0, {'success': False, 'error': 'Failed to reach API server'}


def call_view_form(method: str, path: str, *, data: Optional[dict] = None, query: Optional[dict] = None):
    status, content, ok = http_call_form(method, path, data=data, query=query)
    if ok:
        return status, content
    return 0, {'success': False, 'error': 'Failed to reach API server'}
