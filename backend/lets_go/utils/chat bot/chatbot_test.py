# pip install langchain langchain-community langchain-ollama langgraph
import json
import os
import re
import sys
import difflib
import math
import logging
import urllib.request
import urllib.parse
import urllib.error
import http.cookiejar
from datetime import date, datetime, timedelta
from dataclasses import dataclass
from typing import Any, Optional


LETS_GO_API_BASE_URL = (os.getenv('LETS_GO_API_BASE_URL') or 'http://localhost:8000').strip()


_COOKIE_JAR = http.cookiejar.CookieJar()
_HTTP_OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(_COOKIE_JAR))


_CURRENT_USER: dict[str, Any] = {}


BOT_EMAIL = (os.getenv('LETS_GO_BOT_EMAIL') or '').strip()
BOT_PASSWORD = (os.getenv('LETS_GO_BOT_PASSWORD') or '').strip()


STOPS_GEO_JSON = (os.getenv('LETS_GO_STOPS_GEO_JSON') or '').strip()
_STOPS_GEO_CACHE: Optional[list[dict]] = None


ROUTES_JSON = (os.getenv('LETS_GO_ROUTES_JSON') or '').strip()
_ROUTES_CACHE: Optional[list[dict]] = None


logger = logging.getLogger(__name__)


@dataclass
class BotContext:
    user_id: int


@dataclass
class BookingDraft:
    from_stop_raw: Optional[str] = None
    to_stop_raw: Optional[str] = None
    trip_date: Optional[date] = None
    departure_time: Optional[str] = None
    number_of_seats: Optional[int] = None
    proposed_fare: Optional[int] = None
    selected_trip_id: Optional[str] = None
    selected_from_stop_order: Optional[int] = None
    selected_to_stop_order: Optional[int] = None
    selected_from_stop_name: Optional[str] = None
    selected_to_stop_name: Optional[str] = None
    selected_base_fare: Optional[int] = None
    selected_trip_date: Optional[str] = None
    selected_departure_time: Optional[str] = None
    selected_route_name: Optional[str] = None
    selected_driver_id: Optional[int] = None
    selected_driver_name: Optional[str] = None
    candidates: Optional[list[dict]] = None


@dataclass
class CreateRideDraft:
    route_id: Optional[str] = None
    route_name: Optional[str] = None
    route_candidates: Optional[list[dict]] = None
    vehicle_id: Optional[int] = None
    trip_date: Optional[date] = None
    departure_time: Optional[str] = None
    total_seats: Optional[int] = None
    custom_price: Optional[int] = None
    gender_preference: Optional[str] = None


@dataclass
class MessageDraft:
    trip_id: Optional[str] = None
    recipient_id: Optional[int] = None
    sender_role: Optional[str] = None
    message_text: Optional[str] = None


@dataclass
class NegotiateDraft:
    trip_id: Optional[str] = None
    booking_id: Optional[int] = None
    action: Optional[str] = None
    counter_fare: Optional[int] = None
    note: Optional[str] = None


@dataclass
class CancelBookingDraft:
    booking_id: Optional[int] = None
    reason: Optional[str] = None


@dataclass
class ProfileDraft:
    name: Optional[str] = None
    address: Optional[str] = None
    bankname: Optional[str] = None
    accountno: Optional[str] = None
    iban: Optional[str] = None


@dataclass
class PaymentDraft:
    booking_id: Optional[int] = None
    role: Optional[str] = None
    payment_method: Optional[str] = None
    driver_rating: Optional[float] = None
    driver_feedback: Optional[str] = None
    passenger_rating: Optional[float] = None
    passenger_feedback: Optional[str] = None


@dataclass
class ConversationState:
    ctx: BotContext
    user_name: str = ''
    last_trip_id: Optional[str] = None
    last_booking_id: Optional[int] = None
    active_flow: Optional[str] = None
    awaiting_field: Optional[str] = None
    booking: BookingDraft = None
    create_ride: CreateRideDraft = None
    message: MessageDraft = None
    negotiate: NegotiateDraft = None
    cancel_booking: CancelBookingDraft = None
    profile: ProfileDraft = None
    payment: PaymentDraft = None
    pending_action: Optional[dict] = None
    history: list[dict] = None
    llm_last_text: Optional[str] = None
    llm_last_extract: Optional[dict] = None

    def __post_init__(self):
        if self.booking is None:
            self.booking = BookingDraft()
        if self.create_ride is None:
            self.create_ride = CreateRideDraft()
        if self.message is None:
            self.message = MessageDraft()
        if self.negotiate is None:
            self.negotiate = NegotiateDraft()
        if self.cancel_booking is None:
            self.cancel_booking = CancelBookingDraft()
        if self.profile is None:
            self.profile = ProfileDraft()
        if self.payment is None:
            self.payment = PaymentDraft()
        if self.history is None:
            self.history = []
        if self.llm_last_extract is None:
            self.llm_last_extract = {}


_SESSIONS: dict[int, ConversationState] = {}



def _normalize_text(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip().lower())


def _tokenize(s: str) -> list[str]:
    s = _normalize_text(s)
    s = re.sub(r"[^a-z0-9_\s-]+", " ", s)
    parts = [p for p in s.split() if p]
    return parts


def _llm_chat_enabled() -> bool:
    v = (os.environ.get('LLM_CHAT') or '').strip().lower()
    if v:
        return v in {'1', 'true', 'yes'}
    return _llm_provider() != 'none'


def _llm_chat_prompt(history: list[dict], text: str) -> str:
    lines = [
        'You are a helpful, polite assistant for a ride-sharing app chatbot.',
        'Keep responses short and practical. Ask one clarifying question if needed.',
        'Do not mention internal implementation details or APIs.',
    ]
    for h in (history or [])[-8:]:
        role = (h or {}).get('role')
        t = (h or {}).get('text')
        if not role or not t:
            continue
        lines.append(f"{role}: {t}")
    lines.append(f"user: {text}")
    return "\n".join(lines)


def _llm_chat_reply(st: ConversationState, text: str) -> Optional[str]:
    if not _llm_chat_enabled():
        return None

    prov = _llm_provider()
    prompt = _llm_chat_prompt(st.history or [], text)

    if prov == 'ollama':
        try:
            payload = {
                'model': _ollama_model(),
                'messages': [
                    {'role': 'system', 'content': 'You are a helpful assistant.'},
                    {'role': 'user', 'content': prompt},
                ],
                'stream': False,
            }
            req = urllib.request.Request(
                'http://localhost:11434/api/chat',
                data=json.dumps(payload).encode('utf-8'),
                headers={'Content-Type': 'application/json'},
                method='POST',
            )
            with urllib.request.urlopen(req, timeout=3.5) as resp:
                raw = resp.read().decode('utf-8')
            obj = json.loads(raw)
            content = (((obj or {}).get('message') or {}).get('content') or '').strip()
            return content[:700] if content else None
        except Exception:
            return None

    if prov == 'openai_compat':
        base = _llm_base_url()
        if not base:
            return None
        try:
            url = base + '/chat/completions'
            headers = {'Content-Type': 'application/json'}
            key = _llm_api_key()
            if key:
                headers['Authorization'] = f'Bearer {key}'
            payload = {
                'model': _cloud_model(),
                'messages': [
                    {'role': 'system', 'content': 'You are a helpful assistant.'},
                    {'role': 'user', 'content': prompt},
                ],
                'temperature': 0.7,
            }
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode('utf-8'),
                headers=headers,
                method='POST',
            )
            with urllib.request.urlopen(req, timeout=4.5) as resp:
                raw = resp.read().decode('utf-8')
            obj = json.loads(raw)
            choices = (obj or {}).get('choices') or []
            msg = (choices[0] or {}).get('message') or {} if choices else {}
            content = (msg.get('content') or '').strip()
            return content[:700] if content else None
        except Exception:
            return None

    return None


def _llm_extract_cached(st: ConversationState, text: str) -> dict:
    if st is None:
        return _llm_extract(text)
    t = (text or '').strip()
    if st.llm_last_text == t and isinstance(st.llm_last_extract, dict):
        return st.llm_last_extract
    out = _llm_extract(t)
    st.llm_last_text = t
    st.llm_last_extract = out if isinstance(out, dict) else {}
    return st.llm_last_extract


def _llm_rewrite_prompt(user_text: str, draft_reply: str) -> str:
    return "\n".join([
        'Rewrite the assistant reply into a semi-formal, polite message for a ride-sharing app chatbot.',
        'Requirements:',
        '- Keep ALL ids/numbers/times/dates exactly as-is (e.g., route_id, trip_id, booking_id, vehicle_id, 00:00).',
        '- Keep lists and line breaks. Do not remove important fields.',
        "- If the draft asks to reply 'yes' or 'no', keep the words yes/no exactly.",
        '- Do not mention internal APIs, code, or that an LLM is being used.',
        '- Output ONLY the rewritten reply text.',
        '',
        f'User: {user_text}',
        f'Draft reply: {draft_reply}',
    ])


def _llm_rewrite_reply(st: ConversationState, user_text: str, draft_reply: str) -> Optional[str]:
    if not _llm_chat_enabled():
        return None
    draft = (draft_reply or '').strip()
    if not draft:
        return None

    prov = _llm_provider()
    prompt = _llm_rewrite_prompt(user_text or '', draft)

    if prov == 'ollama':
        try:
            payload = {
                'model': _ollama_model(),
                'messages': [
                    {'role': 'system', 'content': 'You rewrite text safely and preserve structured values.'},
                    {'role': 'user', 'content': prompt},
                ],
                'stream': False,
            }
            req = urllib.request.Request(
                'http://localhost:11434/api/chat',
                data=json.dumps(payload).encode('utf-8'),
                headers={'Content-Type': 'application/json'},
                method='POST',
            )
            with urllib.request.urlopen(req, timeout=3.5) as resp:
                raw = resp.read().decode('utf-8')
            obj = json.loads(raw)
            content = (((obj or {}).get('message') or {}).get('content') or '').strip()
            return content[:900] if content else None
        except Exception:
            return None

    if prov == 'openai_compat':
        base = _llm_base_url()
        if not base:
            return None
        try:
            url = base + '/chat/completions'
            headers = {'Content-Type': 'application/json'}
            key = _llm_api_key()
            if key:
                headers['Authorization'] = f'Bearer {key}'
            payload = {
                'model': _cloud_model(),
                'messages': [
                    {'role': 'system', 'content': 'You rewrite text safely and preserve structured values.'},
                    {'role': 'user', 'content': prompt},
                ],
                'temperature': 0.4,
            }
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode('utf-8'),
                headers=headers,
                method='POST',
            )
            with urllib.request.urlopen(req, timeout=4.5) as resp:
                raw = resp.read().decode('utf-8')
            obj = json.loads(raw)
            choices = (obj or {}).get('choices') or []
            msg = (choices[0] or {}).get('message') or {} if choices else {}
            content = (msg.get('content') or '').strip()
            return content[:900] if content else None
        except Exception:
            return None

    return None


