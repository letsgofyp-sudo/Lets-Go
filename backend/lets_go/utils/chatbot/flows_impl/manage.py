from __future__ import annotations

import re
from typing import Any, Optional

from ..integrations import api
from ..common.helpers import extract_trip_id, normalize_text, parse_relative_datetime, to_int
from ..core import ConversationState

from .utils import format_api_result


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
    if status not in {200, 201, 202}:
        return format_api_result(status, out)
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
        details = (
            f" | {ride.get('from_location', '')} -> {ride.get('to_location', '')}"
            f" | {ride.get('trip_date', '')} {ride.get('departure_time', '')}"
        )

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
    if status not in {200, 201, 202}:
        return format_api_result(status, out)
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
    if ds not in {200, 201, 202}:
        return format_api_result(ds, detail)
    if not isinstance(detail, dict) or not detail.get('success'):
        if isinstance(detail, dict) and (detail.get('error') or detail.get('message') or detail.get('detail')):
            return format_api_result(ds, detail)
        return 'Failed to fetch ride details. Please try again.'

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

    from .continuations import continue_create_flow

    nxt = continue_create_flow(st, text)
    if nxt:
        return header + "\n\n" + nxt
    return header + "\n\n" + "What new date/time should I set? (e.g., 'after 1 hour' or 'tomorrow 12:50am')"
