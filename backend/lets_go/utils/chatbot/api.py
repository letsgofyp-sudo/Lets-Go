from __future__ import annotations

import re
from typing import Any, Optional

from .http_client import call_view, call_view_form
from .state import BotContext
from .helpers import normalize_text, to_int


def api_login(email: str, password: str) -> tuple[Optional[dict], Optional[str]]:
    status, out = call_view_form('POST', '/lets_go/login/', data={'email': email, 'password': password})
    if status <= 0:
        return None, 'API server not reachable.'
    if not isinstance(out, dict) or not out.get('success'):
        return None, str(out.get('error') if isinstance(out, dict) else out)
    users = out.get('UsersData')
    if not isinstance(users, list) or not users:
        return None, 'Login response missing UsersData.'
    user = users[0]
    if not isinstance(user, dict) or user.get('id') is None:
        return None, 'Login response missing user id.'
    return user, None


def api_get_user_profile(user_id: int) -> tuple[int, Any]:
    return call_view('GET', f'/lets_go/users/{int(user_id)}/')


def require_user(ctx: BotContext) -> tuple[Optional[dict], Optional[str]]:
    status, out = api_get_user_profile(int(ctx.user_id))
    if status == 404:
        return None, 'User not found.'
    if status <= 0:
        return None, 'API server not reachable.'
    if not isinstance(out, dict):
        return None, 'Invalid profile response.'
    if (str(out.get('status') or '').strip().upper() == 'BANNED'):
        return None, 'Your account is banned. You cannot perform this operation.'
    return out, None


def api_list_my_vehicles(ctx: BotContext, *, limit: int = 50) -> tuple[int, Any]:
    _ = limit
    return call_view('GET', f'/lets_go/users/{int(ctx.user_id)}/vehicles/')


def api_list_my_rides(ctx: BotContext, *, limit: int = 50) -> tuple[int, Any]:
    return call_view('GET', f'/lets_go/users/{int(ctx.user_id)}/rides/', query={'mode': 'summary', 'limit': int(limit), 'offset': 0})


def api_trip_detail(trip_id: str) -> tuple[int, Any]:
    tid = str(trip_id or '').strip()
    if not tid:
        return 400, {'success': False, 'error': 'trip_id is required.'}
    return call_view('GET', f'/lets_go/ride-booking/{tid}/')


def api_trip_detail_safe(ctx: BotContext, trip_id: str) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    tid = str(trip_id or '').strip()
    if not tid:
        return 400, {'success': False, 'error': 'trip_id is required.'}

    s_r, rides_out = api_list_my_rides(ctx, limit=200)
    rides = (rides_out.get('rides') if isinstance(rides_out, dict) else None) or []
    if any(isinstance(r, dict) and str(r.get('trip_id') or '') == tid for r in rides):
        _ = user
        return api_trip_detail(tid)

    s_b, bookings_out = list_my_bookings(ctx, limit=200)
    _ = s_b
    bookings = (bookings_out.get('bookings') if isinstance(bookings_out, dict) else None) or []
    if any(isinstance(b, dict) and str(b.get('trip_id') or '') == tid for b in bookings):
        _ = user
        return api_trip_detail(tid)

    _ = s_r
    _ = user
    return 403, {'success': False, 'error': 'Not authorized to view this trip.'}


def _my_rides_index_by_trip_id(rides: Any) -> dict[str, dict]:
    out: dict[str, dict] = {}
    if not isinstance(rides, list):
        return out
    for r in rides:
        if not isinstance(r, dict):
            continue
        tid = str(r.get('trip_id') or '').strip()
        if not tid:
            continue
        out[tid] = r
    return out


