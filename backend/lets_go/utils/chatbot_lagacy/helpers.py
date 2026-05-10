import json
import difflib
import math
import re
from datetime import date, datetime, timedelta
from typing import Optional

from .config import STOPS_GEO_JSON


_STOPS_GEO_CACHE: Optional[list[dict]] = None


def normalize_text(s: str) -> str:
    s2 = (s or "").strip().lower()
    s2 = (
        s2.replace("\u2019", "'")
        .replace("\u2018", "'")
        .replace("\u201c", '"')
        .replace("\u201d", '"')
        .replace("\u2014", "-")
        .replace("\u2013", "-")
    )
    return re.sub(r"\s+", " ", s2)


def tokenize(s: str) -> list[str]:
    s = normalize_text(s)
    s = re.sub(r"[^a-z0-9_\s-]+", " ", s)
    return [p for p in s.split() if p]


def to_int(value) -> Optional[int]:
    try:
        if value is None:
            return None

        if isinstance(value, bool):
            return None
        return int(value)
    except Exception:
        return None


def parse_date(text: str) -> Optional[date]:
    t = normalize_text(text)
    if not t:
        return None
    if 'today' in t:
        return date.today()
    if any(k in t for k in ['tomorrow', 'tomarrow', 'tmrw', 'tmr']):
        return date.today() + timedelta(days=1)
    m = re.search(r"\b(\d{4}-\d{2}-\d{2})\b", t)
    if m:
        try:
            return datetime.strptime(m.group(1), '%Y-%m-%d').date()
        except Exception:
            return None
    return None


def parse_time_str(text: str) -> Optional[str]:
    t = normalize_text(text)
    if not t:
        return None
    m = re.search(r"\b(\d{1,2}):(\d{2})\s*(am|pm)\b", t)
    if m:
        hh = int(m.group(1))
        mm = int(m.group(2))
        ampm = m.group(3)
        if hh == 12:
            hh = 0
        if ampm == 'pm':
            hh += 12
        if 0 <= hh <= 23 and 0 <= mm <= 59:
            return f"{hh:02d}:{mm:02d}"
        return None
    m = re.search(r"\b(\d{1,2}):(\d{2})\b", t)
    if m:
        hh = int(m.group(1))
        mm = int(m.group(2))
        if 0 <= hh <= 23 and 0 <= mm <= 59:
            return f"{hh:02d}:{mm:02d}"
        return None
    m = re.search(r"\b(\d{1,2})\s*(am|pm)\b", t)
    if m:
        hh = int(m.group(1))
        ampm = m.group(2)
        if hh == 12:
            hh = 0
        if ampm == 'pm':
            hh += 12
        if 0 <= hh <= 23:
            return f"{hh:02d}:00"
    return None


def _roll_date_forward_if_time_passed(*, tm: str, base: datetime) -> date:
    try:
        hh, mm = [int(x) for x in (tm or '').split(':', 1)]
    except Exception:
        return base.date()
    target = datetime.combine(base.date(), datetime.min.time()).replace(hour=hh, minute=mm)
    if target < base:
        return (base + timedelta(days=1)).date()
    return base.date()


def parse_relative_datetime(text: str, *, base: Optional[datetime] = None) -> Optional[tuple[date, str]]:
    low = normalize_text(text)
    if not low:
        return None
    base_dt = base or datetime.now()

    minutes: Optional[int] = None
    m = re.search(r"\b(?:in|after)\s+(\d{1,3})\s*(?:minute|minutes|min|mins)\b", low)
    if m:
        minutes = int(m.group(1))
    m = re.search(r"\b(?:in|after)\s+(\d{1,2})\s*(?:hour|hours|hr|hrs)\b", low)
    if m:
        minutes = (minutes or 0) + int(m.group(1)) * 60
    if minutes is None and re.search(r"\b(?:in|after)\s+an\s+hour\b", low):
        minutes = 60

    if minutes is not None and minutes > 0:
        dt = base_dt + timedelta(minutes=int(minutes))
        return dt.date(), f"{dt.hour:02d}:{dt.minute:02d}"

    tm = parse_time_str(text)
    if tm:
        d = parse_date(text)
        if d is None:
            d = _roll_date_forward_if_time_passed(tm=tm, base=base_dt)
        return d, tm

    return None


