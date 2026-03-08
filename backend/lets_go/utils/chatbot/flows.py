from __future__ import annotations

import difflib
import re
from datetime import datetime
from typing import Any, Optional

from . import api
from .http_client import call_view
from .helpers import (
    contains_abuse,
    capabilities_text,
    extract_booking_id,
    extract_coord_pairs,
    extract_fare,
    extract_from_to,
    extract_recipient_id,
    extract_seats,
    extract_trip_id,
    help_text,
    looks_like_route_id,
    fuzzy_stop_name,
    nearest_stop_name,
    normalize_text,
    parse_rating_value,
    parse_date,
    parse_relative_datetime,
    parse_time_str,
    to_int,
)
from .llm import llm_chat_reply, llm_extract_cached
from .state import BookingDraft, ConversationState, CreateRideDraft, MessageDraft, NegotiateDraft, PaymentDraft, reset_flow


def _nearest_stop_name_db_first(lat: float, lng: float) -> Optional[str]:
    try:
        status, out = api.api_suggest_stops(q='', limit=1, lat=float(lat), lng=float(lng))
        stops = (out.get('stops') if isinstance(out, dict) else None) or []
        if status > 0 and isinstance(stops, list) and stops:
            s0 = stops[0] if isinstance(stops[0], dict) else None
            name = (s0 or {}).get('stop_name')
            if name:
                return str(name).strip() or None
    except Exception:
        pass
    return nearest_stop_name(float(lat), float(lng))


def render_route_choice(routes: list[dict]) -> str:
    lines = ['I found multiple matching routes. Please reply with the number you want:']
    for i, r in enumerate(routes, start=1):
        if not isinstance(r, dict):
            continue
        lines.append(f"{i}) route_id={r.get('id')} | {r.get('name')}")
    lines.append("You can also say 'cancel' to stop.")
    return "\n".join(lines)


def render_trip_choice(candidates: list[dict]) -> str:
    lines = ['I found multiple matching trips. Reply with the number you want:']
    for i, c in enumerate(candidates, start=1):
        lines.append(
            f"{i}) trip_id={c.get('trip_id')} | {c.get('route_name')} | {c.get('trip_date')} {c.get('departure_time')} | seats={c.get('available_seats')} | base_fare={c.get('base_fare')}"
        )
    lines.append("You can also say 'cancel' to stop.")
    return "\n".join(lines)


def render_vehicle_choice(vehicles: list[dict]) -> str:
    lines = ['I found multiple vehicles. Reply with the number you want:']
    for i, v in enumerate(vehicles, start=1):
        if not isinstance(v, dict):
            continue
        seats = v.get('seats')
        seats_txt = f"{int(seats)}" if seats not in [None, ''] else '-'
        lines.append(
            f"{i}) vehicle_id={v.get('id')} | {v.get('plate_number', '')} | {v.get('company_name', '')} {v.get('model_number', '')} | type={v.get('vehicle_type', '')} | seats={seats_txt} | status={v.get('status', '')}"
        )
    lines.append("You can also say 'cancel' to stop.")
    return "\n".join(lines)


def render_booking_summary(st: ConversationState) -> str:
    d = st.booking
    base_fare = int(d.selected_base_fare or 0)
    proposed = int(d.proposed_fare or base_fare)
    seats = int(d.number_of_seats or 1)
    is_neg = proposed != base_fare
    return "\n".join([
        'Please confirm your booking request:',
        f"- trip_id: {d.selected_trip_id}",
        f"- route: {d.selected_route_name or ''}",
        f"- date/time: {d.selected_trip_date or ''} {d.selected_departure_time or ''}",
        f"- from: {d.selected_from_stop_name} (order {d.selected_from_stop_order})",
        f"- to: {d.selected_to_stop_name} (order {d.selected_to_stop_order})",
        f"- seats: {seats}",
        f"- price per seat: {proposed} (base {base_fare})",
        f"- negotiated: {'yes' if is_neg else 'no'}",
        "Reply 'yes' to confirm or 'no' to cancel.",
    ])


def render_create_summary(st: ConversationState) -> str:
    d = st.create_ride
    return "\n".join([
        'Please confirm your ride creation:',
        f"- route_id: {d.route_id}{(' (' + d.route_name + ')') if d.route_name else ''}",
        f"- vehicle_id: {d.vehicle_id}",
        f"- trip_date: {d.trip_date.isoformat() if d.trip_date else None}",
        f"- departure_time: {d.departure_time}",
        f"- total_seats: {d.total_seats}",
        f"- custom_price: {d.custom_price}",
        f"- gender_preference: {d.gender_preference or 'Any'}",
        "Reply 'yes' to confirm or 'no' to cancel.",
    ])