def delete_my_trip(ctx: BotContext, trip_id: str) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    tid = str(trip_id or '').strip()
    if not tid:
        return 400, {'success': False, 'error': 'trip_id is required.'}

    s, out = api_list_my_rides(ctx, limit=200)
    rides = (out.get('rides') if isinstance(out, dict) else None) or []
    idx = _my_rides_index_by_trip_id(rides)
    ride = idx.get(tid)
    if not ride:
        return 403, {'success': False, 'error': 'Not authorized: this trip was not created by you.'}
    if ride.get('can_delete') is False:
        st = normalize_text(str(ride.get('status') or ride.get('trip_status') or ''))
        if st in {'completed', 'complete'}:
            return 400, {'success': False, 'error': 'Trip cannot be deleted because it is completed.'}
        if st in {'in progress', 'in_progress', 'started', 'ongoing', 'ride_started'}:
            return 400, {'success': False, 'error': 'Trip cannot be deleted because it is in progress.'}
        if st in {'cancelled', 'canceled'}:
            return 400, {'success': False, 'error': 'Trip cannot be deleted because it is cancelled.'}
        if st:
            return 400, {'success': False, 'error': f'Trip cannot be deleted because status={st}.'}
        return 400, {'success': False, 'error': 'Trip cannot be deleted. It may be completed, in progress, cancelled, or have bookings.'}

    _ = s
    _ = user
    return call_view('DELETE', f'/lets_go/trips/{tid}/delete/')


def cancel_my_trip(ctx: BotContext, trip_id: str, *, reason: str) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    tid = str(trip_id or '').strip()
    if not tid:
        return 400, {'success': False, 'error': 'trip_id is required.'}

    s, out = api_list_my_rides(ctx, limit=200)
    rides = (out.get('rides') if isinstance(out, dict) else None) or []
    idx = _my_rides_index_by_trip_id(rides)
    ride = idx.get(tid)
    if not ride:
        return 403, {'success': False, 'error': 'Not authorized: this trip was not created by you.'}
    if ride.get('can_cancel') is False:
        return 400, {'success': False, 'error': 'Trip cannot be cancelled. It may already be cancelled or completed.'}

    _ = s
    _ = user
    return call_view('POST', f'/lets_go/trips/{tid}/cancel/', body={'reason': (reason or 'Cancelled by driver')})


def update_my_trip_safe(ctx: BotContext, trip_id: str, payload: dict) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    tid = str(trip_id or '').strip()
    if not tid:
        return 400, {'success': False, 'error': 'trip_id is required.'}

    if not isinstance(payload, dict) or not payload:
        return 400, {'success': False, 'error': 'payload is required.'}

    s, out = api_list_my_rides(ctx, limit=200)
    rides = (out.get('rides') if isinstance(out, dict) else None) or []
    idx = _my_rides_index_by_trip_id(rides)
    ride = idx.get(tid)
    if not ride:
        return 403, {'success': False, 'error': 'Not authorized: this trip was not created by you.'}

    if ride.get('can_edit') is False:
        st = normalize_text(str(ride.get('status') or ride.get('trip_status') or ''))
        if st:
            return 400, {'success': False, 'error': f'Trip cannot be edited because status={st}.'}
        return 400, {'success': False, 'error': 'Trip cannot be edited. It may be completed, in progress, cancelled, or have bookings.'}

    _ = s
    _ = user
    return call_view('PUT', f'/lets_go/trips/{tid}/update/', body=payload)


def update_trip_gender_preference_safe(ctx: BotContext, trip_id: str, *, gender_preference: str) -> tuple[int, Any]:
    gp = str(gender_preference or '').strip()
    if gp not in {'Male', 'Female', 'Any'}:
        return 400, {'success': False, 'error': "gender_preference must be one of: Male, Female, Any."}
    return update_my_trip_safe(ctx, str(trip_id or '').strip(), {'gender_preference': gp})


def update_trip_vehicle_safe(ctx: BotContext, trip_id: str, *, vehicle_id: int) -> tuple[int, Any]:
    vid = int(vehicle_id or 0)
    if not vid:
        return 400, {'success': False, 'error': 'vehicle_id is required.'}

    s, out = api_list_my_vehicles(ctx)
    if s <= 0:
        return s, out
    vehicles = (out.get('vehicles') if isinstance(out, dict) else None) or []
    found = None
    for v in vehicles:
        if not isinstance(v, dict):
            continue
        try:
            if int(v.get('id') or 0) == vid:
                found = v
                break
        except Exception:
            continue
    if found is None:
        return 403, {'success': False, 'error': 'Not authorized: you do not own this vehicle.'}
    vstatus = str(found.get('status') or '').upper()
    if vstatus not in {'VERIFIED', 'APPROVED'}:
        return 400, {'success': False, 'error': 'Selected vehicle is not verified yet. Please wait for admin verification.'}

    return update_my_trip_safe(ctx, str(trip_id or '').strip(), {'vehicle_id': vid})


