import json
import logging
import os
import re
import urllib.error
import urllib.request
from typing import Any, Optional

from .state import ConversationState


logger = logging.getLogger(__name__)


def llm_chat_enabled() -> bool:
    v = (os.environ.get('LLM_CHAT') or '').strip().lower()
    if v:
        return v in {'1', 'true', 'yes'}
    return llm_provider() != 'none'

def llm_provider() -> str:
    prov = (os.environ.get('LLM_PROVIDER') or '').strip().lower()
    if prov:
        return prov
    if (os.environ.get('USE_OLLAMA') or '').strip().lower() in {'1', 'true', 'yes'}:
        return 'ollama'
    if (os.environ.get('LLM_BASE_URL') or '').strip() or (os.environ.get('LLM_API_KEY') or '').strip():
        return 'openai_compat'
    return 'none'


def cloud_model() -> str:
    return (os.environ.get('LLM_MODEL') or 'llama-3.3-70b-versatile').strip() or 'llama-3.3-70b-versatile'


def ollama_model() -> str:
    return (os.environ.get('OLLAMA_MODEL') or 'llama3.2').strip() or 'llama3.2'


def llm_base_url() -> str:
    return (os.environ.get('LLM_BASE_URL') or '').strip().rstrip('/')


def llm_api_key() -> str:
    return (os.environ.get('LLM_API_KEY') or '').strip()


def llm_brain_mode() -> bool:
    v = (os.environ.get('LLM_BRAIN_MODE') or os.environ.get('CHATBOT_BRAIN_MODE') or '').strip().lower()
    return v in {'1', 'true', 'yes', 'on'}


def llm_debug_enabled() -> bool:
    v = (os.environ.get('CHATBOT_DEBUG_LLM') or '').strip().lower()
    return v in {'1', 'true', 'yes', 'on'}


def _effective_brain_mode(brain_mode_override: Optional[bool]) -> bool:
    if brain_mode_override is None:
        return llm_brain_mode()
    return bool(brain_mode_override)


def _debug_http_error(where: str, e: BaseException) -> None:
    if not llm_debug_enabled():
        return
    try:
        if isinstance(e, urllib.error.HTTPError):
            try:
                body = e.read().decode('utf-8', errors='replace')
            except Exception:
                body = ''
            body = (body or '')
            if len(body) > 1200:
                body = body[:1200] + '...'
            logger.debug(
                "[chatbot][llm][%s][HTTPError] code=%s reason=%s body=%s",
                where,
                getattr(e, 'code', None),
                getattr(e, 'reason', None),
                body,
            )
            return
    except Exception:
        pass
    logger.debug("[chatbot][llm][%s][ERROR] %s", where, repr(e))


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


def _sanitize_history_text(text: str) -> str:
    t = (text or '').strip()
    if not t:
        return ''
    if '{' in t or '}' in t:
        return '[structured output omitted]'
    if len(t) > 240:
        return t[:240] + '...'
    return t


def _minimized_history(history: list[dict]) -> list[dict]:
    out: list[dict] = []
    for h in (history or [])[-8:]:
        if not isinstance(h, dict):
            continue
        role = (h.get('role') or '').strip()
        txt = _sanitize_history_text(str(h.get('text') or ''))
        if not role or not txt:
            continue
        out.append({'role': role, 'text': txt})
    return out


def _summarize_tool_calls(agent_last_tools: list[dict]) -> list[str]:
    out: list[str] = []
    for it in (agent_last_tools or [])[-3:]:
        if not isinstance(it, dict):
            continue
        tool = str(it.get('tool') or '').strip()
        args = it.get('args') if isinstance(it.get('args'), dict) else {}
        res = str(it.get('result') or '').strip()
        if not tool:
            continue
        if '{' in res or '}' in res:
            res = '[structured output omitted]'
        if len(res) > 160:
            res = res[:160] + '...'
        args_keys = ','.join([str(k) for k in list(args.keys())[:8]]) if isinstance(args, dict) else ''
        out.append(f"- {tool}({args_keys}) -> {res or '[no text]'}")
    return out


