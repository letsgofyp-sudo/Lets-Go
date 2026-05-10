"""
Route helpers to merge OSM results with existing DB stops as fallback.
Used inside the chatbot to provide hybrid routing.
"""

import datetime
import os
from typing import List, Dict, Any, Optional, Tuple
import re
import logging

from .osm_client import AmbiguousStopError, build_route_stops, summarize_route_for_cli
from .osm_client import haversine_distance
from ..fare.calculator import calculate_fare
from ..fare.matrix import build_fare_matrix_for_route_stops, summarize_matrix_for_cli
from ..integrations import api


logger = logging.getLogger(__name__)


def _route_stops_from_db_stops(stops: Any) -> Optional[List[Dict[str, Any]]]:
    if not isinstance(stops, list) or len(stops) < 2:
        return None
    coords: list[tuple[float, float]] = []
    names: list[str] = []
    for s in stops:
        if not isinstance(s, dict):
            continue
        lat = s.get('latitude') if s.get('latitude') is not None else s.get('lat')
        lng = s.get('longitude') if s.get('longitude') is not None else s.get('lng')
        if lat is None or lng is None:
            continue
        try:
            coords.append((float(lat), float(lng)))
        except Exception:
            continue
        nm = str(s.get('stop_name') or s.get('name') or '').strip()
        names.append(nm)
    if len(coords) < 2:
        return None
    out: list[Dict[str, Any]] = []
    for i, (lat, lng) in enumerate(coords):
        stop_name = (names[i] if i < len(names) else '').strip() or f"Stop {i + 1}"
        stop: Dict[str, Any] = {
            "stop_order": i + 1,
            "stop_name": stop_name,
            "latitude": float(lat),
            "longitude": float(lng),
            "display_name": stop_name,
        }
        if i == 0:
            stop["distance_from_previous_km"] = 0.0
            stop["duration_from_previous_minutes"] = 0.0
        else:
            d = haversine_distance(coords[i - 1][0], coords[i - 1][1], lat, lng)
            stop["distance_from_previous_km"] = float(d)
            stop["duration_from_previous_minutes"] = float((d / 50.0) * 60.0)
        out.append(stop)
    return out


def _search_routes_json_by_name(from_stop: str, to_stop: str, *, limit: int = 5) -> List[Dict[str, Any]]:
    return []


def _fare_line_for_cli(fare_data: Dict[str, Any]) -> str:
    total_fare = fare_data.get('total_price', 0) if isinstance(fare_data, dict) else 0
    br = fare_data.get('calculation_breakdown') if isinstance(fare_data, dict) else {}
    is_peak = bool((br or {}).get('is_peak_hour'))
    peak_note = ' (peak hour)' if is_peak else ''
    return f"Estimated fare: PKR {int(total_fare or 0)}{peak_note}"


def extract_stop_names_from_text(text: str) -> Optional[Tuple[str, str]]:
    """
    Simple extraction of 'from X to Y' patterns.
    Returns (from_stop, to_stop) or None.
    """

    def _clean_place(s: str) -> str:
        s = (s or '').strip()
        s = re.sub(r"\s+", " ", s)
        s = re.sub(r"^[\s,.;:!?()\[\]{}\-]+", "", s).strip()
        s = re.sub(r"[\s,.;:!?()\[\]{}\-]+$", "", s).strip()
        s = re.sub(r"^please\b\s*", "", s, flags=re.IGNORECASE).strip()

        tail_re = re.compile(
            r"\b(?:fare|price|cost|estimate|estimated|distance|time|duration|minutes|min|km|please)\b$",
            flags=re.IGNORECASE,
        )
        while True:
            s2 = re.sub(r"[\s,.;:!?]+$", "", s).strip()
            s3 = tail_re.sub("", s2).strip()
            if s3 == s:
                break
            s = s3

        low2 = s.lower().strip()
        if not re.search(r"[a-z0-9]", s, flags=re.IGNORECASE):
            return ''
        if low2 in {'from', 'to', 'fare', 'price', 'cost', 'estimate', 'estimated', 'route', 'distance'}:
            return ''
        return s.title()

    patterns = [
        r"from\s+(.+?)\s+to\s+(.+)",
        r"(.+?)\s+to\s+(.+)",
        r"(.+?)\s*->\s*(.+)",
    ]
    low = text.lower()
    for pat in patterns:
        m = re.search(pat, low)
        if m:
            frm = _clean_place(m.group(1))
            to = _clean_place(m.group(2))
            if not frm or not to:
                continue
            exclude = {"ride", "trip", "route", "via", "and", "or", "the"}
            if any(word in exclude for word in frm.split() + to.split()):
                continue
            return frm, to
    return None


