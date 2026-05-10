from __future__ import annotations

from .state_types import ConversationState


def render_route_choice(routes: list[dict]) -> str:
    lines = ['I found multiple matching routes. Please reply with the route number you want:']
    for i, r in enumerate(routes, start=1):
        if not isinstance(r, dict):
            continue
        lines.append(f"{i}) route_id={r.get('id')} | {r.get('name')}")
    lines.append("You can also say 'cancel' to stop.")
    return "\n".join(lines)


def render_location_choice(query: str, candidates: list[dict]) -> str:
    q = (query or '').strip()
    lines = [f"I found multiple matches for '{q}'. Please reply with the location number you mean:"]
    for i, c in enumerate((candidates or [])[:8], start=1):
        if not isinstance(c, dict):
            continue
        dn = str(c.get('display_name') or '').strip()
        if not dn:
            dn = str(c.get('name') or '').strip()
        lines.append(f"{i}) {dn}")
    lines.append("You can also say 'cancel' to stop.")
    return "\n".join(lines)


def render_trip_choice(candidates: list[dict]) -> str:
    lines = ['I found multiple matching trips. Please reply with the trip number you want:']
    for i, c in enumerate(candidates, start=1):
        lines.append(
            f"{i}) trip_id={c.get('trip_id')} | {c.get('route_name')} | {c.get('trip_date')} {c.get('departure_time')} | seats={c.get('available_seats')} | base_fare={c.get('base_fare')}"
        )
    lines.append("You can also say 'cancel' to stop.")
    return "\n".join(lines)


def render_vehicle_choice(vehicles: list[dict]) -> str:
    lines = ['Please choose a vehicle by replying with its number:']
    for i, v in enumerate(vehicles, start=1):
        if not isinstance(v, dict):
            continue
        seats = v.get('seats')
        seats_txt = f"{int(seats)}" if seats not in [None, ''] else '-'
        lines.append(
            f"{i}) vehicle_id={v.get('id')} | {v.get('plate_number', '')} | {v.get('company_name', '')} {v.get('model_number', '')} | type={v.get('vehicle_type', '')} | seats={seats_txt} | status: {v.get('status', '')}"
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