def extract_from_to(text: str) -> tuple[Optional[str], Optional[str]]:
    t = (text or '').strip()
    if not t:
        return None, None

    m = re.search(r"\bfrom\s+(.+?)\s+to\s+(.+?)(?:\s+at\b|\s+on\b|\s+today\b|\s+tomorrow\b|$)", t, flags=re.IGNORECASE)
    if m:
        return m.group(1).strip(' ,.'), m.group(2).strip(' ,.')

    m = re.search(r"\bpick(?:up)?\s+(.+?)\s+drop(?:off)?\s+(.+?)(?:\s+at\b|\s+on\b|\s+today\b|\s+tomorrow\b|$)", t, flags=re.IGNORECASE)
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
    # Canonical LetsGo trip ids are case-sensitive in URLs. Normalize leading 'T' if present.
    # Example: 't325-2026-03-14-16:43' -> 'T325-2026-03-14-16:43'
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


def load_stops_geo() -> list[dict]:
    global _STOPS_GEO_CACHE
    if _STOPS_GEO_CACHE is not None:
        return _STOPS_GEO_CACHE
    path = STOPS_GEO_JSON
    if not path:
        _STOPS_GEO_CACHE = []
        return _STOPS_GEO_CACHE
    try:
        with open(path, 'r', encoding='utf-8') as f:
            obj = json.load(f)
        if isinstance(obj, dict) and isinstance(obj.get('stops'), list):
            _STOPS_GEO_CACHE = obj.get('stops')
        elif isinstance(obj, list):
            _STOPS_GEO_CACHE = obj
        else:
            _STOPS_GEO_CACHE = []
        return _STOPS_GEO_CACHE
    except Exception:
        _STOPS_GEO_CACHE = []
        return _STOPS_GEO_CACHE


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = (math.sin(dp / 2) ** 2) + math.cos(p1) * math.cos(p2) * (math.sin(dl / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return r * c


def nearest_stop_name(lat: float, lon: float) -> Optional[str]:
    stops = load_stops_geo()
    if not stops:
        return None
    best_name: Optional[str] = None
    best_d = None
    for s in stops:
        if not isinstance(s, dict):
            continue
        name = (s.get('name') or s.get('stop_name') or s.get('title') or '').strip()
        try:
            slat = float(s.get('lat') if s.get('lat') is not None else s.get('latitude'))
            slon = float(s.get('lon') if s.get('lon') is not None else (s.get('lng') if s.get('lng') is not None else s.get('longitude')))
        except Exception:
            continue
        if not name:
            continue
        d = haversine_km(lat, lon, slat, slon)
        if best_d is None or d < best_d:
            best_d = d
            best_name = name
    return best_name


def fuzzy_stop_name(raw: str, *, min_score: float = 0.74) -> Optional[str]:
    q = normalize_text(raw)
    if not q:
        return None
    stops = load_stops_geo()
    if not stops:
        return None
    names: list[str] = []
    for s in stops:
        if not isinstance(s, dict):
            continue
        n = str(s.get('name') or s.get('stop_name') or '').strip()
        if n:
            names.append(n)
    if not names:
        return None

    best_name: Optional[str] = None
    best_score = 0.0
    for n in names:
        score = difflib.SequenceMatcher(a=q, b=normalize_text(n)).ratio()
        if score > best_score:
            best_score = float(score)
            best_name = n
    if best_name and best_score >= float(min_score):
        return best_name
    return None


def _route_endpoints_from_stops_geo(route_id: str) -> tuple[Optional[dict], Optional[dict]]:
    rid = (route_id or '').strip()
    if not rid:
        return None, None
    stops = load_stops_geo()
    if not stops:
        return None, None
    matches = [s for s in stops if isinstance(s, dict) and str(s.get('route_id') or '').strip() == rid]
    if len(matches) < 2:
        return None, None
    return matches[0], matches[-1]


def build_create_trip_fare_payload(route_id: str, *, base_fare: int) -> tuple[Optional[dict], Optional[list[dict]]]:
    a, b = _route_endpoints_from_stops_geo(route_id)
    if not a or not b:
        return None, None

    from_name = str(a.get('name') or a.get('stop_name') or '').strip() or 'From'
    to_name = str(b.get('name') or b.get('stop_name') or '').strip() or 'To'
    try:
        lat1 = float(a.get('lat') if a.get('lat') is not None else a.get('latitude'))
        lon1 = float(a.get('lon') if a.get('lon') is not None else (a.get('lng') if a.get('lng') is not None else a.get('longitude')))
        lat2 = float(b.get('lat') if b.get('lat') is not None else b.get('latitude'))
        lon2 = float(b.get('lon') if b.get('lon') is not None else (b.get('lng') if b.get('lng') is not None else b.get('longitude')))
    except Exception:
        return None, None

    dist = float(haversine_km(lat1, lon1, lat2, lon2))
    duration_minutes = int(max(1.0, round((dist / 50.0) * 60.0)))

    stop_breakdown = [
        {
            'from_stop': 1,
            'to_stop': 2,
            'from_stop_name': from_name,
            'to_stop_name': to_name,
            'distance': round(dist, 2),
            'duration': duration_minutes,
            'price': int(base_fare),
            'from_coordinates': {'lat': lat1, 'lng': lon1},
            'to_coordinates': {'lat': lat2, 'lng': lon2},
            'price_breakdown': {'source': 'chatbot'},
        }
    ]

    fare_calculation = {
        'base_fare': int(base_fare),
        'total_distance_km': round(dist, 2),
        'total_duration_minutes': duration_minutes,
        'total_price': int(base_fare),
        'stop_breakdown': stop_breakdown,
        'calculation_breakdown': {
            'source': 'chatbot',
            'note': 'Lightweight endpoints-only breakdown for ride list display',
        },
    }

    return fare_calculation, stop_breakdown


def looks_like_route_id(val: Optional[str]) -> bool:
    v = (val or '').strip()
    if not v:
        return False
    if not re.fullmatch(r"R[0-9A-Z]{2,12}", v, flags=re.IGNORECASE):
        return False
    return any(ch.isdigit() for ch in v)


def looks_like_route_id_strict(val: Optional[str]) -> bool:
    return looks_like_route_id(val)


def contains_abuse(text: str) -> bool:
    low = normalize_text(text)
    bad = ['fuck', 'fucking', 'bitch', 'asshole', 'bastard', 'chutiya', 'madarchod', 'behenchod']
    return any(w in low for w in bad)


def blocked_system_request(text: str) -> Optional[str]:
    low = normalize_text(text)
    blocked_terms = [
        'verify', 'verification', 'approve', 'admin',
        'send otp', 'otp', 'reset password',
        'fcm', 'token',
        'start ride', 'complete ride',
        'update location', 'live location',
        'cancel booking', 'cancel my booking',
        'cancel trip', 'cancel my trip',
        'delete trip', 'remove trip',
        'broadcast',
        'share link', 'share token',
        'ban user', 'unban',
    ]

    info_q_markers = [
        'what is',
        'what are',
        'meaning',
        'define',
        'when',
        'why',
        'how does',
        'how do',
        '?',
    ]

    if 'pickup code' in low:
        if not any(m in low for m in info_q_markers):
            return "I can't do that directly here. Please use the app's official screens/support flow (or contact an admin) for this action."

    if 'sos' in low:
        if not any(m in low for m in info_q_markers):
            return "I can't do that directly here. Please use the app's official screens/support flow (or contact an admin) for this action."

    for term in blocked_terms:
        if term in low:
            return "I can't do that directly here. Please use the app's official screens/support flow (or contact an admin) for this action."
    return None


def help_text() -> str:
    return "\n".join([
        'You can talk naturally. Examples:',
        "- book a ride from Saddar to DHA tomorrow at 6pm",
        "- I need 2 seats",
        "- make it 450 fare",
        "- yes (to confirm)",
        "- cancel (to stop current action)",
        "- ask business rules/questions like: can I chat without booking?",
    ])


def capabilities_text() -> str:
    return "\n".join([
        'I can help you with:',
        '- book a ride (find trips and reserve seats)',
        "- create/post a ride (if you're a driver)",
        '- list your vehicles, bookings, and rides',
        "- delete your created ride (if allowed)",
        "- cancel your created ride (if allowed)",
        '- cancel your booking',
        '- view/send trip chat messages (only if authorized)',
        '',
        "Try: 'book a ride from X to Y tomorrow 6pm' or 'create a ride'.",
    ])


def smalltalk_reply(text: str) -> Optional[str]:
    low = normalize_text(text)
    if any(p in low for p in ['i love you', 'love you']):
        return "Thank you. I can help with rides/bookings—tell me what you'd like to do."
    if any(p in low for p in ['help me', 'i am in trouble', 'im in trouble', 'emergency']):
        return "I'm here to help with the app tasks (booking/creating rides, messages, etc.). If this is an emergency, please contact local emergency services or someone you trust right now."
    return None


def extract_rating(text: str) -> Optional[float]:
    m = re.search(r"\b([1-5](?:\.0)?)\s*(?:star|stars|rating)\b", text or '', flags=re.IGNORECASE)
    if m:
        try:
            return float(m.group(1))
        except Exception:
            return None
    return None


def parse_rating_value(text: str) -> Optional[float]:
    r = extract_rating(text)
    if r is not None:
        return r
    try:
        v = float(str(text or '').strip())
    except Exception:
        return None
    if 1.0 <= v <= 5.0:
        return v
    return None
