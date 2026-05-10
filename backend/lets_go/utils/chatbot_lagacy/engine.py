import json
import logging
import os
import re
import sys
from datetime import datetime
from dataclasses import asdict
from typing import Any, Optional

from . import api
from . import help_bot
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
)
from .helpers import looks_like_route_id
from .llm import llm_api_key, llm_base_url, llm_brain_mode, llm_extract_cached, llm_provider, llm_rewrite_reply, llm_chat_reply
from .state import BotContext, PaymentDraft, get_state, reset_flow


logger = logging.getLogger(__name__)


def _support_only_reply() -> str:
    return "\n".join([
        "I can help with FAQs, the user manual, and general guidance.",
        "For bookings, rides, payments, profile changes, or trip chat, please use the app UI.",
    ])
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


def _safe_json(obj: object) -> str:
    try:
        return json.dumps(obj, ensure_ascii=False, separators=(',', ':'), default=str)
    except Exception:
        return str(obj)


def _redact_obj(obj: object) -> object:
    if isinstance(obj, list):
        return [_redact_obj(x) for x in obj]
    if isinstance(obj, dict):
        out: dict = {}
        for k, v in obj.items():
            key = str(k or '')
            low = key.lower()
            if low.endswith('_url') or low.endswith('url') or low.endswith('_image') or 'document' in low or 'photo' in low:
                continue
            if 'license' in low or 'driving_license' in low or 'cnic' in low:
                continue
            out[k] = _redact_obj(v)
        return out
    if isinstance(obj, str):
        if obj.startswith('http://') or obj.startswith('https://'):
            return '[REDACTED_URL]'
        return obj
    return obj


def _format_api_result(status: int, out: object) -> str:
    try:
        code = int(status or 0)
    except Exception:
        code = 0
    if code in {401, 403} and isinstance(out, dict):
        msg = out.get('error') or out.get('message')
        if isinstance(msg, str) and msg.strip():
            return msg.strip()
    out = _redact_obj(out)
    return f'{status}: {_safe_json(out)}'


