import json
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional
import http.cookiejar

from .config import LETS_GO_API_BASE_URL


_COOKIE_JAR = http.cookiejar.CookieJar()
_HTTP_OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(_COOKIE_JAR))


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

        req = urllib.request.Request(url, data=data_bytes, headers=headers, method=m)
        with _HTTP_OPENER.open(req, timeout=12) as resp:
            raw = resp.read()
            status = getattr(resp, 'status', None) or resp.getcode()
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        return int(status or 0), parsed, True
    except urllib.error.HTTPError as e:
        try:
            raw = e.read()
        except Exception:
            raw = b''
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        return int(getattr(e, 'code', 500) or 500), parsed, True
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
        req = urllib.request.Request(url, data=payload, headers=headers, method=(method or 'POST').upper())
        with _HTTP_OPENER.open(req, timeout=12) as resp:
            raw = resp.read()
            status = getattr(resp, 'status', None) or resp.getcode()
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        return int(status or 0), parsed, True
    except urllib.error.HTTPError as e:
        try:
            raw = e.read()
        except Exception:
            raw = b''
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        return int(getattr(e, 'code', 500) or 500), parsed, True
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
