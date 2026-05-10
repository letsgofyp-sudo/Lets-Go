"""
OpenStreetMap client for geocoding (Nominatim) and routing (OSRM).
Used inside the chatbot to provide dynamic routing with DB fallback.
"""

import json
import math
import requests
from typing import List, Dict, Any, Optional, Tuple

import logging

from .config import ORS_API_KEY, STOPS_GEO_JSON
from .helpers import normalize_text


logger = logging.getLogger(__name__)


_STOPS_GEO_CACHE: Optional[list[dict]] = None


def _load_stops_geo() -> list[dict]:
    global _STOPS_GEO_CACHE
    if isinstance(_STOPS_GEO_CACHE, list):
        return _STOPS_GEO_CACHE
    try:
        with open(STOPS_GEO_JSON, 'r', encoding='utf-8') as f:
            obj = json.load(f)
        if isinstance(obj, list):
            _STOPS_GEO_CACHE = [x for x in obj if isinstance(x, dict)]
        else:
            _STOPS_GEO_CACHE = []
    except Exception:
        _STOPS_GEO_CACHE = []
    return _STOPS_GEO_CACHE


def _geocode_from_local_stops(query: str) -> Optional[Dict[str, Any]]:
    """Try to resolve query against local stops_geo.json (more reliable than global OSM search)."""
    q = normalize_text(query)
    if not q:
        return None
    stops = _load_stops_geo()
    if not stops:
        return None

    best: Optional[dict] = None
    best_score = 0.0
    for s in stops:
        name = normalize_text(str(s.get('name') or s.get('stop_name') or ''))
        if not name:
            continue
        # Exact/contains checks first
        if name == q:
            best = s
            best_score = 1.0
            break
        if q in name or name in q:
            # If query is a short alias (e.g. 'comsats') and appears in a longer local stop name,
            # treat it as a strong match.
            if len(q) >= 4 and q in name:
                score = 0.8
            else:
                score = min(0.95, (min(len(q), len(name)) / max(len(q), len(name))) + 0.2)
            if score > best_score:
                best = s
                best_score = score
            continue
        # Token overlap heuristic
        qt = set(q.split())
        nt = set(name.split())
        if qt and nt:
            inter = len(qt & nt)
            # Single-token queries like 'comsats' should match any local stop that contains that token.
            if len(qt) == 1 and inter == 1:
                score = 0.7
            else:
                score = inter / max(len(qt), len(nt))
            if score > best_score:
                best = s
                best_score = score

    if not best or best_score < 0.55:
        return None

    lat = best.get('lat') if best.get('lat') is not None else best.get('latitude')
    lon = best.get('lng') if best.get('lng') is not None else best.get('lon')
    if lat is None or lon is None:
        return None
    try:
        lat_f = float(lat)
        lon_f = float(lon)
    except Exception:
        return None
    display = str(best.get('display_name') or best.get('name') or best.get('stop_name') or query).strip()
    return {"lat": lat_f, "lon": lon_f, "display_name": display, "address": {"source": "local_stops"}}


class AmbiguousStopError(ValueError):
    def __init__(
        self,
        query: str,
        candidates: List[Dict[str, Any]],
        *,
        stop_index: Optional[int] = None,
        stop_role: Optional[str] = None,
    ):
        super().__init__(f"Ambiguous stop: {query}")
        self.query = query
        self.candidates = candidates
        self.stop_index = stop_index
        self.stop_role = stop_role


def _score_candidate(query_norm: str, cand_name: str) -> float:
    name_norm = normalize_text(cand_name)
    if not query_norm or not name_norm:
        return 0.0
    if name_norm == query_norm:
        return 1.0
    if query_norm in name_norm:
        return 0.9
    qt = set(query_norm.split())
    nt = set(name_norm.split())
    if not qt or not nt:
        return 0.0
    inter = len(qt & nt)
    return inter / max(len(qt), len(nt))