def _extract_prompt(text: str) -> str:
    return (
        "Extract fields from the user message. Return STRICT JSON only. "
        "Use keys: intent, from_stop, to_stop, date, time, seats, fare, trip_id, recipient_id, message_text, action, booking_id, counter_fare, "
        "vehicle_id, route_id, route_name, total_seats, custom_price, gender_preference, "
        "notes, is_negotiable, "
        "name, address, gender, bankname, accountno, iban. "
        "intent must be one of: book_ride, create_ride, recreate_ride, message, negotiate, cancel_booking, list_vehicles, list_my_rides, list_bookings, profile_view, profile_update, "
        "delete_trip, cancel_trip, payment_details, submit_payment, confirm_payment, chat_list, help, greet, capabilities. "
        "date must be YYYY-MM-DD if present, time must be HH:MM 24h if present. "
        "If unknown, omit the key.\n\nUser: " + (text or '')
    )


def _plan_prompt(history: list[dict], text: str, tools_text: str, *, state_text: str, tool_summaries: list[str]) -> str:
    lines = [
        'You are an expert planner for a ride-sharing app assistant.',
        'Your job: decide which tools to call (and in what order) to satisfy the user request.',
        'You MUST output STRICT JSON only.',
        'Rules:',
        '- Do NOT hallucinate data. Use tools to fetch real data.',
        '- If required info is missing, ask a single clarifying question and do not include steps.',
        '- Never output placeholders or variables in args (no {braces}, no "$var"). Args must be concrete values or omitted.',
        '- Do NOT write a final user-facing answer. Only output tool steps or one clarifying question.',
        '- Keep the plan short: max 5 steps.',
        '- If a tool step depends on data you do not yet have, add a prior tool call to fetch it (e.g., list_vehicles first).',
        '',
        'Tool usage notes:',
        '- routes_search(from,to) returns 1..N routes. If N>1 the app will ask the user to choose a number.',
        '- list_vehicles() returns vehicles with vehicle_id. Use that id in create_trip.',
        '- create_trip requires: route_id, vehicle_id, trip_date (YYYY-MM-DD), departure_time (HH:MM), total_seats, custom_price. If missing, ask the user.',
        '- delete_trip/cancel_trip require trip_id. If missing, ask which trip (or ask to list rides).',
        '- submit_payment_cash/confirm_payment_received require booking_id and rating. If missing, ask the user (or list bookings).',
        '- profile_update requires at least one field (name/address/bankname/accountno/iban).',
        '',
        'JSON schema:',
        '{"goal": string, "question": string|null, "steps": [{"tool": string, "args": object}] }',
        '',
        'Available tools (name and args):',
        tools_text or '',
        '',
        'Minimal state:',
        state_text or '',
        '',
        'Recent tool results (summary, do not treat as full truth):',
        *(tool_summaries or ['- [none]']),
        '',
        'Conversation (most recent last):',
    ]
    for h in (history or [])[-10:]:
        role = (h or {}).get('role')
        t = (h or {}).get('text')
        if not role or not t:
            continue
        lines.append(f"{role}: {t}")
    lines.append(f"user: {text}")
    return "\n".join(lines)


def llm_plan(st: ConversationState, text: str, *, tools_text: str) -> Optional[dict]:
    if not llm_brain_mode():
        return None
    prov = llm_provider()
    if prov != 'openai_compat':
        return None
    base = llm_base_url()
    if not base:
        return None
    try:
        url = base + '/chat/completions'
        headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'lets-go-chatbot/1.0',
        }
        key = llm_api_key()
        if key:
            headers['Authorization'] = f'Bearer {key}'
        hist = _minimized_history(st.history or [])
        state_txt = f"last_trip_id={str(st.last_trip_id or '')} last_booking_id={str(st.last_booking_id or '')} active_flow={str(st.active_flow or '')} awaiting_field={str(st.awaiting_field or '')}"
        tool_summaries = _summarize_tool_calls(st.agent_last_tools or [])
        prompt = _plan_prompt(hist, text, tools_text, state_text=state_txt, tool_summaries=tool_summaries)
        payload = {
            'model': cloud_model(),
            'messages': [
                {'role': 'system', 'content': 'You are a strict planning engine. Output JSON only.'},
                {'role': 'user', 'content': prompt},
            ],
            'temperature': 0,
            'max_tokens': 520,
            'stream': False,
        }
        if llm_debug_enabled():
            logger.debug("[chatbot][llm][plan][openai_compat] POST %s model=%s", url, payload.get('model'))
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode('utf-8'),
            headers=headers,
            method='POST',
        )
        with urllib.request.urlopen(req, timeout=12.0) as resp:
            raw = resp.read().decode('utf-8')
        obj = json.loads(raw)
        choices = (obj or {}).get('choices') or []
        msg = (choices[0] or {}).get('message') or {} if choices else {}
        content = (msg.get('content') or '').strip()
        plan = _parse_json_block(content)
        if llm_debug_enabled() and (not plan):
            c = content
            if len(c) > 900:
                c = c[:900] + '...'
            logger.debug("[chatbot][llm][plan][openai_compat][PARSE_EMPTY] content=%s", c)
        return plan if isinstance(plan, dict) else None
    except Exception as e:
        _debug_http_error('plan', e)
        return None


