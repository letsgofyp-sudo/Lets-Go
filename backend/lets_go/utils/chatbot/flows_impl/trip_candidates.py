from __future__ import annotations

import difflib

from ..integrations.http_client import call_view
from ..core import BookingDraft
from ..common.helpers import normalize_text
from ..engine_impl.sanitize import format_api_result


def best_stop_match(stops: list[dict], raw: str) -> tuple[int | None, str | None, float]:
    if not raw:
        return None, None, 0.0
    raw_norm = normalize_text(raw)
    best = (None, None, 0.0)
    for s in stops:
        if not isinstance(s, dict):
            continue
        name = str(s.get('name') or s.get('stop_name') or '')
        score = difflib.SequenceMatcher(a=raw_norm, b=normalize_text(name)).ratio()
        if score > best[2]:
            best = (int(s.get('order') or s.get('stop_order') or 0), name, float(score))
    return best


def find_trip_candidates(st: BookingDraft, *, limit: int = 5) -> list[dict]:
    candidates, _err = find_trip_candidates_safe(st, limit=limit)
    return candidates


def find_trip_candidates_safe(st: BookingDraft, *, limit: int = 5) -> tuple[list[dict], str | None]:
    if not st.from_stop_raw or not st.to_stop_raw:
        return [], None

    query = {
        'user_id': int(st.passenger_id) if st.passenger_id else None,
        'from': st.from_stop_raw,
        'to': st.to_stop_raw,
        'date': (st.trip_date.isoformat() if st.trip_date else None),
        'min_seats': int(st.number_of_seats) if st.number_of_seats else None,
        'limit': 30,
        'offset': 0,
        'sort': 'soonest',
    }
    if st.departure_time:
        query['time_from'] = st.departure_time

    status, out = call_view('GET', '/lets_go/trips/search/', query=query)
    trips = (out.get('trips') if isinstance(out, dict) else None) or []
    if status <= 0:
        return [], 'API server not reachable.'
    if status not in {200, 201, 202}:
        return [], format_api_result(status, out)
    if not isinstance(trips, list) or not trips:
        return [], None

    candidates: list[dict] = []
    for t in trips[:30]:
        if not isinstance(t, dict):
            continue
        trip_id = t.get('trip_id')
        if not trip_id:
            continue

        s2, detail = call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
        if s2 <= 0:
            continue
        if s2 not in {200, 201, 202}:
            continue
        if not isinstance(detail, dict):
            continue
        trip_obj = detail.get('trip') or {}
        route = (trip_obj.get('route') or {})
        stops = route.get('stops') or []
        if not isinstance(stops, list) or not stops:
            continue

        from_order, from_name, from_score = best_stop_match(stops, st.from_stop_raw)
        to_order, to_name, to_score = best_stop_match(stops, st.to_stop_raw)
        if not from_order or not to_order or int(from_order) >= int(to_order):
            continue
        stop_score = min(from_score, to_score)
        if stop_score < 0.55:
            continue

        try:
            driver_id = int(((trip_obj.get('driver') or {}).get('id') or 0))
        except Exception:
            driver_id = 0

        candidates.append({
            'trip_id': str(trip_id),
            'trip_date': str((t.get('departure_time') or '')).split('T', 1)[0] if t.get('departure_time') else None,
            'departure_time': str((t.get('departure_time') or '')).split('T', 1)[-1] if t.get('departure_time') else None,
            'route_name': str(t.get('origin') or ''),
            'available_seats': int(t.get('available_seats') or 0),
            'base_fare': int(t.get('price_per_seat') or 0),
            'driver_id': int(driver_id or 0),
            'driver_name': str((t.get('driver_name') or '') or ''),
            'from_stop_order': int(from_order),
            'to_stop_order': int(to_order),
            'from_stop_name': from_name,
            'to_stop_name': to_name,
            'score': float(stop_score),
        })

    candidates.sort(key=lambda x: (-x.get('score', 0.0), x.get('trip_date') or '', x.get('departure_time') or ''))
    return candidates[:limit], None
