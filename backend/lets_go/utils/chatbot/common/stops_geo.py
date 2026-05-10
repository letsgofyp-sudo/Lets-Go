import difflib
import json
import math
from typing import Optional

from ..core import STOPS_GEO_JSON

from .text import normalize_text


_STOPS_GEO_CACHE: Optional[list[dict]] = None


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
            slon = float(
                s.get('lon')
                if s.get('lon') is not None
                else (s.get('lng') if s.get('lng') is not None else s.get('longitude'))
            )
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

    generic_phrases = {
        normalize_text('mosque'),
        normalize_text('masjid'),
        normalize_text('jamia masjid'),
        normalize_text('park'),
        normalize_text('children park'),
        normalize_text('مسجد'),
        normalize_text('جامع مسجد'),
        normalize_text('پارک'),
    }
    generic_tokens = {
        normalize_text('mosque'),
        normalize_text('masjid'),
        normalize_text('jamia'),
        normalize_text('park'),
        normalize_text('children'),
        normalize_text('مسجد'),
        normalize_text('جامع'),
        normalize_text('پارک'),
        normalize_text('باغ'),
    }

    q_tokens = {t for t in q.split(' ') if t}

    def is_generic_name(n: str) -> bool:
        nn = normalize_text(n)
        if not nn:
            return False
        if nn in generic_phrases:
            return True
        ntoks = [t for t in nn.split(' ') if t]
        if not ntoks:
            return False
        if len(ntoks) <= 2 and any(t in generic_tokens for t in ntoks):
            return True
        return False

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
        if is_generic_name(n):
            if len(q_tokens) <= 1:
                score *= 0.60
            else:
                score *= 0.85
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
        lon1 = float(
            a.get('lon')
            if a.get('lon') is not None
            else (a.get('lng') if a.get('lng') is not None else a.get('longitude'))
        )
        lat2 = float(b.get('lat') if b.get('lat') is not None else b.get('latitude'))
        lon2 = float(
            b.get('lon')
            if b.get('lon') is not None
            else (b.get('lng') if b.get('lng') is not None else b.get('longitude'))
        )
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