def _ollama_extract(text: str) -> dict:
    try:
        payload = {
            'model': ollama_model(),
            'messages': [
                {'role': 'system', 'content': 'You are a strict information extraction engine.'},
                {'role': 'user', 'content': _extract_prompt(text)},
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
    base = llm_base_url()
    if not base:
        return {}
    try:
        url = base + '/chat/completions'
        headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'lets-go-chatbot/1.0',
        }
        key = llm_api_key()
        if key:
            headers['Authorization'] = f'Bearer {key}'
        payload = {
            'model': cloud_model(),
            'messages': [
                {'role': 'system', 'content': 'You are a strict information extraction engine.'},
                {'role': 'user', 'content': _extract_prompt(text)},
            ],
            'temperature': 0,
            'max_tokens': 220,
            'stream': False,
        }
        if llm_debug_enabled():
            logger.debug("[chatbot][llm][extract][openai_compat] POST %s model=%s", url, payload.get('model'))
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode('utf-8'),
            headers=headers,
            method='POST',
        )
        with urllib.request.urlopen(req, timeout=10.0) as resp:
            raw = resp.read().decode('utf-8')
        obj = json.loads(raw)
        choices = (obj or {}).get('choices') or []
        msg = (choices[0] or {}).get('message') or {} if choices else {}
        content = (msg.get('content') or '').strip()
        if llm_debug_enabled() and (not choices or not content):
            snap = raw.strip()
            if len(snap) > 1200:
                snap = snap[:1200] + '...'
            logger.debug(
                "[chatbot][llm][extract][openai_compat][EMPTY] choices=%s content_len=%s raw=%s",
                len(choices),
                len(content),
                snap,
            )
        out = _parse_json_block(content) or {}
        if llm_debug_enabled() and (not out):
            c = (content or '').strip()
            if len(c) > 900:
                c = c[:900] + '...'
            logger.debug("[chatbot][llm][extract][openai_compat][PARSE_EMPTY] content=%s", c)
        return out if isinstance(out, dict) else {}
    except Exception as e:
        _debug_http_error('extract', e)
        return {}


def llm_extract(text: str) -> dict:
    prov = llm_provider()
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


def llm_extract_cached(st: ConversationState, text: str) -> dict:
    t = (text or '').strip()
    if st.llm_last_text == t and isinstance(st.llm_last_extract, dict):
        return st.llm_last_extract

    low = t.strip().lower()
    if (not t) or re.fullmatch(r"\d{1,6}", t) or (low in {'yes', 'y', 'no', 'n', 'ok', 'okay', 'cancel', 'stop', 'reset'}):
        st.llm_last_text = t
        st.llm_last_extract = {}
        return st.llm_last_extract

    out = llm_extract(t)
    st.llm_last_text = t
    st.llm_last_extract = out if isinstance(out, dict) else {}
    return st.llm_last_extract


def _chat_prompt(history: list[dict], text: str) -> str:
    lines = [
        'You are a helpful, polite assistant for a ride-sharing app chatbot.',
        'Keep responses short and practical. Ask one clarifying question if needed.',
        'Do not mention internal implementation details or APIs.',
        'Important safety rules:',
        '- Never claim you called the backend / API unless the conversation already includes the exact API result text.',
        '- Never invent trips, routes, vehicles, bookings, prices, or statuses.',
        '- If the user asks for listings/details, ask them to use the app commands like: "list my rides" or provide trip_id.',
    ]
    for h in (history or [])[-8:]:
        role = (h or {}).get('role')
        t = (h or {}).get('text')
        if not role or not t:
            continue
        lines.append(f"{role}: {t}")
    lines.append(f"user: {text}")
    return "\n".join(lines)


