"""
Route helpers to merge OSM results with existing DB stops as fallback.
Used inside the chatbot to provide hybrid routing.
"""

import datetime
from typing import List, Dict, Any, Optional, Tuple
import re
import traceback
import logging

from .osm_client import build_route_stops, summarize_route_for_cli
from .fare_calculator import calculate_fare
from .fare_matrix import build_fare_matrix_for_route_stops, summarize_matrix_for_cli
from . import api


logger = logging.getLogger(__name__)


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
    # Patterns: "from A to B", "A to B", "A -> B"
    patterns = [
        r"from\s+(.+?)\s+to\s+(.+)",
        r"(.+?)\s+to\s+(.+)",
        r"(.+?)\s*->\s*(.+)",
    ]
    low = text.lower()
    for pat in patterns:
        m = re.search(pat, low)
        if m:
            frm = m.group(1).strip().title()
            to = m.group(2).strip().title()
            # Exclude obvious non-place tokens
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

    # Try to isolate "A to B" part first.
    m = re.search(r"\bfrom\s+(.+?)\s+to\s+(.+)$", low)
    if not m:
        m = re.search(r"^\s*(.+?)\s+to\s+(.+)$", low)
    if not m:
        m = re.search(r"^\s*(.+?)\s*->\s*(.+)$", low)
    if not m:
        return None

    frm_raw = (m.group(1) or '').strip()
    to_raw = (m.group(2) or '').strip()

    # Split out "via ..." from the to-part.
    via_part = ''
    mvia = re.search(r"\bvia\b\s+(.+)$", to_raw)
    if mvia:
        via_part = (mvia.group(1) or '').strip()
        to_raw = re.sub(r"\bvia\b\s+.+$", '', to_raw).strip()

    def _clean_place(s: str) -> str:
        s = (s or '').strip()
        s = re.sub(r"\s+", " ", s)
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

    # De-duplicate while preserving order
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
            # Return simplified dicts for chatbot use
            simplified = []
            for r in routes[:limit]:
                simplified.append({
                    "route_id": r.get("id"),
                    "route_name": r.get("route_name", ""),
                    "stops": r.get("stops", []),
                })
            return simplified
    except Exception:
        pass
    return []

def route_search_with_osm_fallback(text: str, user_context) -> Dict[str, Any]:
    """
    Main entry: try OSM routing first; fall back to DB routes.
    Returns a dict with route options and CLI summaries.
    """
    result = {
        "source": "unknown",
        "routes": [],
        "summary": "",
        "error": None,
    }

    # Extract stop sequence
    seq = extract_stop_sequence_from_text(text)
    if not seq:
        result["error"] = "Could not understand locations. Try: 'From A to B' or 'From A to B via C'."
        return result
    frm, to = seq[0], seq[-1]
    logger.debug("[route_helpers] extracted stop sequence: %r", seq)

    # Try OSM first
    try:
        route_stops = build_route_stops(seq)
        # BotContext is an object, not a dict. Allow optional override if present.
        now_override = getattr(user_context, 'now', None)
        dep_time = now_override if isinstance(now_override, datetime.datetime) else datetime.datetime.now()
        fare_data = calculate_fare(
            route_stops=route_stops,
            fuel_type="Petrol",  # Default; could infer from vehicle later
            vehicle_type="Sedan",
            departure_time=dep_time,
            total_seats=1,
        )
        matrix = build_fare_matrix_for_route_stops(route_stops, fuel_type='Petrol', vehicle_type='Sedan', departure_time=dep_time)
        result["source"] = "osm"
        result["routes"] = [{
            "type": "osm_dynamic",
            "from_stop": frm,
            "to_stop": to,
            "stop_sequence": seq,
            "route_stops": route_stops,
            "fare_calculation": fare_data,
            "fare_matrix": matrix,
        }]
        result["summary"] = summarize_route_for_cli(route_stops) + "\n" + _fare_line_for_cli(fare_data)
        if matrix:
            result["summary"] = result["summary"] + "\n" + summarize_matrix_for_cli(matrix)
        logger.debug("[route_helpers] OSM success")
        return result
    except Exception as e:
        logger.exception("[route_helpers] OSM failed: %s", str(e))
        # OSM failed; fall back to DB
        db_routes = search_db_routes_by_name(frm, to)
        logger.debug("[route_helpers] DB fallback routes count=%s", len(db_routes) if db_routes else 0)
        if db_routes:
            result["source"] = "db_fallback"
            result["routes"] = [{"type": "db_static", **r} for r in db_routes]
            summaries = []
            for r in db_routes:
                name = r.get("route_name", "")
                stops = r.get("stops", [])
                if stops:
                    first = stops[0].get("stop_name", "")
                    last = stops[-1].get("stop_name", "")
                    summaries.append(f"{name}: {first} → {last}")
            result["summary"] = "Found existing routes:\n" + "\n".join(f"- {s}" for s in summaries)
            return result
        else:
            result["source"] = "none"
            result["error"] = f"No route found from '{frm}' to '{to}' via OSM or existing database."
            return result

def cli_route_search_response(text: str, user_context) -> str:
    """
    Produce a CLI-friendly response for route search.
    """
    result = route_search_with_osm_fallback(text, user_context)
    if result["error"]:
        return result["error"]
    return result["summary"]