def geocode_stop_candidates(query: str, country: str = "Pakistan", *, limit: int = 5) -> List[Dict[str, Any]]:
    from .trace import trace
    trace('osm_client.geocode_stop_candidates.enter', query=query, limit=limit)

    qn = normalize_text(query)
    out: List[Dict[str, Any]] = []

    # Local stops (single best match)
    local = _geocode_from_local_stops(query)
    if local:
        out.append({**local, "source": "local"})

    # Major cities
    major_cities = {
        "lahore": (31.5497, 74.3436, "Lahore, Pakistan"),
        "multan": (30.1575, 71.5249, "Multan, Pakistan"),
        "karachi": (24.8607, 67.0011, "Karachi, Pakistan"),
        "islamabad": (33.6844, 73.0479, "Islamabad, Pakistan"),
        "rawalpindi": (33.5651, 73.0169, "Rawalpindi, Pakistan"),
        "faisalabad": (31.4504, 73.1150, "Faisalabad, Pakistan"),
        "vehari": (30.0333, 72.3333, "Vehari, Pakistan"),
        "peoples colony": (30.0500, 72.3500, "Peoples Colony, Vehari"),
    }
    key = (query or '').strip().lower()
    if key in major_cities:
        lat, lon, name = major_cities[key]
        out.append({"lat": lat, "lon": lon, "display_name": name, "address": {}, "source": "major_city"})

    # ORS candidates
    if ORS_API_KEY:
        try:
            trace('osm_client.geocode_stop_candidates.ors.enter', query=query)
            params = {
                "api_key": ORS_API_KEY,
                "text": query,
                "size": max(1, min(int(limit), 10)),
                "boundary.country": "PK",
            }
            resp = requests.get(ORS_GEOCODE_URL, params=params, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            feats = data.get('features') if isinstance(data, dict) else None
            if isinstance(feats, list):
                for f0 in feats[:limit]:
                    if not isinstance(f0, dict):
                        continue
                    geom = f0.get('geometry') if isinstance(f0.get('geometry'), dict) else None
                    coords = (geom or {}).get('coordinates') if isinstance(geom, dict) else None
                    if not (isinstance(coords, list) and len(coords) >= 2):
                        continue
                    lon, lat = float(coords[0]), float(coords[1])
                    props = f0.get('properties') if isinstance(f0.get('properties'), dict) else {}
                    label = (props or {}).get('label') or (props or {}).get('name') or ''
                    out.append({"lat": lat, "lon": lon, "display_name": str(label), "address": (props or {}).get('locality') or {}, "source": "ors"})
            trace('osm_client.geocode_stop_candidates.ors.exit', query=query)
        except Exception as e:
            trace('osm_client.geocode_stop_candidates.ors.error', query=query, error=str(e))
    else:
        trace('osm_client.geocode_stop_candidates.ors.skip', query=query, reason='missing_ors_api_key')

    # Nominatim candidates
    try:
        params = {
            "q": f"{query}, {country}",
            "format": "json",
            "addressdetails": 1,
            "limit": max(1, min(int(limit), 10)),
        }
        resp = requests.get(NOMINATIM_URL, params=params, timeout=8)
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, list):
            for r in data[:limit]:
                if not isinstance(r, dict):
                    continue
                try:
                    out.append({
                        "lat": float(r["lat"]),
                        "lon": float(r["lon"]),
                        "display_name": str(r.get('display_name') or '').strip(),
                        "address": r.get('address', {}),
                        "source": "nominatim",
                    })
                except Exception:
                    continue
    except Exception:
        pass

    # De-dup by rounded coords + name
    uniq: List[Dict[str, Any]] = []
    seen = set()
    for c in out:
        try:
            k = (round(float(c.get('lat')), 6), round(float(c.get('lon')), 6), normalize_text(str(c.get('display_name') or '')))
        except Exception:
            continue
        if k in seen:
            continue
        seen.add(k)
        uniq.append(c)

    # Score + sort
    scored = []
    for c in uniq:
        dn = str(c.get('display_name') or '').strip()
        scored.append((_score_candidate(qn, dn), c))
    scored.sort(key=lambda x: x[0], reverse=True)
    best = [c for _, c in scored if _ > 0.0][:limit]
    if not best and scored:
        # If nothing matches by token overlap, still return the top raw candidates so the caller
        # can either attempt routing or ask the user to disambiguate.
        best = [c for _, c in scored[:limit]]
    trace('osm_client.geocode_stop_candidates.exit', query=query, n=len(best))
    return best

# Default endpoints; can be overridden via env/config if needed
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
OSRM_URL = "https://router.project-osrm.org"