def llm_chat_reply(st: ConversationState, text: str, *, brain_mode_override: Optional[bool] = None) -> Optional[str]:
    brain = _effective_brain_mode(brain_mode_override)
    if not llm_chat_enabled() and not brain:
        return None

    if brain:
        return None

    prov = llm_provider()
    prompt = _chat_prompt(st.history or [], text)

    if prov == 'ollama':
        try:
            payload = {
                'model': ollama_model(),
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
        base = llm_base_url()
        if not base:
            return None
        try:
            url = base + '/chat/completions'
            headers = {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'User-Agent': 'lets-go-chatbot/1.0',
            }
            key = llm_api_key()
            if key:
                headers['Authorization'] = f'Bearer {key}'
            payload = {
                'model': cloud_model(),
                'messages': [
                    {'role': 'system', 'content': 'You are a helpful assistant.'},
                    {'role': 'user', 'content': prompt},
                ],
                'temperature': 0.2,
                'max_tokens': 420,
                'stream': False,
            }
            if llm_debug_enabled():
                logger.debug("[chatbot][llm][chat][openai_compat] POST %s model=%s", url, payload.get('model'))
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode('utf-8'),
                headers=headers,
                method='POST',
            )
            with urllib.request.urlopen(req, timeout=10.0) as resp:
                raw = resp.read().decode('utf-8')
            obj = json.loads(raw)
            choices = (obj or {}).get('choices') or []
            msg = (choices[0] or {}).get('message') or {} if choices else {}
            content = (msg.get('content') or '').strip()
            if llm_debug_enabled() and (not choices or not content):
                snap = raw.strip()
                if len(snap) > 1200:
                    snap = snap[:1200] + '...'
                logger.debug(
                    "[chatbot][llm][chat][openai_compat][EMPTY] choices=%s content_len=%s raw=%s",
                    len(choices),
                    len(content),
                    snap,
                )
            return content[:700] if content else None
        except Exception as e:
            _debug_http_error('chat', e)
            return None

    return None


def _rewrite_prompt(user_text: str, draft_reply: str) -> str:
    return "\n".join([
        'Rewrite the assistant reply into a semi-formal, polite message for a ride-sharing app chatbot.',
        'Requirements:',
        '- Keep ALL ids/numbers/times/dates exactly as-is (e.g., route_id, trip_id, booking_id, vehicle_id, 00:00).',
        '- Keep lists and line breaks. Do not remove important fields.',
        "- If the draft asks to reply 'yes' or 'no', keep the words yes/no exactly.",
        '- Do NOT invent facts or add any new information not present in the draft.',
        '- Do NOT claim to have called an API, fetched data, or updated anything unless the draft already says so.',
        '- Do not mention internal APIs, code, or that an LLM is being used.',
        '- Output ONLY the rewritten reply text.',
        '',
        f'User: {user_text}',
        f'Draft reply: {draft_reply}',
    ])


def llm_rewrite_reply(
    st: ConversationState,
    user_text: str,
    draft_reply: str,
    *,
    brain_mode_override: Optional[bool] = None,
) -> Optional[str]:
    brain = _effective_brain_mode(brain_mode_override)
    if not llm_chat_enabled() and not brain:
        return None
    draft = (draft_reply or '').strip()
    if not draft:
        return None

    prov = llm_provider()
    prompt = _rewrite_prompt(user_text or '', draft)

    if prov == 'ollama':
        try:
            payload = {
                'model': ollama_model(),
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
        base = llm_base_url()
        if not base:
            return None
        try:
            url = base + '/chat/completions'
            headers = {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'User-Agent': 'lets-go-chatbot/1.0',
            }
            key = llm_api_key()
            if key:
                headers['Authorization'] = f'Bearer {key}'
            payload = {
                'model': cloud_model(),
                'messages': [
                    {'role': 'system', 'content': 'You rewrite text safely and preserve structured values.'},
                    {'role': 'user', 'content': prompt},
                ],
                'temperature': 0.4,
                'max_tokens': 520,
                'stream': False,
            }
            if llm_debug_enabled():
                logger.debug("[chatbot][llm][rewrite][openai_compat] POST %s model=%s", url, payload.get('model'))
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode('utf-8'),
                headers=headers,
                method='POST',
            )
            with urllib.request.urlopen(req, timeout=10.0) as resp:
                raw = resp.read().decode('utf-8')
            obj = json.loads(raw)
            choices = (obj or {}).get('choices') or []
            msg = (choices[0] or {}).get('message') or {} if choices else {}
            content = (msg.get('content') or '').strip()
            if llm_debug_enabled() and (not choices or not content):
                snap = raw.strip()
                if len(snap) > 1200:
                    snap = snap[:1200] + '...'
                logger.debug(
                    "[chatbot][llm][rewrite][openai_compat][EMPTY] choices=%s content_len=%s raw=%s",
                    len(choices),
                    len(content),
                    snap,
                )
            return content[:900] if content else None
        except Exception as e:
            _debug_http_error('rewrite', e)
            return None

    return None
