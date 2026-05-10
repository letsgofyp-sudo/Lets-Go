from __future__ import annotations

import json
import re


def has_placeholder(val: object) -> bool:
    if val is None:
        return False
    s = str(val)
    low = s.lower()
    if ('{' in s and '}' in s) or ('$' in s):
        return True
    if 'from_step' in low or 'result of step' in low or 'result_of_step' in low:
        return True
    return False


def safe_int(val: object) -> int:
    if val is None:
        return 0
    if isinstance(val, bool):
        return 0
    if isinstance(val, int):
        return int(val)
    if isinstance(val, float):
        return int(val)
    s = str(val).strip()
    if not s or has_placeholder(s):
        return 0
    if not re.fullmatch(r"\d{1,9}", s):
        return 0
    try:
        return int(s)
    except Exception:
        return 0


def safe_float(val: object) -> float:
    if val is None:
        return 0.0
    if isinstance(val, bool):
        return 0.0
    if isinstance(val, (int, float)):
        return float(val)
    s = str(val).strip()
    if not s or has_placeholder(s):
        return 0.0
    try:
        return float(s)
    except Exception:
        return 0.0


def safe_str(val: object) -> str:
    if val is None:
        return ''
    s = str(val).strip()
    if not s or has_placeholder(s):
        return ''
    return s


def safe_json(obj: object) -> str:
    try:
        return json.dumps(obj, ensure_ascii=False, separators=(',', ':'), default=str)
    except Exception:
        return str(obj)


def redact_obj(obj: object) -> object:
    if isinstance(obj, list):
        return [redact_obj(x) for x in obj]
    if isinstance(obj, dict):
        out: dict = {}
        for k, v in obj.items():
            key = str(k or '')
            low = key.lower()
            if low.endswith('_url') or low.endswith('url') or low.endswith('_image') or 'document' in low or 'photo' in low:
                continue
            if 'license' in low or 'driving_license' in low or 'cnic' in low:
                continue
            out[k] = redact_obj(v)
        return out
    if isinstance(obj, str):
        if obj.startswith('http://') or obj.startswith('https://'):
            return '[REDACTED_URL]'
        return obj
    return obj


def _render_list(title: str, lines: list[str], *, empty_text: str) -> str:
    if not lines:
        return empty_text
    out = [title]
    out.extend(lines)
    return "\n".join(out)


def _as_list(val: object) -> list:
    return val if isinstance(val, list) else []


def _as_dict(val: object) -> dict:
    return val if isinstance(val, dict) else {}


def _render_vehicles(out: dict) -> str | None:
    vehicles = _as_list(out.get('vehicles'))
    if not vehicles:
        return None
    lines: list[str] = []
    for v in vehicles[:10]:
        if not isinstance(v, dict):
            continue
        vid = safe_str(v.get('id'))
        plate = safe_str(v.get('plate_number'))
        company = safe_str(v.get('company_name'))
        model = safe_str(v.get('model_number'))
        vtype = safe_str(v.get('vehicle_type'))
        status = safe_str(v.get('status'))
        seats = safe_str(v.get('seats'))
        parts = [
            f"vehicle_id={vid}" if vid else None,
            plate or None,
            (company + (f" {model}" if model else '')).strip() or None,
            (f"type={vtype}" if vtype else None),
            (f"seats={seats}" if seats else None),
            (f"status: {status}" if status else None),
        ]
        lines.append('- ' + ' | '.join([p for p in parts if p]))
    return _render_list('Here are your vehicles:', lines, empty_text='I could not find any vehicles in your account.')


def _render_bookings(out: dict) -> str | None:
    bookings = _as_list(out.get('bookings'))
    if not bookings:
        return None
    lines: list[str] = []
    for b in bookings[:10]:
        if not isinstance(b, dict):
            continue
        bid = safe_str(b.get('booking_id') or b.get('id'))
        tid = safe_str(b.get('trip_id'))
        rn = b.get('route_names')
        if isinstance(rn, list) and rn:
            origin = safe_str(rn[0]) or 'Unknown'
            dest = safe_str(rn[-1]) or 'Unknown'
        else:
            origin = safe_str(b.get('from_location')) or 'Unknown'
            dest = safe_str(b.get('to_location')) or 'Unknown'
        dt = (safe_str(b.get('trip_date')) + (' ' + safe_str(b.get('departure_time')) if safe_str(b.get('departure_time')) else '')).strip()
        st = safe_str(b.get('booking_status') or b.get('status'))
        parts = [
            f"booking_id={bid}" if bid else None,
            (f"trip_id={tid}" if tid else None),
            f"{origin} -> {dest}",
            dt or None,
            (f"status: {st}" if st else None),
        ]
        lines.append('- ' + ' | '.join([p for p in parts if p]))
    return _render_list('Here are your bookings:', lines, empty_text="I couldn't find any bookings in your account.")


