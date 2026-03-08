import os
import re
import logging

from typing import Any, Optional

from . import api
from .flows import (
    continue_booking_flow,
    continue_create_flow,
    continue_message_flow,
    continue_misc_flows,
    continue_negotiate_flow,
    llm_route_fallback,
    render_booking_summary,
    render_create_summary,
    list_user_created_trips,
    list_user_rides_and_bookings,
    list_user_rides_and_bookings_state,
    list_user_vehicles,
    parse_action,
    parse_yes_no,
    start_recreate_ride_flow,
    start_manage_trip_flow,
    update_booking_from_text,
    update_create_from_text,
    update_message_from_text,
)
from .helpers import (
    blocked_system_request,
    build_create_trip_fare_payload,
    capabilities_text,
    extract_trip_id,
    help_text,
    normalize_text,
    parse_rating_value,
    smalltalk_reply,
)
from .helpers import looks_like_route_id
from .llm import llm_api_key, llm_base_url, llm_brain_mode, llm_extract_cached, llm_provider, llm_rewrite_reply, llm_chat_reply
from .llm import llm_plan
from .state import BotContext, PaymentDraft, get_state, reset_flow


logger = logging.getLogger(__name__)


def _v_list_limit(_st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    lim = _safe_int(a.get('limit') or 20) or 20
    logger.debug("Limit set to %s", lim)
    return {'limit': max(1, min(200, lim))}, None, None


def _v_list_my_rides(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    lim = _safe_int(a.get('limit') or 20) or 20
    vid = _safe_int(a.get('vehicle_id')) if a.get('vehicle_id') is not None else None
    out: dict[str, Any] = {'limit': max(1, min(200, lim))}
    if vid:
        out['vehicle_id'] = int(vid)
    return out, None, None


def _v_routes_search(_st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    frm = _safe_str(a.get('from'))
    to = _safe_str(a.get('to'))
    if not frm or not to:
        return {}, "Which route do you want? Tell me 'FROM ... to ...'.", None
    return {'from': frm, 'to': to}, None, None


def _v_trip_id(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    trip_id = _safe_str(a.get('trip_id') or st.last_trip_id)
    if not trip_id:
        return {}, "Which trip_id? You can say: 'list my rides' first.", None
    return {'trip_id': trip_id}, None, None


def _v_chat_list(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    trip_id = _safe_str(a.get('trip_id') or st.last_trip_id)
    if not trip_id:
        return {}, "Which trip_id? You can say: 'list my rides' first.", None
    lim = _safe_int(a.get('limit') or 25) or 25
    return {'trip_id': trip_id, 'limit': max(1, min(200, lim))}, None, None


def _v_send_message(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    trip_id = _safe_str(a.get('trip_id') or st.last_trip_id)
    rid = _safe_int(a.get('recipient_id') or 0)
    msg = _safe_str(a.get('message_text') or '')
    role = _safe_str(a.get('sender_role') or 'passenger') or 'passenger'
    if not trip_id:
        return {}, "Which trip_id is this message for?", None
    if rid <= 0:
        return {}, 'Who should I message? Provide recipient_id.', None
    if not msg:
        return {}, 'What message should I send?', None
    return {'trip_id': trip_id, 'recipient_id': int(rid), 'sender_role': role, 'message_text': msg}, None, None


def _v_create_trip(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    rid = _safe_str(a.get('route_id') or st.create_ride.route_id)
    vid = _safe_int(a.get('vehicle_id') or st.create_ride.vehicle_id)
    d = _safe_str(a.get('trip_date') or '')
    tm = _safe_str(a.get('departure_time') or '')
    seats = _safe_int(a.get('total_seats') or 0)
    price = _safe_int(a.get('custom_price') or 0)
    gp = _safe_str(a.get('gender_preference') or st.create_ride.gender_preference or 'Any') or 'Any'
    notes = _safe_str(a.get('notes') or st.create_ride.notes or '')
    is_neg = a.get('is_negotiable') if isinstance(a.get('is_negotiable'), bool) else st.create_ride.is_negotiable

    if not rid:
        return {}, "Which route do you want to use? (Tell me 'FROM ... to ...' or provide route_id.)", None
    if not looks_like_route_id(rid):
        return {}, "I need a valid route_id (like R001). Tell me: 'FROM ... to ...' and I'll find the route, or share the route_id.", None
    if not vid:
        return {}, "Which vehicle_id should I use? Say 'show my vehicles' if you're not sure.", None
    if not d or (not re.fullmatch(r"\d{4}-\d{2}-\d{2}", d)):
        return {}, 'Which trip date? (YYYY-MM-DD / today / tomorrow)', None
    if not tm or (not re.fullmatch(r"\d{2}:\d{2}", tm)):
        return {}, 'What departure time? (HH:MM e.g. 18:30)', None
    if not seats:
        return {}, 'How many total seats are you offering?', None
    if price <= 0:
        return {}, 'What is the fare per seat (custom_price)?', None

    out = {
        'route_id': rid,
        'vehicle_id': int(vid),
        'trip_date': d,
        'departure_time': tm,
        'total_seats': int(seats),
        'custom_price': int(price),
        'gender_preference': gp,
    }
    if notes:
        out['notes'] = notes
    if isinstance(is_neg, bool):
        out['is_negotiable'] = bool(is_neg)
    return out, None, None


def _v_delete_trip(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    tid = _safe_str(a.get('trip_id') or st.last_trip_id)
    if not tid:
        return {}, "Which trip_id? You can say: 'list my rides' first.", None
    return {'trip_id': tid}, None, None


def _v_cancel_trip(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    tid = _safe_str(a.get('trip_id') or st.last_trip_id)
    if not tid:
        return {}, "Which trip_id? You can say: 'list my rides' first.", None
    reason = _safe_str(a.get('reason') or 'Cancelled by driver') or 'Cancelled by driver'
    return {'trip_id': tid, 'reason': reason}, None, None


def _v_cancel_booking(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    bid = _safe_int(a.get('booking_id') or st.last_booking_id)
    if not bid:
        return {}, "Which booking_id? You can say: 'list my bookings' first.", None
    reason = _safe_str(a.get('reason') or 'Cancelled by passenger') or 'Cancelled by passenger'
    return {'booking_id': int(bid), 'reason': reason}, None, None


def _v_profile_update(_st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    fields = ['name', 'address', 'gender', 'bankname', 'accountno', 'iban']
    payload = {k: _safe_str(a.get(k) or '') for k in fields}
    if payload.get('gender'):
        g = payload.get('gender', '').strip().lower()
        if g not in {'male', 'female'}:
            return {}, "Gender must be 'male' or 'female'.", None
        payload['gender'] = g
    payload = {k: v for k, v in payload.items() if v}
    if not payload:
        return {}, 'What would you like to update? (name/address/gender/bankname/accountno/iban)', None
    return payload, None, None


def _v_profile_get(st, _a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    last_user = ''
    try:
        for h in reversed(st.history or []):
            if isinstance(h, dict) and (h.get('role') == 'user'):
                last_user = str(h.get('text') or '')
                break
    except Exception:
        last_user = ''
    low = normalize_text(last_user)
    wants = any(k in low for k in {
        'profile', 'account', 'my details', 'my info', 'my information',
        'my name', 'my email', 'my phone', 'my address', 'my gender', 'gender',
        'bank', 'iban', 'account no', 'account number',
        'cnic', 'license', 'driving license', 'emergency contact',
    })
    if not wants:
        return {}, None, 'Profile lookup is only allowed when you explicitly ask about your profile/account details.'
    return {}, None, None


def _v_update_trip_gender_preference(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    tid = _safe_str(a.get('trip_id') or st.last_trip_id)
    gp = _safe_str(a.get('gender_preference') or '')
    if not tid:
        return {}, 'Which trip_id do you want to update?', None
    if not gp:
        return {}, "What gender preference should I set? (Male/Female/Any)", None
    low = normalize_text(gp)
    if low in {'male', 'm'}:
        gp = 'Male'
    elif low in {'female', 'f'}:
        gp = 'Female'
    elif low in {'any', 'either', 'all'}:
        gp = 'Any'
    if gp not in {'Male', 'Female', 'Any'}:
        return {}, 'gender_preference must be Male, Female, or Any.', None
    return {'trip_id': tid, 'gender_preference': gp}, None, None


def _v_update_trip_vehicle(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    tid = _safe_str(a.get('trip_id') or st.last_trip_id)
    if not tid:
        return {}, "Which trip_id do you want to update? You can say: 'list my rides' first.", None

    vid = _safe_int(a.get('vehicle_id') or 0)
    if not vid:
        return {}, "Which vehicle_id should I set? You can say: 'show my vehicles' first.", None

    return {'trip_id': tid, 'vehicle_id': int(vid)}, None, None


def _v_delete_trip_bulk(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    raw = a.get('trip_ids')
    if not isinstance(raw, list):
        return {}, 'Which trip(s) do you want to delete? You can say: delete trip_id=... or list my rides then say delete both.', None
    tids: list[str] = []
    for x in raw:
        s = _safe_str(x)
        if s:
            tids.append(s)
    # Safety limit
    tids = tids[:10]
    if not tids:
        return {}, 'Which trip(s) do you want to delete? Provide at least one trip_id.', None
    return {'trip_ids': tids}, None, None


def _v_list_change_requests(_st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    et = _safe_str(a.get('entity_type') or 'USER_PROFILE').upper() or 'USER_PROFILE'
    if et not in {'USER_PROFILE', 'VEHICLE'}:
        return {}, "entity_type must be USER_PROFILE or VEHICLE.", None

    st = _safe_str(a.get('status') or '').upper()
    if st and st not in {'PENDING', 'APPROVED', 'REJECTED'}:
        return {}, "status must be PENDING, APPROVED, or REJECTED.", None

    lim = _safe_int(a.get('limit') or 10) or 10
    lim = max(1, min(50, lim))

    out: dict[str, Any] = {'entity_type': et, 'limit': lim}
    if st:
        out['status'] = st
    return out, None, None


def _v_payment_details(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    bid = _safe_int(a.get('booking_id') or st.last_booking_id)
    if not bid:
        return {}, "Which booking_id? You can say: 'list my bookings' first.", None
    return {'booking_id': int(bid)}, None, None


def _v_submit_payment_cash(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    bid = _safe_int(a.get('booking_id') or st.last_booking_id)
    rating = _safe_float(a.get('driver_rating'))
    fb = _safe_str(a.get('driver_feedback') or '')
    if not bid:
        return {}, "Which booking_id is this payment for? (You can say: 'list my bookings')", None
    if rating <= 0:
        return {}, 'What driver rating (1-5) should I submit?', None
    if rating < 1 or rating > 5:
        return {}, 'Please provide a rating between 1 and 5.', None
    out = {'booking_id': int(bid), 'driver_rating': float(rating)}
    if fb:
        out['driver_feedback'] = fb
    return out, None, None


def _v_confirm_payment_received(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    bid = _safe_int(a.get('booking_id') or st.last_booking_id)
    rating = _safe_float(a.get('passenger_rating'))
    fb = _safe_str(a.get('passenger_feedback') or '')
    if not bid:
        return {}, 'Which booking_id is this for?', None
    if rating <= 0:
        return {}, 'What passenger rating (1-5) should I submit?', None
    if rating < 1 or rating > 5:
        return {}, 'Please provide a rating between 1 and 5.', None
    out = {'booking_id': int(bid), 'passenger_rating': float(rating)}
    if fb:
        out['passenger_feedback'] = fb
    return out, None, None


def _v_book_ride(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    trip_id = _safe_str(a.get('trip_id') or st.last_trip_id)
    fso = _safe_int(a.get('from_stop_order') or 0)
    tso = _safe_int(a.get('to_stop_order') or 0)
    seats = _safe_int(a.get('number_of_seats') or a.get('seats') or 0)
    fare = _safe_int(a.get('proposed_fare') or 0)
    if not trip_id:
        return {}, 'Which trip_id do you want to book?', None
    if fso <= 0 or tso <= 0:
        return {}, 'Which from_stop_order and to_stop_order?', None
    if seats <= 0:
        return {}, 'How many seats do you want to book?', None
    if fare <= 0:
        return {}, 'What proposed fare per seat?', None
    return {'trip_id': trip_id, 'from_stop_order': int(fso), 'to_stop_order': int(tso), 'number_of_seats': int(seats), 'proposed_fare': int(fare)}, None, None


def _v_list_pending_requests(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    trip_id = _safe_str(a.get('trip_id') or st.last_trip_id)
    if not trip_id:
        return {}, "Which trip_id? You can say: 'list my rides' first.", None
    return {'trip_id': trip_id}, None, None


def _v_negotiation_history(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    trip_id = _safe_str(a.get('trip_id') or st.last_trip_id)
    bid = _safe_int(a.get('booking_id') or st.last_booking_id)
    if not trip_id:
        return {}, 'Which trip_id is this for?', None
    if not bid:
        return {}, 'Which booking_id is this for?', None
    return {'trip_id': trip_id, 'booking_id': int(bid)}, None, None


def _v_negotiation_respond(st, a: dict) -> tuple[dict, Optional[str], Optional[str]]:
    trip_id = _safe_str(a.get('trip_id') or st.negotiate.trip_id or st.last_trip_id)
    bid = _safe_int(a.get('booking_id') or st.negotiate.booking_id or st.last_booking_id)
    action = _safe_str(a.get('action') or '')
    note = _safe_str(a.get('note') or '')
    counter = _safe_int(a.get('counter_fare') or 0)
    if not trip_id:
        return {}, 'Which trip_id is this negotiation for?', None
    if not bid:
        return {}, 'Which booking_id is this negotiation for?', None
    if not action:
        return {}, 'What action should I take? (accept/reject/counter/withdraw)', None
    if action == 'counter' and counter <= 0:
        return {}, 'What counter fare per seat should I propose?', None
    out = {'trip_id': trip_id, 'booking_id': int(bid), 'action': action, 'counter_fare': (int(counter) if counter > 0 else None), 'note': note}
    return out, None, None


_AGENT_TOOL_SPECS: dict[str, dict[str, Any]] = {
    'list_my_rides': {'args_text': 'args={limit:int,vehicle_id:int}', 'confirm': False, 'notes': 'Lists your created rides/trips. Optionally filter by vehicle_id.', 'validate': _v_list_my_rides},
    'list_my_bookings': {'args_text': 'args={limit:int}', 'confirm': False, 'notes': 'Lists your bookings.', 'validate': _v_list_limit},
    'list_vehicles': {'args_text': 'args={limit:int}', 'confirm': False, 'notes': 'Lists your vehicles and their ids.', 'validate': _v_list_limit},
    'routes_search': {'args_text': 'args={from:str,to:str}', 'confirm': False, 'notes': 'May return multiple routes; you must ask the user to choose if ambiguous.', 'validate': _v_routes_search},
    'trip_detail': {'args_text': 'args={trip_id:str}', 'confirm': False, 'notes': 'Returns ride-booking details; restricted to your rides/bookings.', 'validate': _v_trip_id},
    'book_ride': {'args_text': 'args={trip_id:str,from_stop_order:int,to_stop_order:int,number_of_seats:int,proposed_fare:int}', 'confirm': True, 'notes': 'Creates a booking request for a trip.', 'validate': _v_book_ride},
    'chat_list': {'args_text': 'args={trip_id:str,limit:int}', 'confirm': False, 'notes': 'Lists chat messages for a trip you can access.', 'validate': _v_chat_list},
    'send_message': {'args_text': 'args={trip_id:str,recipient_id:int,sender_role:str,message_text:str}', 'confirm': True, 'notes': 'Sends a chat message. Requires confirmation.', 'validate': _v_send_message},
    'create_trip': {'args_text': 'args={route_id:str,vehicle_id:int,trip_date:str,departure_time:str,total_seats:int,custom_price:int,gender_preference:str}', 'confirm': True, 'notes': 'Creates a new trip/ride. Requires confirmation.', 'validate': _v_create_trip},
    'delete_trip': {'args_text': 'args={trip_id:str}', 'confirm': True, 'notes': 'Deletes a trip you created (if allowed).', 'validate': _v_trip_id},
    'delete_trip_bulk': {'args_text': 'args={trip_ids:list[str]}', 'confirm': True, 'notes': 'Deletes multiple trips you created. Requires confirmation.', 'validate': _v_delete_trip_bulk},
    'cancel_trip': {'args_text': 'args={trip_id:str,reason:str}', 'confirm': True, 'notes': 'Cancels a trip you created.', 'validate': _v_cancel_trip},
    'cancel_booking': {'args_text': 'args={booking_id:int,reason:str}', 'confirm': True, 'notes': 'Cancels your own booking.', 'validate': _v_cancel_booking},
    'update_trip_gender_preference': {'args_text': 'args={trip_id:str,gender_preference:str}', 'confirm': True, 'notes': 'Updates gender_preference for a trip you created (if editable). Requires confirmation.', 'validate': _v_update_trip_gender_preference},
    'update_trip_vehicle': {'args_text': 'args={trip_id:str,vehicle_id:int}', 'confirm': True, 'notes': 'Updates vehicle for a trip you created (if editable). Requires confirmation.', 'validate': _v_update_trip_vehicle},
    'list_change_requests': {'args_text': 'args={entity_type:str,status:str,limit:int}', 'confirm': False, 'notes': 'Lists your profile/vehicle change requests (sanitized).', 'validate': _v_list_change_requests},
    'profile_get': {'args_text': 'args={}', 'confirm': False, 'notes': 'Shows your profile (sanitized).', 'validate': _v_profile_get},
    'profile_update': {'args_text': 'args={name:str,address:str,gender:str,bankname:str,accountno:str,iban:str}', 'confirm': True, 'notes': 'Updates safe profile fields. Requires confirmation.', 'validate': _v_profile_update},
    'payment_details': {'args_text': 'args={booking_id:int}', 'confirm': False, 'notes': 'Shows payment details for a booking.', 'validate': _v_payment_details},
    'submit_payment_cash': {'args_text': 'args={booking_id:int,driver_rating:number,driver_feedback:str}', 'confirm': True, 'notes': 'Passenger submits CASH payment + rating. Requires confirmation.', 'validate': _v_submit_payment_cash},
    'confirm_payment_received': {'args_text': 'args={booking_id:int,passenger_rating:number,passenger_feedback:str}', 'confirm': True, 'notes': 'Driver confirms payment received. Requires confirmation.', 'validate': _v_confirm_payment_received},
    'list_pending_requests': {'args_text': 'args={trip_id:str}', 'confirm': False, 'notes': 'Driver lists pending booking requests for a trip.', 'validate': _v_list_pending_requests},
    'negotiation_history': {'args_text': 'args={trip_id:str,booking_id:int}', 'confirm': False, 'notes': 'Shows negotiation history for a booking you are part of.', 'validate': _v_negotiation_history},
    'negotiation_respond': {'args_text': 'args={trip_id:str,booking_id:int,action:str,counter_fare:int,note:str}', 'confirm': True, 'notes': 'Accept/reject/counter/withdraw negotiation. Requires confirmation.', 'validate': _v_negotiation_respond},
}


def _agentic_tools_text() -> str:
    lines: list[str] = []
    for k, v in _AGENT_TOOL_SPECS.items():
        base = f"{k} {v.get('args_text') or ''}".rstrip()
        notes = str(v.get('notes') or '').strip()
        if notes:
            base = base + f" | notes: {notes}"
        lines.append(base)
    return "\n".join(lines)


def _has_placeholder(val: object) -> bool:
    if val is None:
        return False
    s = str(val)
    low = s.lower()
    if ('{' in s and '}' in s) or ('$' in s):
        return True
    if 'from_step' in low or 'result of step' in low or 'result_of_step' in low:
        return True
    return False


def _safe_int(val: object) -> int:
    if val is None:
        return 0
    if isinstance(val, bool):
        return 0
    if isinstance(val, int):
        return int(val)
    if isinstance(val, float):
        return int(val)
    s = str(val).strip()
    if not s or _has_placeholder(s):
        return 0
    if not re.fullmatch(r"\d{1,9}", s):
        return 0
    try:
        return int(s)
    except Exception:
        return 0


def _safe_float(val: object) -> float:
    if val is None:
        return 0.0
    if isinstance(val, bool):
        return 0.0
    if isinstance(val, (int, float)):
        return float(val)
    s = str(val).strip()
    if not s or _has_placeholder(s):
        return 0.0
    try:
        return float(s)
    except Exception:
        return 0.0


def _safe_str(val: object) -> str:
    if val is None:
        return ''
    s = str(val).strip()
    if not s or _has_placeholder(s):
        return ''
    return s


def _validate_agent_tool_call(st, tool: str, args: dict) -> tuple[dict, Optional[str], Optional[str]]:
    tool = str(tool or '').strip()
    a = args if isinstance(args, dict) else {}
    if not tool or tool not in _AGENT_TOOL_SPECS:
        return {}, None, 'Unknown tool.'

    for _, v in a.items():
        if _has_placeholder(v):
            return {}, None, 'I cannot execute tools with placeholder values. Please provide concrete values.'
    spec = _AGENT_TOOL_SPECS.get(tool) or {}
    v = spec.get('validate')
    if callable(v):
        return v(st, a)
    return {}, None, 'Unknown tool.'


def _agent_tool_requires_confirm(tool: str) -> bool:
    spec = _AGENT_TOOL_SPECS.get(str(tool or '').strip()) or {}
    return bool(spec.get('confirm'))


def _confirm_agent_tool_text(tool: str, args: dict) -> str:
    return "\n".join([
        'Please confirm this action:',
        f"- tool: {tool}",
        f"- args: {args}",
        "Reply 'yes' to confirm or 'no' to cancel.",
    ])


def _run_tool(
    st,
    *,
    tool: str,
    args: dict,
    goal: Optional[str] = None,
    remaining_steps: Optional[list] = None,
    confirmed: bool = False,
    skip_confirm: bool = False,
) -> str:
    norm_args, question, err = _validate_agent_tool_call(st, tool, args)
    if question:
        return question
    if err:
        return err

    if (not skip_confirm) and _agent_tool_requires_confirm(tool) and (not confirmed):
        st.active_flow = 'confirm_agent_tool'
        st.pending_action = {
            'type': 'agent_tool',
            'tool': tool,
            'args': norm_args,
            'remaining_steps': remaining_steps or [],
            'goal': goal,
        }
        st.awaiting_field = None
        return _confirm_agent_tool_text(tool, norm_args)

    out_txt = _execute_agent_tool(st, tool, norm_args)
    st.agent_last_tools.append({'tool': tool, 'args': norm_args, 'result': out_txt})
    st.agent_last_plan = {'goal': goal, 'tool': tool, 'args': norm_args}
    return out_txt


def _execute_agent_tool(st, name: str, a: dict) -> str:
    name = str(name or '').strip()
    a = a if isinstance(a, dict) else {}
    if name == 'list_my_rides':
        from .flows import list_user_created_trips_state
        return list_user_created_trips_state(st, limit=int(a.get('limit') or 20), vehicle_id=(int(a.get('vehicle_id')) if a.get('vehicle_id') is not None else None))
    if name == 'list_my_bookings':
        from .flows import list_user_booked_rides_state
        return list_user_booked_rides_state(st, limit=int(a.get('limit') or 20))
    if name == 'list_vehicles':
        if st.active_flow == 'create_ride' or st.awaiting_field == 'vehicle_id':
            from .flows import list_user_vehicles_state
            return list_user_vehicles_state(st, limit=int(a.get('limit') or 20))
        return list_user_vehicles(st.ctx, limit=int(a.get('limit') or 20))
    if name == 'routes_search':
        frm = str(a.get('from') or '').strip()
        to = str(a.get('to') or '').strip()
        status, out = api.api_search_routes(from_location=frm or None, to_location=to or None)
        routes = (out.get('routes') if isinstance(out, dict) else None) or []
        if status <= 0:
            return 'API server not reachable.'
        if not isinstance(routes, list) or not routes:
            return "I couldn't find a matching route. Try different stop names."
        if len(routes) == 1 and isinstance(routes[0], dict):
            r0 = routes[0]
            st.create_ride.route_id = str(r0.get('id') or '').strip() or st.create_ride.route_id
            st.create_ride.route_name = str(r0.get('name') or '').strip() or st.create_ride.route_name
            return f"Selected route_id={st.create_ride.route_id}."
        st.create_ride.route_candidates = routes
        st.active_flow = 'choose_route'
        st.awaiting_field = None
        from .flows import render_route_choice
        return render_route_choice(routes)
    if name == 'trip_detail':
        status, out = api.api_trip_detail_safe(st.ctx, str(a.get('trip_id') or ''))
        return f'{status}: {out}'
    if name == 'update_trip_vehicle':
        status, out = api.update_trip_vehicle_safe(
            st.ctx,
            str(a.get('trip_id') or ''),
            vehicle_id=int(a.get('vehicle_id') or 0),
        )
        if isinstance(out, dict):
            msg = out.get('message') or out.get('error')
            if msg:
                return str(msg)
        return f'{status}: {out}'
    if name == 'book_ride':
        trip_id = str(a.get('trip_id') or '')
        base_fare = api.api_trip_base_fare(trip_id)
        proposed = int(a.get('proposed_fare') or 0)
        payload = {
            'passenger_id': st.ctx.user_id,
            'from_stop_order': int(a.get('from_stop_order') or 0),
            'to_stop_order': int(a.get('to_stop_order') or 0),
            'number_of_seats': int(a.get('number_of_seats') or 1),
            'original_fare': int(base_fare or 0),
            'proposed_fare': proposed,
            'is_negotiated': bool(proposed != int(base_fare or 0)),
        }
        status, out = api.book_ride(st.ctx, trip_id, payload)
        try:
            if isinstance(out, dict):
                st.last_booking_id = int(out.get('booking_id') or out.get('id') or 0) or st.last_booking_id
        except Exception:
            pass
        st.last_trip_id = trip_id or st.last_trip_id
        return f'{status}: {out}'
    if name == 'chat_list':
        status, out = api.list_chat(st.ctx, str(a.get('trip_id') or ''), limit=int(a.get('limit') or 25))
        return f'{status}: {out}'
    if name == 'send_message':
        payload = {
            'sender_id': st.ctx.user_id,
            'recipient_id': int(a.get('recipient_id') or 0),
            'sender_role': str(a.get('sender_role') or 'passenger'),
            'message_text': str(a.get('message_text') or ''),
        }
        status, out = api.send_message(st.ctx, str(a.get('trip_id') or ''), payload)
        return f'{status}: {out}'
    if name == 'delete_trip':
        status, out = api.delete_my_trip(st.ctx, str(a.get('trip_id') or ''))
        if isinstance(out, dict):
            msg = out.get('message') or out.get('error')
            if msg:
                return str(msg)
        return f'{status}: {out}'
    if name == 'delete_trip_bulk':
        tids = a.get('trip_ids') if isinstance(a.get('trip_ids'), list) else []
        if not tids:
            return 'No trip_ids provided.'
        lines: list[str] = []
        for tid in tids:
            trip_id = str(tid or '').strip()
            if not trip_id:
                continue
            status, out = api.delete_my_trip(st.ctx, trip_id)
            msg = None
            if isinstance(out, dict):
                msg = out.get('message') or out.get('error')
            lines.append(f"- trip_id={trip_id}: {(msg or str(out))}")
        return "\n".join(lines) if lines else 'Nothing to delete.'
    if name == 'cancel_trip':
        status, out = api.cancel_my_trip(st.ctx, str(a.get('trip_id') or ''), reason=str(a.get('reason') or 'Cancelled by driver'))
        if isinstance(out, dict):
            msg = out.get('message') or out.get('error')
            if msg:
                return str(msg)
        return f'{status}: {out}'
    if name == 'cancel_booking':
        status, out = api.cancel_my_booking(st.ctx, int(a.get('booking_id') or 0), str(a.get('reason') or 'Cancelled by passenger'))
        if isinstance(out, dict):
            msg = out.get('message') or out.get('error')
            if msg:
                return str(msg)
        return f'{status}: {out}'
    if name == 'update_trip_gender_preference':
        status, out = api.update_trip_gender_preference_safe(
            st.ctx,
            str(a.get('trip_id') or ''),
            gender_preference=str(a.get('gender_preference') or ''),
        )
        if isinstance(out, dict):
            msg = out.get('message') or out.get('error')
            if msg:
                return str(msg)
        return f'{status}: {out}'
    if name == 'list_change_requests':
        status, out = api.list_my_change_requests(
            st.ctx,
            entity_type=str(a.get('entity_type') or 'USER_PROFILE'),
            status=(str(a.get('status')) if a.get('status') is not None else None),
            limit=int(a.get('limit') or 10),
        )
        if status <= 0:
            return 'API server not reachable.'
        if not isinstance(out, dict):
            return f'{status}: {out}'
        crs = out.get('change_requests') if isinstance(out.get('change_requests'), list) else []
        if not crs:
            return 'No change requests found.'
        lines = ['Your change requests:']
        for cr in crs[:10]:
            if not isinstance(cr, dict):
                continue
            cid = cr.get('id')
            et = cr.get('entity_type')
            stt = cr.get('status')
            created = cr.get('created_at')
            reviewed = cr.get('reviewed_at')
            req = cr.get('requested_changes') if isinstance(cr.get('requested_changes'), dict) else {}
            notes = cr.get('review_notes')
            lines.append(f"- id={cid} | entity={et} | status={stt} | created_at={created} | reviewed_at={reviewed}")
            if req:
                req_txt = ", ".join([f"{k}={v}" for k, v in req.items()])
                if req_txt:
                    lines.append(f"  requested_changes: {req_txt}")
            if notes:
                lines.append(f"  review_notes: {notes}")
        return "\n".join(lines)
    if name == 'profile_get':
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
        lines = [f'{status}: Profile']
        for k in ['name', 'username', 'email', 'phone_no', 'address', 'gender', 'status']:
            v = safe.get(k)
            if v is not None and str(v).strip():
                lines.append(f'- {k}: {v}')
        return "\n".join(lines)
    if name == 'profile_update':
        status, out = api.update_my_profile(st.ctx, a)
        if status <= 0:
            return 'API server not reachable.'

        if isinstance(out, dict):
            msg = out.get('message') or out.get('error')
            if msg:
                return str(msg)

            user_obj = out.get('user') if isinstance(out.get('user'), dict) else out
            safe_user = None
            if isinstance(user_obj, dict):
                safe_user = {
                    'id': user_obj.get('id'),
                    'name': user_obj.get('name'),
                    'username': user_obj.get('username'),
                    'email': user_obj.get('email'),
                    'phone_no': user_obj.get('phone_no') or user_obj.get('phone_number'),
                    'address': user_obj.get('address'),
                    'gender': user_obj.get('gender'),
                    'status': user_obj.get('status'),
                }

            pending = out.get('pending_updates') if isinstance(out.get('pending_updates'), dict) else {}
            immediate = out.get('immediate_updates') if isinstance(out.get('immediate_updates'), dict) else {}
            crid = out.get('change_request_id')

            lines = [f'{status}: Profile update submitted.']
            if immediate:
                imm_txt = ", ".join([f"{k}={v}" for k, v in immediate.items()])
                if imm_txt:
                    lines.append(f'Applied immediately: {imm_txt}')
            if pending:
                pend_txt = ", ".join([f"{k}={v}" for k, v in pending.items()])
                if pend_txt:
                    lines.append(f'Pending admin approval: {pend_txt}')
            if crid is not None:
                lines.append(f'Change request id: {crid}')
            if safe_user:
                if pending:
                    lines.append('Current profile values may remain unchanged until approved.')
                for k in ['name', 'address', 'gender', 'status']:
                    v = safe_user.get(k)
                    if v is not None and str(v).strip():
                        lines.append(f'- {k}: {v}')
            return "\n".join(lines)

        return f'{status}: Profile update submitted.'
    if name == 'payment_details':
        status, out = api.get_booking_payment_details_safe(st.ctx, int(a.get('booking_id') or 0))
        return f'{status}: {out}'
    if name == 'submit_payment_cash':
        status, out = api.submit_booking_payment_cash(
            st.ctx,
            int(a.get('booking_id') or 0),
            driver_rating=float(a.get('driver_rating') or 0.0),
            driver_feedback=str(a.get('driver_feedback') or ''),
        )
        if isinstance(out, dict):
            msg = out.get('message') or out.get('error')
            if msg:
                return str(msg)
        return f'{status}: {out}'
    if name == 'confirm_payment_received':
        status, out = api.confirm_booking_payment_received_safe(
            st.ctx,
            int(a.get('booking_id') or 0),
            passenger_rating=float(a.get('passenger_rating') or 0.0),
            passenger_feedback=str(a.get('passenger_feedback') or ''),
        )
        if isinstance(out, dict):
            msg = out.get('message') or out.get('error')
            if msg:
                return str(msg)
        return f'{status}: {out}'
    if name == 'list_pending_requests':
        status, out = api.list_pending_requests_safe(st.ctx, str(a.get('trip_id') or ''))
        return f'{status}: {out}'
    if name == 'negotiation_history':
        status, out = api.negotiation_history_safe(st.ctx, str(a.get('trip_id') or ''), int(a.get('booking_id') or 0))
        return f'{status}: {out}'
    if name == 'negotiation_respond':
        trip_id = str(a.get('trip_id') or '')
        booking_id = int(a.get('booking_id') or 0)
        driver_id = api.api_trip_driver_id(trip_id)
        if not driver_id:
            return 'Trip not found.'
        payload = {
            'action': str(a.get('action') or ''),
            'counter_fare': (int(a.get('counter_fare')) if a.get('counter_fare') is not None else None),
            'note': str(a.get('note') or ''),
        }
        if int(driver_id) == int(st.ctx.user_id):
            status, out = api.negotiate_driver(st.ctx, trip_id, booking_id, {**payload, 'driver_id': st.ctx.user_id})
        else:
            status, out = api.negotiate_passenger(st.ctx, trip_id, booking_id, {**payload, 'passenger_id': st.ctx.user_id})
        st.last_trip_id = trip_id or st.last_trip_id
        st.last_booking_id = booking_id or st.last_booking_id
        return f'{status}: {out}'
    if name == 'create_trip':
        route_id = str(a.get('route_id') or '').strip() or str(st.create_ride.route_id or '')
        trip_date = str(a.get('trip_date') or '').strip()
        departure_time = str(a.get('departure_time') or '').strip()
        payload = {
            'route_id': route_id,
            'vehicle_id': int(a.get('vehicle_id') or 0),
            'departure_time': departure_time,
            'trip_date': trip_date,
            'total_seats': int(a.get('total_seats') or 0),
            'custom_price': int(a.get('custom_price') or 0),
            'gender_preference': str(a.get('gender_preference') or 'Any'),
            'notes': str(a.get('notes') or ''),
            'is_negotiable': (a.get('is_negotiable') if isinstance(a.get('is_negotiable'), bool) else None),
            'driver_id': st.ctx.user_id,
        }
        fare_calc, stop_breakdown = build_create_trip_fare_payload(route_id, base_fare=int(payload.get('custom_price') or 0))
        if fare_calc:
            payload['fare_calculation'] = fare_calc
        if stop_breakdown:
            payload['stop_breakdown'] = stop_breakdown
        if payload.get('is_negotiable') is None:
            payload.pop('is_negotiable', None)
        if not (payload.get('notes') or '').strip():
            payload.pop('notes', None)
        status, out = api.create_ride(st.ctx, payload)
        try:
            if status in {200, 201} and isinstance(out, dict):
                created_tid = (
                    str(out.get('trip_id') or '').strip()
                    or str(((out.get('trip') or {}) if isinstance(out.get('trip'), dict) else {}).get('trip_id') or '').strip()
                )
                if created_tid:
                    st.last_trip_id = created_tid
        except Exception:
            pass
        if isinstance(out, dict):
            msg = out.get('message') or out.get('error')
            if msg:
                return str(msg)
        return f'{status}: {out}'
    return 'Unknown tool.'


def _run_agent_steps(st, steps: list, *, goal: Optional[str]) -> Optional[str]:
    outputs: list[str] = []
    ran_any = False
    for i, step in enumerate(steps):
        if not isinstance(step, dict):
            continue
        tool = str(step.get('tool') or '').strip()
        args = step.get('args') if isinstance(step.get('args'), dict) else {}
        if not tool:
            continue
        out_txt = _run_tool(st, tool=tool, args=args, goal=goal, remaining_steps=steps[i + 1:], confirmed=False, skip_confirm=False)
        if st.active_flow == 'confirm_agent_tool':
            return out_txt
        ran_any = True
        if out_txt:
            outputs.append(out_txt)
        if st.active_flow in {'choose_route', 'choose_trip'}:
            return out_txt
    if outputs:
        return "\n\n".join(outputs)
    if ran_any:
        return 'Done.'
    return None


def handle_message(ctx: BotContext, text: str) -> str:
    st = get_state(ctx.user_id)
    st.history.append({'role': 'user', 'text': text})
    low = normalize_text(text)

    def _finalize(reply: str) -> str:
        draft = reply or ''
        rewritten = None
        low_draft = normalize_text(draft)
        # Never rewrite tool/API status outputs or errors.
        if (
            re.match(r"^\s*\d{3}\s*:\s*", draft)
            or low_draft.startswith('api server not reachable')
            or ('not authorized' in low_draft)
            or ('forbidden' in low_draft)
            or ('verification pending' in low_draft)
            or ('error' in low_draft)
        ):
            rewritten = None
            final = draft
            hist_txt = final
            if ('{' in hist_txt) or ('}' in hist_txt):
                hist_txt = '[structured output omitted]'
            elif len(hist_txt) > 600:
                hist_txt = hist_txt[:600] + '...'
            st.history.append({'role': 'assistant', 'text': hist_txt})
            return final
        rewrite_allowed = (
            bool(draft)
            and ('{' not in draft)
            and ('}' not in draft)
            and ('\n' not in draft)
            and (len(draft) <= 240)
            and (st.active_flow is None)
            and (st.awaiting_field is None)
            and (st.pending_action is None)
            and (not re.match(r"^\s*\d{3}\s*:\s*", draft))
            and ('reply \"yes\"' not in normalize_text(draft))
            and ('please confirm' not in normalize_text(draft))
        )
        if rewrite_allowed:
            rewritten = llm_rewrite_reply(st, text, draft)
        final = rewritten or draft
        hist_txt = final
        if ('{' in hist_txt) or ('}' in hist_txt):
            hist_txt = '[structured output omitted]'
        elif len(hist_txt) > 600:
            hist_txt = hist_txt[:600] + '...'
        st.history.append({'role': 'assistant', 'text': hist_txt})
        return final

    # Detect pasted server logs / debug dumps and avoid routing into booking/create flows.
    if any(k in low for k in {
        '=== update_trip',
        'incoming keys',
        '[update_trip]',
        'http/1.1',
        'django version',
        'starting development server',
        'traceback',
        'quit the server',
    }):
        tid = extract_trip_id(text) or st.last_trip_id
        reset_flow(st)
        if tid:
            return _finalize(_run_tool(st, tool='trip_detail', args={'trip_id': str(tid)}, confirmed=True, skip_confirm=True))
        return _finalize("I see server logs/debug text. Please paste only the trip_id (e.g. T123-...) or say: 'trip details trip_id=...'.")

    # CLI-friendly: intercept profile/vehicle image requests.
    # In terminal mode we do NOT print URLs; however we DO call backend APIs to confirm images exist.
    if (
        any(k in low for k in {'display', 'show', 'list', 'view', 'give', 'get'})
        and any(k in low for k in {'photo', 'photos', 'image', 'images', 'picture', 'pictures'})
        and any(k in low for k in {'profile', 'account', 'cnic', 'license', 'driving', 'live'})
        and not any(k in low for k in {'vehicle', 'vehicles', 'veh'})
    ):
        status, out = api.api_get_user_profile(int(st.ctx.user_id))
        if status <= 0:
            return _finalize('API server not reachable.')
        if not isinstance(out, dict):
            return _finalize('Invalid profile response.')
        keys = [
            'profile_photo',
            'live_photo',
            'cnic_front_image',
            'cnic_back_image',
            'driving_license_front',
            'driving_license_back',
            'accountqr',
        ]
        present = [k for k in keys if str(out.get(k) or '').strip()]
        return _finalize(
            f"I found {len(present)} profile document image(s) on your account. They are shown in the app UI.\n"
            "In terminal mode I won't display image URLs.\n"
            "Say: 'show my profile'."
        )

    if (
        any(k in low for k in {'display', 'show', 'list', 'view', 'give', 'get'})
        and any(k in low for k in {'photo', 'photos', 'image', 'images', 'picture', 'pictures'})
        and any(k in low for k in {'vehicle', 'vehicles', 'veh'})
    ):
        status, out = api.api_list_my_vehicles(st.ctx, limit=50)
        if status <= 0:
            return _finalize('API server not reachable.')
        vehicles = []
        if isinstance(out, dict) and isinstance(out.get('vehicles'), list):
            vehicles = out.get('vehicles')
        elif isinstance(out, list):
            vehicles = out
        if not isinstance(vehicles, list):
            vehicles = []
        total_images = 0
        vehicles_with_images = 0
        for v in vehicles:
            if not isinstance(v, dict):
                continue
            imgs = 0
            for k in ('photo_front', 'photo_back', 'documents_image'):
                if str(v.get(k) or '').strip():
                    imgs += 1
            if imgs:
                vehicles_with_images += 1
                total_images += imgs
        return _finalize(
            f"I found vehicle photos for {vehicles_with_images} vehicle(s) ({total_images} image file(s)). They are shown in the app UI.\n"
            "In terminal mode I won't display image URLs.\n"
            "Say: 'show my vehicles'."
        )

    # OSM/ORS-first routing for 'from X to Y' and distance queries (run before LLM brain mode)
    if (
        any(k in low for k in {'from'})
        or (
            any(k in low for k in {'distance', 'how far', 'far'})
            and re.search(r"\bto\b", low)
        )
    ):
        from .route_helpers import extract_stop_names_from_text, route_search_with_osm_fallback, search_db_routes_by_name

        res = route_search_with_osm_fallback(text, st.ctx)
        summary = (res.get('summary') if isinstance(res, dict) else None) or ''
        err = (res.get('error') if isinstance(res, dict) else None)

        logger.debug("[chatbot][osm] triggered for: %r -> %r error=%r", text, summary, err)

        if summary and not err:
            # If user is in create_ride flow (or starting it), wire this into the draft.
            wants_create = (st.active_flow == 'create_ride') or (st.awaiting_field == 'route_id') or (
                ('create' in low or 'post' in low) and ('ride' in low or 'trip' in low)
            )
            if wants_create:
                st.active_flow = 'create_ride'
                try:
                    from .route_helpers import extract_stop_sequence_from_text
                except Exception:
                    extract_stop_sequence_from_text = None

                seq = extract_stop_sequence_from_text(text) if extract_stop_sequence_from_text else None
                if seq and len(seq) >= 2:
                    frm, to = seq[0], seq[-1]

                    # Save the last computed estimated per-seat fare (used by the create flow).
                    try:
                        if isinstance(res, dict) and isinstance(res.get('routes'), list) and res.get('routes'):
                            r0 = res['routes'][0] if isinstance(res['routes'][0], dict) else {}
                            fd = r0.get('fare_calculation')
                            if isinstance(fd, dict):
                                est = fd.get('total_price')
                                if est is not None:
                                    st.create_ride.estimated_price_per_seat = int(est)
                    except Exception:
                        pass

                    # Try to resolve an existing DB route_id so ride creation can proceed.
                    db_routes = search_db_routes_by_name(frm, to, limit=3)
                    if isinstance(db_routes, list) and len(db_routes) == 1:
                        rid = str((db_routes[0] or {}).get('route_id') or '').strip()
                        if rid:
                            st.create_ride.route_id = rid
                            st.create_ride.route_name = str((db_routes[0] or {}).get('route_name') or '').strip() or st.create_ride.route_name
                            st.awaiting_field = None
                            nxt = continue_create_flow(st, '')
                            return _finalize(summary + ("\n" + nxt if nxt else ''))

                    # No DB route match. Mirror the app: create a route first, then continue ride creation.
                    try:
                        route_stops = None
                        if isinstance(res, dict) and isinstance(res.get('routes'), list) and res.get('routes'):
                            r0 = res['routes'][0] if isinstance(res['routes'][0], dict) else {}
                            route_stops = r0.get('route_stops')
                        if isinstance(route_stops, list) and len(route_stops) >= 2:
                            coords_payload = [
                                {'lat': float(s.get('latitude') or 0.0), 'lng': float(s.get('longitude') or 0.0)}
                                for s in route_stops
                                if isinstance(s, dict)
                            ]
                            names_payload = [str(s.get('stop_name') or '').strip() for s in route_stops if isinstance(s, dict)]
                            coords_payload = [c for c in coords_payload if c.get('lat') and c.get('lng')]
                            names_payload = [n for n in names_payload if n]
                            if len(coords_payload) >= 2:
                                from datetime import datetime
                                create_payload = {
                                    'coordinates': coords_payload,
                                    'route_points': coords_payload,
                                    'location_names': names_payload or [frm, to],
                                    'created_at': datetime.utcnow().isoformat() + 'Z',
                                }
                                s_cr, out_cr = api.api_create_route(st.ctx, create_payload)
                                if s_cr > 0 and isinstance(out_cr, dict) and out_cr.get('success') is True:
                                    rid_new = str(((out_cr.get('route') or {}).get('id')) or '').strip()
                                    if rid_new:
                                        st.create_ride.route_id = rid_new
                                        if seq and len(seq) > 2:
                                            st.create_ride.route_name = f"{frm} to {to} via " + ", ".join(seq[1:-1])
                                        else:
                                            st.create_ride.route_name = f"{frm} to {to}"
                                        st.awaiting_field = None
                                        nxt = continue_create_flow(st, '')
                                        return _finalize(summary + "\n" + f"Created route_id={rid_new}." + ("\n" + nxt if nxt else ''))
                    except Exception:
                        pass

                    # Keep estimate, but be explicit that ride creation still needs a DB route_id.
                    if seq and len(seq) > 2:
                        st.create_ride.route_name = f"{frm} to {to} via " + ", ".join(seq[1:-1])
                    else:
                        st.create_ride.route_name = f"{frm} to {to}"
                    st.create_ride.route_id = None
                    st.awaiting_field = 'route_id'
                    return _finalize(
                        summary + "\n" +
                        "I can estimate distance/fare, but to create a ride I need an existing route_id in the system.\n"
                        "Please provide route_id (e.g., R001) or use stop names that exist in your database routes."
                    )

            # Otherwise, treat this as a pure routing/distance info request.
            return _finalize(summary)

        logger.debug("[chatbot][osm] OSM/DB failed, falling back to LLM brain mode")

    # Vehicle image URLs (explicit request).
    # Allow both: "vehicle image urls" and follow-ups like "i want image urls".
    last_assistant_text = ''
    for _h in reversed(st.history or []):
        if isinstance(_h, dict) and _h.get('role') == 'assistant' and isinstance(_h.get('text'), str):
            last_assistant_text = _h.get('text')
            break
    if (
        any(k in low for k in {'image', 'images', 'photo', 'photos'})
        and (
            any(k in low for k in {'url', 'urls', 'link', 'links'})
            or (('vehicle' in low) or ('vehicles' in low) or ('veh' in low))
            or ((st.agent_last_plan or {}).get('tool') == 'list_vehicles')
            or ('here are your vehicles' in normalize_text(last_assistant_text))
        )
    ):
        # Terminal/CLI testing: don't print image URLs; the mobile app UI will display images.
        return _finalize(
            "Images are shown in the app UI. In terminal mode I can list your vehicles, but I won't display image URLs here.\n"
            "Say: 'show my vehicles'."
        )

    # Admin messaging is not supported unless the user provides a numeric recipient_id.
    if ('admin' in low) and any(k in low for k in {'chat', 'message', 'text', 'dm'}):
        return _finalize("I can't message 'admin' by name. Please provide a numeric recipient_id (e.g. recipient_id=123).")

    # Early deterministic routing: if user mentions a specific vehicle id along with ride/trip,
    # treat it as a request to list *their created rides* filtered by that vehicle.
    # Booking-by-vehicle is not a supported feature, and letting this fall through often
    # misroutes into the booking flow.
    # Do NOT hijack edit/update/change/set intents (e.g., "make ride vehicle from 14 to 15").
    if (
        any(k in low for k in {'vehicle', 'vehicle_id', 'veh'})
        and re.search(r"\b(\d{1,6})\b", low)
        and not any(k in low for k in {'edit', 'update', 'change', 'set', 'make'})
    ):
        if any(k in low for k in {'ride', 'rides', 'trip', 'trips'}) and not any(k in low for k in {'book', 'reserve'}):
            # Avoid hijacking real route phrases like "from X to Y".
            if not re.search(r"\bfrom\b", low) and not re.search(r"\bto\b", low):
                m = re.search(r"\b(\d{1,6})\b", low)
                vid0 = int(m.group(1)) if m else 0
                if vid0:
                    reset_flow(st)
                    out_txt = _run_tool(st, tool='list_my_rides', args={'limit': 50, 'vehicle_id': vid0}, confirmed=True, skip_confirm=True)
                    return _finalize(out_txt)

    brain = llm_brain_mode()
    if brain:
        prov = llm_provider()
        if prov == 'none':
            return 'LLM brain mode is enabled, but no LLM provider is configured. Set LLM_PROVIDER (openai_compat or ollama).'
        if prov == 'openai_compat':
            if not llm_base_url():
                return 'LLM brain mode is enabled, but LLM_BASE_URL is missing.'
            if not llm_api_key():
                return 'LLM brain mode is enabled, but LLM_API_KEY is missing.'

    # CLI-friendly: update a pending created ride's vehicle without requiring an explicit trip_id.
    # Example: "make the ride with pending status vehicle from 14 to 15"
    # This runs before LLM intent extraction to intercept 'make' + 'pending' + 'vehicle' patterns.
    if (
        any(k in low for k in {'make', 'edit', 'update', 'change', 'set'})
        and any(k in low for k in {'vehicle', 'veh', 'vehicle_id'})
        and ('pending' in low)
        and re.search(r"\b(\d{1,6})\b", low)
    ):
        tid2 = extract_trip_id(text) or st.last_trip_id
        if not tid2:
            status, out = api.api_list_my_rides(st.ctx, limit=50)
            rides = (out.get('rides') if isinstance(out, dict) else None) or []
            if status > 0 and isinstance(rides, list) and rides:
                pending = []
                for r in rides:
                    if not isinstance(r, dict):
                        continue
                    st_txt = str(r.get('status') or '').strip().lower()
                    if st_txt == 'pending':
                        tid0 = str(r.get('trip_id') or '').strip()
                        if tid0:
                            pending.append(tid0)
                if len(pending) == 1:
                    tid2 = pending[0]
        m = re.findall(r"\b(\d{1,6})\b", low)
        vid = int(m[-1]) if m else 0
        if tid2 and vid:
            st.active_flow = 'confirm_agent_tool'
            st.pending_action = {
                'type': 'agent_tool',
                'tool': 'update_trip_vehicle',
                'args': {'trip_id': str(tid2), 'vehicle_id': int(vid)},
                'remaining_steps': [],
                'goal': 'Update trip vehicle',
            }
            st.awaiting_field = None
            return _finalize(_confirm_agent_tool_text('update_trip_vehicle', {'trip_id': str(tid2), 'vehicle_id': int(vid)}))

    llm_extract_cached(st, text)

    if (('exact reason' in low) or ('exact' in low and 'reason' in low) or ('what' in low and 'reason' in low)):
        last = (st.history[-2].get('text') if isinstance(st.history[-2], dict) and len(st.history) >= 2 else '')
        if isinstance(last, str) and ('unable to delete' in last.lower() or 'cannot be deleted' in last.lower() or 'cannot be cancelled' in last.lower()):
            return _finalize(last)

    blocked = blocked_system_request(text)
    if blocked is not None:
        return _finalize(blocked)

    if low in {'cancel', 'stop', 'reset'}:
        reset_flow(st)
        return _finalize('Okay, cancelled. What would you like to do next?')

    if st.active_flow in {'cancel_booking', 'confirm_cancel_booking'}:
        if any(p in low for p in {'not canceling', 'not cancelling', 'dont cancel', "don't cancel", 'no booking', 'not booking', 'not a booking'}):
            reset_flow(st)
            return _finalize('Okay. You are not cancelling a booking. What would you like to do instead?')

    # If the user is in a ride creation/selection flow but asks to list rides/trips, switch context.
    if st.active_flow in {'create_ride', 'choose_route', 'choose_vehicle'}:
        if any(k in low for k in {'my rides', 'my trips', 'list rides', 'list trips', 'show rides', 'show trips', 'give me my trips', 'give me my rides'}):
            reset_flow(st)

    # Break out of message flow when the user asks about profile/change requests.
    if st.active_flow == 'message':
        if any(k in low for k in {'change request', 'change-request', 'change requests', 'change-requests', 'profile', 'account'}) and not any(
            k in low for k in {'send message', 'message', 'chat', 'text', 'dm'}
        ):
            reset_flow(st)

    if any(p in low for p in {'round trip', 'roundtrip', 'two way', 'two-way', 'return trip', 'return journey', 'back trip'}):
        if any(k in low for k in {'ride', 'trip', 'create'}):
            return _finalize("Trips are currently one-way only. If you need a return journey, please create a second ride for the return leg.")

    if st.active_flow and st.awaiting_field and (low in {'no', 'n'}):
        reset_flow(st)
        return _finalize('Okay, cancelled. What would you like to do next?')

    cont = (
        continue_booking_flow(st, text)
        or continue_create_flow(st, text)
        or continue_message_flow(st, text)
        or continue_negotiate_flow(st, text)
        or continue_misc_flows(st, text)
    )
    if cont is not None:
        return _finalize(cont)

    # Bulk delete after listing created rides.
    if (
        any(k in low for k in {'delete', 'remove'})
        and any(k in low for k in {'both', 'all', 'these', 'them', 'those'})
        and isinstance(getattr(st, 'last_listed_trip_ids', None), list)
        and len(st.last_listed_trip_ids) >= 2
    ):
        st.active_flow = 'confirm_agent_tool'
        st.pending_action = {
            'type': 'agent_tool',
            'tool': 'delete_trip_bulk',
            'args': {'trip_ids': st.last_listed_trip_ids[:10]},
            'remaining_steps': [],
            'goal': 'Delete multiple trips',
        }
        st.awaiting_field = None
        return _finalize(_confirm_agent_tool_text('delete_trip_bulk', {'trip_ids': st.last_listed_trip_ids[:10]}))

    # If the user provides a trip_id and says delete, route to trip deletion (avoid cancel_booking misroutes).
    if any(k in low for k in {'delete', 'remove'}) and (extract_trip_id(text) or st.last_trip_id):
        tid = extract_trip_id(text) or st.last_trip_id
        if tid:
            st.active_flow = 'confirm_agent_tool'
            st.pending_action = {
                'type': 'agent_tool',
                'tool': 'delete_trip',
                'args': {'trip_id': str(tid)},
                'remaining_steps': [],
                'goal': 'Delete trip',
            }
            st.awaiting_field = None
            return _finalize(_confirm_agent_tool_text('delete_trip', {'trip_id': str(tid)}))

    if any(k in low for k in {'change request', 'change-request', 'change requests', 'change-requests'}) and any(
        k in low for k in {'status', 'statuses', 'state', 'pending', 'approved', 'rejected'}
    ):
        entity = 'USER_PROFILE'
        if 'vehicle' in low:
            entity = 'VEHICLE'
        status_filter = None
        if 'pending' in low:
            status_filter = 'PENDING'
        elif 'approved' in low:
            status_filter = 'APPROVED'
        elif 'rejected' in low:
            status_filter = 'REJECTED'

        args = {'entity_type': entity, 'limit': 10}
        if status_filter:
            args['status'] = status_filter
        out_txt = _run_tool(
            st,
            tool='list_change_requests',
            args=args,
            confirmed=True,
            skip_confirm=True,
        )
        return _finalize(out_txt)

    if any(k in low for k in {'vehicle', 'vehicle_id', 'veh'}) and re.search(r"\b(\d{1,6})\b", low):
        wants_vehicle_filtered_rides = (
            any(k in low for k in {'rides', 'ride', 'trips', 'trip'})
            and any(k in low for k in {'my', 'created', 'posted', 'show', 'list', 'give'})
        ) or (
            # e.g. "i have asked veh 15" after an unfiltered list
            ('asked' in low and any(k in low for k in {'veh', 'vehicle', 'vehicle_id'}))
        )
        if (
            wants_vehicle_filtered_rides
            and not any(k in low for k in {'book', 'reserve'})
            and not any(k in low for k in {'edit', 'update', 'change', 'set'})
        ):
            m = re.search(r"\b(\d{1,6})\b", low)
            vid = int(m.group(1)) if m else 0
            if vid:
                # Ensure we don't stay stuck in unrelated flows.
                if st.active_flow in {'book_ride', 'create_ride', 'choose_route', 'choose_trip', 'choose_vehicle'}:
                    reset_flow(st)
                return _finalize(
                    _run_tool(
                        st,
                        tool='list_my_rides',
                        args={'limit': 50, 'vehicle_id': vid},
                        confirmed=True,
                        skip_confirm=True,
                    )
                )

    if (
        any(k in low for k in {'edit', 'update', 'change', 'set'})
        and any(k in low for k in {'vehicle', 'veh', 'vehicle_id'})
        and (('trip' in low) or ('ride' in low) or extract_trip_id(text) or st.last_trip_id)
        and re.search(r"\b(\d{1,6})\b", low)
    ):
        tid2 = extract_trip_id(text) or st.last_trip_id
        if not tid2:
            # If the user says "pending ride" but didn't provide trip_id, try to pick it.
            status, out = api.api_list_my_rides(st.ctx, limit=50)
            rides = (out.get('rides') if isinstance(out, dict) else None) or []
            if status > 0 and isinstance(rides, list) and rides:
                pending = []
                for r in rides:
                    if not isinstance(r, dict):
                        continue
                    st_txt = str(r.get('status') or '').strip().lower()
                    if st_txt == 'pending':
                        tid0 = str(r.get('trip_id') or '').strip()
                        if tid0:
                            pending.append(tid0)
                if ('pending' in low) and len(pending) == 1:
                    tid2 = pending[0]
                elif len(rides) == 1 and isinstance(rides[0], dict):
                    tid0 = str(rides[0].get('trip_id') or '').strip()
                    if tid0:
                        tid2 = tid0

        if not tid2:
            return _finalize("Which trip_id do you want to update? You can say: 'list my rides'.")
        m = re.findall(r"\b(\d{1,6})\b", low)
        vid = int(m[-1]) if m else 0
        if not vid:
            return _finalize("Which vehicle_id should I set? You can say: 'show my vehicles'.")
        st.active_flow = 'confirm_agent_tool'
        st.pending_action = {
            'type': 'agent_tool',
            'tool': 'update_trip_vehicle',
            'args': {'trip_id': str(tid2), 'vehicle_id': int(vid)},
            'remaining_steps': [],
            'goal': 'Update trip vehicle',
        }
        st.awaiting_field = None
        return _finalize(_confirm_agent_tool_text('update_trip_vehicle', {'trip_id': str(tid2), 'vehicle_id': int(vid)}))

    if (
        (any(k in low for k in {'edit', 'update', 'change', 'set', 'make'}) and any(k in low for k in {'male', 'female'}))
        and (any(k in low for k in {'ride', 'trip', 'recent', 'recently'}) or extract_trip_id(text) or st.last_trip_id)
    ):
        tid2 = extract_trip_id(text) or st.last_trip_id
        if not tid2:
            return _finalize('Which trip_id do you want to update?')
        if ('male' in low) and ('female' in low):
            return _finalize("Do you want gender_preference=Male or Female?")
        gp = 'Male' if 'male' in low else 'Female'
        st.active_flow = 'confirm_agent_tool'
        st.pending_action = {
            'type': 'agent_tool',
            'tool': 'update_trip_gender_preference',
            'args': {'trip_id': str(tid2), 'gender_preference': gp},
            'remaining_steps': [],
            'goal': 'Update trip gender_preference',
        }
        st.awaiting_field = None
        return _finalize(_confirm_agent_tool_text('update_trip_gender_preference', {'trip_id': str(tid2), 'gender_preference': gp}))

    if (
        ('pending' in low)
        and any(k in low for k in {'edit', 'editable', 'update', 'change'})
        and (any(k in low for k in {'male', 'female', 'gender'}) or st.last_trip_id or extract_trip_id(text))
    ):
        tid2 = extract_trip_id(text) or st.last_trip_id
        if tid2:
            return _finalize(
                "If the trip is still editable, I can update its gender_preference. "
                "Tell me 'male only' or 'female only' (and include the trip_id if it's not your last trip)."
            )
        return _finalize(
            "If the trip is still editable, I can update its gender_preference. "
            "Share the trip_id and say 'male only' or 'female only'."
        )

    if (
        (any(k in low for k in {'recreate', 'repeat', 'clone', 'repost'}) and any(k in low for k in {'ride', 'trip'}))
        or (
            any(k in low for k in {'last', 'recent'})
            and any(k in low for k in {'ride', 'trip'})
            and any(k in low for k in {'again', 'same'})
        )
    ):
        return _finalize(start_recreate_ride_flow(st, text))

    if brain:
        tid = extract_trip_id(text)
        wants_rides = (
            (('api' in low) and any(k in low for k in {'ride', 'rides', 'trip', 'trips'}))
            or ('list my rides' in low)
            or (('my' in low or 'all' in low) and ('created' in low) and any(k in low for k in {'ride', 'rides', 'trip', 'trips'}))
        )
        if wants_rides:
            return _finalize(_run_tool(st, tool='list_my_rides', args={'limit': 50}, confirmed=True, skip_confirm=True))

        if tid and any(k in low for k in {'detail', 'details', 'complete', 'full', 'show'}):
            return _finalize(_run_tool(st, tool='trip_detail', args={'trip_id': tid}, confirmed=True, skip_confirm=True))

        if (
            any(k in low for k in {'update', 'edit', 'change', 'set', 'make'})
            and any(k in low for k in {'fare', 'price', 'seat price', 'gender'})
            and any(k in low for k in {'ride', 'trip', 'pending'})
        ):
            tid2 = tid or st.last_trip_id
            if tid2:
                return _finalize(
                    "I can't update an existing trip's fare or gender preference after it's created. "
                    f"If you want, I can cancel trip_id={tid2} and then recreate a new ride with your desired settings."
                )
            return _finalize(
                "I can't update an existing trip's fare or gender preference after it's created. "
                "If you share the trip_id, I can help you cancel it and recreate a new ride with your desired settings."
            )

    if brain:
        if (st.active_flow in {'choose_route', 'choose_trip', 'choose_vehicle'}) or ((st.active_flow or '').startswith('confirm_')):
            pass
        else:
            try:
                routed = llm_route_fallback(st, text)
            except Exception:
                routed = None
            if routed is not None:
                return _finalize(routed)

    if brain:
        if (
            ('status' in low or 'statuses' in low)
            and ('book' in low or 'booking' in low)
            and ('create' in low or 'created' in low or 'posted' in low)
            and ('ride' in low or 'rides' in low or 'trip' in low or 'trips' in low)
        ):
            return _finalize(list_user_rides_and_bookings_state(st, rides_limit=20, bookings_limit=20))

        if (('delete' in low or 'remove' in low) and ('booking' not in low) and st.last_trip_id):
            return _finalize(start_manage_trip_flow(st, text, mode='delete'))

        if st.active_flow in {'choose_route', 'choose_trip'} or (st.active_flow or '').startswith('confirm_'):
            pass
        elif re.fullmatch(r"\d{1,6}", low) or (low in {'yes', 'y', 'no', 'n', 'ok', 'okay', 'cancel', 'stop', 'reset'}):
            pass
        else:

            plan = llm_plan(st, text, tools_text=_agentic_tools_text())
            if isinstance(plan, dict):
                st.agent_last_plan = plan
                question = plan.get('question')
                if isinstance(question, str) and question.strip():
                    return _finalize(question.strip())
                steps = plan.get('steps')
                if isinstance(steps, list) and steps:
                    out_msg = _run_agent_steps(st, steps, goal=str(plan.get('goal') or '').strip() or None)
                    if out_msg is not None:
                        return _finalize(out_msg)

    llm_routed = None
    if not ((st.active_flow in {'choose_route', 'choose_trip', 'choose_vehicle'}) or ((st.active_flow or '').startswith('confirm_'))):
        try:
            llm_routed = llm_route_fallback(st, text)
        except Exception as e:
            llm_routed = None

    if st.active_flow == 'choose_trip':
        if not st.booking.candidates:
            reset_flow(st)
            return _finalize('No candidates left. Please start again.')
        m = re.search(r"\b(\d+)\b", low)
        if not m:
            if any(k in low for k in {'any', 'either', 'whichever'}):
                idx = 1
            else:
                return _finalize('Please reply with the trip number (e.g. 1), or type cancel.')
        else:
            idx = int(m.group(1) or 0)
        if idx < 1 or idx > len(st.booking.candidates):
            return _finalize(f"Please choose a number between 1 and {len(st.booking.candidates)}.")
        chosen = st.booking.candidates[idx - 1]
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
        return _finalize(render_booking_summary(st))

    if st.active_flow == 'choose_route':
        d = st.create_ride
        if not d.route_candidates:
            reset_flow(st)
            return _finalize('No routes to choose from. Please start again.')
        m = re.search(r"\b(\d+)\b", low)
        if not m:
            if any(k in low for k in {'any', 'either', 'whichever'}):
                idx = 1
            else:
                return _finalize('Please reply with the route number (e.g. 1), or type cancel.')
        else:
            idx = int(m.group(1) or 0)
        if idx < 1 or idx > len(d.route_candidates):
            return _finalize(f"Please choose a number between 1 and {len(d.route_candidates)}.")
        chosen = d.route_candidates[idx - 1]
        d.route_id = str(chosen.get('id') or chosen.get('route_id') or '').strip() or d.route_id
        d.route_name = str(chosen.get('name') or chosen.get('route_name') or '').strip() or d.route_name
        d.route_candidates = None
        st.active_flow = 'create_ride'
        st.awaiting_field = None
        return _finalize(continue_create_flow(st, '') or "Okay. Let's create a ride. Which route are you driving?")

    if st.active_flow == 'choose_vehicle':
        d = st.create_ride
        if not d.vehicle_candidates:
            reset_flow(st)
            return _finalize('No vehicles to choose from. Please start again.')
        m = re.search(r"\b(\d+)\b", low)
        if not m:
            if any(k in low for k in {'any', 'either', 'whichever'}):
                picked = 1
            else:
                return _finalize('Please reply with the vehicle number (e.g. 1), or type cancel.')
        else:
            picked = int(m.group(1) or 0)
        chosen = None
        for v in (d.vehicle_candidates or []):
            if not isinstance(v, dict):
                continue
            try:
                if int(v.get('id') or 0) == int(picked):
                    chosen = v
                    break
            except Exception:
                continue
        if chosen is None:
            idx = picked
            if idx < 1 or idx > len(d.vehicle_candidates):
                return _finalize(f"Please choose a number between 1 and {len(d.vehicle_candidates)}, or reply with a vehicle_id.")
            chosen = d.vehicle_candidates[idx - 1] if isinstance(d.vehicle_candidates[idx - 1], dict) else {}
        try:
            d.vehicle_id = int((chosen or {}).get('id') or 0) or d.vehicle_id
        except Exception:
            pass
        d.vehicle_candidates = None
        st.active_flow = 'create_ride'
        st.awaiting_field = None
        return _finalize(continue_create_flow(st, '') or 'Okay. Continue with ride creation.')

    if st.active_flow in {
        'confirm_booking',
        'confirm_create',
        'confirm_message',
        'confirm_negotiate',
        'confirm_cancel_booking',
        'confirm_delete_trip',
        'confirm_cancel_trip',
        'confirm_agent_tool',
        'confirm_profile_update',
        'confirm_submit_payment',
        'confirm_confirm_payment',
    }:
        yn = parse_yes_no(low)

        if st.active_flow == 'confirm_profile_update' and yn is None:
            d = st.profile

            if st.awaiting_field == 'profile_gender':
                if 'male' in low:
                    d.gender = 'male'
                    st.awaiting_field = None
                elif 'female' in low:
                    d.gender = 'female'
                    st.awaiting_field = None
                else:
                    return _finalize("Please reply with 'male' or 'female'.")
            else:
                if low in {'male', 'female'}:
                    d.gender = low
                m = re.search(r"\bgender\s*(?:[:=]|to)?\s*(male|female)\b", text or '', flags=re.IGNORECASE)
                if m:
                    d.gender = m.group(1).strip().lower()
                elif re.fullmatch(r"\s*gender\s*", text or '', flags=re.IGNORECASE):
                    st.awaiting_field = 'profile_gender'
                    return _finalize("What gender should I set in your profile? Reply 'male' or 'female'.")

                m = re.search(r"\bname\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
                if m:
                    d.name = m.group(1).strip()
                m = re.search(r"\baddress\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
                if m:
                    d.address = m.group(1).strip()
                m = re.search(r"\bbank\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
                if m:
                    d.bankname = m.group(1).strip()
                m = re.search(r"\baccount\s*no\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
                if m:
                    d.accountno = m.group(1).strip()
                m = re.search(r"\biban\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
                if m:
                    d.iban = m.group(1).strip()

            changed_lines: list[str] = []
            if d.name:
                changed_lines.append(f"- name: {d.name}")
            if d.address:
                changed_lines.append(f"- address: {d.address}")
            if d.gender:
                changed_lines.append(f"- gender: {d.gender}")
            if d.bankname:
                changed_lines.append(f"- bankname: {d.bankname}")
            if d.accountno:
                changed_lines.append(f"- accountno: {d.accountno}")
            if d.iban:
                changed_lines.append(f"- iban: {d.iban}")
            if not changed_lines:
                return _finalize("Tell me what to update (e.g., 'update profile gender: female' or 'change address: ...').")
            return _finalize("\n".join([
                'Please confirm profile update:',
                *changed_lines,
                "Reply 'yes' to confirm or 'no' to cancel.",
            ]))

        if yn is True:
            action = st.pending_action or {}
            if action.get('type') == 'agent_tool':
                tool = str(action.get('tool') or '').strip()
                args = action.get('args') if isinstance(action.get('args'), dict) else {}
                remaining = action.get('remaining_steps') if isinstance(action.get('remaining_steps'), list) else []
                goal = str(action.get('goal') or '').strip() or None

                out_text = _run_tool(
                    st,
                    tool=tool,
                    args=args,
                    goal=goal,
                    remaining_steps=remaining,
                    confirmed=True,
                    skip_confirm=True,
                )
                combined = [out_text] if out_text else []
                if st.active_flow in {'choose_route', 'choose_trip'}:
                    return _finalize(out_text)

                out_msg = _run_agent_steps(st, remaining, goal=goal)
                if st.active_flow == 'confirm_agent_tool' and out_msg is not None:
                    return _finalize("\n\n".join([*(combined or []), out_msg]) if combined else out_msg)
                if st.active_flow in {'choose_route', 'choose_trip'} and out_msg is not None:
                    return _finalize(out_msg)

                reset_flow(st)
                st.pending_action = None
                st.active_flow = None
                if out_msg:
                    combined.append(out_msg)
                return _finalize("\n\n".join(combined) if combined else 'Done.')

            type_to_tool = {
                'delete_trip': 'delete_trip',
                'cancel_trip': 'cancel_trip',
                'book_ride': 'book_ride',
                'negotiate': 'negotiation_respond',
                'submit_payment': 'submit_payment_cash',
                'confirm_payment': 'confirm_payment_received',
                'cancel_booking': 'cancel_booking',
                'profile_update': 'profile_update',
                'create_ride': 'create_trip',
                'message': 'send_message',
            }

            mapped_tool = type_to_tool.get(str(action.get('type') or '').strip())
            if mapped_tool:
                tool_args: dict[str, Any] = {}

                if mapped_tool == 'delete_trip':
                    tool_args = {'trip_id': str(action.get('trip_id') or st.last_trip_id or '')}
                elif mapped_tool == 'cancel_trip':
                    tool_args = {'trip_id': str(action.get('trip_id') or st.last_trip_id or ''), 'reason': str(action.get('reason') or 'Cancelled by driver')}
                elif mapped_tool == 'cancel_booking':
                    d = st.cancel_booking
                    tool_args = {'booking_id': int(d.booking_id or 0), 'reason': str(d.reason or 'Cancelled by passenger')}
                elif mapped_tool == 'profile_update':
                    d = st.profile
                    tool_args = {
                        'name': d.name,
                        'address': d.address,
                        'gender': d.gender,
                        'bankname': d.bankname,
                        'accountno': d.accountno,
                        'iban': d.iban,
                    }
                elif mapped_tool == 'send_message':
                    d = st.message
                    tool_args = {
                        'trip_id': str(d.trip_id or st.last_trip_id or ''),
                        'recipient_id': int(d.recipient_id or 0),
                        'sender_role': str(d.sender_role or 'passenger'),
                        'message_text': str(d.message_text or ''),
                    }
                elif mapped_tool == 'create_trip':
                    d = st.create_ride
                    tool_args = {
                        'route_id': str(d.route_id or ''),
                        'vehicle_id': int(d.vehicle_id or 0),
                        'trip_date': (d.trip_date.isoformat() if d.trip_date else ''),
                        'departure_time': str(d.departure_time or ''),
                        'total_seats': int(d.total_seats or 0),
                        'custom_price': int(d.custom_price or 0),
                        'gender_preference': str(d.gender_preference or 'Any'),
                        'notes': str(d.notes or ''),
                        'is_negotiable': (bool(d.is_negotiable) if d.is_negotiable is not None else None),
                    }
                elif mapped_tool == 'book_ride':
                    d = st.booking
                    tool_args = {
                        'trip_id': str(d.selected_trip_id or st.last_trip_id or ''),
                        'from_stop_order': int(d.selected_from_stop_order or 0),
                        'to_stop_order': int(d.selected_to_stop_order or 0),
                        'number_of_seats': int(d.number_of_seats or 0),
                        'proposed_fare': int(d.proposed_fare or 0),
                    }
                elif mapped_tool == 'submit_payment_cash':
                    d = st.payment
                    tool_args = {
                        'booking_id': int(d.booking_id or 0),
                        'driver_rating': float(d.driver_rating or 0.0),
                        'driver_feedback': str(d.driver_feedback or ''),
                    }
                elif mapped_tool == 'confirm_payment_received':
                    d = st.payment
                    tool_args = {
                        'booking_id': int(d.booking_id or 0),
                        'passenger_rating': float(d.passenger_rating or 0.0),
                        'passenger_feedback': str(d.passenger_feedback or ''),
                    }
                elif mapped_tool == 'negotiation_respond':
                    d = st.negotiate
                    tool_args = {
                        'trip_id': str(d.trip_id or st.last_trip_id or ''),
                        'booking_id': int(d.booking_id or 0),
                        'action': str(d.action or ''),
                        'counter_fare': (int(d.counter_fare) if d.counter_fare is not None else None),
                        'note': str(d.note or ''),
                    }

                out_text = _run_tool(st, tool=mapped_tool, args=tool_args, confirmed=True, skip_confirm=True)
                reset_flow(st)
                return _finalize(out_text)

            reset_flow(st)
            return _finalize('Done.')

        if yn is False:
            reset_flow(st)
            return _finalize('Okay, cancelled. What would you like to do next?')
        return _finalize("Please reply 'yes' to confirm or 'no' to cancel.")

    try:
        llm_routed = llm_route_fallback(st, text)
    except Exception as e:
        llm_routed = None
        if (os.environ.get('CHATBOT_DEBUG_LLM') or '').strip().lower() in {'1', 'true', 'yes'}:
            logger.exception('[chatbot][llm_route_fallback][ERROR]: %s', repr(e))
    if llm_routed is not None:
        return _finalize(llm_routed)

    if brain:
        return _finalize(
            "Tell me what you want to do. For example: 'list my rides', 'trip details trip_id=... ', 'create a ride from X to Y', or 'recreate my last ride'."
        )

    smalltalk = smalltalk_reply(text)
    if smalltalk is not None and not st.active_flow:
        return _finalize(smalltalk)

    intent = api.intent(text)
    if intent == 'help':
        return _finalize(help_text())
    if intent == 'capabilities':
        return _finalize(capabilities_text())
    if intent == 'greet':
        name = st.user_name or 'there'
        return _finalize(f"Hi {name}. What would you like to do today—book a ride or create a ride?")

    if intent == 'book_ride':
        st.active_flow = 'book_ride'
        update_booking_from_text(st, text)
        return _finalize(continue_booking_flow(st, text) or 'Where are you starting from (pickup stop)?')

    if intent == 'create_ride':
        st.active_flow = 'create_ride'
        update_create_from_text(st, text)
        return _finalize(continue_create_flow(st, text) or "Okay. Let's create a ride. Which route are you driving?")

    if intent == 'message':
        st.active_flow = 'message'
        update_message_from_text(st, text)
        return _finalize(continue_message_flow(st, text) or 'Which trip? Please provide trip_id.')

    if intent == 'negotiate':
        st.active_flow = 'negotiate'
        st.awaiting_field = None
        out = continue_negotiate_flow(st, text) or 'Provide trip_id and booking_id.'
        return _finalize(out)

    if intent == 'cancel_booking':
        st.active_flow = 'cancel_booking'
        from .helpers import extract_booking_id, to_int
        st.cancel_booking.booking_id = extract_booking_id(text) or st.last_booking_id or to_int(text)
        if not st.cancel_booking.booking_id:
            st.awaiting_field = 'booking_id'
            return _finalize('Which booking do you want to cancel? Provide booking_id.')
        st.cancel_booking.reason = 'Cancelled by passenger'
        st.active_flow = 'confirm_cancel_booking'
        st.pending_action = {'type': 'cancel_booking'}
        return _finalize("\n".join([
            'Please confirm cancellation:',
            f"- booking_id: {st.cancel_booking.booking_id}",
            f"- reason: {st.cancel_booking.reason}",
            "Reply 'yes' to confirm or 'no' to cancel.",
        ]))

    if intent == 'chat_list':
        trip_id = extract_trip_id(text) or st.last_trip_id
        if not trip_id:
            st.active_flow = 'chat_list'
            st.awaiting_field = 'trip_id'
            return _finalize('Which trip chat do you want to view? Provide trip_id.')
        status, out = api.list_chat(st.ctx, str(trip_id), limit=25)
        return _finalize(f'{status}: {out}')

    if intent == 'profile_view':
        status, out = api.get_my_profile(st.ctx)
        if status <= 0:
            return _finalize('API server not reachable.')
        if not isinstance(out, dict):
            return _finalize(f'{status}: {out}')
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
        return _finalize(f'{status}: {safe}')

    if intent == 'profile_update':
        st.active_flow = 'confirm_profile_update'
        st.pending_action = {'type': 'profile_update'}
        d = st.profile
        m = re.search(r"\bname\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.name = m.group(1).strip()
        m = re.search(r"\baddress\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.address = m.group(1).strip()
        m = re.search(r"\bgender\s*(?:[:=]|to)?\s*(male|female)\b", text or '', flags=re.IGNORECASE)
        if m:
            d.gender = m.group(1).strip().lower()
        m = re.search(r"\bbank\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.bankname = m.group(1).strip()
        m = re.search(r"\baccount\s*no\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.accountno = m.group(1).strip()
        m = re.search(r"\biban\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.iban = m.group(1).strip()
        if not any([d.name, d.address, d.gender, d.bankname, d.accountno, d.iban]):
            reset_flow(st)
            return _finalize("Tell me what to update (e.g., 'update profile gender: female' or 'change address: ...').")
        return _finalize("\n".join([
            'Please confirm profile update:',
            f"- name: {d.name}",
            f"- address: {d.address}",
            f"- gender: {d.gender}",
            f"- bankname: {d.bankname}",
            f"- accountno: {d.accountno}",
            f"- iban: {d.iban}",
            "Reply 'yes' to confirm or 'no' to cancel.",
        ]))

    if intent == 'payment_details':
        from .helpers import extract_booking_id
        booking_id = extract_booking_id(text) or st.last_booking_id
        if not booking_id:
            st.active_flow = 'payment_details'
            st.awaiting_field = 'booking_id'
            return _finalize('Which booking payment details do you want? Provide booking_id.')
        status, out = api.get_booking_payment_details_safe(st.ctx, int(booking_id))
        return _finalize(f'{status}: {out}')

    if intent == 'submit_payment':
        from .helpers import extract_booking_id
        st.payment = PaymentDraft()
        st.payment.booking_id = extract_booking_id(text) or st.last_booking_id
        st.payment.driver_rating = parse_rating_value(text)
        if st.payment.booking_id is None:
            st.active_flow = 'submit_payment'
            st.awaiting_field = 'booking_id'
            return _finalize('Which booking are you paying for? Provide booking_id.')
        if st.payment.driver_rating is None:
            st.active_flow = 'submit_payment'
            st.awaiting_field = 'driver_rating'
            return _finalize("Please provide driver rating (1-5). Example: '5' or '5 stars'.")
        st.payment.driver_feedback = ''
        st.active_flow = 'confirm_submit_payment'
        st.pending_action = {'type': 'submit_payment'}
        return _finalize("\n".join([
            'Please confirm payment submission (CASH):',
            f"- booking_id: {st.payment.booking_id}",
            f"- driver_rating: {st.payment.driver_rating}",
            "Reply 'yes' to confirm or 'no' to cancel.",
        ]))

    if intent == 'confirm_payment':
        from .helpers import extract_booking_id
        st.payment = PaymentDraft()
        st.payment.booking_id = extract_booking_id(text)
        st.payment.passenger_rating = parse_rating_value(text)
        if st.payment.booking_id is None:
            st.active_flow = 'confirm_payment'
            st.awaiting_field = 'booking_id'
            return _finalize('Which booking payment do you want to confirm? Provide booking_id.')
        if st.payment.passenger_rating is None:
            st.active_flow = 'confirm_payment'
            st.awaiting_field = 'passenger_rating'
            return _finalize("Please provide passenger rating (1-5). Example: '5' or '5 stars'.")
        st.payment.passenger_feedback = ''
        st.active_flow = 'confirm_confirm_payment'
        st.pending_action = {'type': 'confirm_payment'}
        return _finalize("\n".join([
            'Please confirm payment received:',
            f"- booking_id: {st.payment.booking_id}",
            f"- passenger_rating: {st.payment.passenger_rating}",
            "Reply 'yes' to confirm or 'no' to cancel.",
        ]))

    if intent == 'list_vehicles':
        return _finalize(list_user_vehicles(st.ctx))

    if intent == 'list_my_rides':
        return _finalize(list_user_created_trips(st.ctx))

    if intent == 'list_bookings':
        status, out = api.list_my_bookings(st.ctx, limit=10)
        return _finalize(f'{status}: {out}')

    if intent == 'delete_trip':
        return _finalize(start_manage_trip_flow(st, text, mode='delete'))

    if intent == 'cancel_trip':
        return _finalize(start_manage_trip_flow(st, text, mode='cancel'))

    llm_reply = llm_chat_reply(st, text)
    if llm_reply:
        return _finalize(llm_reply)

    return _finalize("Tell me what you want to do (for example: book a ride from X to Y, or create a ride).")


def ask_bot(user_id: int, question: str):
    ctx = BotContext(user_id=int(user_id))
    reply = handle_message(ctx, question)
    logger.debug("Bot: %s", reply)