def _map_llm_intent(val: Any) -> Optional[str]:
    s = _normalize_text(str(val or ''))
    if not s:
        return None
    if s in {'book_ride', 'book', 'booking', 'reserve', 'reserve_ride'}:
        return 'book_ride'
    if s in {'create_ride', 'create', 'post_ride', 'post', 'ride_posting'}:
        return 'create_ride'
    if s in {'message', 'send_message', 'chat', 'chat_send'}:
        return 'message'
    if s in {'negotiate', 'negotiation'}:
        return 'negotiate'
    if s in {'cancel_booking', 'cancel', 'cancel ride', 'cancel booking'}:
        return 'cancel_booking'
    return None


def _llm_route_fallback(st: ConversationState, text: str) -> Optional[str]:
    llm = _llm_extract_cached(st, text)
    if not isinstance(llm, dict) or not llm:
        return None

    inferred = _map_llm_intent(llm.get('intent'))
    if inferred == 'book_ride':
        st.active_flow = 'book_ride'
        st.awaiting_field = None
        _update_booking_from_text(st, text)
        return _continue_booking_flow(st, text)

    if inferred == 'create_ride':
        st.active_flow = 'create_ride'
        st.awaiting_field = None
        _update_create_from_text(st, text)
        return _continue_create_flow(st, text) or "Okay. Let's create a ride. Which route are you driving?"

    if inferred == 'message':
        st.active_flow = 'message'
        st.awaiting_field = None
        _update_message_from_text(st, text)
        return _continue_message_flow(st, text) or "Okay. Let's send a message."

    if inferred == 'negotiate':
        st.active_flow = 'negotiate'
        st.awaiting_field = None
        st.negotiate = NegotiateDraft(trip_id=st.last_trip_id, booking_id=st.last_booking_id)
        return _continue_negotiate_flow(st, text)

    if inferred == 'cancel_booking':
        st.active_flow = 'cancel_booking'
        st.cancel_booking.booking_id = _extract_booking_id(text) or st.last_booking_id
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

    return None


def _extract_coord_pairs(text: str) -> list[tuple[float, float]]:
    low = (text or '').lower()
    out: list[tuple[float, float]] = []

    mlat = re.search(r"\b(?:lat|latitude)\b\s*[:=]?\s*(-?\d+(?:\.\d+)?)", low)
    mlon = re.search(r"\b(?:lon|lng|longitude)\b\s*[:=]?\s*(-?\d+(?:\.\d+)?)", low)
    if mlat and mlon:
        try:
            lat = float(mlat.group(1))
            lon = float(mlon.group(1))
            if -90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0:
                out.append((lat, lon))
        except Exception:
            pass

    pairs = re.findall(r"(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)", low)
    for a, b in pairs:
        try:
            lat = float(a)
            lon = float(b)
        except Exception:
            continue
        if -90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0:
            out.append((lat, lon))

    seen = set()
    deduped: list[tuple[float, float]] = []
    for lat, lon in out:
        key = (round(lat, 6), round(lon, 6))
        if key in seen:
            continue
        seen.add(key)
        deduped.append((lat, lon))
    return deduped


def _load_stops_geo() -> list[dict]:
    global _STOPS_GEO_CACHE
    if _STOPS_GEO_CACHE is not None:
        return _STOPS_GEO_CACHE
    path = STOPS_GEO_JSON
    if not path:
        _STOPS_GEO_CACHE = []
        return _STOPS_GEO_CACHE
    try:
        with open(path, 'r', encoding='utf-8') as f:
            obj = json.load(f)
        if isinstance(obj, dict) and isinstance(obj.get('stops'), list):
            _STOPS_GEO_CACHE = obj.get('stops')
        elif isinstance(obj, list):
            _STOPS_GEO_CACHE = obj
        else:
            _STOPS_GEO_CACHE = []
        return _STOPS_GEO_CACHE
    except Exception:
        _STOPS_GEO_CACHE = []
        return _STOPS_GEO_CACHE


