from __future__ import annotations

import re
from typing import Optional

from ..integrations import api
from ..common.helpers import (
    extract_booking_id,
    extract_fare,
    extract_seats,
    extract_trip_id,
    looks_like_route_id,
    normalize_text,
    parse_date,
    parse_rating_value,
    parse_relative_datetime,
    parse_time_str,
    to_int,
)
from ..core import ConversationState, reset_flow

from .listing import list_user_vehicles_state
from .manage import start_recreate_ride_flow
from .rendering import render_booking_summary, render_create_summary, render_trip_choice
from .routing import resolve_route_from_text
from .updates import update_booking_from_text, update_create_from_text, update_message_from_text
from .utils import format_api_result


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

    from .trip_candidates import find_trip_candidates_safe

    candidates, cand_err = find_trip_candidates_safe(st.booking)
    if cand_err:
        st.awaiting_field = None
        return cand_err
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
        return 'What base fare per seat would you like to set? (Example: 80)'

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
        return "Which trip is this for? Please provide trip_id. (If you don't know it, reply: list my rides or list my bookings)"

    if d.recipient_id is None:
        driver_id = api.api_trip_driver_id(str(d.trip_id))
        if driver_id and int(driver_id) != int(st.ctx.user_id):
            d.recipient_id = int(driver_id)
            d.sender_role = d.sender_role or 'passenger'
        else:
            st.awaiting_field = 'recipient_id'
            return 'Who should receive the message? Please provide recipient_id.'

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
        return 'Which trip is this for? Please provide trip_id.'
    if not d.booking_id:
        st.awaiting_field = 'booking_id'
        return 'Which booking is this for? Please provide booking_id.'
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
    if low in {'yes', 'y', 'confirm'}:
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
        _, err = api.require_system_access(st.ctx)
        if err:
            reset_flow(st)
            return err
        trip_id = extract_trip_id(text) or (st.last_trip_id or '')
        if not trip_id:
            return 'Which trip chat do you want to view? Please provide trip_id.'
        st.awaiting_field = None
        status, out = api.list_chat(st.ctx, str(trip_id), limit=25)
        reset_flow(st)
        return format_api_result(status, out)

    if st.active_flow == 'payment_details' and st.awaiting_field == 'booking_id':
        _, err = api.require_system_access(st.ctx)
        if err:
            reset_flow(st)
            return err
        bid = extract_booking_id(text) or to_int(text)
        if not bid:
            return 'Which booking payment details do you want? Please provide booking_id.'
        st.awaiting_field = None
        status, out = api.get_booking_payment_details_safe(st.ctx, int(bid))
        reset_flow(st)
        return format_api_result(status, out)

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