def handle_message(ctx: BotContext, text: str) -> str:
    st = get_state(ctx.user_id)
    regression_mode = 'support_bot_regression' in (sys.argv or [])

    from .trace import trace
    trace('engine.handle_message.enter', user_id=getattr(ctx, 'user_id', None), text=text, active_flow=getattr(st, 'active_flow', None), awaiting_field=getattr(st, 'awaiting_field', None))

    debug_enabled = str(os.getenv('LETS_GO_BOT_DEBUG', '') or '').strip().lower() in {'1', 'true', 'yes', 'on'}

    def _dbg(event: str, payload: dict | None = None) -> None:
        if not debug_enabled:
            return
        try:
            ts = datetime.now().strftime('%H:%M:%S')
            base = f"[bot-debug {ts}] {event}"
            if payload:
                print(base + " | " + ", ".join(f"{k}={payload[k]!r}" for k in sorted(payload.keys())), flush=True)
            else:
                print(base, flush=True)
        except Exception:
            return
    # Optional stateless mode for regression/fuzzing to avoid flow/state leakage across prompts.
    # Default is OFF so production behavior is unchanged.
    # NOTE: We preserve multi-turn selection flows (choose_*), otherwise replies like "2" can't be applied.
    if regression_mode or str(os.getenv('LETS_GO_BOT_STATELESS', '')).strip().lower() in {'1', 'true', 'yes', 'on'}:
        if (st.active_flow or '') not in {'choose_route', 'choose_trip', 'choose_vehicle', 'choose_location'}:
            reset_flow(st)
        # Clear any cached LLM extraction so --no-llm runs can't accidentally reuse
        # previously cached intent extraction from earlier sessions.
        st.llm_last_text = None
        st.llm_last_extract = {}
        st.last_trip_id = None
        st.last_booking_id = None
        st.last_listed_trip_ids = []

    _dbg('incoming', {
        'user_id': getattr(ctx, 'user_id', None),
        'active_flow': getattr(st, 'active_flow', None),
        'awaiting_field': getattr(st, 'awaiting_field', None),
        'text': (text or '')[:240],
    })
    st.history.append({'role': 'user', 'text': text})
    low = normalize_text(text)

    def _rule_intent(txt: str) -> str:
        t = normalize_text(txt)
        if not t:
            return ''
        from .trace import trace
        trace('engine._rule_intent.start', text=t)
        if 'suggest stops' in t or t.startswith('suggest stop'):
            return 'suggest_stops'
        if t.startswith('what about '):
            return 'clarify'
        if ('without login' in t) or ('without logging in' in t) or ('guest mode' in t) or ('as guest' in t):
            return 'faq_guest_limits'
        if 'pickup code' in t:
            return 'faq_pickup_code'
        if t == 'sos' or ' sos' in f' {t} ':
            return 'faq_sos'
        if (
            ('about' in t and ('app' in t or 'lets go' in t or 'let\'s go' in t))
            or t in {'what is this app', 'what is this app about', 'what is lets go', "what is let's go"}
        ):
            return 'manual_about_app'
        if any(k in t for k in {'help', 'how to use', 'what can you do'}):
            return 'help'
        if any(k in t for k in {'capabilities', 'features', 'what can you do'}):
            return 'capabilities'
        if any(k in t.split() for k in {'hi', 'hello', 'hey'}):
            return 'greet'
        if 'faq' in t or 'faqs' in t:
            return 'faq'
        if 'manual' in t:
            return 'manual'
        if 'my profile' in t or t == 'profile' or 'profile details' in t or 'account details' in t or 'who am i' in t:
            return 'profile_view'
        if 'change requests' in t or 'verification requests' in t:
            return 'list_change_requests'
        if 'trip details' in t or (t.startswith('trip') and 'details' in t):
            return 'trip_detail'
        if 'my bookings' in t or 'list bookings' in t or 'booking history' in t or 'booked' in t:
            return 'list_bookings'
        if 'my rides' in t or 'my trips' in t or 'ride history' in t or 'list rides' in t:
            return 'list_my_rides'
        if 'my vehicles' in t or 'list vehicles' in t or 'show vehicles' in t:
            return 'list_vehicles'
        if 'chat history' in t or 'chat list' in t or 'list chat' in t or (t.startswith('show chat') and 'trip' in t):
            return 'chat_list'
        if 'payment details' in t or ('payment' in t and 'booking' in t):
            return 'payment_details'
        if "why can't i book" in t or "why cant i book" in t or ('cannot' in t and 'book' in t and 'why' in t):
            return 'faq_booking_blocked'
        if "why can't i create" in t or "why cant i create" in t or ('cannot' in t and 'create' in t and 'why' in t):
            return 'faq_create_ride_blocked'
        if 'fare negotiation' in t or ('negotiate' in t and 'work' in t):
            return 'faq_negotiation'
        if 'how do payments work' in t or ('payments' in t and 'work' in t):
            return 'faq_payments'
        if 'how do notifications work' in t or ('notifications' in t and 'work' in t):
            return 'faq_notifications'
        if 'cancel booking' in t:
            return 'cancel_booking'
        if 'cancel trip' in t:
            return 'cancel_trip'
        if 'delete trip' in t:
            return 'delete_trip'
        if 'create ride' in t or 'post a ride' in t:
            return 'create_ride'
        if 'book a ride' in t or (('book' in t) and ('ride' in t or 'trip' in t)):
            return 'book_ride'
        if 'send message' in t or (t.startswith('message') and 'trip' in t):
            return 'message'
        if 'negotiate' in t:
            return 'negotiate'
        return ''

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
            or ('guests cannot access' in low_draft)
            or ('not verified yet' in low_draft)
            or ('account is blocked' in low_draft)
            or ('account is banned' in low_draft)
            or ('restricted to' in low_draft)
            or ('do not have access' in low_draft)
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
        if rewrite_allowed and (not regression_mode):
            rewritten = llm_rewrite_reply(st, text, draft)
        final = rewritten or draft
        hist_txt = final
        if ('{' in hist_txt) or ('}' in hist_txt):
            hist_txt = '[structured output omitted]'
        elif len(hist_txt) > 600:
            hist_txt = hist_txt[:600] + '...'
        st.history.append({'role': 'assistant', 'text': hist_txt})
        _dbg('finalize', {
            'active_flow': getattr(st, 'active_flow', None),
            'awaiting_field': getattr(st, 'awaiting_field', None),
            'reply_len': len(final or ''),
            'reply_preview': (final or '')[:240],
        })
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
            status, out = api.api_trip_detail_safe(st.ctx, str(tid))
            return _finalize(_format_api_result(status, out))
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
        if err == 'ambiguous_stop' and isinstance(res, dict):
            amb = res.get('ambiguity') if isinstance(res.get('ambiguity'), dict) else {}
            query = str((amb or {}).get('query') or '').strip()
            cands = (amb or {}).get('candidates') if isinstance((amb or {}).get('candidates'), list) else []
            stop_role = str((amb or {}).get('stop_role') or '').strip() or None
            stop_index = (amb or {}).get('stop_index')
            try:
                stop_index = int(stop_index) if stop_index is not None else None
            except Exception:
                stop_index = None
            if query and cands:
                st.active_flow = 'choose_location'
                st.awaiting_field = None
                st.pending_action = {
                    'type': 'choose_location',
                    'original_text': text,
                    'query': query,
                    'candidates': cands[:8],
                    'stop_role': stop_role,
                    'stop_index': stop_index,
                }
                from .flows import render_location_choice
                return _finalize(render_location_choice(query, cands))

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
                    from .flows import list_user_created_trips_state
                    return _finalize(list_user_created_trips_state(st, limit=50, vehicle_id=vid0))

    brain = (False if regression_mode else llm_brain_mode())
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
        reset_flow(st)
        return _finalize(_support_only_reply())

    if not regression_mode:
        llm_extract_cached(st, text)

    if (('exact reason' in low) or ('exact' in low and 'reason' in low) or ('what' in low and 'reason' in low)):
        last = (st.history[-2].get('text') if isinstance(st.history[-2], dict) and len(st.history) >= 2 else '')
        if isinstance(last, str) and ('unable to delete' in last.lower() or 'cannot be deleted' in last.lower() or 'cannot be cancelled' in last.lower()):
            return _finalize(last)

    # Don't let blocked_system_request override auth-matrix queries like 'verification requests'.
    # Those should flow into the normal intent handlers which apply auth gating.
    if _rule_intent(text) != 'list_change_requests':
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

    # If a user is stuck in a flow awaiting a numeric booking_id but asks a new question,
    # treat it as a flow interruption and reset.
    if st.active_flow == 'cancel_booking' and st.awaiting_field == 'booking_id':
        inferred = _rule_intent(text)
        bid = extract_booking_id(text) or to_int(text)
        if (not bid) and inferred and inferred not in {'cancel_booking'}:
            reset_flow(st)

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
        reset_flow(st)
        return _finalize(_support_only_reply())

    # If the user provides a trip_id and says delete, route to trip deletion (avoid cancel_booking misroutes).
    if any(k in low for k in {'delete', 'remove'}) and (extract_trip_id(text) or st.last_trip_id):
        tid = extract_trip_id(text) or st.last_trip_id
        if tid:
            reset_flow(st)
            return _finalize(_support_only_reply())

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
        status, out = api.list_my_change_requests(st.ctx, entity_type=str(args.get('entity_type') or 'USER_PROFILE'), status=(str(args.get('status')) if args.get('status') is not None else None), limit=int(args.get('limit') or 10))
        return _finalize(_format_api_result(status, out))

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
                from .flows import list_user_created_trips_state
                return _finalize(
                    list_user_created_trips_state(st, limit=50, vehicle_id=vid)
                )

    if (
        any(k in low for k in {'edit', 'update', 'change', 'set'})
        and any(k in low for k in {'vehicle', 'veh', 'vehicle_id'})
        and (('trip' in low) or ('ride' in low) or extract_trip_id(text) or st.last_trip_id)
        and re.search(r"\b(\d{1,6})\b", low)
    ):
        reset_flow(st)
        return _finalize(_support_only_reply())

    if (
        (any(k in low for k in {'edit', 'update', 'change', 'set', 'make'}) and any(k in low for k in {'male', 'female'}))
        and (any(k in low for k in {'ride', 'trip', 'recent', 'recently'}) or extract_trip_id(text) or st.last_trip_id)
    ):
        reset_flow(st)
        return _finalize(_support_only_reply())

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
        reset_flow(st)
        return _finalize(_support_only_reply())

    if brain:
        tid = extract_trip_id(text)
        wants_rides = (
            (('api' in low) and any(k in low for k in {'ride', 'rides', 'trip', 'trips'}))
            or ('list my rides' in low)
            or (('my' in low or 'all' in low) and ('created' in low) and any(k in low for k in {'ride', 'rides', 'trip', 'trips'}))
        )
        if wants_rides:
            from .flows import list_user_created_trips_state
            return _finalize(list_user_created_trips_state(st, limit=50))

        if tid and any(k in low for k in {'detail', 'details', 'complete', 'full', 'show'}):
            status, out = api.api_trip_detail_safe(st.ctx, str(tid))
            return _finalize(_format_api_result(status, out))

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
            reset_flow(st)
            return _finalize(_support_only_reply())

        if st.active_flow in {'choose_route', 'choose_trip'} or (st.active_flow or '').startswith('confirm_'):
            pass
        elif re.fullmatch(r"\d{1,6}", low) or (low in {'yes', 'y', 'no', 'n', 'ok', 'okay', 'cancel', 'stop', 'reset'}):
            pass

    llm_routed = None
    if not ((st.active_flow in {'choose_route', 'choose_trip', 'choose_vehicle', 'choose_location'}) or ((st.active_flow or '').startswith('confirm_'))):
        try:
            llm_routed = llm_route_fallback(st, text)
        except Exception as e:
            llm_routed = None

    if st.active_flow == 'choose_location':
        action = st.pending_action if isinstance(st.pending_action, dict) else {}
        if action.get('type') != 'choose_location':
            reset_flow(st)
            return _finalize('Please start again.')
        query = str(action.get('query') or '').strip()
        cands = action.get('candidates') if isinstance(action.get('candidates'), list) else []
        orig = str(action.get('original_text') or '').strip()
        stop_role = str(action.get('stop_role') or '').strip() or None
        stop_index = action.get('stop_index')
        try:
            stop_index = int(stop_index) if stop_index is not None else None
        except Exception:
            stop_index = None
        if not query or not cands or not orig:
            reset_flow(st)
            return _finalize('Please start again.')
        m = re.search(r"\b(\d+)\b", low)
        if not m:
            if any(k in low for k in {'any', 'either', 'whichever'}):
                idx = 1
            else:
                return _finalize('Please reply with the location number (e.g. 1), or type cancel.')
        else:
            idx = int(m.group(1) or 0)
        if idx < 1 or idx > len(cands):
            return _finalize(f"Please choose a number between 1 and {len(cands)}.")
        chosen = cands[idx - 1] if isinstance(cands[idx - 1], dict) else {}
        chosen_name = str(chosen.get('display_name') or '').strip() or query

        def _replace_occurrence(haystack: str, needle: str, repl: str, *, which: str = 'first') -> str:
            try:
                matches = list(re.finditer(re.escape(needle), haystack, flags=re.IGNORECASE))
            except Exception:
                matches = []
            if not matches:
                return haystack
            m0 = matches[-1] if which == 'last' else matches[0]
            return haystack[:m0.start()] + repl + haystack[m0.end():]

        # If we know which side was ambiguous, replace that occurrence.
        # - from => first occurrence
        # - to   => last occurrence
        # Otherwise fall back to first.
        if stop_role == 'to':
            patched = _replace_occurrence(orig, query, chosen_name, which='last')
        else:
            patched = _replace_occurrence(orig, query, chosen_name, which='first')
        reset_flow(st)
        try:
            from .route_helpers import route_search_with_osm_fallback
            res2 = route_search_with_osm_fallback(patched, st.ctx)
            summary2 = (res2.get('summary') if isinstance(res2, dict) else None) or ''
            err2 = (res2.get('error') if isinstance(res2, dict) else None)
            if summary2 and not err2:
                return _finalize(summary2)
            if err2 == 'ambiguous_stop' and isinstance(res2, dict):
                amb2 = res2.get('ambiguity') if isinstance(res2.get('ambiguity'), dict) else {}
                query2 = str((amb2 or {}).get('query') or '').strip()
                cands2 = (amb2 or {}).get('candidates') if isinstance((amb2 or {}).get('candidates'), list) else []
                stop_role2 = str((amb2 or {}).get('stop_role') or '').strip() or None
                stop_index2 = (amb2 or {}).get('stop_index')
                try:
                    stop_index2 = int(stop_index2) if stop_index2 is not None else None
                except Exception:
                    stop_index2 = None
                if query2 and cands2:
                    st.active_flow = 'choose_location'
                    st.awaiting_field = None
                    st.pending_action = {
                        'type': 'choose_location',
                        'original_text': patched,
                        'query': query2,
                        'candidates': cands2[:8],
                        'stop_role': stop_role2,
                        'stop_index': stop_index2,
                    }
                    from .flows import render_location_choice
                    return _finalize(render_location_choice(query2, cands2))
            return _finalize("I couldn't resolve that location clearly. Please try again with more details (city/area).")
        except Exception:
            return _finalize("I couldn't resolve that location clearly. Please try again with more details (city/area).")

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
        'confirm_profile_update',
        'confirm_submit_payment',
        'confirm_confirm_payment',
    }:
        reset_flow(st)
        return _finalize(_support_only_reply())

    # Prefer deterministic rule-intents for system/knowledge actions.
    # LLM extraction can sometimes misclassify them (e.g. 'change requests' -> help), which breaks auth regression.
    rule_intent = _rule_intent(text)
    trace('engine.rule_intent', intent=rule_intent)
    _dbg('rule_intent', {
        'intent': rule_intent,
        'active_flow': getattr(st, 'active_flow', None),
        'awaiting_field': getattr(st, 'awaiting_field', None),
    })
    llm_routed = None
    if rule_intent not in {
        'help',
        'capabilities',
        'greet',
        'faq',
        'manual',
        'manual_about_app',
        'faq_guest_limits',
        'faq_booking_blocked',
        'faq_create_ride_blocked',
        'faq_negotiation',
        'faq_pickup_code',
        'faq_payments',
        'faq_notifications',
        'faq_sos',
        'profile_view',
        'list_change_requests',
        'trip_detail',
        'chat_list',
        'payment_details',
        'list_bookings',
        'list_my_rides',
        'list_vehicles',
    }:
        if not regression_mode:
            try:
                llm_routed = llm_route_fallback(st, text)
            except Exception as e:
                llm_routed = None
                if (os.environ.get('CHATBOT_DEBUG_LLM') or '').strip().lower() in {'1', 'true', 'yes'}:
                    logger.exception('[chatbot][llm_route_fallback][ERROR]: %s', repr(e))
    if llm_routed is not None:
        _dbg('llm_routed', {
            'reply_len': len(llm_routed or ''),
            'reply_preview': (llm_routed or '')[:240],
        })
    if llm_routed is not None:
        return _finalize(llm_routed)

    if brain:
        return _finalize(_support_only_reply())

    smalltalk = help_bot.maybe_handle_smalltalk(st, text)
    if smalltalk is not None and not st.active_flow:
        return _finalize(smalltalk)

    intent = _rule_intent(text)
    trace('engine.intent', intent=intent)
    _dbg('intent', {
        'intent': intent,
        'active_flow': getattr(st, 'active_flow', None),
        'awaiting_field': getattr(st, 'awaiting_field', None),
    })

    # Support-only mode: do not perform account actions or call internal tools.
    # Keep: FAQs/manual/smalltalk/routing assistance.
    support_only_blocked_intents = {
        'profile_update',
        'submit_payment',
        'confirm_payment',
        'book_ride',
        'create_ride',
        'recreate_ride',
        'message',
        'negotiate',
        'cancel_booking',
        'cancel_trip',
        'delete_trip',
    }
    if intent in support_only_blocked_intents:
        reset_flow(st)
        return _finalize(_support_only_reply())
    if intent == 'clarify':
        reset_flow(st)
        return _finalize(
            "I'm not sure what you mean by that. Please ask about a feature (e.g. 'my bookings', 'my rides', 'create ride', 'book ride', 'faqs', 'user manual')."
        )
    help_reply = help_bot.maybe_handle_help(st, text, intent=intent)
    if help_reply is not None:
        return _finalize(help_reply)

    if intent == 'manual_about_app':
        reset_flow(st)
        try:
            from lets_go.management.commands import support_bot_cli as cli

            snaps = cli._manual_snippets_for_query(text, max_sections=1, max_chars=900)
            if snaps:
                return _finalize(str(snaps[0]))
        except Exception:
            pass
        return _finalize(capabilities_text())

    if intent in {
        'faq_guest_limits',
        'faq_booking_blocked',
        'faq_create_ride_blocked',
        'faq_negotiation',
        'faq_pickup_code',
        'faq_payments',
        'faq_notifications',
        'faq_sos',
    }:
        reset_flow(st)
        try:
            from lets_go.management.commands import support_bot_cli as cli

            snaps = cli._faq_snippets_for_query(text, max_items=3)
            if snaps:
                return _finalize("\n\n".join(snaps))
        except Exception:
            pass
        return _finalize(help_text())

    if intent == 'suggest_stops':
        reset_flow(st)
        q = ''
        m = re.search(r"\bq\s*=\s*([^\n\r]+)", text or '', flags=re.IGNORECASE)
        if m:
            q = (m.group(1) or '').strip()
        if not q:
            q = re.sub(r"^\s*suggest\s+stops\s*", "", text or '', flags=re.IGNORECASE).strip()
        status, out = api.api_suggest_stops(q=q or '', limit=8)
        if status <= 0:
            return _finalize('API server not reachable.')
        stops = (out.get('stops') if isinstance(out, dict) else None) or []
        if not isinstance(stops, list) or not stops:
            return _finalize('No stops found. Try a different query.')
        names: list[str] = []
        for s in stops:
            if isinstance(s, dict):
                nm = str(s.get('stop_name') or s.get('name') or '').strip()
                if nm:
                    names.append(nm)
        if not names:
            return _finalize(_format_api_result(status, out))
        lines = ['Stops:']
        for nm in names[:10]:
            lines.append(f"- {nm}")
        return _finalize("\n".join(lines))

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

    if intent == 'trip_detail':
        if int(getattr(st.ctx, 'user_id', 0) or 0) <= 0:
            return _finalize(_format_api_result(403, {'error': 'Guests cannot access this feature.'}))
        # Align with regression expectations: PENDING/REJECTED/BANNED are denied.
        _, access_err = api.require_system_access(st.ctx)
        if access_err:
            return _finalize(access_err)
        trip_id = extract_trip_id(text) or st.last_trip_id
        if not trip_id:
            st.active_flow = 'trip_detail'
            st.awaiting_field = 'trip_id'
            return _finalize('Which trip details do you want? Provide trip_id.')
        status, out = api.api_trip_detail_safe(st.ctx, str(trip_id))
        return _finalize(_format_api_result(status, out))

    if intent == 'list_change_requests':
        _, access_err = api.require_system_access(st.ctx)
        if access_err:
            return _finalize(access_err)
        status, out = api.list_my_change_requests(st.ctx, entity_type='USER_PROFILE', status=None, limit=10)
        if status <= 0:
            return _finalize('API server not reachable.')
        if status in {401, 403}:
            return _finalize(_format_api_result(status, out))
        if not isinstance(out, dict):
            return _finalize(_format_api_result(status, out))
        crs = out.get('change_requests') if isinstance(out.get('change_requests'), list) else []
        if not crs:
            return _finalize('No change requests found.')
        lines = ['Your change requests:']
        for cr in crs[:10]:
            if not isinstance(cr, dict):
                continue
            lines.append(f"- id={cr.get('id')} | entity={cr.get('entity_type')} | status={cr.get('status')} | created_at={cr.get('created_at')}")
        return _finalize("\n".join(lines))

    if intent == 'chat_list':
        if int(getattr(st.ctx, 'user_id', 0) or 0) <= 0:
            return _finalize(_format_api_result(403, {'error': 'Guests cannot access this feature.'}))
        _, access_err = api.require_system_access(st.ctx)
        if access_err:
            return _finalize(access_err)
        trip_id = extract_trip_id(text) or st.last_trip_id
        if not trip_id:
            st.active_flow = 'chat_list'
            st.awaiting_field = 'trip_id'
            return _finalize('Which trip chat do you want to view? Provide trip_id.')
        status, out = api.list_chat(st.ctx, str(trip_id), limit=25)
        return _finalize(_format_api_result(status, out))

    if intent == 'profile_view':
        _, access_err = api.require_system_access(st.ctx)
        if access_err:
            return _finalize(access_err)
        status, out = api.get_my_profile(st.ctx)
        if status <= 0:
            return _finalize('API server not reachable.')
        if status in {401, 403}:
            return _finalize(_format_api_result(status, out))
        if not isinstance(out, dict):
            return _finalize(_format_api_result(status, out))
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
        if int(getattr(st.ctx, 'user_id', 0) or 0) <= 0:
            return _finalize(_format_api_result(403, {'error': 'Guests cannot access this feature.'}))
        _, access_err = api.require_system_access(st.ctx)
        if access_err:
            return _finalize(access_err)
        booking_id = extract_booking_id(text) or st.last_booking_id
        if not booking_id:
            st.active_flow = 'payment_details'
            st.awaiting_field = 'booking_id'
            return _finalize('Which booking payment details do you want? Provide booking_id.')
        status, out = api.get_booking_payment_details_safe(st.ctx, int(booking_id))
        return _finalize(_format_api_result(status, out))

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
        return _finalize(_format_api_result(status, out))

    if intent == 'delete_trip':
        return _finalize(start_manage_trip_flow(st, text, mode='delete'))

    if intent == 'cancel_trip':
        return _finalize(start_manage_trip_flow(st, text, mode='cancel'))

    if not regression_mode:
        llm_reply = llm_chat_reply(st, text)
        if llm_reply:
            return _finalize(llm_reply)

    return _finalize("Tell me what you want to do (for example: book a ride from X to Y, or create a ride).")


def ask_bot(user_id: int, question: str):
    ctx = BotContext(user_id=int(user_id))
    reply = handle_message(ctx, question)
    logger.debug("Bot: %s", reply)