def extract_stop_sequence_from_text(text: str) -> Optional[List[str]]:
    """Extract a stop sequence from text.

    Supports:
      - from A to B
      - A to B
      - from A to B via C
      - from A to B via C and D
      - A to B via C, D
    Returns list like [A, C, D, B].
    """
    if not text:
        return None

    low = text.lower().strip()

    m = re.search(r"\bfrom\s+(.+?)\s+to\s+(.+)$", low)
    if not m:
        m = re.search(r"^\s*(.+?)\s+to\s+(.+)$", low)
    if not m:
        m = re.search(r"^\s*(.+?)\s*->\s*(.+)$", low)
    if not m:
        return None

    frm_raw = (m.group(1) or '').strip()
    to_raw = (m.group(2) or '').strip()

    via_part = ''
    mvia = re.search(r"\bvia\b\s+(.+)$", to_raw)
    if mvia:
        via_part = (mvia.group(1) or '').strip()
        to_raw = re.sub(r"\bvia\b\s+.+$", '', to_raw).strip()

    def _clean_place(s: str) -> str:
        s = (s or '').strip()
        s = re.sub(r"\s+", " ", s)
        s = re.sub(r"^[\s,.;:!?()\[\]{}\-]+", "", s).strip()
        s = re.sub(r"[\s,.;:!?()\[\]{}\-]+$", "", s).strip()
        s = re.sub(r"^please\b\s*", "", s, flags=re.IGNORECASE).strip()
        tail_re = re.compile(
            r"\b(?:fare|price|cost|estimate|estimated|distance|time|duration|minutes|min|km|please)\b$",
            flags=re.IGNORECASE,
        )
        while True:
            s2 = re.sub(r"[\s,.;:!?]+$", "", s).strip()
            s3 = tail_re.sub("", s2).strip()
            if s3 == s:
                break
            s = s3
        low2 = s.lower().strip()
        if not re.search(r"[a-z0-9]", s, flags=re.IGNORECASE):
            return ''
        if low2 in {'from', 'to', 'fare', 'price', 'cost', 'estimate', 'estimated', 'route', 'distance'}:
            return ''
        return s.title()

    frm = _clean_place(frm_raw)
    to = _clean_place(to_raw)
    if not frm or not to:
        return None

    exclude = {"ride", "trip", "route", "via", "and", "or", "the"}
    if any(word in exclude for word in frm.split() + to.split()):
        return None

    vias: List[str] = []
    if via_part:
        parts = re.split(r"\s*(?:,|\band\b|\&|/)\s*", via_part)
        for p in parts:
            v = _clean_place(p)
            if v and not any(word in exclude for word in v.split()):
                vias.append(v)

    seq: List[str] = []
    for s in [frm] + vias + [to]:
        if s and s not in seq:
            seq.append(s)

    if len(seq) < 2:
        return None
    return seq


def search_db_routes_by_name(from_stop: str, to_stop: str, limit: int = 5) -> List[Dict[str, Any]]:
    """
    Fallback: search existing DB routes by matching stop names.
    Returns list of route dicts (simplified) or empty.
    """
    try:
        status, out = api.api_search_routes(from_location=from_stop, to_location=to_stop)
        if status > 0 and isinstance(out, dict):
            routes = out.get("routes", [])
            simplified = []
            for r in routes[:limit]:
                simplified.append(
                    {
                        "route_id": r.get("id"),
                        "route_name": r.get("route_name", ""),
                        "stops": r.get("stops", []),
                    }
                )
            return simplified
    except Exception:
        pass
    return []