def list_user_vehicles(ctx: BotContext, *, limit: int = 20) -> str:
    status, out = api.api_list_my_vehicles(ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    vehicles = (out.get('vehicles') if isinstance(out, dict) else None) or []
    if not isinstance(vehicles, list) or not vehicles:
        return 'I could not find any vehicles in your account.'

    lines = ['Here are your vehicles:']
    for v in vehicles[:limit]:
        if not isinstance(v, dict):
            continue
        seats = v.get('seats')
        seats_txt = f"{int(seats)}" if seats not in [None, ''] else '-'
        lines.append(
            f"- vehicle_id={v.get('id')} | {v.get('plate_number', '')} | {v.get('company_name', '')} {v.get('model_number', '')} | type={v.get('vehicle_type', '')} | seats={seats_txt} | status={v.get('status', '')}"
        )
    lines.append('Reply with the vehicle_id you want to use.')
    return "\n".join(lines)


def list_user_vehicles_state(st: ConversationState, *, limit: int = 20) -> str:
    status, out = api.api_list_my_vehicles(st.ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    vehicles = (out.get('vehicles') if isinstance(out, dict) else None) or []
    if not isinstance(vehicles, list) or not vehicles:
        return 'I could not find any vehicles in your account.'
    st.create_ride.vehicle_candidates = vehicles
    if st.active_flow == 'create_ride' or st.awaiting_field == 'vehicle_id':
        st.active_flow = 'choose_vehicle'
        st.awaiting_field = None
        return render_vehicle_choice(vehicles[:limit])
    return list_user_vehicles(st.ctx, limit=limit)


def list_user_created_trips(ctx: BotContext, *, limit: int = 20) -> str:
    status, out = api.api_list_my_rides(ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    rides = (out.get('rides') if isinstance(out, dict) else None) or []
    if not isinstance(rides, list) or not rides:
        return "I couldn't find any rides/trips created by you."

    def _format(rides_list: list[dict]) -> str:
        def _origin(r: dict) -> str:
            rn = r.get('route_names')
            if isinstance(rn, list) and rn:
                return str(rn[0] or '').strip() or 'Unknown'
            v = r.get('from_location')
            return str(v or '').strip() or 'Unknown'

        def _dest(r: dict) -> str:
            rn = r.get('route_names')
            if isinstance(rn, list) and rn:
                return str(rn[-1] or '').strip() or 'Unknown'
            v = r.get('to_location')
            return str(v or '').strip() or 'Unknown'

        lines = ['Here are your created rides:']
        for r in rides_list[:limit]:
            if not isinstance(r, dict):
                continue
            trip_id = str(r.get('trip_id') or '').strip()
            lines.append(
                f"- trip_id={trip_id} | {_origin(r)} -> {_dest(r)} | {r.get('trip_date', '')} {r.get('departure_time', '')} | status={r.get('status', '')}"
            )
        return "\n".join(lines)
    return _format(rides)


def list_user_created_trips_state(st: ConversationState, *, limit: int = 20, vehicle_id: Optional[int] = None) -> str:
    status, out = api.api_list_my_rides(st.ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    rides = (out.get('rides') if isinstance(out, dict) else None) or []
    if not isinstance(rides, list) or not rides:
        return "I couldn't find any rides/trips created by you."

    if vehicle_id is not None:
        try:
            vid = int(vehicle_id)
        except Exception:
            vid = 0
        if vid:
            filtered = []
            for r in rides:
                if not isinstance(r, dict):
                    continue
                v = r.get('vehicle') if isinstance(r.get('vehicle'), dict) else {}
                try:
                    if int(v.get('id') or 0) == vid:
                        filtered.append(r)
                except Exception:
                    continue
            rides = filtered
            if not rides:
                return f"I couldn't find any created rides on vehicle_id={vid}."

    try:
        st.last_listed_trip_ids = []
        for r in (rides[:limit] if isinstance(rides, list) else []):
            if not isinstance(r, dict):
                continue
            tid = str(r.get('trip_id') or '').strip()
            if tid:
                st.last_listed_trip_ids.append(tid)
    except Exception:
        st.last_listed_trip_ids = []
    if isinstance(rides, list) and rides:
        try:
            first = rides[0] if isinstance(rides[0], dict) else None
            trip_id = str((first or {}).get('trip_id') or '').strip()
            if trip_id:
                st.last_trip_id = trip_id
        except Exception:
            pass

    def _stops_from_trip_detail(trip_id: str) -> tuple[Optional[str], Optional[str]]:
        try:
            s2, detail = api.api_trip_detail(str(trip_id))
            if s2 <= 0 or not isinstance(detail, dict):
                return None, None
            trip_obj = (detail.get('trip') or {}) if isinstance(detail.get('trip'), dict) else {}
            route = (trip_obj.get('route') or {}) if isinstance(trip_obj.get('route'), dict) else {}
            stops = route.get('stops') or []
            if not isinstance(stops, list) or not stops:
                return None, None
            first = stops[0] if isinstance(stops[0], dict) else None
            last = stops[-1] if isinstance(stops[-1], dict) else None
            a = str((first or {}).get('name') or (first or {}).get('stop_name') or '').strip() or None
            b = str((last or {}).get('name') or (last or {}).get('stop_name') or '').strip() or None
            return a, b
        except Exception:
            return None, None

    def _origin(r: dict) -> str:
        rn = r.get('route_names')
        if isinstance(rn, list) and rn:
            v0 = str(rn[0] or '').strip()
            if v0:
                return v0
        v = str(r.get('from_location') or '').strip()
        if v and v.lower() != 'unknown':
            return v
        trip_id = str(r.get('trip_id') or '').strip()
        if trip_id:
            a, _ = _stops_from_trip_detail(trip_id)
            if a:
                return a
        return 'Unknown'

    def _dest(r: dict) -> str:
        rn = r.get('route_names')
        if isinstance(rn, list) and rn:
            v0 = str(rn[-1] or '').strip()
            if v0:
                return v0
        v = str(r.get('to_location') or '').strip()
        if v and v.lower() != 'unknown':
            return v
        trip_id = str(r.get('trip_id') or '').strip()
        if trip_id:
            _, b = _stops_from_trip_detail(trip_id)
            if b:
                return b
        return 'Unknown'

    lines = ['Here are your created rides:']
    for r in rides[:limit]:
        if not isinstance(r, dict):
            continue
        trip_id = str(r.get('trip_id') or '').strip()
        v = r.get('vehicle') if isinstance(r.get('vehicle'), dict) else {}
        vtxt = ''
        if isinstance(v, dict) and v.get('id') is not None:
            plate = str(v.get('plate_number') or '').strip()
            vtxt = f" | vehicle_id={v.get('id')}" + (f" ({plate})" if plate else '')
        lines.append(
            f"- trip_id={trip_id} | {_origin(r)} -> {_dest(r)} | {r.get('trip_date', '')} {r.get('departure_time', '')}{vtxt} | status={r.get('status', '')}"
        )
    return "\n".join(lines)


def list_user_booked_rides(ctx: BotContext, *, limit: int = 20) -> str:
    status, out = api.list_my_bookings(ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    bookings = (out.get('bookings') if isinstance(out, dict) else None) or []
    if not isinstance(bookings, list) or not bookings:
        return "I couldn't find any booked rides in your account."

    def _origin(b: dict) -> str:
        rn = b.get('route_names')
        if isinstance(rn, list) and rn:
            return str(rn[0] or '').strip() or 'Unknown'
        v = b.get('from_location')
        return str(v or '').strip() or 'Unknown'

    def _dest(b: dict) -> str:
        rn = b.get('route_names')
        if isinstance(rn, list) and rn:
            return str(rn[-1] or '').strip() or 'Unknown'
        v = b.get('to_location')
        return str(v or '').strip() or 'Unknown'

    lines = ['Here are your booked rides:']
    for b in bookings[:limit]:
        if not isinstance(b, dict):
            continue
        booking_id = str(b.get('booking_id') or b.get('id') or '').strip()
        trip_id = str(b.get('trip_id') or '').strip()
        st = b.get('booking_status') or b.get('status') or ''
        lines.append(
            f"- booking_id={booking_id} | trip_id={trip_id} | {_origin(b)} -> {_dest(b)} | {b.get('trip_date', '')} {b.get('departure_time', '')} | status={st}"
        )
    return "\n".join(lines)


def list_user_booked_rides_state(st: ConversationState, *, limit: int = 20) -> str:
    status, out = api.list_my_bookings(st.ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    bookings = (out.get('bookings') if isinstance(out, dict) else None) or []
    if not isinstance(bookings, list) or not bookings:
        return "I couldn't find any booked rides in your account."
    if isinstance(bookings, list) and bookings:
        try:
            first = bookings[0] if isinstance(bookings[0], dict) else None
            bid = (first or {}).get('id') or 0
            st.last_booking_id = int(bid) if bid else st.last_booking_id
            tid = str((first or {}).get('trip_id') or '').strip()
            if tid and not st.last_trip_id:
                st.last_trip_id = tid
        except Exception:
            pass

    def _origin(b: dict) -> str:
        rn = b.get('route_names')
        if isinstance(rn, list) and rn:
            return str(rn[0] or '').strip() or 'Unknown'
        v = b.get('from_location')
        return str(v or '').strip() or 'Unknown'

    def _dest(b: dict) -> str:
        rn = b.get('route_names')
        if isinstance(rn, list) and rn:
            return str(rn[-1] or '').strip() or 'Unknown'
        v = b.get('to_location')
        return str(v or '').strip() or 'Unknown'

    lines = ['Here are your booked rides:']
    for b in bookings[:limit]:
        if not isinstance(b, dict):
            continue
        booking_id = str(b.get('booking_id') or b.get('id') or '').strip()
        trip_id = str(b.get('trip_id') or '').strip()
        st_txt = b.get('booking_status') or b.get('status') or ''
        lines.append(
            f"- booking_id={booking_id} | trip_id={trip_id} | {_origin(b)} -> {_dest(b)} | {b.get('trip_date', '')} {b.get('departure_time', '')} | status={st_txt}"
        )
    return "\n".join(lines)


def list_user_rides_and_bookings(ctx: BotContext, *, rides_limit: int = 20, bookings_limit: int = 20) -> str:
    created = list_user_created_trips(ctx, limit=rides_limit)
    booked = list_user_booked_rides(ctx, limit=bookings_limit)
    return "\n\n".join([created, booked])


def list_user_rides_and_bookings_state(st: ConversationState, *, rides_limit: int = 20, bookings_limit: int = 20) -> str:
    created = list_user_created_trips_state(st, limit=rides_limit)
    booked = list_user_booked_rides_state(st, limit=bookings_limit)
    return "\n\n".join([created, booked])


def best_stop_match(stops: list[dict], raw: str) -> tuple[Optional[int], Optional[str], float]:
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
    if not st.from_stop_raw or not st.to_stop_raw:
        return []

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
    if status <= 0 or not isinstance(trips, list) or not trips:
        return []

    candidates: list[dict] = []
    for t in trips[:30]:
        if not isinstance(t, dict):
            continue
        trip_id = t.get('trip_id')
        if not trip_id:
            continue

        s2, detail = call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
        if s2 <= 0 or not isinstance(detail, dict):
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
    return candidates[:limit]


def routes_from_stop_suggestions(from_q: str, to_q: str) -> list[dict]:
    s1, out1 = api.api_suggest_stops(q=from_q or '', limit=10)
    s2, out2 = api.api_suggest_stops(q=to_q or '', limit=10)
    stops1 = (out1.get('stops') if isinstance(out1, dict) else None) or []
    stops2 = (out2.get('stops') if isinstance(out2, dict) else None) or []
    if s1 <= 0 or s2 <= 0:
        return []
    if not isinstance(stops1, list) or not isinstance(stops2, list):
        return []

    from_routes: dict[str, dict] = {}
    for s in stops1[:20]:
        if not isinstance(s, dict):
            continue
        rid = str(s.get('route_id') or '').strip()
        if not rid:
            continue
        score = float(s.get('score') or 0.0)
        cur = from_routes.get(rid)
        if cur is None or score > float(cur.get('_score') or 0.0):
            from_routes[rid] = {'id': rid, 'name': str(s.get('route_name') or '').strip(), '_score': score}

    to_routes: dict[str, dict] = {}
    for s in stops2[:20]:
        if not isinstance(s, dict):
            continue
        rid = str(s.get('route_id') or '').strip()
        if not rid:
            continue
        score = float(s.get('score') or 0.0)
        cur = to_routes.get(rid)
        if cur is None or score > float(cur.get('_score') or 0.0):
            to_routes[rid] = {'id': rid, 'name': str(s.get('route_name') or '').strip(), '_score': score}

    common = set(from_routes.keys()) & set(to_routes.keys())
    routes: list[dict] = []
    for rid in common:
        a = from_routes.get(rid) or {}
        b = to_routes.get(rid) or {}
        routes.append({'id': rid, 'name': (a.get('name') or b.get('name') or rid), '_score': float(a.get('_score') or 0.0) + float(b.get('_score') or 0.0)})

    routes.sort(key=lambda x: -float(x.get('_score') or 0.0))
    for r in routes:
        r.pop('_score', None)
    return routes[:8]


def resolve_route_from_text(st: ConversationState, raw: str) -> Optional[str]:
    d = st.create_ride
    t = (raw or '').strip()
    if not t:
        return None

    if contains_abuse(t):
        return "I want to help, but please keep it respectful. Tell me the pickup and drop-off stops like: 'Quaid-e-Azam Park to Fasal Town'."

    m = re.search(r"\b(R[0-9A-Z]{2,12})\b", t, flags=re.IGNORECASE)
    if m:
        candidate = (m.group(1) or '').strip().upper()
        if looks_like_route_id(candidate):
            d.route_id = candidate
            d.route_name = None
            d.route_candidates = None
            return None

    llm = llm_extract_cached(st, t)
    if isinstance(llm, dict) and llm.get('route_id') and looks_like_route_id(str(llm.get('route_id')).strip()):
        d.route_id = str(llm.get('route_id')).strip().upper()
        d.route_name = None
        d.route_candidates = None
        return None

    frm, to = extract_from_to(t)
    if isinstance(llm, dict):
        if llm.get('from_stop') and not frm:
            frm = str(llm.get('from_stop')).strip() or frm
        if llm.get('to_stop') and not to:
            to = str(llm.get('to_stop')).strip() or to

    if not frm and not to:
        if len(t) <= 64 and not re.search(r"\b(recreate|re-book|rebook|book|booking|create|post|ride|trip|recent|last)\b", t, flags=re.IGNORECASE):
            m2 = re.search(r"^(.+?)\s+to\s+(.+)$", t, flags=re.IGNORECASE)
            if m2:
                left = (m2.group(1) or '').strip(' ,.-')
                right = (m2.group(2) or '').strip(' ,.-')
                if 0 < len(left) <= 32 and 0 < len(right) <= 32:
                    frm = left or None
                    to = right or None

    if not frm and not to:
        pairs = extract_coord_pairs(t)
        if pairs:
            if len(pairs) >= 2:
                frm = _nearest_stop_name_db_first(pairs[0][0], pairs[0][1]) or frm
                to = _nearest_stop_name_db_first(pairs[1][0], pairs[1][1]) or to
            else:
                frm = _nearest_stop_name_db_first(pairs[0][0], pairs[0][1]) or frm

    if not frm or not to:
        llm_reply = llm_chat_reply(st, t)
        if llm_reply:
            return llm_reply
        return "Tell me the route using two stop names, like: 'Quaid-e-Azam Park to Fasal Town'."

    frm2 = fuzzy_stop_name(frm) or frm
    to2 = fuzzy_stop_name(to) or to

    status, out = api.api_search_routes(from_location=frm2, to_location=to2)
    routes = (out.get('routes') if isinstance(out, dict) else None) or []
    if status <= 0:
        return 'API server not reachable.'

    if not isinstance(routes, list) or not routes:
        derived = routes_from_stop_suggestions(frm2, to2)
        if derived:
            raw_norm = normalize_text(t)
            scored: list[tuple[float, dict]] = []
            for r in derived:
                if not isinstance(r, dict):
                    continue
                name = str(r.get('name') or '')
                rid = str(r.get('id') or '')
                score = max(
                    difflib.SequenceMatcher(a=raw_norm, b=normalize_text(name)).ratio(),
                    difflib.SequenceMatcher(a=raw_norm, b=normalize_text(rid)).ratio(),
                )
                scored.append((float(score), r))
            scored.sort(key=lambda x: -x[0])
            best_score, best = scored[0]
            if best_score >= 0.80:
                d.route_id = str(best.get('id') or '').strip() or d.route_id
                d.route_name = str(best.get('name') or '').strip() or None
                d.route_candidates = None
                return None
            d.route_candidates = [r for _, r in scored[:8]]
            st.active_flow = 'choose_route'
            st.awaiting_field = None
            return render_route_choice(d.route_candidates)

        d.route_id = None
        d.route_name = t
        d.route_candidates = None
        llm_reply = llm_chat_reply(st, f"User couldn't find route for: from={frm2} to={to2}. Help them rephrase with correct stop names.")
        return llm_reply or "I couldn't find that route in the system. Try slightly different stop names (or tell me nearby landmarks), like: 'Vehari Quaid-e-Azam Park to Vehari Fasal Town'."

    if len(routes) == 1:
        r0 = routes[0]
        if isinstance(r0, dict):
            d.route_id = str(r0.get('id') or '').strip() or d.route_id
            d.route_name = str(r0.get('name') or '').strip() or None
            d.route_candidates = None
        return None

    raw_norm = normalize_text(t)
    scored: list[tuple[float, dict]] = []
    for r in routes:
        if not isinstance(r, dict):
            continue
        name = str(r.get('name') or '')
        rid = str(r.get('id') or '')
        score = max(
            difflib.SequenceMatcher(a=raw_norm, b=normalize_text(name)).ratio(),
            difflib.SequenceMatcher(a=raw_norm, b=normalize_text(rid)).ratio(),
        )
        scored.append((float(score), r))
    scored.sort(key=lambda x: -x[0])

    best_score, best = scored[0]
    if best_score >= 0.80:
        d.route_id = str(best.get('id') or '').strip() or d.route_id
        d.route_name = str(best.get('name') or '').strip() or None
        d.route_candidates = None
        return None

    d.route_candidates = [r for _, r in scored[:8]]
    st.active_flow = 'choose_route'
    st.awaiting_field = None
    return render_route_choice(d.route_candidates)


def _cancel_reason_from_text(text: str) -> Optional[str]:
    raw = (text or '').strip()
    if not raw:
        return None
    m = re.search(r"\breason\s*[:=]\s*(.+)$", raw, flags=re.IGNORECASE)
    if m:
        return (m.group(1) or '').strip() or None
    m = re.search(r"\bbecause\s+(.+)$", raw, flags=re.IGNORECASE)
    if m:
        return (m.group(1) or '').strip() or None
    return None


def _pick_most_recent_ride(rides: Any) -> Optional[dict]:
    if not isinstance(rides, list) or not rides:
        return None
    for r in rides:
        if isinstance(r, dict) and r.get('trip_id'):
            return r
    return None


def start_manage_trip_flow(st: ConversationState, text: str, *, mode: str) -> str:
    trip_id = extract_trip_id(text) or st.last_trip_id
    status, out = api.api_list_my_rides(st.ctx, limit=50)
    if status <= 0:
        return 'API server not reachable.'
    rides = (out.get('rides') if isinstance(out, dict) else None) or []
    if not trip_id:
        picked = _pick_most_recent_ride(rides)
        trip_id = str((picked or {}).get('trip_id') or '').strip() or None
    if not trip_id:
        return "I couldn't find any created rides in your account."

    ride = None
    if isinstance(rides, list):
        for r in rides:
            if isinstance(r, dict) and str(r.get('trip_id') or '').strip() == str(trip_id):
                ride = r
                break

    details = ''
    if isinstance(ride, dict):
        details = f" | {ride.get('from_location', '')} -> {ride.get('to_location', '')} | {ride.get('trip_date', '')} {ride.get('departure_time', '')} | status={ride.get('status', '')}"

    if mode == 'delete':
        st.active_flow = 'confirm_delete_trip'
        st.pending_action = {'type': 'delete_trip', 'trip_id': str(trip_id)}
        st.awaiting_field = None
        return "\n".join([
            'Please confirm trip deletion:',
            f"- trip_id: {trip_id}{details}",
            "Reply 'yes' to confirm or 'no' to cancel.",
        ])

    reason = _cancel_reason_from_text(text) or 'Cancelled by driver'
    st.active_flow = 'confirm_cancel_trip'
    st.pending_action = {'type': 'cancel_trip', 'trip_id': str(trip_id), 'reason': reason}
    st.awaiting_field = None
    return "\n".join([
        'Please confirm trip cancellation:',
        f"- trip_id: {trip_id}{details}",
        f"- reason: {reason}",
        "Reply 'yes' to confirm or 'no' to cancel.",
    ])


def _pick_most_recent_completed_ride(rides: Any) -> Optional[dict]:
    if not isinstance(rides, list) or not rides:
        return None
    for r in rides:
        if not isinstance(r, dict) or not r.get('trip_id'):
            continue
        stt = normalize_text(str(r.get('status') or r.get('trip_status') or ''))
        if stt in {'completed', 'complete'}:
            return r
    return None


def start_recreate_ride_flow(st: ConversationState, text: str) -> str:
    status, out = api.api_list_my_rides(st.ctx, limit=50)
    if status <= 0:
        return 'API server not reachable.'
    rides = (out.get('rides') if isinstance(out, dict) else None) or []

    picked = _pick_most_recent_completed_ride(rides)
    if picked is None:
        low = normalize_text(text)
        if any(k in low for k in ['last ride', 'recent ride', 'my last ride', 'my recent ride']):
            picked = _pick_most_recent_ride(rides)
    if not picked:
        return "I couldn't find any completed rides to recreate."

    trip_id = str((picked or {}).get('trip_id') or '').strip()
    if not trip_id:
        return "I couldn't identify the trip_id of that ride."

    ds, detail = api.api_trip_detail(trip_id)
    if ds <= 0:
        return 'API server not reachable.'
    if not isinstance(detail, dict) or not detail.get('success'):
        if isinstance(detail, dict) and detail.get('error'):
            return str(detail.get('error'))
        return 'Failed to fetch ride details.'

    trip = detail.get('trip') if isinstance(detail.get('trip'), dict) else {}
    route = detail.get('route') if isinstance(detail.get('route'), dict) else {}
    vehicle = detail.get('vehicle') if isinstance(detail.get('vehicle'), dict) else {}

    d = st.create_ride
    d.route_id = str(route.get('id') or '').strip().upper() or None
    d.route_name = str(route.get('name') or '').strip() or None
    d.route_candidates = None
    d.vehicle_id = to_int(vehicle.get('id')) or d.vehicle_id
    d.total_seats = to_int(trip.get('total_seats')) or d.total_seats
    d.custom_price = to_int(trip.get('base_fare')) or d.custom_price
    gp = str(trip.get('gender_preference') or '').strip()
    d.gender_preference = gp if gp in {'Male', 'Female', 'Any'} else (d.gender_preference or 'Any')
    d.notes = str(trip.get('notes') or '').strip() or None
    if trip.get('is_negotiable') is not None:
        d.is_negotiable = bool(trip.get('is_negotiable'))

    dt = parse_relative_datetime(text)
    if dt:
        d.trip_date, d.departure_time = dt

    st.active_flow = 'create_ride'
    st.awaiting_field = None

    stops = route.get('stops') if isinstance(route.get('stops'), list) else []
    from_name = str(picked.get('from_location') or '').strip()
    to_name = str(picked.get('to_location') or '').strip()
    if (not from_name or from_name.lower() == 'unknown') and stops:
        first = stops[0] if isinstance(stops[0], dict) else {}
        from_name = str(first.get('name') or '').strip() or from_name
    if (not to_name or to_name.lower() == 'unknown') and stops:
        last = stops[-1] if isinstance(stops[-1], dict) else {}
        to_name = str(last.get('name') or '').strip() or to_name
    from_name = from_name or 'From'
    to_name = to_name or 'To'
    plate = str(vehicle.get('plate_number') or '').strip()
    veh_str = plate or (f"vehicle_id={d.vehicle_id}" if d.vehicle_id else 'vehicle')
    route_id = d.route_id or 'Unknown'

    stop_preview = ''
    if stops:
        names = [str(s.get('name') or '').strip() for s in stops if isinstance(s, dict) and str(s.get('name') or '').strip()]
        if names:
            if len(names) <= 6:
                stop_preview = "Stops: " + " -> ".join(names)
            else:
                stop_preview = "Stops: " + " -> ".join(names[:3]) + " -> ... -> " + " -> ".join(names[-2:])

    header = "\n".join([
        'I found your ride and can recreate it with a new date/time:',
        f"- Trip: {trip_id}",
        f"- Route: {from_name} -> {to_name} (route_id={route_id})",
        *([f"- {stop_preview}"] if stop_preview else []),
        f"- Vehicle: {veh_str}",
        f"- Fare per seat: {d.custom_price}",
        f"- Seats offered: {d.total_seats}",
        f"- Gender preference: {d.gender_preference or 'Any'}",
    ])

    nxt = continue_create_flow(st, text)
    if nxt:
        return header + "\n\n" + nxt
    return header + "\n\n" + "What new date/time should I set? (e.g., 'after 1 hour' or 'tomorrow 12:50am')"


def update_booking_from_text(st: ConversationState, text: str) -> None:
    d = st.booking
    llm = llm_extract_cached(st, text)
    frm, to = extract_from_to(text)
    if llm.get('from_stop'):
        d.from_stop_raw = str(llm.get('from_stop')).strip()
    elif frm:
        d.from_stop_raw = frm
    if llm.get('to_stop'):
        d.to_stop_raw = str(llm.get('to_stop')).strip()
    elif to:
        d.to_stop_raw = to

    if (not d.from_stop_raw or not d.to_stop_raw):
        pairs = extract_coord_pairs(text)
        if pairs:
            if not d.from_stop_raw and (st.awaiting_field == 'from_stop' or len(pairs) >= 2):
                d.from_stop_raw = _nearest_stop_name_db_first(pairs[0][0], pairs[0][1]) or d.from_stop_raw
            if not d.to_stop_raw:
                idx = 1 if len(pairs) >= 2 else 0
                if st.awaiting_field == 'to_stop' or len(pairs) >= 2:
                    d.to_stop_raw = _nearest_stop_name_db_first(pairs[idx][0], pairs[idx][1]) or d.to_stop_raw

    if llm.get('date'):
        try:
            d.trip_date = datetime.strptime(str(llm.get('date')), '%Y-%m-%d').date()
        except Exception:
            pass
    if d.trip_date is None:
        d.trip_date = parse_date(text) or d.trip_date

    if llm.get('time'):
        d.departure_time = str(llm.get('time')).strip()
    if d.departure_time is None:
        d.departure_time = parse_time_str(text) or d.departure_time

    if llm.get('seats'):
        d.number_of_seats = to_int(llm.get('seats')) or d.number_of_seats
    if d.number_of_seats is None:
        d.number_of_seats = extract_seats(text) or d.number_of_seats

    if llm.get('fare'):
        d.proposed_fare = to_int(llm.get('fare')) or d.proposed_fare
    if d.proposed_fare is None:
        d.proposed_fare = extract_fare(text) or d.proposed_fare


def update_create_from_text(st: ConversationState, text: str) -> None:
    d = st.create_ride
    llm = llm_extract_cached(st, text)
    if isinstance(llm, dict):
        if llm.get('route_id'):
            candidate = str(llm.get('route_id')).strip()
            if looks_like_route_id(candidate):
                d.route_id = candidate
                d.route_name = None
                d.route_candidates = None
        if llm.get('route_name') and not d.route_id:
            rn = str(llm.get('route_name')).strip()
            if rn and len(rn) <= 80 and re.search(r"\b(from|to)\b", rn, flags=re.IGNORECASE):
                d.route_name = rn
        if d.vehicle_id is None and llm.get('vehicle_id') is not None:
            d.vehicle_id = to_int(llm.get('vehicle_id')) or d.vehicle_id
        if d.total_seats is None and llm.get('total_seats') is not None:
            d.total_seats = to_int(llm.get('total_seats')) or d.total_seats
        if d.custom_price is None and llm.get('custom_price') is not None:
            d.custom_price = to_int(llm.get('custom_price')) or d.custom_price
        if llm.get('gender_preference'):
            gp = str(llm.get('gender_preference')).strip().lower()
            if gp in {'female', 'f'}:
                d.gender_preference = 'Female'
            elif gp in {'male', 'm'}:
                d.gender_preference = 'Male'
            elif gp in {'any', 'all', 'no preference'}:
                d.gender_preference = 'Any'
        if llm.get('notes') is not None:
            v = str(llm.get('notes') or '').strip()
            if v:
                d.notes = v
        if llm.get('is_negotiable') is not None:
            raw = str(llm.get('is_negotiable')).strip().lower()
            if raw in {'0', 'false', 'no', 'off'}:
                d.is_negotiable = False
            elif raw in {'1', 'true', 'yes', 'on'}:
                d.is_negotiable = True
        if llm.get('date') and d.trip_date is None:
            try:
                d.trip_date = datetime.strptime(str(llm.get('date')), '%Y-%m-%d').date()
            except Exception:
                pass
        if llm.get('time') and d.departure_time is None:
            d.departure_time = str(llm.get('time')).strip() or d.departure_time

    if d.trip_date is None or d.departure_time is None:
        dt = parse_relative_datetime(text)
        if dt:
            if d.trip_date is None:
                d.trip_date = dt[0]
            if d.departure_time is None:
                d.departure_time = dt[1]

    m = re.search(r"\broute[_\s-]*id\s*[:=]\s*([A-Za-z0-9_-]+)\b", text or '', flags=re.IGNORECASE)
    if m:
        candidate = (m.group(1) or '').strip()
        if looks_like_route_id(candidate):
            d.route_id = candidate
            d.route_name = None
            d.route_candidates = None
        else:
            d.route_name = candidate
            d.route_id = None

    d.trip_date = d.trip_date or parse_date(text)
    d.departure_time = d.departure_time or parse_time_str(text)

    if d.vehicle_id is None:
        m = re.search(r"\bvehicle[_\s-]*id\s*[:=]\s*(\d+)\b", text or '', flags=re.IGNORECASE)
        if m:
            d.vehicle_id = to_int(m.group(1))

    if d.total_seats is None:
        m = re.search(r"\btotal\s*seats\s*[:=]?\s*(\d+)\b", text or '', flags=re.IGNORECASE)
        if m:
            d.total_seats = to_int(m.group(1))
        if d.total_seats is None:
            d.total_seats = extract_seats(text)

    if d.custom_price is None:
        d.custom_price = extract_fare(text)

    if re.search(r"\bfemale\b", text or '', flags=re.IGNORECASE):
        d.gender_preference = 'Female'
    elif re.search(r"\bmale\b", text or '', flags=re.IGNORECASE):
        d.gender_preference = 'Male'
    elif re.search(r"\bany\b", text or '', flags=re.IGNORECASE):
        d.gender_preference = 'Any'

    low = normalize_text(text)
    if d.is_negotiable is None:
        if any(p in low for p in ['fixed price', 'no negotiation', 'not negotiable', 'non negotiable', 'non-negotiable']):
            d.is_negotiable = False
        elif 'negotiable' in low or 'negotiation' in low:
            d.is_negotiable = True

    m = re.search(r"\b(?:note|notes|description|desc)\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
    if m:
        v = (m.group(1) or '').strip()
        if v:
            d.notes = v


def update_message_from_text(st: ConversationState, text: str) -> None:
    d = st.message
    llm = llm_extract_cached(st, text)
    d.trip_id = d.trip_id or extract_trip_id(text) or st.last_trip_id
    if d.recipient_id is None:
        if llm.get('recipient_id'):
            d.recipient_id = to_int(llm.get('recipient_id'))
        if d.recipient_id is None:
            d.recipient_id = extract_recipient_id(text)
    if d.message_text is None and llm.get('message_text'):
        d.message_text = str(llm.get('message_text')).strip()
    if d.message_text is None:
        raw = (text or '').strip()
        m = re.search(r"\b(?:message|msg|text)\b\s*(.+)$", raw, flags=re.IGNORECASE)
        if m:
            remainder = (m.group(1) or '').strip()
            remainder = re.sub(r"\btrip[_\s-]*id\b\s*[:=]?\s*([A-Za-z0-9._:-]+)", " ", remainder, flags=re.IGNORECASE)
            remainder = re.sub(r"\brecipient[_\s-]*id\b\s*[:=]?\s*(\d+)", " ", remainder, flags=re.IGNORECASE)
            remainder = re.sub(r"\bto\s+user\s+(\d+)", " ", remainder, flags=re.IGNORECASE)
            remainder = re.sub(r"\s+", " ", remainder).strip()
            d.message_text = remainder or None
    if d.sender_role is None:
        if re.search(r"\bdriver\b", text or '', flags=re.IGNORECASE):
            d.sender_role = 'driver'
        if re.search(r"\bpassenger\b", text or '', flags=re.IGNORECASE):
            d.sender_role = 'passenger'


def map_llm_intent(val: Any) -> Optional[str]:
    s = normalize_text(str(val or ''))
    if not s:
        return None
    if s in {'book_ride', 'book', 'booking', 'reserve', 'reserve_ride'}:
        return 'book_ride'
    if s in {'create_ride', 'create', 'post_ride', 'post', 'ride_posting'}:
        return 'create_ride'
    if s in {'recreate_ride', 'recreate', 'recreate ride', 'recreate_ride_post', 'repeat_ride', 'repeat ride', 'clone ride', 'repost ride'}:
        return 'recreate_ride'
    if s in {'message', 'send_message', 'chat', 'chat_send'}:
        return 'message'
    if s in {'negotiate', 'negotiation'}:
        return 'negotiate'
    if s in {'cancel_booking', 'cancel', 'cancel ride', 'cancel booking'}:
        return 'cancel_booking'
    if s in {'list_vehicles', 'vehicles', 'my_vehicles', 'list vehicle', 'list vehicles'}:
        return 'list_vehicles'
    if s in {'list_my_rides', 'my_rides', 'list rides', 'list my rides', 'rides'}:
        return 'list_my_rides'
    if s in {'delete_trip', 'delete_ride', 'delete ride', 'remove ride', 'remove trip', 'delete trip'}:
        return 'delete_trip'
    if s in {'cancel_trip', 'cancel_ride', 'cancel ride', 'cancel trip'}:
        return 'cancel_trip'
    if s in {'list_bookings', 'my_bookings', 'list bookings', 'bookings'}:
        return 'list_bookings'
    if s in {'profile_view', 'profile', 'my_profile', 'view profile'}:
        return 'profile_view'
    if s in {'profile_update', 'update profile', 'edit profile'}:
        return 'profile_update'
    if s in {'help'}:
        return 'help'
    if s in {'greet', 'hello', 'hi'}:
        return 'greet'
    if s in {'capabilities', 'features', 'what can you do'}:
        return 'capabilities'
    return None


def llm_route_fallback(st: ConversationState, text: str) -> Optional[str]:
    llm = llm_extract_cached(st, text)
    if not isinstance(llm, dict) or not llm:
        return None

    inferred = map_llm_intent(llm.get('intent'))
    if inferred == 'book_ride':
        st.active_flow = 'book_ride'
        st.awaiting_field = None
        update_booking_from_text(st, text)
        return continue_booking_flow(st, text)

    if inferred == 'create_ride':
        low = normalize_text(text)
        if any(k in low for k in ['recreate', 'repeat', 'clone', 'repost']) and any(k in low for k in ['ride', 'trip']):
            return start_recreate_ride_flow(st, text)
        st.active_flow = 'create_ride'
        st.awaiting_field = None
        update_create_from_text(st, text)
        return continue_create_flow(st, text) or "Okay. Let's create a ride. Which route are you driving?"

    if inferred == 'recreate_ride':
        return start_recreate_ride_flow(st, text)

    if inferred == 'message':
        st.active_flow = 'message'
        st.awaiting_field = None
        update_message_from_text(st, text)
        return continue_message_flow(st, text) or "Okay. Let's send a message."

    if inferred == 'negotiate':
        st.active_flow = 'negotiate'
        st.awaiting_field = None
        st.negotiate = NegotiateDraft(trip_id=st.last_trip_id, booking_id=st.last_booking_id)
        return continue_negotiate_flow(st, text)

    if inferred == 'cancel_booking':
        st.active_flow = 'cancel_booking'
        st.cancel_booking.booking_id = extract_booking_id(text) or st.last_booking_id
        if not st.cancel_booking.booking_id:
            st.awaiting_field = 'booking_id'
            return 'Which booking do you want to cancel? Provide booking_id.'
        st.cancel_booking.reason = st.cancel_booking.reason or 'Cancelled by passenger'
        st.active_flow = 'confirm_cancel_booking'
        st.pending_action = {'type': 'cancel_booking'}
        return "\n".join([
            'Please confirm cancellation:',
            f"- booking_id: {st.cancel_booking.booking_id}",
            f"- reason: {st.cancel_booking.reason}",
            "Reply 'yes' to confirm or 'no' to cancel.",
        ])

    if inferred == 'list_vehicles':
        if st.active_flow == 'create_ride' or st.awaiting_field == 'vehicle_id':
            return list_user_vehicles_state(st)
        return list_user_vehicles(st.ctx)

    if inferred == 'list_my_rides':
        return list_user_created_trips_state(st)

    if inferred == 'delete_trip':
        return start_manage_trip_flow(st, text, mode='delete')

    if inferred == 'cancel_trip':
        return start_manage_trip_flow(st, text, mode='cancel')

    if inferred == 'list_bookings':
        return list_user_booked_rides_state(st, limit=10)

    if inferred == 'profile_view':
        status, out = api.get_my_profile(st.ctx)
        if status <= 0:
            return 'API server not reachable.'
        if not isinstance(out, dict):
            return f'{status}: {out}'
        safe = {
            'id': out.get('id'),
            'name': out.get('name'),
            'username': out.get('username'),
            'email': out.get('email'),
            'phone_no': out.get('phone_no') or out.get('phone_number'),
            'address': out.get('address'),
            'gender': out.get('gender'),
            'status': out.get('status'),
        }
        return f'{status}: {safe}'

    if inferred == 'profile_update':
        st.active_flow = 'confirm_profile_update'
        st.pending_action = {'type': 'profile_update'}
        d = st.profile
        if isinstance(llm, dict):
            if llm.get('name') is not None:
                d.name = str(llm.get('name')).strip() or d.name
            if llm.get('address') is not None:
                d.address = str(llm.get('address')).strip() or d.address
            if llm.get('gender') is not None:
                g = str(llm.get('gender')).strip().lower()
                if g in {'male', 'female'}:
                    d.gender = g
            if llm.get('bankname') is not None:
                d.bankname = str(llm.get('bankname')).strip() or d.bankname
            if llm.get('accountno') is not None:
                d.accountno = str(llm.get('accountno')).strip() or d.accountno
            if llm.get('iban') is not None:
                d.iban = str(llm.get('iban')).strip() or d.iban
        if not any([d.name, d.address, d.gender, d.bankname, d.accountno, d.iban]):
            return "Tell me what to update (e.g., 'update profile name: Ali' or 'change address: ...')."
        lines: list[str] = ['Please confirm profile update:']
        if d.name:
            lines.append(f"- name: {d.name}")
        if d.address:
            lines.append(f"- address: {d.address}")
        if d.gender:
            lines.append(f"- gender: {d.gender}")
        if d.bankname:
            lines.append(f"- bankname: {d.bankname}")
        if d.accountno:
            lines.append(f"- accountno: {d.accountno}")
        if d.iban:
            lines.append(f"- iban: {d.iban}")
        lines.append("Reply 'yes' to confirm or 'no' to cancel.")
        return "\n".join(lines)

    if inferred == 'help':
        return help_text()

    if inferred == 'capabilities':
        return capabilities_text()

    if inferred == 'greet':
        name = st.user_name or 'there'
        return f"Hi {name}. What would you like to do today—book a ride or create a ride?"

    return None


def continue_booking_flow(st: ConversationState, text: str) -> Optional[str]:
    if st.active_flow != 'book_ride':
        return None

    if st.awaiting_field == 'from_stop' and text:
        st.booking.from_stop_raw = text.strip()
        st.awaiting_field = None
    elif st.awaiting_field == 'to_stop' and text:
        st.booking.to_stop_raw = text.strip()
        st.awaiting_field = None
    elif st.awaiting_field == 'date':
        st.booking.trip_date = parse_date(text) or st.booking.trip_date
        st.awaiting_field = None
    elif st.awaiting_field == 'time':
        st.booking.departure_time = parse_time_str(text) or st.booking.departure_time
        st.awaiting_field = None
    elif st.awaiting_field == 'seats':
        st.booking.number_of_seats = to_int(text) or extract_seats(text) or st.booking.number_of_seats
        st.awaiting_field = None
    elif st.awaiting_field == 'fare':
        st.booking.proposed_fare = to_int(text) or extract_fare(text) or st.booking.proposed_fare
        st.awaiting_field = None
    else:
        update_booking_from_text(st, text)

    if not st.booking.from_stop_raw:
        st.awaiting_field = 'from_stop'
        return 'Where are you starting from (pickup stop)?'
    if not st.booking.to_stop_raw:
        st.awaiting_field = 'to_stop'
        return 'Where do you want to go (drop-off stop)?'
    if not st.booking.trip_date:
        st.awaiting_field = 'date'
        return 'Which date? (today / tomorrow / YYYY-MM-DD)'
    if not st.booking.departure_time:
        st.awaiting_field = 'time'
        return 'What time? (e.g., 18:30 or 6pm)'
    if not st.booking.number_of_seats:
        st.awaiting_field = 'seats'
        return 'How many seats do you need?'

    candidates = find_trip_candidates(st.booking)
    if not candidates:
        st.awaiting_field = None
        return 'I could not find a matching scheduled trip. Try a different time/date or specify a trip_id.'

    if len(candidates) > 1:
        st.booking.candidates = candidates
        st.active_flow = 'choose_trip'
        st.awaiting_field = None
        return render_trip_choice(candidates)

    chosen = candidates[0]
    st.booking.candidates = candidates
    st.booking.selected_trip_id = chosen.get('trip_id')
    st.booking.selected_from_stop_order = chosen.get('from_stop_order')
    st.booking.selected_to_stop_order = chosen.get('to_stop_order')
    st.booking.selected_from_stop_name = chosen.get('from_stop_name')
    st.booking.selected_to_stop_name = chosen.get('to_stop_name')
    st.booking.selected_base_fare = chosen.get('base_fare')
    st.booking.selected_trip_date = chosen.get('trip_date')
    st.booking.selected_departure_time = chosen.get('departure_time')
    st.booking.selected_route_name = chosen.get('route_name')
    st.booking.selected_driver_id = chosen.get('driver_id')
    st.booking.selected_driver_name = chosen.get('driver_name')
    st.active_flow = 'confirm_booking'
    st.pending_action = {'type': 'book_ride'}
    st.awaiting_field = None
    return render_booking_summary(st)


def continue_create_flow(st: ConversationState, text: str) -> Optional[str]:
    if st.active_flow != 'create_ride':
        return None

    d = st.create_ride

    if st.awaiting_field == 'route_id':
        low = normalize_text(text)
        if any(p in low for p in ['vehicle', 'vehicles', 'my vehicle', 'my vehicles', 'show vehicle', 'show vehicles', 'list vehicle', 'list vehicles', 'which vehicle', 'what vehicle']):
            return list_user_vehicles_state(st)
        if (
            any(k in low for k in ['db', 'database', 'take it from', 'fetch it', 'from the api', 'from api'])
            and any(k in low for k in ['last', 'recent', 'previous', 'completed'])
            and any(k in low for k in ['ride', 'trip'])
        ):
            return start_recreate_ride_flow(st, text)
    if st.awaiting_field == 'route_id' and text:
        msg = resolve_route_from_text(st, text)
        if msg:
            return msg
        if st.active_flow == 'choose_route':
            return None
        if not looks_like_route_id(d.route_id):
            d.route_name = (text or '').strip() or d.route_name
            d.route_id = None
            st.awaiting_field = 'route_id'
            return 'Please provide a valid route_id (e.g., R001), or describe the route as "FROM ... to ...".'
        st.awaiting_field = None
    elif st.awaiting_field == 'vehicle_id':
        update_create_from_text(st, text)
        if d.vehicle_id:
            st.awaiting_field = None
        else:
            low = normalize_text(text)
            if any(p in low for p in ['dont remember', "don't remember", 'do not remember', 'what vehicle', 'my vehicle', 'which vehicle', 'which i have', 'what i have', 'list vehicle', 'show vehicle', 'list vehicles', 'show vehicles']):
                return list_user_vehicles_state(st)
            picked = to_int(text)
            if picked is None:
                m = re.search(r"\b(?:vehicle[_\s-]*id|vehicle|use)\b\s*[:=]?\s*(\d+)\b", text or '', flags=re.IGNORECASE)
                if m:
                    picked = to_int(m.group(1))
            if picked is None:
                s, out = api.api_list_my_vehicles(st.ctx)
                vehicles = (out.get('vehicles') if isinstance(out, dict) else None) or []
                if s > 0 and isinstance(vehicles, list):
                    matches = []
                    raw = (text or '').strip()
                    raw_norm = normalize_text(raw)
                    color_req = None
                    mcol = re.search(r"\b(black|white|blue|red|silver|grey|gray|green|yellow)\b", raw_norm)
                    if mcol:
                        color_req = mcol.group(1)
                    seat_req = None
                    mseat = re.search(r"\b(\d{1,2})\s*(?:seat|seats|seater)\b", raw_norm)
                    if mseat:
                        try:
                            seat_req = int(mseat.group(1))
                        except Exception:
                            seat_req = None
                    wants_tw = any(k in raw_norm for k in ['bike', 'motorbike', 'motorcycle', 'two wheeler', '2 wheeler', 'tw'])
                    wants_fw = any(k in raw_norm for k in ['car', 'four wheeler', '4 wheeler', 'fw'])
                    for v in vehicles:
                        if not isinstance(v, dict):
                            continue
                        plate = str(v.get('plate_number') or '').strip()
                        plate_norm = normalize_text(plate)
                        if plate and (plate in raw or (plate_norm and plate_norm in raw_norm)):
                            matches.append(v)
                            continue
                        if color_req:
                            col = normalize_text(str(v.get('color') or ''))
                            if col and color_req in col:
                                matches.append(v)
                                continue
                        if seat_req is not None:
                            try:
                                vseats = int(v.get('seats') or 0)
                            except Exception:
                                vseats = 0
                            if vseats == seat_req:
                                matches.append(v)
                                continue
                        if wants_tw or wants_fw:
                            vt = normalize_text(str(v.get('vehicle_type') or ''))
                            if wants_tw and vt == 'tw':
                                matches.append(v)
                                continue
                            if wants_fw and vt == 'fw':
                                matches.append(v)
                                continue
                    if len(matches) == 1:
                        picked = to_int(matches[0].get('id'))
                    elif len(matches) > 1:
                        lines = ['I found multiple matching vehicles. Please reply with the vehicle_id you want:']
                        for mv in matches[:8]:
                            if not isinstance(mv, dict):
                                continue
                            lines.append(
                                f"- vehicle_id={mv.get('id')} | {mv.get('plate_number', '')} | {mv.get('company_name', '')} {mv.get('model_number', '')} | color={mv.get('color', '')} | seats={mv.get('seats', '')}"
                            )
                        return "\n".join(lines)
            d.vehicle_id = picked or d.vehicle_id
            st.awaiting_field = None
    elif st.awaiting_field == 'trip_date':
        dt = parse_relative_datetime(text)
        if dt:
            d.trip_date, d.departure_time = dt
        else:
            d.trip_date = parse_date(text) or d.trip_date
            if not d.departure_time:
                d.departure_time = parse_time_str(text) or d.departure_time
        st.awaiting_field = None
    elif st.awaiting_field == 'departure_time':
        dt = parse_relative_datetime(text)
        if dt:
            d.trip_date, d.departure_time = dt
        else:
            d.departure_time = parse_time_str(text) or d.departure_time
        st.awaiting_field = None
    elif st.awaiting_field == 'total_seats':
        d.total_seats = to_int(text) or extract_seats(text) or d.total_seats
        st.awaiting_field = None
    elif st.awaiting_field == 'custom_price':
        low = normalize_text(text)
        if any(p in low for p in ['use estimated', 'use the estimated', 'estimated fare', 'same as estimated', 'as estimated', 'use estimate', 'use estimation']):
            if getattr(d, 'estimated_price_per_seat', None):
                try:
                    d.custom_price = int(getattr(d, 'estimated_price_per_seat'))
                except Exception:
                    d.custom_price = d.custom_price
            else:
                d.custom_price = d.custom_price
        else:
            d.custom_price = to_int(text) or extract_fare(text) or d.custom_price
        st.awaiting_field = None
    else:
        update_create_from_text(st, text)

    if not d.route_id and (d.route_name or '').strip() and st.awaiting_field != 'route_id':
        msg = resolve_route_from_text(st, d.route_name or '')
        if msg:
            return msg
        if st.active_flow == 'choose_route':
            return None

    if not d.route_id:
        st.awaiting_field = 'route_id'
        return "Please tell me the route using stop names (e.g., 'Zoo Road to Quaid Park'). If you know the route_id you can also type it (e.g., R001)."
    if not d.vehicle_id:
        st.awaiting_field = 'vehicle_id'
        return 'What is the vehicle_id you want to use? (If you do not know, reply: show my vehicles)'
    if not d.trip_date:
        st.awaiting_field = 'trip_date'
        return 'Which date? (today / tomorrow / YYYY-MM-DD)'
    if not d.departure_time:
        st.awaiting_field = 'departure_time'
        return 'What departure time? (e.g., 18:30 or 6pm)'
    if not d.total_seats:
        st.awaiting_field = 'total_seats'
        return 'How many total seats are you offering?'
    if not d.custom_price:
        st.awaiting_field = 'custom_price'
        return 'What is the base fare per seat (custom_price)? (Example: 80)'

    st.active_flow = 'confirm_create'
    st.pending_action = {'type': 'create_ride'}
    st.awaiting_field = None
    return render_create_summary(st)


def continue_message_flow(st: ConversationState, text: str) -> Optional[str]:
    if st.active_flow != 'message':
        return None

    d = st.message
    if st.awaiting_field == 'trip_id':
        d.trip_id = (text or '').strip() or d.trip_id
        st.awaiting_field = None
    elif st.awaiting_field == 'recipient_id':
        d.recipient_id = to_int(text) or d.recipient_id
        st.awaiting_field = None
    elif st.awaiting_field == 'message_text':
        d.message_text = (text or '').strip() or d.message_text
        st.awaiting_field = None
    else:
        update_message_from_text(st, text)

    d.trip_id = d.trip_id or st.last_trip_id
    if not d.trip_id:
        st.awaiting_field = 'trip_id'
        return "Which trip? Please provide trip_id. (If you don't know it, reply: list my rides or list my bookings)"

    if d.recipient_id is None:
        driver_id = api.api_trip_driver_id(str(d.trip_id))
        if driver_id and int(driver_id) != int(st.ctx.user_id):
            d.recipient_id = int(driver_id)
            d.sender_role = d.sender_role or 'passenger'
        else:
            st.awaiting_field = 'recipient_id'
            return 'Who should receive the message? Provide recipient_id.'

    if not d.message_text:
        st.awaiting_field = 'message_text'
        return 'What message should I send?'

    st.active_flow = 'confirm_message'
    st.pending_action = {'type': 'message'}
    st.awaiting_field = None
    return "\n".join([
        'Please confirm sending this message:',
        f"- trip_id: {d.trip_id}",
        f"- recipient_id: {d.recipient_id}",
        f"- sender_role: {d.sender_role or 'passenger'}",
        f"- text: {d.message_text}",
        "Reply 'yes' to confirm or 'no' to cancel.",
    ])


def continue_negotiate_flow(st: ConversationState, text: str) -> Optional[str]:
    if st.active_flow != 'negotiate':
        return None

    d = st.negotiate
    d.trip_id = d.trip_id or extract_trip_id(text) or st.last_trip_id
    d.booking_id = d.booking_id or extract_booking_id(text) or st.last_booking_id
    d.action = d.action or parse_action(text)
    if d.counter_fare is None:
        m = re.search(r"\bcounter(?:[_\s-]*fare)?\b\s*[:=]?\s*(\d{2,6})\b", text or '', flags=re.IGNORECASE)
        if m:
            d.counter_fare = to_int(m.group(1))
        if d.counter_fare is None:
            d.counter_fare = extract_fare(text)
    if d.note is None:
        m = re.search(r"\bnote\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.note = m.group(1).strip()

    if not d.trip_id:
        st.awaiting_field = 'trip_id'
        return 'Which trip? Provide trip_id.'
    if not d.booking_id:
        st.awaiting_field = 'booking_id'
        return 'Which booking? Provide booking_id.'
    if not d.action:
        st.awaiting_field = 'action'
        return 'What do you want to do? (accept / reject / counter / withdraw)'
    if d.action == 'counter' and not d.counter_fare:
        st.awaiting_field = 'counter_fare'
        return 'What counter fare per seat should I propose?'

    st.active_flow = 'confirm_negotiate'
    st.pending_action = {'type': 'negotiate'}
    st.awaiting_field = None
    return "\n".join([
        'Please confirm negotiation action:',
        f"- trip_id: {d.trip_id}",
        f"- booking_id: {d.booking_id}",
        f"- action: {d.action}",
        f"- counter_fare: {d.counter_fare if d.action == 'counter' else None}",
        "Reply 'yes' to confirm or 'no' to cancel.",
    ])


def parse_yes_no(text: str) -> Optional[bool]:
    low = normalize_text(text)
    if low in {'yes', 'y', 'confirm', 'ok', 'okay'}:
        return True
    if low in {'no', 'n'}:
        return False
    return None


def parse_action(text: str) -> Optional[str]:
    low = normalize_text(text)
    if 'accept' in low:
        return 'accept'
    if 'reject' in low or 'decline' in low:
        return 'reject'
    if 'counter' in low:
        return 'counter'
    if 'withdraw' in low or 'cancel' in low:
        return 'withdraw'
    if low in {'accept', 'reject', 'counter', 'withdraw'}:
        return low
    return None


def continue_misc_flows(st: ConversationState, text: str) -> Optional[str]:
    if st.active_flow == 'cancel_booking' and st.awaiting_field == 'booking_id':
        bid = extract_booking_id(text) or to_int(text)
        if not bid:
            return 'Please provide a valid booking_id (number).'
        st.cancel_booking.booking_id = int(bid)
        st.cancel_booking.reason = st.cancel_booking.reason or 'Cancelled by passenger'
        st.awaiting_field = None
        st.active_flow = 'confirm_cancel_booking'
        st.pending_action = {'type': 'cancel_booking'}
        return "\n".join([
            'Please confirm cancellation:',
            f"- booking_id: {st.cancel_booking.booking_id}",
            f"- reason: {st.cancel_booking.reason}",
            "Reply 'yes' to confirm or 'no' to cancel.",
        ])

    if st.active_flow == 'chat_list' and st.awaiting_field == 'trip_id':
        trip_id = extract_trip_id(text) or (text or '').strip()
        if not trip_id:
            return 'Please provide a trip_id.'
        st.awaiting_field = None
        status, out = api.list_chat(st.ctx, str(trip_id), limit=25)
        reset_flow(st)
        return f'{status}: {out}'

    if st.active_flow == 'payment_details' and st.awaiting_field == 'booking_id':
        bid = extract_booking_id(text) or to_int(text)
        if not bid:
            return 'Please provide a valid booking_id (number).'
        st.awaiting_field = None
        status, out = api.get_booking_payment_details_safe(st.ctx, int(bid))
        reset_flow(st)
        return f'{status}: {out}'

    if st.active_flow == 'submit_payment':
        if st.awaiting_field == 'booking_id':
            bid = extract_booking_id(text) or to_int(text)
            if not bid:
                return 'Please provide a valid booking_id (number).'
            st.payment.booking_id = int(bid)
            st.awaiting_field = 'driver_rating'
            return "Please provide driver rating (1-5). Example: '5' or '5 stars'."

        if st.awaiting_field == 'driver_rating':
            rating = parse_rating_value(text)
            if rating is None:
                return 'Please provide a rating between 1 and 5.'
            st.payment.driver_rating = float(rating)
            st.payment.driver_feedback = st.payment.driver_feedback or ''
            st.awaiting_field = None
            st.active_flow = 'confirm_submit_payment'
            st.pending_action = {'type': 'submit_payment'}
            return "\n".join([
                'Please confirm payment submission (CASH):',
                f"- booking_id: {st.payment.booking_id}",
                f"- driver_rating: {st.payment.driver_rating}",
                "Reply 'yes' to confirm or 'no' to cancel.",
            ])

    if st.active_flow == 'confirm_payment':
        if st.awaiting_field == 'booking_id':
            bid = extract_booking_id(text) or to_int(text)
            if not bid:
                return 'Please provide a valid booking_id (number).'
            st.payment.booking_id = int(bid)
            st.awaiting_field = 'passenger_rating'
            return "Please provide passenger rating (1-5). Example: '5' or '5 stars'."

        if st.awaiting_field == 'passenger_rating':
            rating = parse_rating_value(text)
            if rating is None:
                return 'Please provide a rating between 1 and 5.'
            st.payment.passenger_rating = float(rating)
            st.payment.passenger_feedback = st.payment.passenger_feedback or ''
            st.awaiting_field = None
            st.active_flow = 'confirm_confirm_payment'
            st.pending_action = {'type': 'confirm_payment'}
            return "\n".join([
                'Please confirm payment received:',
                f"- booking_id: {st.payment.booking_id}",
                f"- passenger_rating: {st.payment.passenger_rating}",
                "Reply 'yes' to confirm or 'no' to cancel.",
            ])

    return None