def api_search_routes(*, from_location: Optional[str], to_location: Optional[str]) -> tuple[int, Any]:
    return call_view(
        'GET',
        '/lets_go/routes/search/',
        query={'from': (from_location or '').strip() or None, 'to': (to_location or '').strip() or None},
    )


def api_suggest_stops(*, q: str, limit: int = 8, lat: Optional[float] = None, lng: Optional[float] = None) -> tuple[int, Any]:
    query: dict[str, Any] = {'q': (q or '').strip(), 'limit': int(limit)}
    if lat is not None and lng is not None:
        query['lat'] = float(lat)
        query['lng'] = float(lng)
    return call_view('GET', '/lets_go/stops/suggest/', query=query)


def api_create_route(ctx: BotContext, payload: dict) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    if not isinstance(payload, dict) or not payload:
        return 400, {'success': False, 'error': 'payload is required.'}
    _ = user
    return call_view('POST', '/lets_go/create_route/', body=payload)


def create_ride(ctx: BotContext, payload: dict) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    driver_id = payload.get('driver_id') or ctx.user_id
    if int(driver_id) != int(ctx.user_id):
        return 403, {'success': False, 'error': 'Not authorized: driver_id must match your user_id.'}

    vehicle_id = payload.get('vehicle_id')
    if vehicle_id:
        status, out = api_list_my_vehicles(ctx)
        vehicles = (out.get('vehicles') if isinstance(out, dict) else None) or []
        found = None
        for v in vehicles:
            if isinstance(v, dict) and int(v.get('id') or 0) == int(vehicle_id):
                found = v
                break
        if found is None:
            return 403, {'success': False, 'error': 'Not authorized: you do not own this vehicle.'}
        vstatus = str(found.get('status') or '').upper()
        if vstatus not in {'VERIFIED', 'APPROVED'}:
            return 400, {'success': False, 'error': 'Selected vehicle is not verified yet. Please wait for admin verification.'}

    _ = user
    return call_view('POST', '/lets_go/create_trip/', body=payload)


def book_ride(ctx: BotContext, trip_id: str, payload: dict) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    passenger_id = payload.get('passenger_id') or ctx.user_id
    if int(passenger_id) != int(ctx.user_id):
        return 403, {'success': False, 'error': 'Not authorized: passenger_id must match your user_id.'}

    status, detail = call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
    if status == 404:
        return 404, {'success': False, 'error': 'Trip not found'}
    driver_id = None
    try:
        if isinstance(detail, dict):
            driver_id = int(((detail.get('trip') or {}).get('driver') or {}).get('id') or 0)
    except Exception:
        driver_id = None
    if driver_id and int(driver_id) == int(passenger_id):
        return 403, {'success': False, 'error': 'Driver cannot book their own trip.'}

    _ = user
    return call_view('POST', f'/lets_go/ride-booking/{trip_id}/request/', body={**payload, 'passenger_id': passenger_id})


def list_my_bookings(ctx: BotContext, *, limit: int = 10) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    _ = user
    return call_view('GET', f'/lets_go/users/{ctx.user_id}/bookings/', query={'mode': 'summary', 'limit': int(limit), 'offset': 0})


def cancel_my_booking(ctx: BotContext, booking_id: int, reason: str) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    status, bookings_out = list_my_bookings(ctx, limit=200)
    _ = status
    bookings = (bookings_out.get('bookings') if isinstance(bookings_out, dict) else None) or []
    if not any(isinstance(b, dict) and int(b.get('id') or 0) == int(booking_id) for b in bookings):
        return 403, {'success': False, 'error': 'Not authorized: this booking does not belong to you.'}
    _ = user
    return call_view('POST', f'/lets_go/bookings/{int(booking_id)}/cancel/', body={'reason': reason or 'Cancelled by passenger'})


