from __future__ import annotations

import difflib
import re
from typing import Optional

from ..integrations import api
from ..common.helpers import (
    contains_abuse,
    extract_coord_pairs,
    extract_from_to,
    fuzzy_stop_name,
    looks_like_route_id,
    nearest_stop_name,
    normalize_text,
    to_int,
)
from ..llm import llm_chat_reply, llm_extract_cached
from ..core import ConversationState

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


def routes_from_stop_suggestions(from_q: str, to_q: str) -> list[dict]:
    s1, out1 = api.api_suggest_stops(q=from_q or '', limit=10)
    s2, out2 = api.api_suggest_stops(q=to_q or '', limit=10)
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
        routes.append({'id': rid, 'name': (a.get('name') or b.get('name') or rid), '_score': float(a.get('_score') or 0.0) + float(b.get('_score') or 0.0)})

    routes.sort(key=lambda x: -float(x.get('_score') or 0.0))
    for r in routes:
        r.pop('_score', None)
    return routes[:8]


def resolve_route_from_text(st: ConversationState, raw: str) -> Optional[str]:
    d = st.create_ride
    t = (raw or '').strip()
    if not t:
        return None

    if contains_abuse(t):
        return "I want to help, but please keep it respectful. Tell me the pickup and drop-off stops like: 'Quaid-e-Azam Park to Fasal Town'."

    m = re.search(r"\b(R[0-9A-Z]{2,12})\b", t, flags=re.IGNORECASE)
    if m:
        candidate = (m.group(1) or '').strip().upper()
        if looks_like_route_id(candidate):
            d.route_id = candidate
            d.route_name = None
            d.route_candidates = None
            return None

    llm = llm_extract_cached(st, t)
    if isinstance(llm, dict) and llm.get('route_id') and looks_like_route_id(str(llm.get('route_id')).strip()):
        d.route_id = str(llm.get('route_id')).strip().upper()
        d.route_name = None
        d.route_candidates = None
        return None

    frm, to = extract_from_to(t)
    if isinstance(llm, dict):
        if llm.get('from_stop') and not frm:
            frm = str(llm.get('from_stop')).strip() or frm
        if llm.get('to_stop') and not to:
            to = str(llm.get('to_stop')).strip() or to

    if not frm and not to:
        if len(t) <= 64 and not re.search(r"\b(recreate|re-book|rebook|book|booking|create|post|ride|trip|recent|last)\b", t, flags=re.IGNORECASE):
            m2 = re.search(r"^(.+?)\s+to\s+(.+)$", t, flags=re.IGNORECASE)
            if m2:
                left = (m2.group(1) or '').strip(' ,.-')
                right = (m2.group(2) or '').strip(' ,.-')
                if 0 < len(left) <= 32 and 0 < len(right) <= 32:
                    frm = left or None
                    to = right or None

    if not frm and not to:
        pairs = extract_coord_pairs(t)
        if pairs:
            if len(pairs) >= 2:
                frm = _nearest_stop_name_db_first(pairs[0][0], pairs[0][1]) or frm
                to = _nearest_stop_name_db_first(pairs[1][0], pairs[1][1]) or to
            else:
                frm = _nearest_stop_name_db_first(pairs[0][0], pairs[0][1]) or frm

    if not frm or not to:
        llm_reply = llm_chat_reply(st, t)
        if llm_reply:
            return llm_reply
        return "Tell me the route using two stop names, like: 'Quaid-e-Azam Park to Fasal Town'."

    frm2 = fuzzy_stop_name(frm) or frm
    to2 = fuzzy_stop_name(to) or to

    status, out = api.api_search_routes(from_location=frm2, to_location=to2)
    routes = (out.get('routes') if isinstance(out, dict) else None) or []
    if status <= 0:
        return 'API server not reachable.'

    if status not in {200, 201, 202}:
        return format_api_result(status, out)

    if not isinstance(routes, list) or not routes:
        derived = routes_from_stop_suggestions(frm2, to2)
        if derived:
            raw_norm = normalize_text(t)
            scored: list[tuple[float, dict]] = []
            for r in derived:
                if not isinstance(r, dict):
                    continue
                name = str(r.get('name') or '')
                rid = str(r.get('id') or '')
                score = max(
                    difflib.SequenceMatcher(a=raw_norm, b=normalize_text(name)).ratio(),
                    difflib.SequenceMatcher(a=raw_norm, b=normalize_text(rid)).ratio(),
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
            return render_route_choice(d.route_candidates)

        d.route_id = None
        d.route_name = t
        d.route_candidates = None
        llm_reply = llm_chat_reply(st, f"User couldn't find route for: from={frm2} to={to2}. Help them rephrase with correct stop names.")
        return llm_reply or "I couldn't find that route in the system. Try slightly different stop names (or tell me nearby landmarks), like: 'Vehari Quaid-e-Azam Park to Vehari Fasal Town'."

    if len(routes) == 1:
        r0 = routes[0]
        if isinstance(r0, dict):
            d.route_id = str(r0.get('id') or '').strip() or d.route_id
            d.route_name = str(r0.get('name') or '').strip() or None
            d.route_candidates = None
        return None

    raw_norm = normalize_text(t)
    scored: list[tuple[float, dict]] = []
    for r in routes:
        if not isinstance(r, dict):
            continue
        name = str(r.get('name') or '')
        rid = str(r.get('id') or '')
        score = max(
            difflib.SequenceMatcher(a=raw_norm, b=normalize_text(name)).ratio(),
            difflib.SequenceMatcher(a=raw_norm, b=normalize_text(rid)).ratio(),
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
    return render_route_choice(d.route_candidates)