def _load_routes_json() -> list[dict]:
    global _ROUTES_CACHE
    if _ROUTES_CACHE is not None:
        return _ROUTES_CACHE
    path = ROUTES_JSON
    if not path:
        _ROUTES_CACHE = []
        return _ROUTES_CACHE
    try:
        with open(path, 'r', encoding='utf-8') as f:
            obj = json.load(f)
        if isinstance(obj, dict) and isinstance(obj.get('routes'), list):
            _ROUTES_CACHE = obj.get('routes')
        elif isinstance(obj, list):
            _ROUTES_CACHE = obj
        else:
            _ROUTES_CACHE = []
        return _ROUTES_CACHE
    except Exception:
        _ROUTES_CACHE = []
        return _ROUTES_CACHE


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = (math.sin(dp / 2) ** 2) + math.cos(p1) * math.cos(p2) * (math.sin(dl / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return r * c


def _nearest_stop_name(lat: float, lon: float) -> Optional[str]:
    stops = _load_stops_geo()
    if not stops:
        return None
    best_name: Optional[str] = None
    best_d = None
    for s in stops:
        if not isinstance(s, dict):
            continue
        name = (s.get('name') or s.get('stop_name') or s.get('title') or '').strip()
        try:
            slat = float(s.get('lat') if s.get('lat') is not None else s.get('latitude'))
            slon = float(s.get('lon') if s.get('lon') is not None else (s.get('lng') if s.get('lng') is not None else s.get('longitude')))
        except Exception:
            continue
        if not name:
            continue
        d = _haversine_km(lat, lon, slat, slon)
        if best_d is None or d < best_d:
            best_d = d
            best_name = name
    return best_name


def _parse_json_block(text: str) -> Optional[dict]:
    if not text:
        return None
    m = re.search(r"\{.*\}", text, flags=re.DOTALL)
    if not m:
        return None
    try:
        val = json.loads(m.group(0))
    except Exception:
        return None
    return val if isinstance(val, dict) else None


def _extract_rating(text: str) -> Optional[float]:
    m = re.search(r"\b([1-5](?:\.0)?)\s*(?:star|stars|rating)\b", text or '', flags=re.IGNORECASE)
    if m:
        try:
            return float(m.group(1))
        except Exception:
            return None
    return None


def _parse_rating_value(text: str) -> Optional[float]:
    r = _extract_rating(text)
    if r is not None:
        return r
    try:
        v = float(str(text or '').strip())
    except Exception:
        return None
    if 1.0 <= v <= 5.0:
        return v
    return None


def _blocked_system_request(text: str) -> Optional[str]:
    low = _normalize_text(text)
    blocked_terms = [
        'verify', 'verification', 'approve', 'admin',
        'send otp', 'otp', 'reset password',
        'fcm', 'token',
        'start ride', 'complete ride',
        'update location', 'live location',
        'pickup code',
        'broadcast',
        'sos',
        'share link', 'share token',
        'ban user', 'unban',
    ]
    for term in blocked_terms:
        if term in low:
            return "I can't do that directly here. Please use the app's official screens/support flow (or contact an admin) for this action."
    return None


def _to_int(value) -> Optional[int]:
    try:
        if value is None:
            return None
        if isinstance(value, bool):
            return None
        return int(value)
    except Exception:
        return None


def _parse_date(text: str) -> Optional[date]:
    t = _normalize_text(text)
    if not t:
        return None
    if 'today' in t:
        return date.today()
    if 'tomorrow' in t:
        return date.today() + timedelta(days=1)
    m = re.search(r"\b(\d{4}-\d{2}-\d{2})\b", t)
    if m:
        try:
            return datetime.strptime(m.group(1), '%Y-%m-%d').date()
        except Exception:
            return None
    return None


def _parse_time_str(text: str) -> Optional[str]:
    t = _normalize_text(text)
    if not t:
        return None
    m = re.search(r"\b(\d{1,2}):(\d{2})\b", t)
    if m:
        hh = int(m.group(1))
        mm = int(m.group(2))
        if 0 <= hh <= 23 and 0 <= mm <= 59:
            return f"{hh:02d}:{mm:02d}"
        return None
    m = re.search(r"\b(\d{1,2})\s*(am|pm)\b", t)
    if m:
        hh = int(m.group(1))
        ampm = m.group(2)
        if hh == 12:
            hh = 0
        if ampm == 'pm':
            hh += 12
        if 0 <= hh <= 23:
            return f"{hh:02d}:00"
    return None


def _extract_from_to(text: str) -> tuple[Optional[str], Optional[str]]:
    t = (text or '').strip()
    if not t:
        return None, None

    m = re.search(r"\bfrom\s+(.+?)\s+to\s+(.+?)(?:\s+at\b|\s+on\b|\s+today\b|\s+tomorrow\b|$)", t, flags=re.IGNORECASE)
    if m:
        return m.group(1).strip(' ,.'), m.group(2).strip(' ,.')

    m = re.search(r"\bpick(?:up)?\s+(.+?)\s+drop(?:off)?\s+(.+?)(?:\s+at\b|\s+on\b|\s+today\b|\s+tomorrow\b|$)", t, flags=re.IGNORECASE)
    if m:
        return m.group(1).strip(' ,.'), m.group(2).strip(' ,.')

    return None, None


def _extract_seats(text: str) -> Optional[int]:
    m = re.search(r"\b(\d{1,2})\s*(?:seat|seats)\b", text or '', flags=re.IGNORECASE)
    if m:
        v = _to_int(m.group(1))
        if v and v > 0:
            return v
    return None


def _extract_fare(text: str) -> Optional[int]:
    m = re.search(r"\b(?:for|fare|price)\s*[:=]?\s*([0-9]{2,6})\b", text or '', flags=re.IGNORECASE)
    if m:
        return _to_int(m.group(1))
    return None


def _llm_provider() -> str:
    prov = (os.environ.get('LLM_PROVIDER') or '').strip().lower()
    if prov:
        return prov
    if (os.environ.get('USE_OLLAMA') or '').strip().lower() in {'1', 'true', 'yes'}:
        return 'ollama'
    # If you provided a base URL or API key (or you kept the defaults), enable openai_compat.
    if (os.environ.get('LLM_BASE_URL') or '').strip() or (os.environ.get('LLM_API_KEY') or '').strip():
        return 'openai_compat'
    if _llm_base_url() and _llm_api_key():
        return 'openai_compat'
    return 'none'


def _llm_model() -> str:
    return (os.environ.get('LLM_MODEL') or '').strip()


def _cloud_model() -> str:
    return (os.environ.get('LLM_MODEL') or 'llama-3.3-70b-versatile').strip() or 'llama-3.3-70b-versatile'


def _ollama_model() -> str:
    return (os.environ.get('OLLAMA_MODEL') or 'llama3.2').strip() or 'llama3.2'


def _llm_base_url() -> str:
    return (os.environ.get('LLM_BASE_URL') or 'https://api.groq.com/openai/v1').strip().rstrip('/')



def _llm_api_key() -> str:
    # return (os.environ.get('LLM_API_KEY') or '').strip()

    return (os.environ.get('LLM_API_KEY') or '').strip()



def _llm_extract_prompt(text: str) -> str:
    return (
        "Extract fields from the user message. Return STRICT JSON only. "
        "Use keys: intent, from_stop, to_stop, date, time, seats, fare, trip_id, recipient_id, message_text, action, booking_id, counter_fare, "
        "vehicle_id, route_id, route_name, total_seats, custom_price, gender_preference. "
        "intent must be one of: book_ride, create_ride, message, negotiate, cancel_booking, list_vehicles, list_my_rides, list_bookings, profile_view, profile_update, help, greet, capabilities. "
        "date must be YYYY-MM-DD if present, time must be HH:MM 24h if present. "
        "If unknown, omit the key.\n\nUser: " + (text or '')
    )


def _ollama_extract(text: str) -> dict:
    try:
        payload = {
            'model': _ollama_model(),
            'messages': [
                {'role': 'system', 'content': 'You are a strict information extraction engine.'},
                {'role': 'user', 'content': _llm_extract_prompt(text)},
            ],
            'stream': False,
        }
        req = urllib.request.Request(
            'http://localhost:11434/api/chat',
            data=json.dumps(payload).encode('utf-8'),
            headers={'Content-Type': 'application/json'},
            method='POST',
        )
        with urllib.request.urlopen(req, timeout=2.5) as resp:
            raw = resp.read().decode('utf-8')
        obj = json.loads(raw)
        content = (((obj or {}).get('message') or {}).get('content') or '').strip()
        out = _parse_json_block(content) or {}
        return out if isinstance(out, dict) else {}
    except Exception:
        return {}


def _openai_compat_extract(text: str) -> dict:
    base = _llm_base_url()
    if not base:
        return {}
    try:
        url = base + '/chat/completions'
        headers = {'Content-Type': 'application/json'}
        key = _llm_api_key()
        if key:
            headers['Authorization'] = f'Bearer {key}'
        payload = {
            'model': _cloud_model(),
            'messages': [
                {'role': 'system', 'content': 'You are a strict information extraction engine.'},
                {'role': 'user', 'content': _llm_extract_prompt(text)},
            ],
            'temperature': 0,
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode('utf-8'),
            headers=headers,
            method='POST',
        )
        with urllib.request.urlopen(req, timeout=3.5) as resp:
            raw = resp.read().decode('utf-8')
        obj = json.loads(raw)
        choices = (obj or {}).get('choices') or []
        msg = (choices[0] or {}).get('message') or {} if choices else {}
        content = (msg.get('content') or '').strip()
        out = _parse_json_block(content) or {}
        return out if isinstance(out, dict) else {}
    except Exception:
        return {}


def _llm_extract(text: str) -> dict:
    prov = _llm_provider()

    if prov == 'openai_compat':
        out = _openai_compat_extract(text)
        if out:
            return out
        if (os.environ.get('USE_OLLAMA') or '').strip().lower() in {'1', 'true', 'yes'}:
            return _ollama_extract(text)
        return {}

    if prov == 'ollama':
        return _ollama_extract(text)

    return {}


def _call_view(method: str, path: str, *, body: Optional[dict] = None, query: Optional[dict] = None):
    method = (method or 'GET').upper()
    status, content, ok = _http_call_json(method, LETS_GO_API_BASE_URL, path, body=body, query=query)
    if ok:
        return status, content
    return 0, {'success': False, 'error': 'Failed to reach API server'}


def _call_view_form(method: str, path: str, *, data: Optional[dict] = None, query: Optional[dict] = None):
    method = (method or 'POST').upper()
    status, content, ok = _http_call_form(method, LETS_GO_API_BASE_URL, path, data=data, query=query)
    if ok:
        return status, content
    return 0, {'success': False, 'error': 'Failed to reach API server'}


def _http_call_json(method: str, base_url: str, path: str, *, body: Optional[dict], query: Optional[dict]) -> tuple[int, Any, bool]:
    try:
        url = urllib.parse.urljoin(base_url.rstrip('/') + '/', path.lstrip('/'))
        if query:
            qs = urllib.parse.urlencode({k: v for k, v in (query or {}).items() if v is not None}, doseq=True)
            if qs:
                url = url + ('&' if '?' in url else '?') + qs

        data_bytes = None
        headers = {
            'Accept': 'application/json',
        }
        if method in {'POST', 'PUT', 'PATCH', 'DELETE'}:
            headers['Content-Type'] = 'application/json'
            data_bytes = json.dumps(body or {}).encode('utf-8')

        req = urllib.request.Request(url, data=data_bytes, headers=headers, method=method)
        with _HTTP_OPENER.open(req, timeout=12) as resp:
            raw = resp.read()
            status = getattr(resp, 'status', None) or resp.getcode()
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        return int(status or 0), parsed, True
    except urllib.error.HTTPError as e:
        try:
            raw = e.read()
        except Exception:
            raw = b''
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        return int(getattr(e, 'code', 500) or 500), parsed, True
    except Exception:
        return 0, None, False


def _http_call_form(method: str, base_url: str, path: str, *, data: Optional[dict], query: Optional[dict]) -> tuple[int, Any, bool]:
    try:
        url = urllib.parse.urljoin(base_url.rstrip('/') + '/', path.lstrip('/'))
        if query:
            qs = urllib.parse.urlencode({k: v for k, v in (query or {}).items() if v is not None}, doseq=True)
            if qs:
                url = url + ('&' if '?' in url else '?') + qs

        headers = {
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
        }
        payload = urllib.parse.urlencode({k: v for k, v in (data or {}).items() if v is not None}, doseq=True).encode('utf-8')
        req = urllib.request.Request(url, data=payload, headers=headers, method=method)
        with _HTTP_OPENER.open(req, timeout=12) as resp:
            raw = resp.read()
            status = getattr(resp, 'status', None) or resp.getcode()
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        return int(status or 0), parsed, True
    except urllib.error.HTTPError as e:
        try:
            raw = e.read()
        except Exception:
            raw = b''
        text = raw.decode('utf-8', errors='ignore') if raw else ''
        try:
            parsed = json.loads(text) if text else None
        except Exception:
            parsed = text
        return int(getattr(e, 'code', 500) or 500), parsed, True
    except Exception:
        return 0, None, False


def api_login(email: str, password: str) -> tuple[Optional[dict], Optional[str]]:
    status, out = _call_view_form('POST', '/lets_go/login/', data={'email': email, 'password': password})
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
    return _call_view('GET', f'/lets_go/users/{int(user_id)}/')


def _require_user(ctx: BotContext) -> tuple[Optional[dict], Optional[str]]:
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
    return _call_view('GET', f'/lets_go/users/{int(ctx.user_id)}/vehicles/')


def _list_user_vehicles(ctx: BotContext, *, limit: int = 20) -> str:
    status, out = api_list_my_vehicles(ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    vehicles = []
    if isinstance(out, dict):
        vehicles = out.get('vehicles') or []
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


def api_list_my_rides(ctx: BotContext, *, limit: int = 50) -> tuple[int, Any]:
    return _call_view('GET', f'/lets_go/users/{int(ctx.user_id)}/rides/', query={'mode': 'summary', 'limit': int(limit), 'offset': 0})


def api_search_routes(*, from_location: Optional[str], to_location: Optional[str]) -> tuple[int, Any]:
    return _call_view(
        'GET',
        '/lets_go/routes/search/',
        query={
            'from': (from_location or '').strip() or None,
            'to': (to_location or '').strip() or None,
        },
    )


def api_suggest_stops(*, q: str, limit: int = 8, lat: Optional[float] = None, lng: Optional[float] = None) -> tuple[int, Any]:
    query: dict[str, Any] = {'q': (q or '').strip(), 'limit': int(limit)}
    if lat is not None and lng is not None:
        query['lat'] = float(lat)
        query['lng'] = float(lng)
    return _call_view('GET', '/lets_go/stops/suggest/', query=query)


def _render_route_choice(routes: list[dict]) -> str:
    lines = ['I found multiple matching routes. Please reply with the number you want:']
    for i, r in enumerate(routes, start=1):
        if not isinstance(r, dict):
            continue
        lines.append(f"{i}) route_id={r.get('id')} | {r.get('name')}")
    lines.append("You can also say 'cancel' to stop.")
    return "\n".join(lines)


def _looks_like_route_id(val: Optional[str]) -> bool:
    v = (val or '').strip()
    if not v:
        return False
    # Backend route ids are strings like: R001 or R7E97D377 / RC317BEAF
    return bool(re.fullmatch(r"R[0-9A-Z]{2,12}", v, flags=re.IGNORECASE))


def _contains_abuse(text: str) -> bool:
    low = _normalize_text(text)
    bad = [
        'fuck', 'fucking', 'bitch', 'asshole', 'bastard', 'chutiya', 'madarchod', 'behenchod',
    ]
    return any(w in low for w in bad)


def _routes_from_stop_suggestions(from_q: str, to_q: str) -> list[dict]:
    s1, out1 = api_suggest_stops(q=from_q or '', limit=10)
    s2, out2 = api_suggest_stops(q=to_q or '', limit=10)
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
        routes.append({
            'id': rid,
            'name': (a.get('name') or b.get('name') or rid),
            '_score': float(a.get('_score') or 0.0) + float(b.get('_score') or 0.0),
        })
    routes.sort(key=lambda x: -float(x.get('_score') or 0.0))
    for r in routes:
        r.pop('_score', None)
    return routes[:8]


def _routes_from_local_json(from_q: str, to_q: str) -> list[dict]:
    routes = _load_routes_json()
    if not routes:
        return []
    fq = _normalize_text(from_q)
    tq = _normalize_text(to_q)
    scored: list[tuple[float, dict]] = []
    for r in routes:
        if not isinstance(r, dict):
            continue
        rid = str(r.get('id') or r.get('route_id') or '').strip()
        name = str(r.get('name') or r.get('route_name') or '').strip()
        stops = r.get('stops') or r.get('route_stops') or []
        if not rid or not isinstance(stops, list) or not stops:
            continue
        stops_norm = [_normalize_text(str(s or '')) for s in stops if str(s or '').strip()]
        if not stops_norm:
            continue
        best_f = max([difflib.SequenceMatcher(a=fq, b=s).ratio() for s in stops_norm] or [0.0])
        best_t = max([difflib.SequenceMatcher(a=tq, b=s).ratio() for s in stops_norm] or [0.0])
        score = min(best_f, best_t)
        if score < 0.55:
            continue
        scored.append((float(score), {'id': rid, 'name': name or rid}))
    scored.sort(key=lambda x: -x[0])
    return [r for _, r in scored[:8]]


def _resolve_route_from_text(st: ConversationState, raw: str) -> Optional[str]:
    d = st.create_ride
    t = (raw or '').strip()
    if not t:
        return None

    if _contains_abuse(t):
        return "I want to help, but please keep it respectful. Tell me the pickup and drop-off stops like: 'Quaid-e-Azam Park to Fasal Town'."

    m = re.search(r"\b(R[0-9A-Z]{2,12})\b", t, flags=re.IGNORECASE)
    if m:
        d.route_id = m.group(1).upper()
        d.route_name = None
        d.route_candidates = None
        return None

    llm = _llm_extract_cached(st, t)
    if isinstance(llm, dict):
        if llm.get('route_id') and _looks_like_route_id(str(llm.get('route_id')).strip()):
            d.route_id = str(llm.get('route_id')).strip().upper()
            d.route_name = None
            d.route_candidates = None
            return None

    frm, to = _extract_from_to(t)
    if isinstance(llm, dict):
        if llm.get('from_stop') and not frm:
            frm = str(llm.get('from_stop')).strip() or frm
        if llm.get('to_stop') and not to:
            to = str(llm.get('to_stop')).strip() or to
    if not frm and not to:
        m2 = re.search(r"^(.+?)\s+to\s+(.+)$", t, flags=re.IGNORECASE)
        if m2:
            frm = (m2.group(1) or '').strip(' ,.-') or None
            to = (m2.group(2) or '').strip(' ,.-') or None

    if not frm and not to:
        pairs = _extract_coord_pairs(t)
        if pairs:
            if len(pairs) >= 2:
                frm = _nearest_stop_name(pairs[0][0], pairs[0][1]) or frm
                to = _nearest_stop_name(pairs[1][0], pairs[1][1]) or to
            else:
                frm = _nearest_stop_name(pairs[0][0], pairs[0][1]) or frm
    # Don't hit route search unless we have BOTH from and to; otherwise random sentences become route searches.
    if not frm or not to:
        llm_reply = _llm_chat_reply(st, t)
        if llm_reply:
            return llm_reply
        return "Tell me the route using two stop names, like: 'Quaid-e-Azam Park to Fasal Town'."

    status, out = api_search_routes(from_location=frm, to_location=to)
    routes = (out.get('routes') if isinstance(out, dict) else None) or []
    if status <= 0:
        return 'API server not reachable.'
    if not isinstance(routes, list) or not routes:
        # Try deriving routes from stop suggestions (DB) and then optional local JSON fallback.
        derived = _routes_from_stop_suggestions(frm, to)
        if not derived:
            derived = _routes_from_local_json(frm, to)
        if derived:
            raw_norm = _normalize_text(t)
            scored: list[tuple[float, dict]] = []
            for r in derived:
                if not isinstance(r, dict):
                    continue
                name = str(r.get('name') or '')
                rid = str(r.get('id') or '')
                score = max(
                    difflib.SequenceMatcher(a=raw_norm, b=_normalize_text(name)).ratio(),
                    difflib.SequenceMatcher(a=raw_norm, b=_normalize_text(rid)).ratio(),
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
            return _render_route_choice(d.route_candidates)

        d.route_id = None
        d.route_name = t
        d.route_candidates = None
        llm_reply = _llm_chat_reply(st, f"User couldn't find route for: from={frm} to={to}. Help them rephrase with correct stop names.")
        return llm_reply or "I couldn't find that route in the system. Try slightly different stop names (or tell me nearby landmarks), like: 'Vehari Quaid-e-Azam Park to Vehari Fasal Town'."

    if len(routes) == 1:
        r0 = routes[0]
        if isinstance(r0, dict):
            d.route_id = str(r0.get('id') or '').strip() or d.route_id
            d.route_name = str(r0.get('name') or '').strip() or None
            d.route_candidates = None
        return None

    raw_norm = _normalize_text(t)
    scored: list[tuple[float, dict]] = []
    for r in routes:
        if not isinstance(r, dict):
            continue
        name = str(r.get('name') or '')
        rid = str(r.get('id') or '')
        score = max(
            difflib.SequenceMatcher(a=raw_norm, b=_normalize_text(name)).ratio(),
            difflib.SequenceMatcher(a=raw_norm, b=_normalize_text(rid)).ratio(),
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
    return _render_route_choice(d.route_candidates)


def _api_trip_driver_id(trip_id: str) -> Optional[int]:
    status, detail = _call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
    if status <= 0 or not isinstance(detail, dict):
        return None
    try:
        return _to_int(((detail.get('trip') or {}).get('driver') or {}).get('id'))
    except Exception:
        return None


def _api_trip_base_fare(trip_id: str) -> int:
    status, detail = _call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
    if status <= 0 or not isinstance(detail, dict):
        return 0
    try:
        return int(((detail.get('trip') or {}).get('base_fare') or 0) or 0)
    except Exception:
        return 0


def _list_user_created_trips(ctx: BotContext, *, limit: int = 20) -> str:
    status, out = api_list_my_rides(ctx, limit=limit)
    if status <= 0:
        return 'API server not reachable.'
    rides = []
    if isinstance(out, dict):
        rides = out.get('rides') or []
    if not isinstance(rides, list) or not rides:
        return "I couldn't find any rides/trips created by you."

    lines = ['Here are your created rides:']
    for r in rides[:limit]:
        if not isinstance(r, dict):
            continue
        lines.append(
            f"- trip_id={r.get('trip_id')} | {r.get('from_location', '')} -> {r.get('to_location', '')} | {r.get('trip_date', '')} {r.get('departure_time', '')} | status={r.get('status', '')}"
        )
    return "\n".join(lines)


def _get_state(user_id: int) -> ConversationState:
    st = _SESSIONS.get(int(user_id))
    if st is not None:
        return st
    ctx = BotContext(user_id=int(user_id))
    st = ConversationState(ctx=ctx)
    st.user_name = str(_CURRENT_USER.get('name') or '').strip()
    _SESSIONS[int(user_id)] = st
    return st


def _reset_flow(st: ConversationState):
    st.active_flow = None
    st.awaiting_field = None
    st.pending_action = None
    st.booking = BookingDraft()
    st.create_ride = CreateRideDraft()
    st.message = MessageDraft()
    st.negotiate = NegotiateDraft()
    st.cancel_booking = CancelBookingDraft()
    st.profile = ProfileDraft()
    st.payment = PaymentDraft()


def _parse_yes_no(text: str) -> Optional[bool]:
    low = _normalize_text(text)
    if low in {'yes', 'y', 'confirm', 'ok', 'okay'}:
        return True
    if low in {'no', 'n'}:
        return False
    return None


def _parse_action(text: str) -> Optional[str]:
    low = _normalize_text(text)
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


def _extract_booking_id(text: str) -> Optional[int]:
    m = re.search(r"\bbooking[_\s-]*id\s*[:=]\s*(\d+)\b", text or '', flags=re.IGNORECASE)
    if m:
        return _to_int(m.group(1))
    m = re.search(r"\bbooking\s+(\d+)\b", text or '', flags=re.IGNORECASE)
    if m:
        return _to_int(m.group(1))
    return None


def _continue_booking_flow(st: ConversationState, text: str) -> Optional[str]:
    if st.active_flow != 'book_ride':
        return None

    if st.awaiting_field == 'from_stop' and text:
        st.booking.from_stop_raw = text.strip()
        st.awaiting_field = None
    elif st.awaiting_field == 'to_stop' and text:
        st.booking.to_stop_raw = text.strip()
        st.awaiting_field = None
    elif st.awaiting_field == 'date':
        st.booking.trip_date = _parse_date(text) or st.booking.trip_date
        st.awaiting_field = None
    elif st.awaiting_field == 'time':
        st.booking.departure_time = _parse_time_str(text) or st.booking.departure_time
        st.awaiting_field = None
    elif st.awaiting_field == 'seats':
        st.booking.number_of_seats = _to_int(text) or _extract_seats(text) or st.booking.number_of_seats
        st.awaiting_field = None
    elif st.awaiting_field == 'fare':
        st.booking.proposed_fare = _to_int(text) or _extract_fare(text) or st.booking.proposed_fare
        st.awaiting_field = None
    else:
        _update_booking_from_text(st, text)

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

    candidates = _find_trip_candidates(st.booking)
    if not candidates:
        st.awaiting_field = None
        return 'I could not find a matching scheduled trip. Try a different time/date or specify a trip_id.'

    if len(candidates) > 1:
        st.booking.candidates = candidates
        st.active_flow = 'choose_trip'
        st.awaiting_field = None
        return _render_trip_choice(candidates)

    chosen = candidates[0]
    st.booking.candidates = candidates
    st.booking.selected_trip_id = chosen.get('trip_id')
    st.booking.selected_from_stop_order = chosen.get('from_stop_order')
    st.booking.selected_to_stop_order = chosen.get('to_stop_order')
    st.booking.selected_from_stop_name = chosen.get('from_stop_name')
    st.booking.selected_to_stop_name = chosen.get('to_stop_name')
    st.active_flow = 'confirm_booking'
    st.pending_action = {'type': 'book_ride'}
    st.awaiting_field = None
    return _render_booking_summary(st)


def _continue_create_flow(st: ConversationState, text: str) -> Optional[str]:
    if st.active_flow != 'create_ride':
        return None

    d = st.create_ride
    if st.awaiting_field == 'route_id' and text:
        msg = _resolve_route_from_text(st, text)
        if msg:
            return msg
        if st.active_flow == 'choose_route':
            return None
        if not _looks_like_route_id(d.route_id):
            d.route_name = (text or '').strip() or d.route_name
            d.route_id = None
            st.awaiting_field = 'route_id'
            return 'Please provide a valid route_id (e.g., R001), or describe the route as "FROM ... to ...".'
        st.awaiting_field = None
    elif st.awaiting_field == 'vehicle_id':
        low = _normalize_text(text)
        if any(p in low for p in ['dont remember', "don't remember", 'do not remember', 'what vehicle', 'my vehicle', 'which vehicle', 'list vehicle', 'show vehicle']):
            return _list_user_vehicles(st.ctx)
        picked = _to_int(text)
        if picked is None:
            # Allow selecting by plate number (e.g., "use ADU-6312").
            s, out = api_list_my_vehicles(st.ctx)
            vehicles = (out.get('vehicles') if isinstance(out, dict) else None) or []
            if s > 0 and isinstance(vehicles, list):
                matches = []
                raw = (text or '').strip()
                raw_norm = _normalize_text(raw)
                for v in vehicles:
                    if not isinstance(v, dict):
                        continue
                    plate = str(v.get('plate_number') or '').strip()
                    plate_norm = _normalize_text(plate)
                    if plate and (plate in raw or (plate_norm and plate_norm in raw_norm)):
                        matches.append(v)
                if len(matches) == 1:
                    picked = _to_int(matches[0].get('id'))
        d.vehicle_id = picked or d.vehicle_id
        st.awaiting_field = None
    elif st.awaiting_field == 'trip_date':
        d.trip_date = _parse_date(text) or d.trip_date
        if not d.departure_time:
            d.departure_time = _parse_time_str(text) or d.departure_time
        st.awaiting_field = None
    elif st.awaiting_field == 'departure_time':
        d.departure_time = _parse_time_str(text) or d.departure_time
        st.awaiting_field = None
    elif st.awaiting_field == 'total_seats':
        d.total_seats = _to_int(text) or _extract_seats(text) or d.total_seats
        st.awaiting_field = None
    elif st.awaiting_field == 'custom_price':
        d.custom_price = _to_int(text) or _extract_fare(text) or d.custom_price
        st.awaiting_field = None
    else:
        _update_create_from_text(st, text)

    if not d.route_id:
        st.awaiting_field = 'route_id'
        return "Please tell me the route using stop names (e.g., 'Quaid-e-Azam Park to Fasal Town'). If you know the route_id you can also type it (e.g., R001)."
    if not d.vehicle_id:
        st.awaiting_field = 'vehicle_id'
        return 'What is the vehicle_id you want to use?'
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
        return 'What is the base fare per seat (custom_price)?'

    st.active_flow = 'confirm_create'
    st.pending_action = {'type': 'create_ride'}
    st.awaiting_field = None
    return _render_create_summary(st)


def _continue_message_flow(st: ConversationState, text: str) -> Optional[str]:
    if st.active_flow != 'message':
        return None

    d = st.message
    if st.awaiting_field == 'trip_id':
        d.trip_id = (text or '').strip() or d.trip_id
        st.awaiting_field = None
    elif st.awaiting_field == 'recipient_id':
        d.recipient_id = _to_int(text) or d.recipient_id
        st.awaiting_field = None
    elif st.awaiting_field == 'message_text':
        d.message_text = (text or '').strip() or d.message_text
        st.awaiting_field = None
    else:
        _update_message_from_text(st, text)

    d.trip_id = d.trip_id or st.last_trip_id
    if not d.trip_id:
        st.awaiting_field = 'trip_id'
        return 'Which trip? Please provide trip_id.'

    if d.recipient_id is None:
        driver_id = _api_trip_driver_id(str(d.trip_id))
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


def _continue_negotiate_flow(st: ConversationState, text: str) -> Optional[str]:
    if st.active_flow != 'negotiate':
        return None

    d = st.negotiate
    d.trip_id = d.trip_id or _extract_trip_id(text) or st.last_trip_id
    d.booking_id = d.booking_id or _extract_booking_id(text) or st.last_booking_id
    d.action = d.action or _parse_action(text)
    if d.counter_fare is None:
        d.counter_fare = _extract_fare(text)
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
        return "What do you want to do? (accept / reject / counter / withdraw)"
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


def _parse_kb_message(message_text: str) -> Optional[dict]:
    t = (message_text or '').strip()
    if not t:
        return None
    if t.startswith('{') and t.endswith('}'):
        try:
            obj = json.loads(t)
            if isinstance(obj, dict) and obj.get('type') in {'faq', 'rule'}:
                return obj
        except Exception:
            return None
    m = re.match(r"^(faq|rule)\s*:\s*(.+?)\s*\|\|\s*(.+)$", t, flags=re.IGNORECASE)
    if m:
        return {
            'type': m.group(1).strip().lower(),
            'q': m.group(2).strip(),
            'a': m.group(3).strip(),
        }
    return None


def search_kb(query: str, *, limit: int = 400) -> Optional[str]:
    return None


def _fallback_business_rules_answer(text: str) -> Optional[str]:
    low = _normalize_text(text)
    if 'chat' in low and ('allowed' in low or 'can i' in low):
        return 'Chat is allowed only for active bookings (confirmed/accepted/booked) on the trip.'
    if 'create' in low and ('trip' in low or 'ride' in low):
        return 'To create a ride: your account must not be banned, your license/profile verification must be complete, and the selected vehicle must be verified.'
    if 'cancel' in low and 'booking' in low:
        return 'You can cancel a booking from your booking details. Some cases allow cancel during an in-progress ride (cancel on board).'
    if 'fare' in low or 'price' in low:
        return 'Fares are provided by the client calculation and stored per trip/booking; negotiation can happen per-seat.'
    return None


def create_ride(ctx: BotContext, payload: dict) -> tuple[int, Any]:
    user, err = _require_user(ctx)
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

    return _call_view('POST', '/lets_go/create_trip/', body=payload)


def book_ride(ctx: BotContext, trip_id: str, payload: dict) -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    passenger_id = payload.get('passenger_id') or ctx.user_id
    if int(passenger_id) != int(ctx.user_id):
        return 403, {'success': False, 'error': 'Not authorized: passenger_id must match your user_id.'}

    # Fetch driver id from booking details to prevent self-booking.
    status, detail = _call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
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

    return _call_view(
        'POST',
        f'/lets_go/ride-booking/{trip_id}/request/',
        body={**payload, 'passenger_id': passenger_id},
    )


def negotiate_driver(ctx: BotContext, trip_id: str, booking_id: int, payload: dict) -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    driver_id = payload.get('driver_id') or ctx.user_id
    if int(driver_id) != int(ctx.user_id):
        return 403, {'success': False, 'error': 'Not authorized: driver_id must match your user_id.'}

    # API-based check: ensure this trip belongs to driver's created rides
    status, rides_out = api_list_my_rides(ctx, limit=200)
    rides = (rides_out.get('rides') if isinstance(rides_out, dict) else None) or []
    if not any(isinstance(r, dict) and str(r.get('trip_id')) == str(trip_id) for r in rides):
        return 403, {'success': False, 'error': 'Not authorized: only the trip driver can respond.'}

    return _call_view(
        'POST',
        f'/lets_go/ride-booking/{trip_id}/requests/{booking_id}/respond/',
        body={**payload, 'driver_id': driver_id},
    )


def negotiate_passenger(ctx: BotContext, trip_id: str, booking_id: int, payload: dict) -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    passenger_id = payload.get('passenger_id') or ctx.user_id
    if int(passenger_id) != int(ctx.user_id):
        return 403, {'success': False, 'error': 'Not authorized: passenger_id must match your user_id.'}

    status, bookings_out = list_my_bookings(ctx, limit=200)
    bookings = (bookings_out.get('bookings') if isinstance(bookings_out, dict) else None) or []
    if not any(isinstance(b, dict) and int(b.get('id') or 0) == int(booking_id) for b in bookings):
        return 403, {'success': False, 'error': 'Not authorized: this booking does not belong to you.'}

    return _call_view(
        'POST',
        f'/lets_go/ride-booking/{trip_id}/requests/{booking_id}/passenger-respond/',
        body={**payload, 'passenger_id': passenger_id},
    )


def send_message(ctx: BotContext, trip_id: str, payload: dict) -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    sender_id = payload.get('sender_id') or ctx.user_id
    if int(sender_id) != int(ctx.user_id):
        return 403, {'success': False, 'error': 'Not authorized: sender_id must match your user_id.'}

    if not _can_access_trip_chat(ctx, str(trip_id)):
        return 403, {'success': False, 'error': 'Not authorized to send messages for this trip.'}

    return _call_view(
        'POST',
        f'/lets_go/chat/{trip_id}/messages/send/',
        body={**payload, 'sender_id': sender_id},
    )


def list_my_bookings(ctx: BotContext, *, limit: int = 10) -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    return _call_view(
        'GET',
        f'/lets_go/users/{ctx.user_id}/bookings/',
        query={'mode': 'summary', 'limit': int(limit), 'offset': 0},
    )


def cancel_my_booking(ctx: BotContext, booking_id: int, reason: str) -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    status, bookings_out = list_my_bookings(ctx, limit=200)
    bookings = (bookings_out.get('bookings') if isinstance(bookings_out, dict) else None) or []
    if not any(isinstance(b, dict) and int(b.get('id') or 0) == int(booking_id) for b in bookings):
        return 403, {'success': False, 'error': 'Not authorized: this booking does not belong to you.'}
    return _call_view(
        'POST',
        f'/lets_go/bookings/{int(booking_id)}/cancel/',
        body={'reason': reason or 'Cancelled by passenger'},
    )


def _can_access_trip_chat(ctx: BotContext, trip_id: str) -> bool:
    # Determine driver id from ride-booking details (does not auto-update status).
    status, detail = _call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
    if status <= 0 or not isinstance(detail, dict):
        return False
    try:
        driver_id = int(((detail.get('trip') or {}).get('driver') or {}).get('id') or 0)
    except Exception:
        driver_id = 0
    if driver_id and int(driver_id) == int(ctx.user_id):
        return True

    # Otherwise, allow chat if this user has any active booking on this trip.
    status, bookings_out = list_my_bookings(ctx, limit=200)
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
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    if not _can_access_trip_chat(ctx, str(trip_id)):
        return 403, {'success': False, 'error': 'Not authorized to view chat for this trip.'}
    return _call_view(
        'GET',
        f'/lets_go/chat/{trip_id}/messages/',
        query={'user_id': int(ctx.user_id), 'limit': int(limit)},
    )


def get_my_profile(ctx: BotContext) -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    return _call_view(
        'GET',
        f'/lets_go/users/{ctx.user_id}/',
    )


def update_my_profile(ctx: BotContext, payload: dict) -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    return _call_view(
        'PATCH',
        f'/lets_go/users/{ctx.user_id}/',
        body=payload,
    )


def get_booking_payment_details_safe(ctx: BotContext, booking_id: int) -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}

    # Try passenger first, then driver.
    s1, out1 = _call_view('GET', f'/lets_go/bookings/{int(booking_id)}/payment/', query={'role': 'PASSENGER', 'user_id': int(ctx.user_id)})
    if s1 != 403:
        return s1, out1
    s2, out2 = _call_view('GET', f'/lets_go/bookings/{int(booking_id)}/payment/', query={'role': 'DRIVER', 'user_id': int(ctx.user_id)})
    return s2, out2


def submit_booking_payment_cash(ctx: BotContext, booking_id: int, *, driver_rating: float, driver_feedback: str = '') -> tuple[int, Any]:
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    status, bookings_out = list_my_bookings(ctx, limit=200)
    bookings = (bookings_out.get('bookings') if isinstance(bookings_out, dict) else None) or []
    if not any(isinstance(b, dict) and int(b.get('id') or 0) == int(booking_id) for b in bookings):
        return 403, {'success': False, 'error': 'Not authorized as passenger'}
    return _call_view_form(
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
    user, err = _require_user(ctx)
    if err:
        return 403, {'success': False, 'error': err}
    # Driver authorization is enforced by the API itself.
    return _call_view(
        'POST',
        f'/lets_go/bookings/{int(booking_id)}/payment/confirm/',
        body={
            'driver_id': int(ctx.user_id),
            'received': True,
            'passenger_rating': float(passenger_rating),
            'passenger_feedback': passenger_feedback or '',
        },
    )


def _intent(text: str) -> str:
    low = _normalize_text(text)
    if any(p in low for p in ['what can you do', 'what can u do', 'what you can do', 'how can you help', 'help me with', 'commands', 'features']):
        return 'capabilities'
    if any(p in low for p in ['my vehicles', 'my vehicle', 'what vehicle i have', 'what vehicles i have', 'show my vehicles', 'list my vehicles']):
        return 'list_vehicles'
    if any(p in low for p in ['which ride i created', 'which trip i created', 'my rides', 'my trips', 'rides i created', 'trips i created', 'show my rides', 'list my rides', 'show my trips', 'list my trips']):
        return 'list_my_rides'

    if re.search(r"\b(book|reserve)\b", low) and re.search(r"\b(ride|trip)\b", low):
        return 'book_ride'
    if any(p in low for p in ['my bookings', 'show my bookings', 'list my bookings', 'booking history', 'my booking']):
        return 'list_bookings'
    if 'cancel' in low and 'booking' in low:
        return 'cancel_booking'
    if any(p in low for p in ['payment details', 'payment status', 'show payment', 'booking payment']):
        return 'payment_details'
    if ('pay' in low or 'submit payment' in low) and 'booking' in low:
        return 'submit_payment'
    if ('confirm payment' in low or 'payment received' in low) and 'booking' in low:
        return 'confirm_payment'
    if any(p in low for p in ['my profile', 'show my profile', 'profile details']):
        return 'profile_view'
    if any(p in low for p in ['update profile', 'change address', 'change name', 'update bank', 'update iban', 'update account']):
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


def _continue_misc_flows(st: ConversationState, text: str) -> Optional[str]:
    low = _normalize_text(text)

    if st.active_flow == 'cancel_booking' and st.awaiting_field == 'booking_id':
        bid = _extract_booking_id(text) or _to_int(text)
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
        trip_id = _extract_trip_id(text) or (text or '').strip()
        if not trip_id:
            return 'Please provide a trip_id.'
        st.awaiting_field = None
        status, out = list_chat(st.ctx, str(trip_id), limit=25)
        _reset_flow(st)
        return f'{status}: {out}'

    if st.active_flow == 'payment_details' and st.awaiting_field == 'booking_id':
        bid = _extract_booking_id(text) or _to_int(text)
        if not bid:
            return 'Please provide a valid booking_id (number).'
        st.awaiting_field = None
        status, out = get_booking_payment_details_safe(st.ctx, int(bid))
        _reset_flow(st)
        return f'{status}: {out}'

    if st.active_flow == 'submit_payment':
        if st.awaiting_field == 'booking_id':
            bid = _extract_booking_id(text) or _to_int(text)
            if not bid:
                return 'Please provide a valid booking_id (number).'
            st.payment.booking_id = int(bid)
            st.awaiting_field = 'driver_rating'
            return "Please provide driver rating (1-5). Example: '5' or '5 stars'."

        if st.awaiting_field == 'driver_rating':
            rating = _parse_rating_value(text)
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
            bid = _extract_booking_id(text) or _to_int(text)
            if not bid:
                return 'Please provide a valid booking_id (number).'
            st.payment.booking_id = int(bid)
            st.awaiting_field = 'passenger_rating'
            return "Please provide passenger rating (1-5). Example: '5' or '5 stars'."

        if st.awaiting_field == 'passenger_rating':
            rating = _parse_rating_value(text)
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


def _extract_trip_id(text: str) -> Optional[str]:
    m = re.search(r"\btrip[_\s-]*id\s*[:=]\s*([A-Za-z0-9._:-]+)", text or '', flags=re.IGNORECASE)
    if m:
        return m.group(1)
    m = re.search(r"\b(T\d{2,6}-[A-Za-z0-9:-]{6,})\b", text or '', flags=re.IGNORECASE)
    if m:
        return m.group(1)
    return None


def _best_stop_match(stops: list[dict], raw: str) -> tuple[Optional[int], Optional[str], float]:
    if not raw:
        return None, None, 0.0
    raw_norm = _normalize_text(raw)
    best = (None, None, 0.0)
    for s in stops:
        if not isinstance(s, dict):
            continue
        name = str(s.get('name') or s.get('stop_name') or '')
        score = difflib.SequenceMatcher(a=raw_norm, b=_normalize_text(name)).ratio()
        if score > best[2]:
            best = (int(s.get('order') or s.get('stop_order') or 0), name, float(score))
    return best


def _find_trip_candidates(draft: BookingDraft, *, limit: int = 5) -> list[dict]:
    if not draft.from_stop_raw or not draft.to_stop_raw:
        return []

    query = {
        'user_id': int(draft.passenger_id) if draft.passenger_id else None,
        'from': draft.from_stop_raw,
        'to': draft.to_stop_raw,
        'date': (draft.trip_date.isoformat() if draft.trip_date else None),
        'min_seats': int(draft.number_of_seats) if draft.number_of_seats else None,
        'limit': 30,
        'offset': 0,
        'sort': 'soonest',
    }
    if draft.departure_time:
        query['time_from'] = draft.departure_time

    status, out = _call_view('GET', '/lets_go/trips/search/', query=query)
    trips = (out.get('trips') if isinstance(out, dict) else None) or []
    if not isinstance(trips, list) or not trips:
        return []

    candidates: list[dict] = []
    for t in trips[:30]:
        if not isinstance(t, dict):
            continue
        trip_id = t.get('trip_id')
        if not trip_id:
            continue

        # Fetch stop orders from ride-booking details.
        s2, detail = _call_view('GET', f'/lets_go/ride-booking/{trip_id}/')
        if s2 <= 0 or not isinstance(detail, dict):
            continue
        trip_obj = detail.get('trip') or {}
        route = (trip_obj.get('route') or {})
        stops = route.get('stops') or []
        if not isinstance(stops, list) or not stops:
            continue

        from_order, from_name, from_score = _best_stop_match(stops, draft.from_stop_raw)
        to_order, to_name, to_score = _best_stop_match(stops, draft.to_stop_raw)
        if not from_order or not to_order or int(from_order) >= int(to_order):
            continue
        stop_score = min(from_score, to_score)
        if stop_score < 0.55:
            continue

        try:
            driver_id = int(((trip_obj.get('driver') or {}).get('id') or 0))
        except Exception:
            driver_id = 0

        # Seats and fare are on the search payload.
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


def _render_trip_choice(candidates: list[dict]) -> str:
    lines = ['I found multiple matching trips. Reply with the number you want:']
    for i, c in enumerate(candidates, start=1):
        lines.append(
            f"{i}) trip_id={c.get('trip_id')} | {c.get('route_name')} | {c.get('trip_date')} {c.get('departure_time')} | seats={c.get('available_seats')} | base_fare={c.get('base_fare')}"
        )
    lines.append("You can also say 'cancel' to stop.")
    return "\n".join(lines)


def _render_booking_summary(st: ConversationState) -> str:
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


def _render_create_summary(st: ConversationState) -> str:
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


def _help_text() -> str:
    return "\n".join([
        'You can talk naturally. Examples:',
        "- book a ride from Saddar to DHA tomorrow at 6pm",
        "- I need 2 seats",
        "- make it 450 fare",
        "- yes (to confirm)",
        "- cancel (to stop current action)",
        "- ask business rules/questions like: can I chat without booking?",
    ])


def _capabilities_text() -> str:
    return "\n".join([
        "I can help you with:",
        "- book a ride (find trips and reserve seats)",
        "- create/post a ride (if you're a driver)",
        "- list your vehicles, bookings, and rides",
        "- cancel your booking",
        "- view/send trip chat messages (only if authorized)",
        "",
        "Try: 'book a ride from X to Y tomorrow 6pm' or 'create a ride'.",
    ])


def _smalltalk_reply(text: str) -> Optional[str]:
    low = _normalize_text(text)
    if any(p in low for p in ['i love you', 'love you']):
        return "Thank you. I can help with rides/bookings—tell me what you'd like to do."
    if any(p in low for p in ['help me', 'i am in trouble', 'im in trouble', 'emergency']):
        return "I'm here to help with the app tasks (booking/creating rides, messages, etc.). If this is an emergency, please contact local emergency services or someone you trust right now."
    return None


def _update_booking_from_text(st: ConversationState, text: str):
    d = st.booking
    llm = _llm_extract_cached(st, text)
    frm, to = _extract_from_to(text)
    if llm.get('from_stop'):
        d.from_stop_raw = str(llm.get('from_stop')).strip()
    elif frm:
        d.from_stop_raw = frm
    if llm.get('to_stop'):
        d.to_stop_raw = str(llm.get('to_stop')).strip()
    elif to:
        d.to_stop_raw = to

    if (not d.from_stop_raw or not d.to_stop_raw):
        pairs = _extract_coord_pairs(text)
        if pairs:
            if not d.from_stop_raw and (st.awaiting_field == 'from_stop' or len(pairs) >= 2):
                d.from_stop_raw = _nearest_stop_name(pairs[0][0], pairs[0][1]) or d.from_stop_raw
            if not d.to_stop_raw:
                idx = 1 if len(pairs) >= 2 else 0
                if st.awaiting_field == 'to_stop' or len(pairs) >= 2:
                    d.to_stop_raw = _nearest_stop_name(pairs[idx][0], pairs[idx][1]) or d.to_stop_raw

    if llm.get('date'):
        try:
            d.trip_date = datetime.strptime(str(llm.get('date')), '%Y-%m-%d').date()
        except Exception:
            pass
    if d.trip_date is None:
        d.trip_date = _parse_date(text) or d.trip_date

    if llm.get('time'):
        d.departure_time = str(llm.get('time')).strip()
    if d.departure_time is None:
        d.departure_time = _parse_time_str(text) or d.departure_time

    if llm.get('seats'):
        d.number_of_seats = _to_int(llm.get('seats')) or d.number_of_seats
    if d.number_of_seats is None:
        d.number_of_seats = _extract_seats(text) or d.number_of_seats

    if llm.get('fare'):
        d.proposed_fare = _to_int(llm.get('fare')) or d.proposed_fare
    if d.proposed_fare is None:
        d.proposed_fare = _extract_fare(text) or d.proposed_fare


def _update_create_from_text(st: ConversationState, text: str):
    d = st.create_ride
    llm = _llm_extract_cached(st, text)
    if isinstance(llm, dict):
        if llm.get('route_id'):
            candidate = str(llm.get('route_id')).strip()
            if _looks_like_route_id(candidate):
                d.route_id = candidate
                d.route_name = None
                d.route_candidates = None
        if llm.get('route_name') and not d.route_id:
            d.route_name = str(llm.get('route_name')).strip() or d.route_name
        if d.vehicle_id is None and llm.get('vehicle_id') is not None:
            d.vehicle_id = _to_int(llm.get('vehicle_id')) or d.vehicle_id
        if d.total_seats is None and llm.get('total_seats') is not None:
            d.total_seats = _to_int(llm.get('total_seats')) or d.total_seats
        if d.custom_price is None and llm.get('custom_price') is not None:
            d.custom_price = _to_int(llm.get('custom_price')) or d.custom_price
        if llm.get('gender_preference'):
            gp = str(llm.get('gender_preference')).strip().lower()
            if gp in {'female', 'f'}:
                d.gender_preference = 'Female'
            elif gp in {'male', 'm'}:
                d.gender_preference = 'Male'
            elif gp in {'any', 'all', 'no preference'}:
                d.gender_preference = 'Any'
        if llm.get('date') and d.trip_date is None:
            try:
                d.trip_date = datetime.strptime(str(llm.get('date')), '%Y-%m-%d').date()
            except Exception:
                pass
        if llm.get('time') and d.departure_time is None:
            d.departure_time = str(llm.get('time')).strip() or d.departure_time

    m = re.search(r"\broute[_\s-]*id\s*[:=]\s*([A-Za-z0-9_-]+)\b", text or '', flags=re.IGNORECASE)
    if m:
        candidate = (m.group(1) or '').strip()
        if _looks_like_route_id(candidate):
            d.route_id = candidate
            d.route_name = None
            d.route_candidates = None
        else:
            d.route_name = candidate
            d.route_id = None
    d.trip_date = d.trip_date or _parse_date(text)
    d.departure_time = d.departure_time or _parse_time_str(text)
    if d.vehicle_id is None:
        m = re.search(r"\bvehicle[_\s-]*id\s*[:=]\s*(\d+)\b", text or '', flags=re.IGNORECASE)
        if m:
            d.vehicle_id = _to_int(m.group(1))
    if d.total_seats is None:
        m = re.search(r"\btotal\s*seats\s*[:=]?\s*(\d+)\b", text or '', flags=re.IGNORECASE)
        if m:
            d.total_seats = _to_int(m.group(1))
        if d.total_seats is None:
            d.total_seats = _extract_seats(text)
    if d.custom_price is None:
        d.custom_price = _extract_fare(text)
    if re.search(r"\bfemale\b", text or '', flags=re.IGNORECASE):
        d.gender_preference = 'Female'
    elif re.search(r"\bmale\b", text or '', flags=re.IGNORECASE):
        d.gender_preference = 'Male'
    elif re.search(r"\bany\b", text or '', flags=re.IGNORECASE):
        d.gender_preference = 'Any'


def _update_message_from_text(st: ConversationState, text: str):
    d = st.message
    llm = _llm_extract_cached(st, text)
    d.trip_id = d.trip_id or _extract_trip_id(text) or st.last_trip_id
    if d.recipient_id is None and llm.get('recipient_id'):
        d.recipient_id = _to_int(llm.get('recipient_id'))
    if d.message_text is None and llm.get('message_text'):
        d.message_text = str(llm.get('message_text')).strip()
    if d.message_text is None:
        m = re.search(r"\b(?:message|msg|text)\b\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.message_text = m.group(1).strip()
    if d.sender_role is None:
        if re.search(r"\bdriver\b", text or '', flags=re.IGNORECASE):
            d.sender_role = 'driver'
        if re.search(r"\bpassenger\b", text or '', flags=re.IGNORECASE):
            d.sender_role = 'passenger'


def handle_message(ctx: BotContext, text: str) -> str:
    st = _get_state(ctx.user_id)
    st.history.append({'role': 'user', 'text': text})
    low = _normalize_text(text)

    # Always run LLM extraction once per message (agent loop: user -> llm -> bot ...)
    _llm_extract_cached(st, text)

    def _finalize(reply: str) -> str:
        draft = reply or ''
        rewritten = _llm_rewrite_reply(st, text, draft)
        final = rewritten or draft
        st.history.append({'role': 'assistant', 'text': final})
        return final

    blocked = _blocked_system_request(text)
    if blocked is not None:
        return _finalize(blocked)

    smalltalk = _smalltalk_reply(text)
    if smalltalk is not None and not st.active_flow:
        return _finalize(smalltalk)

    if low in {'cancel', 'stop', 'reset'}:
        _reset_flow(st)
        return _finalize('Okay, cancelled. What would you like to do next?')

    cont = (
        _continue_booking_flow(st, text)
        or _continue_create_flow(st, text)
        or _continue_message_flow(st, text)
        or _continue_negotiate_flow(st, text)
        or _continue_misc_flows(st, text)
    )
    if cont is not None:
        return _finalize(cont)

    if st.active_flow == 'choose_trip':
        if not st.booking.candidates:
            _reset_flow(st)
            return _finalize('No candidates left. Please start again.')
        m = re.search(r"\b(\d+)\b", low)
        if not m:
            return _finalize('Please reply with the trip number (e.g. 1), or type cancel.')
        idx = _to_int(m.group(1))
        if not idx or idx < 1 or idx > len(st.booking.candidates):
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
        return _finalize(_render_booking_summary(st))

    if st.active_flow == 'choose_route':
        d = st.create_ride
        if not d.route_candidates:
            _reset_flow(st)
            return _finalize('No route candidates left. Please start again.')
        m = re.search(r"\b(\d+)\b", low)
        if not m:
            return _finalize('Please reply with the route number (e.g. 1), or type cancel.')
        idx = _to_int(m.group(1))
        if not idx or idx < 1 or idx > len(d.route_candidates):
            return _finalize(f"Please choose a number between 1 and {len(d.route_candidates)}.")
        chosen = d.route_candidates[idx - 1]
        if isinstance(chosen, dict):
            d.route_id = str(chosen.get('id') or '').strip() or d.route_id
            d.route_name = str(chosen.get('name') or '').strip() or None
        d.route_candidates = None
        st.active_flow = 'create_ride'
        st.awaiting_field = None
        # Continue slot filling
        return _finalize(_continue_create_flow(st, '') or _render_create_summary(st))

    if st.active_flow in {'confirm_booking', 'confirm_create', 'confirm_message', 'confirm_negotiate', 'confirm_cancel_booking', 'confirm_profile_update', 'confirm_submit_payment', 'confirm_confirm_payment'}:
        yn = _parse_yes_no(text)
        if yn is None and st.active_flow == 'confirm_create':
            _update_create_from_text(st, text)
            # If the user typed a route description during confirm, attempt to resolve it.
            if not _looks_like_route_id(st.create_ride.route_id) and (st.create_ride.route_name or '').strip():
                msg = _resolve_route_from_text(st, st.create_ride.route_name or '')
                if msg:
                    return _finalize(msg)
            return _finalize(_render_create_summary(st))
        if yn is True:
            action = st.pending_action or {}
            if action.get('type') == 'book_ride':
                d = st.booking
                base_fare = int(d.selected_base_fare or 0)
                if base_fare <= 0 and d.selected_trip_id:
                    base_fare = _api_trip_base_fare(str(d.selected_trip_id))
                proposed = int(d.proposed_fare or base_fare)
                payload = {
                    'passenger_id': st.ctx.user_id,
                    'from_stop_order': int(d.selected_from_stop_order or 0),
                    'to_stop_order': int(d.selected_to_stop_order or 0),
                    'number_of_seats': int(d.number_of_seats or 1),
                    'original_fare': base_fare,
                    'proposed_fare': proposed,
                    'is_negotiated': bool(proposed != base_fare),
                }
                status, out = book_ride(st.ctx, str(d.selected_trip_id), payload)
                st.last_trip_id = str(d.selected_trip_id)
                try:
                    if isinstance(out, dict):
                        st.last_booking_id = _to_int(out.get('booking_id') or out.get('id')) or st.last_booking_id
                except Exception:
                    pass
                _reset_flow(st)
                return _finalize(f'{status}: {out}')

            if action.get('type') == 'cancel_booking':
                d = st.cancel_booking
                status, out = cancel_my_booking(st.ctx, int(d.booking_id or 0), d.reason or 'Cancelled by passenger')
                _reset_flow(st)
                return _finalize(f'{status}: {out}')

            if action.get('type') == 'profile_update':
                d = st.profile
                payload = {}
                if d.name is not None:
                    payload['name'] = d.name
                if d.address is not None:
                    payload['address'] = d.address
                if d.bankname is not None:
                    payload['bankname'] = d.bankname
                if d.accountno is not None:
                    payload['accountno'] = d.accountno
                if d.iban is not None:
                    payload['iban'] = d.iban
                status, out = update_my_profile(st.ctx, payload)
                _reset_flow(st)
                return _finalize(f'{status}: {out}')

            if action.get('type') == 'submit_payment':
                d = st.payment
                status, out = submit_booking_payment_cash(
                    st.ctx,
                    int(d.booking_id or 0),
                    driver_rating=float(d.driver_rating or 0.0),
                    driver_feedback=d.driver_feedback or '',
                )
                _reset_flow(st)
                return f'{status}: {out}'

            if action.get('type') == 'confirm_payment':
                d = st.payment
                status, out = confirm_booking_payment_received(
                    st.ctx,
                    int(d.booking_id or 0),
                    passenger_rating=float(d.passenger_rating or 0.0),
                    passenger_feedback=d.passenger_feedback or '',
                )
                _reset_flow(st)
                return f'{status}: {out}'

            if action.get('type') == 'negotiate':
                d = st.negotiate
                booking_id = int(d.booking_id or 0)
                if booking_id <= 0:
                    _reset_flow(st)
                    return 'Invalid booking_id.'
                trip_id = str(d.trip_id)
                driver_id = _api_trip_driver_id(trip_id)
                if not driver_id:
                    _reset_flow(st)
                    return 'Trip not found.'
                is_driver = int(driver_id) == int(st.ctx.user_id)
                payload = {
                    'action': d.action,
                    'counter_fare': d.counter_fare,
                    'note': d.note,
                }
                if is_driver:
                    status, out = negotiate_driver(st.ctx, trip_id, booking_id, {**payload, 'driver_id': st.ctx.user_id})
                else:
                    # Verify booking belongs to this passenger via API
                    s_b, out_b = list_my_bookings(st.ctx, limit=200)
                    bookings = (out_b.get('bookings') if isinstance(out_b, dict) else None) or []
                    if not any(isinstance(b, dict) and int(b.get('id') or 0) == int(booking_id) for b in bookings):
                        _reset_flow(st)
                        return 'Not authorized: this booking does not belong to you.'
                    status, out = negotiate_passenger(st.ctx, trip_id, booking_id, {**payload, 'passenger_id': st.ctx.user_id})
                st.last_trip_id = trip_id
                st.last_booking_id = booking_id
                _reset_flow(st)
                return _finalize(f'{status}: {out}')

            if action.get('type') == 'create_ride':
                d = st.create_ride
                if not _looks_like_route_id(d.route_id):
                    # Last-chance resolve to avoid sending free-text as route_id.
                    msg = _resolve_route_from_text(st, d.route_name or d.route_id or '')
                    if msg:
                        return _finalize(msg)
                    if not _looks_like_route_id(d.route_id):
                        st.active_flow = 'create_ride'
                        st.awaiting_field = 'route_id'
                        return _finalize('Please provide a valid route_id (e.g., R001).')
                payload = {
                    'route_id': d.route_id,
                    'vehicle_id': d.vehicle_id,
                    'departure_time': d.departure_time,
                    'trip_date': d.trip_date.isoformat() if d.trip_date else None,
                    'total_seats': d.total_seats,
                    'custom_price': d.custom_price,
                    'gender_preference': d.gender_preference or 'Any',
                    'driver_id': st.ctx.user_id,
                }
                status, out = create_ride(st.ctx, payload)
                _reset_flow(st)
                return _finalize(f'{status}: {out}')

            if action.get('type') == 'message':
                d = st.message
                if not d.trip_id:
                    _reset_flow(st)
                    return 'Trip not found in context. Please specify trip_id.'
                if not d.recipient_id:
                    _reset_flow(st)
                    return 'Recipient not found. Please specify recipient_id.'
                payload = {
                    'sender_id': st.ctx.user_id,
                    'recipient_id': int(d.recipient_id),
                    'sender_role': d.sender_role or 'passenger',
                    'message_text': d.message_text or '',
                }
                status, out = send_message(st.ctx, str(d.trip_id), payload)
                st.last_trip_id = str(d.trip_id)
                _reset_flow(st)
                return _finalize(f'{status}: {out}')

            _reset_flow(st)
            return _finalize('Done.')

        if yn is False:
            _reset_flow(st)
            return _finalize('Okay, cancelled. What would you like to do next?')
        return _finalize("Please reply 'yes' to confirm or 'no' to cancel.")

    intent = _intent(text)
    if intent == 'help':
        return _finalize(_help_text())
    if intent == 'capabilities':
        return _finalize(_capabilities_text())
    if intent == 'greet':
        name = st.user_name or 'there'
        return _finalize(f"Hi {name}. What would you like to do today—book a ride or create a ride?")

    if intent == 'kb':
        routed = _llm_route_fallback(st, text)
        if routed is not None:
            return _finalize(routed)

    if intent == 'list_vehicles':
        return _finalize(_list_user_vehicles(st.ctx))

    if intent == 'list_my_rides':
        return _finalize(_list_user_created_trips(st.ctx))

    if intent == 'list_bookings':
        status, out = list_my_bookings(st.ctx, limit=10)
        return _finalize(f'{status}: {out}')

    if intent == 'cancel_booking':
        st.active_flow = 'cancel_booking'
        st.cancel_booking.booking_id = _extract_booking_id(text) or st.last_booking_id
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
        trip_id = _extract_trip_id(text) or st.last_trip_id
        if not trip_id:
            st.active_flow = 'chat_list'
            st.awaiting_field = 'trip_id'
            return _finalize('Which trip chat do you want to view? Provide trip_id.')
        status, out = list_chat(st.ctx, str(trip_id), limit=25)
        return _finalize(f'{status}: {out}')

    if intent == 'profile_view':
        status, out = get_my_profile(st.ctx)
        return _finalize(f'{status}: {out}')

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
        m = re.search(r"\bbank\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.bankname = m.group(1).strip()
        m = re.search(r"\baccount\s*no\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.accountno = m.group(1).strip()
        m = re.search(r"\biban\s*[:=]\s*(.+)$", text or '', flags=re.IGNORECASE)
        if m:
            d.iban = m.group(1).strip()
        if not any([d.name, d.address, d.bankname, d.accountno, d.iban]):
            _reset_flow(st)
            return _finalize("Tell me what to update (e.g., 'update profile name: Ali' or 'change address: ...').")
        return _finalize("\n".join([
            'Please confirm profile update:',
            f"- name: {d.name}",
            f"- address: {d.address}",
            f"- bankname: {d.bankname}",
            f"- accountno: {d.accountno}",
            f"- iban: {d.iban}",
            "Reply 'yes' to confirm or 'no' to cancel.",
        ]))

    if intent == 'payment_details':
        booking_id = _extract_booking_id(text) or st.last_booking_id
        if not booking_id:
            st.active_flow = 'payment_details'
            st.awaiting_field = 'booking_id'
            return _finalize('Which booking payment details do you want? Provide booking_id.')
        status, out = get_booking_payment_details_safe(st.ctx, int(booking_id))
        return _finalize(f'{status}: {out}')

    if intent == 'submit_payment':
        st.payment = PaymentDraft()
        st.payment.booking_id = _extract_booking_id(text) or st.last_booking_id
        st.payment.driver_rating = _parse_rating_value(text)
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
        st.payment = PaymentDraft()
        st.payment.booking_id = _extract_booking_id(text)
        st.payment.passenger_rating = _parse_rating_value(text)
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

    if intent == 'negotiate':
        st.active_flow = 'negotiate'
        st.awaiting_field = None
        st.negotiate = NegotiateDraft(trip_id=st.last_trip_id, booking_id=st.last_booking_id)
        return _finalize(_continue_negotiate_flow(st, text) or 'Provide trip_id and booking_id.')

    if intent == 'book_ride':
        st.active_flow = 'book_ride'
        _update_booking_from_text(st, text)

        if not st.booking.from_stop_raw:
            st.awaiting_field = 'from_stop'
            return _finalize('Where are you starting from (pickup stop)?')
        if not st.booking.to_stop_raw:
            st.awaiting_field = 'to_stop'
            return _finalize('Where do you want to go (drop-off stop)?')
        if not st.booking.trip_date:
            st.awaiting_field = 'date'
            return _finalize('Which date? (today / tomorrow / YYYY-MM-DD)')
        if not st.booking.departure_time:
            st.awaiting_field = 'time'
            return _finalize('What time? (e.g., 18:30 or 6pm)')
        if not st.booking.number_of_seats:
            st.awaiting_field = 'seats'
            return _finalize('How many seats do you need?')

        candidates = _find_trip_candidates(st.booking)
        if not candidates:
            return _finalize('I could not find a matching scheduled trip. Try a different time/date or specify a trip_id.')

        if len(candidates) > 1:
            st.booking.candidates = candidates
            st.active_flow = 'choose_trip'
            return _finalize(_render_trip_choice(candidates))

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
        return _finalize(_render_booking_summary(st))

    if intent == 'create_ride':
        st.active_flow = 'create_ride'
        _update_create_from_text(st, text)

        d = st.create_ride
        if not d.route_id:
            st.awaiting_field = 'route_id'
            return _finalize("Please tell me the route using stop names (e.g., 'Quaid-e-Azam Park to Fasal Town'). If you know the route_id you can also type it (e.g., R001).")
        if not d.vehicle_id:
            st.awaiting_field = 'vehicle_id'
            return _finalize('What is the vehicle_id you want to use?')
        if not d.trip_date:
            st.awaiting_field = 'trip_date'
            return _finalize('Which date? (today / tomorrow / YYYY-MM-DD)')
        if not d.departure_time:
            st.awaiting_field = 'departure_time'
            return _finalize('What departure time? (e.g., 18:30 or 6pm)')
        if not d.total_seats:
            st.awaiting_field = 'total_seats'
            return _finalize('How many total seats are you offering?')
        if not d.custom_price:
            st.awaiting_field = 'custom_price'
            return _finalize('What is the base fare per seat (custom_price)?')

        st.active_flow = 'confirm_create'
        st.pending_action = {'type': 'create_ride'}
        return _finalize(_render_create_summary(st))

    if intent == 'message':
        st.active_flow = 'message'
        _update_message_from_text(st, text)
        d = st.message
        if not d.trip_id:
            st.awaiting_field = 'trip_id'
            return _finalize('Which trip? Please provide trip_id.')

        if d.recipient_id is None:
            driver_id = _api_trip_driver_id(str(d.trip_id))
            if driver_id and int(driver_id) != int(st.ctx.user_id):
                d.recipient_id = int(driver_id)
                d.sender_role = d.sender_role or 'passenger'
            else:
                st.awaiting_field = 'recipient_id'
                return _finalize('Who should receive the message? Provide recipient_id.')

        if not d.message_text:
            st.awaiting_field = 'message_text'
            return _finalize('What message should I send?')

        st.active_flow = 'confirm_message'
        st.pending_action = {'type': 'message'}
        return _finalize("\n".join([
            'Please confirm sending this message:',
            f"- trip_id: {d.trip_id}",
            f"- recipient_id: {d.recipient_id}",
            f"- sender_role: {d.sender_role or 'passenger'}",
            f"- text: {d.message_text}",
            "Reply 'yes' to confirm or 'no' to cancel.",
        ]))

    answer = search_kb(text)
    if answer:
        return _finalize(answer)
    fallback = _fallback_business_rules_answer(text)
    if fallback:
        return _finalize(fallback)
    llm_reply = _llm_chat_reply(st, text)
    if llm_reply:
        return _finalize(llm_reply)
    return _finalize("Tell me what you want to do (for example: book a ride from X to Y, or create a ride).")


# --- STEP 3: Build the Graph ---
def ask_bot(user_id: int, question: str):
    ctx = BotContext(user_id=int(user_id))
    reply = handle_message(ctx, question)
    logger.debug("Bot: %s", reply)

# --- STEP 4: Test it ---
if __name__ == '__main__':
    try:
        from lets_go.utils.chatbot.cli import main
        main()
    except Exception:
        if BOT_EMAIL == 'your-email@example.com' or BOT_PASSWORD == 'your-password':
            raise SystemExit('Set LETS_GO_BOT_EMAIL and LETS_GO_BOT_PASSWORD environment variables (or edit BOT_EMAIL/BOT_PASSWORD in chatbot_test.py).')
        user, err = api_login(BOT_EMAIL, BOT_PASSWORD)
        if err:
            raise SystemExit(f'Login failed: {err}')
        _CURRENT_USER.clear()
        _CURRENT_USER.update(user)
        user_id = int(user.get('id'))
        logger.debug("Logged in as user_id=%s (%s)", user_id, user.get('name', ''))

        while True:
            q = input('You: ').strip()
            if not q:
                continue
            if q.lower() in {'exit', 'quit'}:
                break
            ask_bot(user_id, q)
