from __future__ import annotations

import re
from datetime import datetime
from typing import Any, Optional

from ..integrations import api
from ..common.helpers import (
    capabilities_text,
    contains_abuse,
    extract_booking_id,
    extract_coord_pairs,
    extract_fare,
    extract_from_to,
    extract_recipient_id,
    extract_seats,
    extract_trip_id,
    fuzzy_stop_name,
    help_text,
    looks_like_route_id,
    nearest_stop_name,
    normalize_text,
    parse_date,
    parse_relative_datetime,
    parse_time_str,
    to_int,
)
from ..llm import llm_chat_reply, llm_extract_cached
from ..core import ConversationState, NegotiateDraft

from .rendering import render_route_choice
from .utils import format_api_result


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
        from .continuations import continue_booking_flow

        return continue_booking_flow(st, text)

    if inferred == 'create_ride':
        low = normalize_text(text)
        if any(k in low for k in ['recreate', 'repeat', 'clone', 'repost']) and any(k in low for k in ['ride', 'trip']):
            return "I can guide you through creating a ride in the app.\nOpen the app and go to: Create Ride → select route/stops → set date/time → seats → fare → confirm."
        return "I can guide you through creating a ride in the app.\nOpen the app and go to: Create Ride → select route/stops → set date/time → seats → fare → confirm."

    if inferred == 'recreate_ride':
        return "I can guide you through recreating a ride in the app.\nOpen the app → My Rides → choose a past ride → Recreate/Repeat → review details → confirm."

    if inferred == 'message':
        st.active_flow = 'message'
        st.awaiting_field = None
        update_message_from_text(st, text)
        from .continuations import continue_message_flow

        return continue_message_flow(st, text) or "Okay. Let's send a message."

    if inferred == 'negotiate':
        st.active_flow = 'negotiate'
        st.awaiting_field = None
        st.negotiate = NegotiateDraft(trip_id=st.last_trip_id, booking_id=st.last_booking_id)
        from .continuations import continue_negotiate_flow

        return continue_negotiate_flow(st, text)

    if inferred == 'cancel_booking':
        st.active_flow = 'cancel_booking'
        st.cancel_booking.booking_id = extract_booking_id(text) or st.last_booking_id
        if not st.cancel_booking.booking_id:
            st.awaiting_field = 'booking_id'
            return 'Which booking do you want to cancel? Please provide booking_id.'
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
        from .listing import list_user_vehicles, list_user_vehicles_state

        if st.active_flow == 'create_ride' or st.awaiting_field == 'vehicle_id':
            return list_user_vehicles_state(st)
        return list_user_vehicles(st.ctx)

    if inferred == 'list_my_rides':
        from .listing import list_user_created_trips_state

        return list_user_created_trips_state(st)

    if inferred == 'delete_trip':
        from .manage import start_manage_trip_flow

        return start_manage_trip_flow(st, text, mode='delete')

    if inferred == 'cancel_trip':
        from .manage import start_manage_trip_flow

        return start_manage_trip_flow(st, text, mode='cancel')

    if inferred == 'list_bookings':
        from .listing import list_user_booked_rides_state

        return list_user_booked_rides_state(st, limit=10)

    if inferred == 'profile_view':
        status, out = api.get_my_profile(st.ctx)
        if status <= 0:
            return 'API server not reachable.'
        if not isinstance(out, dict):
            return format_api_result(status, out)
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
        return format_api_result(status, safe)

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
        return f"Hi {name}. How can I help you today? You can ask to find available rides, get fare/route info, or view help topics."

    return None