# OpenRouteService endpoints (used by the Flutter app)
ORS_GEOCODE_URL = "https://api.openrouteservice.org/geocode/search"
ORS_DIRECTIONS_URL = "https://api.openrouteservice.org/v2/directions/driving-car/geojson"

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance between two points on Earth (km)."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def geocode_stop(query: str, country: str = "Pakistan") -> Optional[Dict[str, Any]]:
    """
    Geocode a stop name using Nominatim.
    Returns dict with 'lat', 'lon', 'display_name', or None if not found.
    Includes fallback coordinates for major Pakistani cities.
    """
    from .trace import trace
    trace('osm_client.geocode_stop.enter', query=query)

    cands = geocode_stop_candidates(query, country=country, limit=5)
    if not cands:
        trace('osm_client.geocode_stop.failed', query=query)
        return None

    qn = normalize_text(query)
    scored: List[Tuple[float, Dict[str, Any]]] = []
    for c in cands:
        try:
            dn = str(c.get('display_name') or '').strip()
        except Exception:
            dn = ''
        scored.append((_score_candidate(qn, dn), c))
    scored.sort(key=lambda x: x[0], reverse=True)

    top_score, top = scored[0]
    second_score = scored[1][0] if len(scored) >= 2 else 0.0
    top_name = normalize_text(str(top.get('display_name') or ''))
    second_name = normalize_text(str(scored[1][1].get('display_name') or '')) if len(scored) >= 2 else ''

    if (
        len(scored) >= 2
        and top_name
        and second_name
        and top_name != second_name
        and float(top_score) < 0.95
        and float(second_score) >= 0.70
        and (float(top_score) - float(second_score)) < 0.12
    ):
        trace(
            'osm_client.geocode_stop.ambiguous',
            query=query,
            top_score=float(top_score),
            second_score=float(second_score),
            top_display_name=top.get('display_name'),
        )
        raise AmbiguousStopError(query=query, candidates=[c for _, c in scored[:5]])

    trace('osm_client.geocode_stop.top', query=query, display_name=top.get('display_name'), source=top.get('source'))
    return {
        "lat": top.get('lat'),
        "lon": top.get('lon'),
        "display_name": top.get('display_name'),
        "address": top.get('address') or {},
    }

def osrm_route(
    coordinates: List[Tuple[float, float]],
    overview: str = "simplified"
) -> Optional[Dict[str, Any]]:
    """
    Get OSRM route between a list of (lat, lon) coordinates.
    Returns dict with distance (km), duration (seconds), geometry, or None.
    """
    if len(coordinates) < 2:
        return None
    try:
        # Build coordinate string for OSRM
        coord_str = ";".join(f"{lon},{lat}" for lat, lon in coordinates)
        url = f"{OSRM_URL}/route/v1/driving/{coord_str}"
        params = {
            "overview": overview,
            "alternatives": "false",
            "steps": "false",
        }
        response = requests.get(url, params=params, timeout=8)
        response.raise_for_status()
        data = response.json()
        if data.get("code") != "Ok" or not data.get("routes"):
            return None
        route = data["routes"][0]
        return {
            "distance_km": route["distance"] / 1000.0,
            "duration_seconds": route["duration"],
            "geometry": route.get("geometry"),
        }
    except Exception as e:
        return None


def ors_directions(coordinates: List[Tuple[float, float]]) -> Optional[Dict[str, Any]]:
    """Route using OpenRouteService directions (distance/duration + geometry)."""
    from .trace import trace
    if not ORS_API_KEY:
        trace('osm_client.ors_directions.skip', reason='missing_ors_api_key')
        return None
    if len(coordinates) < 2:
        return None
    try:
        trace('osm_client.ors_directions.enter', n_coords=len(coordinates))
        coords = [[lon, lat] for (lat, lon) in coordinates]
        response = requests.post(
            ORS_DIRECTIONS_URL,
            headers={
                "Authorization": ORS_API_KEY,
                "Content-Type": "application/json",
            },
            data=json.dumps({"coordinates": coords}),
            timeout=15,
        )
        response.raise_for_status()
        data = response.json()
        feats = data.get("features") if isinstance(data, dict) else None
        if not isinstance(feats, list) or not feats:
            return None
        f0 = feats[0]
        props = f0.get("properties") if isinstance(f0, dict) else {}
        summary = (props or {}).get("summary") if isinstance(props, dict) else None
        dist_m = (summary or {}).get("distance") if isinstance(summary, dict) else None
        dur_s = (summary or {}).get("duration") if isinstance(summary, dict) else None
        geom = f0.get("geometry") if isinstance(f0, dict) else None
        trace('osm_client.ors_directions.exit', distance_km=(float(dist_m) / 1000.0) if dist_m is not None else None)
        return {
            "distance_km": (float(dist_m) / 1000.0) if dist_m is not None else None,
            "duration_seconds": float(dur_s) if dur_s is not None else None,
            "geometry": geom,
        }
    except Exception as e:
        trace('osm_client.ors_directions.error', error=str(e))
        return None

