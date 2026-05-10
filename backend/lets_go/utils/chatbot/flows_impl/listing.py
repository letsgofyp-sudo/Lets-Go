from __future__ import annotations

import os
from typing import Optional

from ..integrations import api
from ..core import BotContext, ConversationState

from .utils import format_api_result


def list_user_vehicles(ctx: BotContext, *, limit: int = 20) -> str:
    status, out = api.api_list_my_vehicles(ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    if status not in {200, 201, 202}:
        return format_api_result(status, out)
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
            f"- vehicle_id={v.get('id')} | {v.get('plate_number', '')} | {v.get('company_name', '')} {v.get('model_number', '')} | type={v.get('vehicle_type', '')} | seats={seats_txt} | status: {v.get('status', '')}"
        )
    lines.append('Reply with the vehicle_id you want to use.')
    return "\n".join(lines)


def list_user_vehicles_state(st: ConversationState, *, limit: int = 20) -> str:
    status, out = api.api_list_my_vehicles(st.ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    if status not in {200, 201, 202}:
        return format_api_result(status, out)
    vehicles = (out.get('vehicles') if isinstance(out, dict) else None) or []
    if not isinstance(vehicles, list) or not vehicles:
        return 'I could not find any vehicles in your account.'
    st.create_ride.vehicle_candidates = vehicles
    if st.active_flow == 'create_ride' or st.awaiting_field == 'vehicle_id':
        st.active_flow = 'choose_vehicle'
        st.awaiting_field = None
        from .rendering import render_vehicle_choice

        return render_vehicle_choice(vehicles[:limit])
    return list_user_vehicles(st.ctx, limit=limit)


def list_user_created_trips(ctx: BotContext, *, limit: int = 20) -> str:
    status, out = api.api_list_my_rides(ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    if status not in {200, 201, 202}:
        return format_api_result(status, out)
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
                f"- trip_id={trip_id} | {_origin(r)} -> {_dest(r)} | {r.get('trip_date', '')} {r.get('departure_time', '')} | status: {r.get('status', '')}"
            )
        return "\n".join(lines)

    return _format(rides)


def list_user_created_trips_state(st: ConversationState, *, limit: int = 20, vehicle_id: Optional[int] = None) -> str:
    status, out = api.api_list_my_rides(st.ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    if status not in {200, 201, 202}:
        return format_api_result(status, out)
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

    def _stops_from_trip_detail(trip_id: str) -> tuple[str | None, str | None]:
        try:
            if str(os.getenv('LETS_GO_BOT_STATELESS', '')).strip().lower() in {'1', 'true', 'yes', 'on'}:
                return None, None
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
            f"- trip_id={trip_id} | {_origin(r)} -> {_dest(r)} | {r.get('trip_date', '')} {r.get('departure_time', '')}{vtxt} | status: {r.get('status', '')}"
        )
    return "\n".join(lines)


def list_user_booked_rides(ctx: BotContext, *, limit: int = 20) -> str:
    status, out = api.list_my_bookings(ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    if status not in {200, 201, 202}:
        return format_api_result(status, out)
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
        st_txt = b.get('booking_status') or b.get('status') or ''
        lines.append(
            f"- booking_id={booking_id} | trip_id={trip_id} | {_origin(b)} -> {_dest(b)} | {b.get('trip_date', '')} {b.get('departure_time', '')} | status: {st_txt}"
        )
    return "\n".join(lines)


def list_user_booked_rides_state(st: ConversationState, *, limit: int = 20) -> str:
    status, out = api.list_my_bookings(st.ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    if status not in {200, 201, 202}:
        return format_api_result(status, out)
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
            f"- booking_id={booking_id} | trip_id={trip_id} | {_origin(b)} -> {_dest(b)} | {b.get('trip_date', '')} {b.get('departure_time', '')} | status: {st_txt}"
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