def _can_access_trip_chat(ctx: BotContext, trip_id: str) -> bool:
    status, detail = call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
    if status <= 0 or not isinstance(detail, dict):
        return False
    try:
        driver_id = int(((detail.get('trip') or {}).get('driver') or {}).get('id') or 0)
    except Exception:
        driver_id = 0
    if driver_id and int(driver_id) == int(ctx.user_id):
        return True

    status, bookings_out = list_my_bookings(ctx, limit=200)
    _ = status
    bookings = (bookings_out.get('bookings') if isinstance(bookings_out, dict) else None) or []
    for b in bookings:
        if not isinstance(b, dict):
            continue
        if str(b.get('trip_id')) != str(trip_id):
            continue
        st = str(b.get('booking_status') or b.get('status') or '').upper()
        if st in {'CONFIRMED', 'COMPLETED'}:
            return True
    return False


def list_chat(ctx: BotContext, trip_id: str, *, limit: int = 25) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    if not _can_access_trip_chat(ctx, str(trip_id)):
        return 403, {'success': False, 'error': 'Not authorized to view chat for this trip.'}
    _ = user
    return call_view('GET', f'/lets_go/chat/{trip_id}/messages/', query={'user_id': int(ctx.user_id), 'limit': int(limit)})


def send_message(ctx: BotContext, trip_id: str, payload: dict) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    sender_id = payload.get('sender_id') or ctx.user_id
    if int(sender_id) != int(ctx.user_id):
        return 403, {'success': False, 'error': 'Not authorized: sender_id must match your user_id.'}

    if not _can_access_trip_chat(ctx, str(trip_id)):
        return 403, {'success': False, 'error': 'Not authorized to send messages for this trip.'}

    _ = user
    return call_view('POST', f'/lets_go/chat/{trip_id}/messages/send/', body={**payload, 'sender_id': sender_id})


def get_my_profile(ctx: BotContext) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    _ = user
    return call_view('GET', f'/lets_go/users/{ctx.user_id}/')


def update_my_profile(ctx: BotContext, payload: dict) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    _ = user
    return call_view('PATCH', f'/lets_go/users/{ctx.user_id}/', body=payload)


def list_my_change_requests(
    ctx: BotContext,
    *,
    entity_type: str = 'USER_PROFILE',
    status: Optional[str] = None,
    vehicle_id: Optional[int] = None,
    limit: int = 10,
) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    et = (entity_type or '').strip().upper() or 'USER_PROFILE'
    st = (status or '').strip().upper() if status is not None else None

    q: dict[str, Any] = {
        'entity_type': et,
        'limit': int(limit or 10),
    }
    if st:
        q['status'] = st
    if vehicle_id is not None:
        q['vehicle_id'] = int(vehicle_id)
    _ = user
    return call_view('GET', f'/lets_go/users/{int(ctx.user_id)}/change-requests/', query=q)


def get_booking_payment_details_safe(ctx: BotContext, booking_id: int) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    s1, out1 = call_view('GET', f'/lets_go/bookings/{int(booking_id)}/payment/', query={'role': 'PASSENGER', 'user_id': int(ctx.user_id)})
    if s1 != 403:
        return s1, out1
    s2, out2 = call_view('GET', f'/lets_go/bookings/{int(booking_id)}/payment/', query={'role': 'DRIVER', 'user_id': int(ctx.user_id)})
    _ = user
    return s2, out2


def submit_booking_payment_cash(ctx: BotContext, booking_id: int, *, driver_rating: float, driver_feedback: str = '') -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    status, bookings_out = list_my_bookings(ctx, limit=200)
    _ = status
    bookings = (bookings_out.get('bookings') if isinstance(bookings_out, dict) else None) or []
    if not any(isinstance(b, dict) and int(b.get('id') or 0) == int(booking_id) for b in bookings):
        return 403, {'success': False, 'error': 'Not authorized as passenger'}

    _ = user
    return call_view_form(
        'POST',
        f'/lets_go/bookings/{int(booking_id)}/payment/submit/',
        data={
            'passenger_id': str(ctx.user_id),
            'driver_rating': str(driver_rating),
            'driver_feedback': driver_feedback or '',
            'payment_method': 'CASH',
        },
    )