def build_route_stops(stop_names: List[str]) -> List[Dict[str, Any]]:
    """
    Convert a list of stop names to route_stops with coordinates using OSM.
    Falls back to haversine distances if OSRM fails.
    Returns list of dicts: {stop_name, latitude, longitude, distance_from_previous_km, duration_from_previous_minutes}
    """
    from .trace import trace
    trace('osm_client.build_route_stops.enter', stop_names=stop_names)

    route_stops = []
    coords = []
    for i, name in enumerate(stop_names):
        try:
            geo = geocode_stop(name)
        except AmbiguousStopError as e:
            role = 'via'
            if i == 0:
                role = 'from'
            elif i == (len(stop_names) - 1):
                role = 'to'
            raise AmbiguousStopError(
                query=getattr(e, 'query', name),
                candidates=getattr(e, 'candidates', []) or [],
                stop_index=i,
                stop_role=role,
            )
        if not geo:
            # If geocoding fails, we cannot build a proper route; abort or skip
            raise ValueError(f"Could not geocode stop: {name}")
        trace('osm_client.build_route_stops.geocoded', name=name, display_name=geo.get('display_name'), lat=geo.get('lat'), lon=geo.get('lon'))
        logger.debug(
            "[osm_client] stop geocoded: name=%r display=%r lat=%s lon=%s",
            name,
            geo.get('display_name'),
            geo.get('lat'),
            geo.get('lon'),
        )
        stop = {
            "stop_order": i + 1,
            "stop_name": name,
            "latitude": geo["lat"],
            "longitude": geo["lon"],
            "display_name": geo["display_name"],
        }
        route_stops.append(stop)
        coords.append((geo["lat"], geo["lon"]))

    # Prefer ORS directions when available, fallback to OSRM, then haversine.
    route_ors = ors_directions(coords)
    route_osrm = None if route_ors else osrm_route(coords)
    route = route_ors or route_osrm
    if route and route.get("distance_km") and route.get("duration_seconds") is not None:
        trace('osm_client.build_route_stops.routed', distance_km=route.get('distance_km'), duration_seconds=route.get('duration_seconds'))
        logger.debug(
            "[osm_client] routing provider=%s distance_km=%s duration_s=%s",
            "ors" if route_ors else "osrm",
            route.get('distance_km'),
            route.get('duration_seconds'),
        )
        # Use OSRM distances/durations; we don't have per-segment breakdown without `steps=true`
        # For simplicity, distribute total distance proportionally to haversine per segment
        total_osrm_dist = float(route["distance_km"])
        total_osrm_dur = float(route["duration_seconds"]) / 60.0  # minutes
        # Compute haversine per segment for proportion
        haversine_distances = []
        for i in range(len(coords) - 1):
            d = haversine_distance(coords[i][0], coords[i][1], coords[i+1][0], coords[i+1][1])
            haversine_distances.append(d)
        sum_hav = sum(haversine_distances)
        for i, stop in enumerate(route_stops):
            if i == 0:
                stop["distance_from_previous_km"] = 0.0
                stop["duration_from_previous_minutes"] = 0.0
            else:
                segment_hav = haversine_distances[i-1]
                proportion = segment_hav / sum_hav if sum_hav > 0 else 0
                stop["distance_from_previous_km"] = total_osrm_dist * proportion
                stop["duration_from_previous_minutes"] = total_osrm_dur * proportion
    else:
        trace('osm_client.build_route_stops.routed_fallback_haversine')
        logger.debug("[osm_client] routing fallback: haversine")
        # Fallback: use haversine for both distance and duration (assume 50 km/h average)
        for i, stop in enumerate(route_stops):
            if i == 0:
                stop["distance_from_previous_km"] = 0.0
                stop["duration_from_previous_minutes"] = 0.0
            else:
                dist = haversine_distance(coords[i-1][0], coords[i-1][1], coords[i][0], coords[i][1])
                stop["distance_from_previous_km"] = dist
                stop["duration_from_previous_minutes"] = (dist / 50.0) * 60.0  # minutes
    trace('osm_client.build_route_stops.exit', n_stops=len(route_stops))
    return route_stops

def summarize_route_for_cli(route_stops: List[Dict[str, Any]]) -> str:
    """Return a CLI-friendly summary of a route."""
    if not route_stops:
        return "No route found."
    total_km = sum(s["distance_from_previous_km"] for s in route_stops)
    total_min = sum(s["duration_from_previous_minutes"] for s in route_stops)
    names = [s["stop_name"] for s in route_stops]
    return (
        f"Route: {' → '.join(names)}\n"
        f"Distance: {total_km:.2f} km\n"
        f"Estimated time: {int(total_min)} min"
    )