def route_search_with_osm_fallback(text: str, user_context) -> Dict[str, Any]:
    """
    Main entry: try OSM routing first; fall back to DB routes.
    Returns a dict with route options and CLI summaries.
    """
    from ..tools.trace import trace

    trace('route_helpers.route_search.enter', text=text)
    result = {
        "source": "unknown",
        "routes": [],
        "summary": "",
        "error": None,
    }

    seq = extract_stop_sequence_from_text(text)
    if not seq:
        trace('route_helpers.route_search.no_sequence')
        result["error"] = "I couldn't understand the locations. Try: 'From A to B' or 'From A to B via C'."
        return result
    frm, to = seq[0], seq[-1]
    trace('route_helpers.route_search.sequence', frm=frm, to=to, seq=seq)
    logger.debug("[route_helpers] extracted stop sequence: %r", seq)

    try:
        route_stops = build_route_stops(seq)
        trace(
            'route_helpers.route_search.osm.route_stops',
            n_stops=len(route_stops) if isinstance(route_stops, list) else None,
        )
        now_override = getattr(user_context, 'now', None)
        dep_time = now_override if isinstance(now_override, datetime.datetime) else datetime.datetime.now()
        fare_data = calculate_fare(
            route_stops=route_stops,
            fuel_type="Petrol",
            vehicle_type="Sedan",
            departure_time=dep_time,
            total_seats=1,
        )
        matrix = build_fare_matrix_for_route_stops(
            route_stops,
            fuel_type='Petrol',
            vehicle_type='Sedan',
            departure_time=dep_time,
        )
        result["source"] = "osm"
        result["routes"] = [
            {
                "type": "osm_dynamic",
                "from_stop": frm,
                "to_stop": to,
                "stop_sequence": seq,
                "route_stops": route_stops,
                "fare_calculation": fare_data,
                "fare_matrix": matrix,
            }
        ]
        result["summary"] = summarize_route_for_cli(route_stops) + "\n" + _fare_line_for_cli(fare_data)
        if matrix:
            result["summary"] = result["summary"] + "\n" + summarize_matrix_for_cli(matrix)
        trace(
            'route_helpers.route_search.osm.success',
            distance_km=(fare_data or {}).get('total_distance_km') if isinstance(fare_data, dict) else None,
            total_price=(fare_data or {}).get('total_price') if isinstance(fare_data, dict) else None,
        )
        logger.debug("[route_helpers] OSM success")
        return result
    except AmbiguousStopError as e:
        trace(
            'route_helpers.route_search.osm.ambiguous',
            query=getattr(e, 'query', None),
            n_candidates=len(getattr(e, 'candidates', []) or []),
        )
        result["source"] = "osm"
        result["routes"] = []
        result["summary"] = ""
        result["error"] = "ambiguous_stop"
        result["ambiguity"] = {
            "query": getattr(e, 'query', None),
            "candidates": getattr(e, 'candidates', []) or [],
            "stop_index": getattr(e, 'stop_index', None),
            "stop_role": getattr(e, 'stop_role', None),
        }
        return result
    except Exception as e:
        trace('route_helpers.route_search.osm.failed', error=str(e))
        logger.warning("[route_helpers] OSM failed: %s", str(e))
        db_routes = search_db_routes_by_name(frm, to)
        trace(
            'route_helpers.route_search.db_fallback',
            routes=len(db_routes) if isinstance(db_routes, list) else None,
        )
        logger.debug("[route_helpers] DB fallback routes count=%s", len(db_routes) if db_routes else 0)
        if db_routes:
            result["source"] = "db_fallback"
            result["routes"] = [{"type": "db_static", **r} for r in db_routes]

            try:
                first_route = db_routes[0] if isinstance(db_routes[0], dict) else {}
                route_stops = _route_stops_from_db_stops(first_route.get("stops"))
                if route_stops:
                    now_override = getattr(user_context, 'now', None)
                    dep_time = now_override if isinstance(now_override, datetime.datetime) else datetime.datetime.now()
                    fare_data = calculate_fare(
                        route_stops=route_stops,
                        fuel_type="Petrol",
                        vehicle_type="Sedan",
                        departure_time=dep_time,
                        total_seats=1,
                    )
                    matrix = build_fare_matrix_for_route_stops(
                        route_stops,
                        fuel_type='Petrol',
                        vehicle_type='Sedan',
                        departure_time=dep_time,
                    )
                    result["routes"] = [
                        {
                            "type": "db_static_estimated",
                            "from_stop": frm,
                            "to_stop": to,
                            "stop_sequence": seq,
                            "route_name": str(first_route.get("route_name") or '').strip(),
                            "route_id": first_route.get("route_id"),
                            "route_stops": route_stops,
                            "fare_calculation": fare_data,
                            "fare_matrix": matrix,
                        }
                    ]
                    result["summary"] = summarize_route_for_cli(route_stops) + "\n" + _fare_line_for_cli(fare_data)
                    if matrix:
                        result["summary"] = result["summary"] + "\n" + summarize_matrix_for_cli(matrix)
                    return result
            except Exception:
                pass

            summaries = []
            for r in db_routes:
                name = r.get("route_name", "")
                stops = r.get("stops", [])
                if stops and isinstance(stops, list):
                    first = (stops[0] or {}).get("stop_name", "") if isinstance(stops[0], dict) else ""
                    last = (stops[-1] or {}).get("stop_name", "") if isinstance(stops[-1], dict) else ""
                    summaries.append(f"{name}: {first} → {last}")
                elif name:
                    summaries.append(str(name))
            result["summary"] = "Found existing routes:\n" + "\n".join(f"- {s}" for s in summaries)
            return result

        json_routes = _search_routes_json_by_name(frm, to, limit=5)
        if json_routes:
            result["source"] = "json_fallback"
            result["routes"] = [{"type": "json_static", **r} for r in json_routes]
            summaries2 = [
                str(r.get('route_name') or '').strip()
                for r in json_routes
                if str(r.get('route_name') or '').strip()
            ]
            result["summary"] = "Found existing routes (offline):\n" + "\n".join(f"- {s}" for s in summaries2)
            return result

        result["source"] = "none"
        result["error"] = f"No route found from '{frm}' to '{to}'. Please check the place names and try again."
        return result


def cli_route_search_response(text: str, user_context) -> str:
    """
    Produce a CLI-friendly response for route search.
    """
    result = route_search_with_osm_fallback(text, user_context)
    if result["error"]:
        if result.get('error') == 'ambiguous_stop':
            return "I found multiple matches for one of the locations. Please add more details (city/area) and try again."
        return f"Estimated fare unavailable. {result['error']} Please check your locations and try again."
    return result["summary"]