def confirm_booking_payment_received(ctx: BotContext, booking_id: int, *, passenger_rating: float, passenger_feedback: str = '') -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    _ = user
    return call_view(
        'POST',
        f'/lets_go/bookings/{int(booking_id)}/payment/confirm/',
        body={
            'driver_id': int(ctx.user_id),
            'received': True,
            'passenger_rating': float(passenger_rating),
            'passenger_feedback': passenger_feedback or '',
        },
    )


def confirm_booking_payment_received_safe(ctx: BotContext, booking_id: int, *, passenger_rating: float, passenger_feedback: str = '') -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    status, out = call_view('GET', f'/lets_go/bookings/{int(booking_id)}/payment/', query={'role': 'DRIVER', 'user_id': int(ctx.user_id)})
    if status == 403:
        return 403, {'success': False, 'error': 'Not authorized as driver for this booking.'}
    if status <= 0:
        return status, out
    _ = out
    _ = user
    return confirm_booking_payment_received(ctx, int(booking_id), passenger_rating=passenger_rating, passenger_feedback=passenger_feedback)


def api_trip_driver_id(trip_id: str) -> Optional[int]:
    status, detail = call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
    if status <= 0 or not isinstance(detail, dict):
        return None
    try:
        return to_int(((detail.get('trip') or {}).get('driver') or {}).get('id'))
    except Exception:
        return None


def api_trip_base_fare(trip_id: str) -> int:
    status, detail = call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
    if status <= 0 or not isinstance(detail, dict):
        return 0
    try:
        return int(((detail.get('trip') or {}).get('base_fare') or 0) or 0)
    except Exception:
        return 0


def negotiate_driver(ctx: BotContext, trip_id: str, booking_id: int, payload: dict) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    driver_id = payload.get('driver_id') or ctx.user_id
    if int(driver_id) != int(ctx.user_id):
        return 403, {'success': False, 'error': 'Not authorized: driver_id must match your user_id.'}

    status, rides_out = api_list_my_rides(ctx, limit=200)
    _ = status
    rides = (rides_out.get('rides') if isinstance(rides_out, dict) else None) or []
    if not any(isinstance(r, dict) and str(r.get('trip_id')) == str(trip_id) for r in rides):
        return 403, {'success': False, 'error': 'Not authorized: only the trip driver can respond.'}

    _ = user
    return call_view('POST', f'/lets_go/ride-booking/{trip_id}/requests/{booking_id}/respond/', body={**payload, 'driver_id': driver_id})


def negotiate_passenger(ctx: BotContext, trip_id: str, booking_id: int, payload: dict) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    passenger_id = payload.get('passenger_id') or ctx.user_id
    if int(passenger_id) != int(ctx.user_id):
        return 403, {'success': False, 'error': 'Not authorized: passenger_id must match your user_id.'}

    status, bookings_out = list_my_bookings(ctx, limit=200)
    _ = status
    bookings = (bookings_out.get('bookings') if isinstance(bookings_out, dict) else None) or []
    if not any(isinstance(b, dict) and int(b.get('id') or 0) == int(booking_id) for b in bookings):
        return 403, {'success': False, 'error': 'Not authorized: this booking does not belong to you.'}

    _ = user
    return call_view('POST', f'/lets_go/ride-booking/{trip_id}/requests/{booking_id}/passenger-respond/', body={**payload, 'passenger_id': passenger_id})


def list_pending_requests_safe(ctx: BotContext, trip_id: str) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    tid = str(trip_id or '').strip()
    if not tid:
        return 400, {'success': False, 'error': 'trip_id is required.'}

    status, rides_out = api_list_my_rides(ctx, limit=200)
    rides = (rides_out.get('rides') if isinstance(rides_out, dict) else None) or []
    if status <= 0:
        return status, rides_out
    if not any(isinstance(r, dict) and str(r.get('trip_id') or '') == tid for r in rides):
        return 403, {'success': False, 'error': 'Not authorized: only the trip driver can view requests.'}

    _ = user
    return call_view('GET', f'/lets_go/ride-booking/{tid}/requests/', query={'user_id': int(ctx.user_id)})


