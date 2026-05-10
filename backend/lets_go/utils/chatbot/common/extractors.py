import re
from typing import Optional

from .text import normalize_text, to_int


def extract_from_to(text: str) -> tuple[Optional[str], Optional[str]]:
    t = (text or '').strip()
    if not t:
        return None, None

    m = re.search(
        r"\bfrom\s+(.+?)\s+to\s+(.+?)(?:\s+at\b|\s+on\b|\s+today\b|\s+tomorrow\b|$)",
        t,
        flags=re.IGNORECASE,
    )
    if m:
        return m.group(1).strip(' ,.'), m.group(2).strip(' ,.')

    m = re.search(
        r"\bpick(?:up)?\s+(.+?)\s+drop(?:off)?\s+(.+?)(?:\s+at\b|\s+on\b|\s+today\b|\s+tomorrow\b|$)",
        t,
        flags=re.IGNORECASE,
    )
    if m:
        return m.group(1).strip(' ,.'), m.group(2).strip(' ,.')

    return None, None


def extract_seats(text: str) -> Optional[int]:
    m = re.search(r"\b(\d{1,2})\s*(?:seat|seats)\b", text or '', flags=re.IGNORECASE)
    if m:
        v = to_int(m.group(1))
        if v and v > 0:
            return v
    return None


def extract_fare(text: str) -> Optional[int]:
    m = re.search(r"\b(?:for|fare|price)\s*[:=]?\s*([0-9]{2,6})\b", text or '', flags=re.IGNORECASE)
    if m:
        return to_int(m.group(1))
    return None


def extract_booking_id(text: str) -> Optional[int]:
    m = re.search(r"\bbooking[_\s-]*id\s*[:=]?\s*(\d+)\b", text or '', flags=re.IGNORECASE)
    if m:
        return to_int(m.group(1))
    m = re.search(r"\bbooking\s+(\d+)\b", text or '', flags=re.IGNORECASE)
    if m:
        return to_int(m.group(1))
    return None


def _normalize_trip_id(tid: str) -> str:
    t = (tid or '').strip()
    if not t:
        return ''
    if re.match(r"^[tT]\d{2,6}-", t):
        return 'T' + t[1:]
    return t


def extract_trip_id(text: str) -> Optional[str]:
    m = re.search(r"\btrip[_\s-]*id\s*[:=]?\s*([A-Za-z0-9._:-]+)", text or '', flags=re.IGNORECASE)
    if m:
        out = _normalize_trip_id(m.group(1))
        return out or None
    m = re.search(r"\b(T\d{2,6}-[A-Za-z0-9:-]{6,})\b", text or '', flags=re.IGNORECASE)
    if m:
        out = _normalize_trip_id(m.group(1))
        return out or None
    return None


def extract_recipient_id(text: str) -> Optional[int]:
    m = re.search(r"\brecipient[_\s-]*id\s*[:=]?\s*(\d+)\b", text or '', flags=re.IGNORECASE)
    if m:
        return to_int(m.group(1))
    m = re.search(r"\bto\s+user\s+(\d+)\b", text or '', flags=re.IGNORECASE)
    if m:
        return to_int(m.group(1))
    return None


def extract_coord_pairs(text: str) -> list[tuple[float, float]]:
    low = (text or '').lower()
    out: list[tuple[float, float]] = []

    mlat = re.search(r"\b(?:lat|latitude)\b\s*[:=]?\s*(-?\d+(?:\.\d+)?)", low)
    mlon = re.search(r"\b(?:lon|lng|longitude)\b\s*[:=]?\s*(-?\d+(?:\.\d+)?)", low)
    if mlat and mlon:
        try:
            lat = float(mlat.group(1))
            lon = float(mlon.group(1))
            if -90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0:
                out.append((lat, lon))
        except Exception:
            pass

    pairs = re.findall(r"(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)", low)
    for a, b in pairs:
        try:
            lat = float(a)
            lon = float(b)
        except Exception:
            continue
        if -90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0:
            out.append((lat, lon))

    seen = set()
    deduped: list[tuple[float, float]] = []
    for lat, lon in out:
        key = (round(lat, 6), round(lon, 6))
        if key in seen:
            continue
        seen.add(key)
        deduped.append((lat, lon))
    return deduped


def looks_like_route_id(val: Optional[str]) -> bool:
    v = (val or '').strip()
    if not v:
        return False
    if not re.fullmatch(r"R[0-9A-Z]{2,12}", v, flags=re.IGNORECASE):
        return False
    return any(ch.isdigit() for ch in v)


def looks_like_route_id_strict(val: Optional[str]) -> bool:
    return looks_like_route_id(val)