def _render_profile(out: dict) -> str | None:
    if not isinstance(out, dict):
        return None
    if ('name' not in out) and ('id' not in out) and ('username' not in out):
        return None
    safe = {
        'id': out.get('id'),
        'name': out.get('name'),
        'username': out.get('username'),
        'gender': out.get('gender'),
        'address': out.get('address'),
        'status': out.get('status'),
        'driver_rating': out.get('driver_rating'),
        'passenger_rating': out.get('passenger_rating'),
    }
    lines: list[str] = ['Profile:']
    for k in ['id', 'name', 'username', 'gender', 'address', 'status', 'driver_rating', 'passenger_rating']:
        v = safe.get(k)
        s = safe_str(v)
        if s:
            lines.append(f"- {k}: {s}")
    if len(lines) == 1:
        return None
    return "\n".join(lines)


def _render_change_requests(out: dict) -> str | None:
    crs = _as_list(out.get('change_requests'))
    if not crs:
        return None
    lines: list[str] = []
    for c in crs[:10]:
        if not isinstance(c, dict):
            continue
        cid = safe_str(c.get('id'))
        entity = safe_str(c.get('entity_type'))
        status = safe_str(c.get('status'))
        created = safe_str(c.get('created_at'))
        parts = [
            (f"id={cid}" if cid else None),
            (f"entity={entity}" if entity else None),
            (f"status: {status}" if status else None),
            (f"created_at={created}" if created else None),
        ]
        lines.append('- ' + ' | '.join([p for p in parts if p]))
    return _render_list('Your change requests:', lines, empty_text='No change requests found.')


def _render_chat(out: dict) -> str | None:
    msgs = out.get('messages')
    if not isinstance(msgs, list) or not msgs:
        return None
    lines: list[str] = []
    for m in msgs[:12]:
        if not isinstance(m, dict):
            continue
        sender = safe_str(m.get('sender_type') or m.get('sender_role') or m.get('sender'))
        text = safe_str(m.get('message_text') or m.get('text') or m.get('message'))
        if not text:
            continue
        if len(text) > 220:
            text = text[:220] + '...'
        lines.append(f"- {sender + ': ' if sender else ''}{text}")
    return _render_list('Recent chat messages:', lines, empty_text='No chat messages found.')


def format_api_result(status: int, out: object) -> str:
    try:
        code = int(status or 0)
    except Exception:
        code = 0
    if code in {401, 403} and isinstance(out, dict):
        msg = out.get('error') or out.get('message')
        if isinstance(msg, str) and msg.strip():
            return msg.strip()
    if code <= 0:
        return 'API server not reachable.'

    redacted = redact_obj(out)
    obj = _as_dict(redacted)
    if obj:
        rendered = (
            _render_profile(obj)
            or _render_vehicles(obj)
            or _render_bookings(obj)
            or _render_change_requests(obj)
            or _render_chat(obj)
        )
        if rendered:
            return rendered

        msg = obj.get('message') or obj.get('detail') or obj.get('error')
        if isinstance(msg, str) and msg.strip() and code in {200, 201, 202}:
            return msg.strip()
        if isinstance(msg, str) and msg.strip() and code >= 400:
            return msg.strip()

    if code in {200, 201, 202, 204}:
        return safe_json(redacted)
    if 300 <= code < 400:
        return 'This request was redirected. Please try again.'
    if 400 <= code < 500:
        return "Sorry, I couldn't complete that request. Please check your input and try again."
    if code >= 500:
        return "Sorry, something went wrong on our side. Please try again in a moment."
    return "Sorry, I couldn't complete that request right now. Please try again."