def negotiation_history_safe(ctx: BotContext, trip_id: str, booking_id: int) -> tuple[int, Any]:
    user, err = require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    tid = str(trip_id or '').strip()
    bid = int(booking_id or 0)
    if not tid:
        return 400, {'success': False, 'error': 'trip_id is required.'}
    if bid <= 0:
        return 400, {'success': False, 'error': 'booking_id is required.'}

    s_r, rides_out = api_list_my_rides(ctx, limit=200)
    rides = (rides_out.get('rides') if isinstance(rides_out, dict) else None) or []
    if s_r <= 0:
        return s_r, rides_out
    if any(isinstance(r, dict) and str(r.get('trip_id') or '') == tid for r in rides):
        _ = user
        return call_view('GET', f'/lets_go/ride-booking/{tid}/negotiation/{bid}/', query={'user_id': int(ctx.user_id), 'role': 'DRIVER'})

    s_b, bookings_out = list_my_bookings(ctx, limit=200)
    bookings = (bookings_out.get('bookings') if isinstance(bookings_out, dict) else None) or []
    if s_b <= 0:
        return s_b, bookings_out
    if not any(isinstance(b, dict) and int(b.get('id') or 0) == int(bid) and str(b.get('trip_id') or '') == tid for b in bookings):
        return 403, {'success': False, 'error': 'Not authorized to view negotiation for this booking.'}
    if any(p in low for p in ['my vehicles', 'my vehicle', 'what vehicle i have', 'what vehicles i have', 'show my vehicles', 'list my vehicles']):
        return 'list_vehicles'
    if any(p in low for p in [
        'which ride i created', 'which trip i created',
        'my rides', 'my trips', 'rides i created', 'trips i created',
        'show my rides', 'list my rides', 'show my trips', 'list my trips',
        'all rides', 'all my rides', 'all trips', 'all my trips',
        'recent ride', 'recent trip', 'recently created ride', 'recently created trip',
        'most recent ride', 'most recent trip', 'most recent created ride', 'most recent created trip',
        'most recent rides', 'most recent trips', 'most recent created rides', 'most recent created trips',
        'latest ride', 'latest trip', 'last ride', 'last trip',
        'ride i just created', 'trip i just created',
    ]):
        return 'list_my_rides'

    if (re.search(r"\b(delete|remove)\b", low) and re.search(r"\b(ride|trip)\b", low)):
        return 'delete_trip'
    if ('cancel' in low and re.search(r"\b(ride|trip)\b", low) and 'booking' not in low):
        return 'cancel_trip'

    if re.search(r"\b(book|reserve)\b", low) and re.search(r"\b(ride|trip)\b", low):
        return 'book_ride'
    if any(p in low for p in ['my bookings', 'show my bookings', 'list my bookings', 'booking history', 'my booking']):
        return 'list_bookings'
    if 'cancel' in low and 'booking' in low:
        return 'cancel_booking'
    if any(p in low for p in ['payment details', 'payment status', 'show payment', 'booking payment']):
        return 'payment_details'
    if ('confirm payment' in low or 'payment received' in low) and 'booking' in low:
        return 'confirm_payment'
    if (re.search(r"\bpay\b", low) or ('submit payment' in low)) and 'booking' in low:
        return 'submit_payment'
    if any(p in low for p in ['my profile', 'show my profile', 'profile details']):
        return 'profile_view'
    if (
        any(p in low for p in ['update profile', 'change address', 'change name', 'update bank', 'update iban', 'update account'])
        or (('gender' in low) and any(p in low for p in ['profile', 'my gender', 'account']))
    ):
        return 'profile_update'
    if ('chat' in low and ('history' in low or 'messages' in low or 'show' in low)):
        return 'chat_list'

    if re.search(r"\b(create|post|make)\b", low) and re.search(r"\b(ride|trip)\b", low):
        return 'create_ride'
    if any(k in low for k in ['message', 'msg', 'text']) or (low.startswith('chat ') or low == 'chat'):
        return 'message'
    if any(k in low for k in ['negotiate', 'counter', 'accept', 'reject', 'withdraw']):
        return 'negotiate'
    if any(k in low for k in ['hi', 'hello', 'hey', 'assalam', 'salam', 'asalam', 'aoa']) and len(low.split()) <= 4:
        return 'greet'
    if low in {'help', '/help'}:
        return 'help'
    return 'kb'
